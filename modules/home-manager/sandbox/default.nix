{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.sandbox;

  proxyFilterFile = pkgs.writeText "sandbox-proxy-filter" (concatStringsSep "\n" cfg.network.allowedHosts);

  proxyConfigFile = pkgs.writeText "sandbox-proxy.conf" ''
    Port ${toString cfg.network.proxyPort}
    Listen 127.0.0.1
    Timeout 600
    DefaultErrorFile "${pkgs.tinyproxy}/share/tinyproxy/default.html"
    StatFile "${pkgs.tinyproxy}/share/tinyproxy/stats.html"
    LogLevel Warning
    MaxClients 100
    Allow 127.0.0.1
    Filter "${proxyFilterFile}"
    FilterDefaultDeny Yes
    FilterType ere
    FilterURLs Off
    ConnectPort 443
    ConnectPort 563
  '';

  proxyEnv = optionalString cfg.network.enable ''
    export HTTP_PROXY=http://127.0.0.1:${toString cfg.network.proxyPort}
    export HTTPS_PROXY=http://127.0.0.1:${toString cfg.network.proxyPort}
    export http_proxy=http://127.0.0.1:${toString cfg.network.proxyPort}
    export https_proxy=http://127.0.0.1:${toString cfg.network.proxyPort}
    export NO_PROXY=127.0.0.1,localhost,::1
    export no_proxy=127.0.0.1,localhost,::1
  '';

  initScript = pkgs.writeShellScript "sandbox-init" ''
    # Box uses its own home-manager profile, not the host's /etc/profiles
    # (which would leak host-installed tools — most notably `box` itself).
    export PATH="/home/user/.nix-profile/bin:$PATH"
    export NIX_REMOTE=daemon
    export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
    export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
    ${proxyEnv}
    # Stay at caller's cwd (auto-bound). Fall back to /home/user if it's gone.
    [ -d "$PWD" ] || cd /home/user
    if [ $# -eq 0 ]; then
      exec zsh
    else
      exec "$@"
    fi
  '';

  # Whitelist /dev: replace buildFHSEnv's full /dev bind with a minimal
  # devtmpfs containing only standard nodes (null, zero, full, random,
  # urandom, tty, ptmx, pts, fd, stdin, stdout, stderr, console).
  # /dev/hidraw* gets re-added on top via hidrawBinds when exposeFidoDevices
  # is true. Anything else (cameras, mics, input events, GPU, etc.) is
  # absent unless the user explicitly adds it via extraBwrapArgs.
  minimalDev = [ "--dev" "/dev" ];

  hidrawBinds = optionals cfg.exposeFidoDevices (
    concatMap
      (n: [ "--dev-bind-try" "/dev/hidraw${toString n}" "/dev/hidraw${toString n}" ])
      (range 0 9)
  );

  claudeStateBind = optionals cfg.exposeClaudeState [
    "--bind" "${config.home.homeDirectory}/.claude" "/home/user/.claude"
    # ~/.claude.json holds auth + "user has been set up" state; without it
    # Claude Code treats every invocation as a first-run (theme picker etc).
    "--bind" "${config.home.homeDirectory}/.claude.json" "/home/user/.claude.json"
  ];

  tmpfsMasks = concatMap (p: [ "--tmpfs" p ]) cfg.mountTmpfs;
  roBinds = concatMap (p: [ "--ro-bind" p p ]) cfg.mountsRO;
  rwBinds = concatMap (p: [ "--bind" p p ]) cfg.mountsRW;

  fhs = pkgs.buildFHSEnv {
    name = "${cfg.name}-fhs";
    targetPkgs = cfg.targetPkgs;
    multiPkgs = pkgs: cfg.multiPkgs pkgs;
    runScript = "${initScript}";
    # Namespace unshares — buildFHSEnv passes these straight to bwrap flags.
    inherit (cfg) unshareIpc unsharePid unshareUts unshareCgroup unshareNet privateTmp dieWithParent;
    # Compute the caller's cwd top-level dir so we can mask it (hiding cwd's
    # siblings) before re-binding just $PWD itself. Runs in the same shell
    # as extraBwrapArgs, which can reference these variables.
    extraPreBwrapCmds = ''
      if [ -n "''${PWD-}" ] && [ "$PWD" != "/" ]; then
        _stripped="''${PWD#/}"
        BOX_CWD_TOP="/''${_stripped%%/*}"
      else
        BOX_CWD_TOP="/tmp"
      fi
      ${optionalString (cfg.seccompFile != null) ''
        # Open the seccomp BPF program on FD 9; bwrap reads it via --seccomp 9.
        exec 9< ${cfg.seccompFile}
      ''}
    '';
    extraBwrapArgs =
      # Hostname inside the UTS namespace (requires unshareUts).
      (optionals (cfg.hostname != null && cfg.unshareUts) [ "--hostname" cfg.hostname ])
      # tmpfs masks must come FIRST so they hide buildFHSEnv's auto-binds;
      # then our explicit binds re-introduce only the subpaths we want.
      ++ tmpfsMasks
      # Dynamically mask the top-level of $PWD so siblings of cwd aren't visible.
      ++ [ "--tmpfs" "$BOX_CWD_TOP" ]
      # Replace host /dev with a minimal devtmpfs; hidraw added back below.
      ++ minimalDev
      ++ [
        "--bind" "${cfg.stateDir}/home" "/home/user"
      ]
      ++ claudeStateBind
      ++ hidrawBinds
      ++ roBinds
      ++ rwBinds
      ++ cfg.extraBwrapArgs
      ++ optionals (cfg.seccompFile != null) [ "--seccomp" "9" ]
      # Auto-bind the caller's cwd LAST so it survives every mask above.
      # Writable so active development inside the box works.
      ++ [ "--bind-try" "$PWD" "$PWD" ];
  };

  box = pkgs.writeShellApplication {
    name = cfg.name;
    runtimeInputs = with pkgs; [ coreutils trash-cli ];
    inheritPath = false;
    text = ''
      if [ "''${1:-}" = "nuke" ]; then
        echo "Trashing ${cfg.stateDir}..."
        trash-put "${cfg.stateDir}" 2>/dev/null || echo "No state directory."
        exit 0
      fi
      mkdir -p "${cfg.stateDir}/home"

      if [ "''${1:-}" = "hm-switch" ]; then
        echo "Bootstrapping/refreshing home-manager inside box..."
        exec ${fhs}/bin/${cfg.name}-fhs bash -lc 'home-manager switch --flake ${cfg.homeManagerFlake} -b backup --impure'
      fi

      # Auto-bootstrap on first run: if the box's home has no nix-profile yet,
      # run home-manager switch to populate dotfiles / packages.
      if ${if cfg.homeManagerFlake != null then "true" else "false"} && [ ! -L "${cfg.stateDir}/home/.nix-profile" ]; then
        echo "First run — bootstrapping box home-manager (${cfg.homeManagerFlake})..."
        ${fhs}/bin/${cfg.name}-fhs bash -lc 'home-manager switch --flake ${cfg.homeManagerFlake} -b backup --impure' || {
          echo "Bootstrap failed. Run '${cfg.name} hm-switch' manually."
          exit 1
        }
      fi

      exec ${fhs}/bin/${cfg.name}-fhs "$@"
    '';
  };
in {
  options.kirk.sandbox = {
    enable = mkEnableOption "bubblewrap + FHS sandbox (replaces ubuntuContainer)";

    name = mkOption {
      type = types.str;
      default = "box";
      description = "Command name for the sandbox launcher.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/data/.state/sandbox";
      description = "Writable state directory (the sandbox's home lives at <stateDir>/home).";
    };

    targetPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = pkgs: with pkgs; [
        glibc
        coreutils
        bashInteractive
        zsh
        git
        openssh
        curl
        wget
        cacert
        gnumake
        gcc
        python3
        nodejs
        sudo
        less
        vim
        util-linux
        file
        which
        gnused
        gnugrep
        gawk
        findutils
        nix
        home-manager
        claude-code
      ];
      description = "Function returning the packages exposed inside the FHS (available in /usr/bin etc.).";
    };

    multiPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = _: [];
      description = "Function returning packages provided for both x86_64 and i686 inside the FHS.";
    };

    mountTmpfs = mkOption {
      type = with types; listOf str;
      default = [
        "/data"
        "/home"
        "/var"
        "/opt"
        "/root"
        "/srv"
        "/mnt"
        "/media"
        "/boot"
        # Hide host's dbus/pulseaudio/ssh-agent/etc. user sockets.
        "/run/user"
      ];
      description = ''
        Host top-level directories to mask with a tmpfs inside the sandbox.
        buildFHSEnv auto-mounts every directory under / from the host;
        masking forces the sandbox to see only what is explicitly bound via
        mountsRO/mountsRW/extraBwrapArgs.
      '';
    };

    unshareIpc = mkOption {
      type = types.bool;
      default = true;
      description = "Unshare SysV IPC and POSIX message queues from the host.";
    };

    unsharePid = mkOption {
      type = types.bool;
      default = true;
      description = "Give the box its own PID namespace — host PIDs are invisible, and box processes can't signal host processes.";
    };

    unshareUts = mkOption {
      type = types.bool;
      default = true;
      description = "Unshare UTS (hostname/domainname) namespace.";
    };

    unshareCgroup = mkOption {
      type = types.bool;
      default = true;
      description = "Unshare cgroup namespace.";
    };

    unshareNet = mkOption {
      type = types.bool;
      default = false;
      description = "Unshare the network namespace — fully blocks network from the box. Off by default since most workflows need network.";
    };

    privateTmp = mkOption {
      type = types.bool;
      default = true;
      description = "Use a private tmpfs at /tmp instead of sharing host /tmp.";
    };

    dieWithParent = mkOption {
      type = types.bool;
      default = true;
      description = "Kill all box processes when the launcher exits (clean lifecycle).";
    };

    network = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Route the box's HTTP/HTTPS traffic through a local domain-allowlist proxy
          (tinyproxy). Loopback (127.0.0.1, localhost) bypasses the proxy via NO_PROXY.
          Disabling this gives the box full host network access — convenient but
          undoes a primary security goal.
        '';
      };

      proxyPort = mkOption {
        type = types.port;
        default = 8888;
        description = "TCP port the proxy listens on (loopback only).";
      };

      allowedHosts = mkOption {
        type = with types; listOf str;
        default = [
          # Anthropic / Claude
          ''^api\.anthropic\.com$''
          ''^platform\.claude\.com$''
          # GitHub
          ''^github\.com$''
          ''^api\.github\.com$''
          ''^codeload\.github\.com$''
          ''^.*\.githubusercontent\.com$''
          # Nix
          ''^cache\.nixos\.org$''
          ''^channels\.nixos\.org$''
          ''^.*\.cachix\.org$''
          # npm
          ''^registry\.npmjs\.org$''
        ];
        description = ''
          Regex patterns (extended POSIX) matching allowed destination hostnames.
          tinyproxy applies these as a Filter with FilterDefaultDeny=Yes, so anything
          not matching is blocked. Loopback bypasses this list entirely via NO_PROXY.
        '';
      };
    };

    mountsRO = mkOption {
      type = with types; listOf str;
      default = [
        "/data/.system-configuration"
        "/data/.secret/ssh/id_ed25519_yubi.pub"
        "/data/.secret/ssh/id_ed25519_yubi"
      ];
      description = "Host paths bind-mounted read-only inside the sandbox (same path inside and out).";
    };

    mountsRW = mkOption {
      type = with types; listOf str;
      default = [];
      description = "Host paths bind-mounted read-write inside the sandbox (same path inside and out).";
    };

    homeManagerFlake = mkOption {
      type = with types; nullOr str;
      default = "/data/.system-configuration#sandbox";
      example = "/data/.system-configuration#sandbox";
      description = ''
        Flake reference for the box's home-manager config. When non-null,
        running `box` for the first time will auto-bootstrap home-manager.
        Use `box hm-switch` to re-apply after changes.
      '';
    };

    exposeClaudeState = mkOption {
      type = types.bool;
      default = true;
      description = "Bind-mount host ~/.claude into the sandbox so Claude Code's state persists.";
    };

    exposeFidoDevices = mkOption {
      type = types.bool;
      default = true;
      description = "Expose /dev/hidraw0..9 so libfido2 can talk to the YubiKey (needed for SSH SK signing).";
    };

    hostname = mkOption {
      type = with types; nullOr str;
      default = "box";
      example = "box";
      description = ''
        Hostname the box reports inside its UTS namespace. Visible in shell
        prompts (`%m` in zsh, `\h` in bash) and via `hostname`/`uname -n`.
        Requires `unshareUts = true` (default). Set to `null` to inherit
        the host's hostname.
      '';
    };

    extraBwrapArgs = mkOption {
      type = with types; listOf str;
      default = [];
      example = [ "--unshare-net" ];
      description = "Additional raw bwrap arguments appended to the invocation.";
    };

    seccompFile = mkOption {
      type = with types; nullOr path;
      default = null;
      example = literalExpression "./box-seccomp.bpf";
      description = ''
        Path to a compiled seccomp BPF program. When set, the box uses
        `--seccomp` to apply syscall filtering. Generating the BPF requires
        a separate libseccomp-based tool; this option is intentionally manual
        for now. If null, no seccomp filter is applied (bwrap's defaults still
        drop most capabilities via the user namespace).
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ box ];

    systemd.user.services.sandbox-proxy = mkIf cfg.network.enable {
      Unit = {
        Description = "Domain-allowlist HTTP proxy for the sandbox";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.tinyproxy}/bin/tinyproxy -d -c ${proxyConfigFile}";
        Restart = "on-failure";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
