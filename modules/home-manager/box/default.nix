{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
with lib; let
  cfg = config.kirk.box;

  boxBrokerPkg = inputs.self.packages.${pkgs.system}.box-broker;

  proxyFilterFile = pkgs.writeText "sandbox-proxy-filter" (concatStringsSep "\n" cfg.network.allowedHosts);

  # ─── Box-broker: in-box CLI for approval-gated host ops ─────────────
  # Every action that needs human approval (PR ops, Linear ticket
  # creation, git push/pull/fetch, batch-sign, agent lifecycle hooks)
  # routes through the `box-broker` Rust binary: builds an envelope,
  # writes it to ${cfg.brokerRoot}/request/, waits for the host
  # `box-approver` TUI to gate + dispatch. Both binaries live in the
  # same Rust crate (modules/home-manager/box/packages/box-broker/)
  # and share envelope/response types via the `box_broker` lib.
  #
  # Security: box only knows how to drop a file. The host approver
  # holds the write tokens (GitHub PAT, Linear PAT, the YubiKey-bound
  # SSH key) and only invokes whitelisted endpoints per op-id.

  # In-box `git` wrapper. Blocks network-touching subcommands
  # (push / pull / fetch) with a helpful message; everything else
  # passes through to the real git binary. Network ops are deliberately
  # the human's job — run them on the host against the same working
  # tree (which is bind-mounted both directions). `git-batch-sign` is
  # still available via `box-broker git-batch-sign`.
  gitWrapperScript = pkgs.writeShellApplication {
    name = "git";
    runtimeInputs = with pkgs; [coreutils];
    inheritPath = false;
    text = ''
      set -euo pipefail
      REAL_GIT=${pkgs.git}/bin/git
      if [ $# -lt 1 ]; then exec "$REAL_GIT"; fi
      case "$1" in
        push|pull|fetch)
          SUB="$1"
          shift
          cat >&2 <<EOF
      \`git $SUB\` is gated by the approval TUI. Use the brokered version:

        box-broker git $SUB $*

      See \`box-broker --help\` for the full subcommand list.
      EOF
          exit 11
          ;;
      esac
      exec "$REAL_GIT" "$@"
    '';
  };

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

  # The box runs inside an unshared net ns; slirp4netns NATs out via tap0.
  # Host's 127.0.0.1 is reachable as 10.0.2.2 (slirp4netns default gateway).
  proxyEnv = optionalString cfg.network.enable ''
    export HTTP_PROXY=http://10.0.2.2:${toString cfg.network.proxyPort}
    export HTTPS_PROXY=http://10.0.2.2:${toString cfg.network.proxyPort}
    export http_proxy=http://10.0.2.2:${toString cfg.network.proxyPort}
    export https_proxy=http://10.0.2.2:${toString cfg.network.proxyPort}
    export NO_PROXY=127.0.0.1,localhost,::1
    export no_proxy=127.0.0.1,localhost,::1
  '';

  # When network.enable=true, bwrap's runScript points HERE instead of
  # directly to initScript. We're running inside bwrap's user+net namespaces
  # with CAP_NET_ADMIN/CAP_SYS_ADMIN (via --cap-add). Spawn slirp4netns to
  # set up the tap device, then drop caps and exec the real init.
  # nftables ruleset applied inside the box's netns. Drops all outbound
  # except to the proxy address; drops all inbound except related/established
  # (so proxy responses return). Effectively forces ALL outbound traffic —
  # including raw sockets — through tinyproxy's domain allowlist.
  nftRuleset = pkgs.writeText "box-nftables.rules" ''
    table inet filter {
      chain output {
        type filter hook output priority 0; policy drop;
        ct state established,related accept
        oifname "lo" accept
        # The ONLY permitted destination is tinyproxy on host loopback. Every
        # outbound flow — HTTPS, SSH tunneled through CONNECT, DNS done on the
        # host side — must go through here, where the domain allowlist applies.
        ip daddr 10.0.2.2 tcp dport ${toString cfg.network.proxyPort} accept
      }
      chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        iifname "lo" accept
      }
    }
  '';

  # Runs INSIDE the new netns (via nsenter). Applies nftables filter, drops
  # caps, then execs init. No marker waiting — slirp4netns is already up.
  innerChild = pkgs.writeShellScript "box-net-inner" ''
    ${pkgs.nftables}/bin/nft -f ${nftRuleset} || {
      echo "WARNING: nftables filter failed; raw-socket bypass not blocked." >&2
    }
    exec ${pkgs.util-linux}/bin/setpriv --inh-caps=-all --ambient-caps=-all -- ${initScript} "$@"
  '';

  # 1. Spawn a backgrounded `sleep` in a new netns to act as a netns holder
  #    (gives us a stable /proc/PID/ns/net for slirp4netns to attach to).
  # 2. Start slirp4netns in OUR (parent's) netns, attached to the holder's netns.
  # 3. exec into nsenter foreground — the user command (zsh) keeps the
  #    terminal because we're not in a backgrounded process group.
  slirpWrapper = pkgs.writeShellScript "box-slirp-wrapper" ''
    ${pkgs.util-linux}/bin/unshare --net ${pkgs.coreutils}/bin/sleep infinity &
    HOLDER_PID=$!

    for _ in $(seq 1 20); do
      [ -e "/proc/$HOLDER_PID/ns/net" ] && break
      sleep 0.05
    done

    ${pkgs.slirp4netns}/bin/slirp4netns --configure --mtu=65520 "$HOLDER_PID" tap0 2>/dev/null &
    SLIRP_PID=$!
    sleep 0.3

    # die-with-parent on bwrap reaps the holder + slirp4netns when zsh exits.
    exec ${pkgs.util-linux}/bin/nsenter --net=/proc/$HOLDER_PID/ns/net -- ${innerChild} "$@"
  '';

  initScript = pkgs.writeShellScript "sandbox-init" ''
    # Box uses its own home-manager profile, not the host's /etc/profiles
    # (which would leak host-installed tools — most notably `box` itself).
    export PATH="/home/user/.nix-profile/bin:$PATH"
    export NIX_REMOTE=daemon
    export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
    export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
    # Stable identifier for this box session. Propagated into every
    # request-approval envelope so the approval TUI can group requests
    # by agent and render an "active agents" pane.
    export BOX_SESSION_ID="$(date +%s%N).$$"
    # Fire a `terminated` agent-event when this init script exits so the
    # TUI removes the agent row from the bottom pane. The trap fires on
    # normal exit, EOF on the controlling tty, SIGHUP from a closing
    # terminal — anything that lets the shell unwind cleanly. SIGKILL
    # is uncatchable; in that rare case the agent row will linger.
    trap 'box-broker agent-event terminated || true' EXIT
    ${proxyEnv}
    ${optionalString (cfg.githubTokenFile != null) ''
      if [ -r ${cfg.githubTokenFile} ]; then
        GITHUB_PERSONAL_ACCESS_TOKEN=$(${pkgs.coreutils}/bin/tr -d '[:space:]' < ${cfg.githubTokenFile})
        export GITHUB_PERSONAL_ACCESS_TOKEN
      fi
    ''}
    # Stay at caller's cwd (auto-bound). Fall back to /home/user if it's gone.
    [ -d "$PWD" ] || cd /home/user
    # Apply direnv for the cwd before exec'ing the user command, so non-shell
    # invocations like `box claude --resume` still inherit the project's
    # .envrc / flake devshell env vars. zsh users get this automatically via
    # the direnv hook; this branch covers the direct-exec case.
    if [ -x /home/user/.nix-profile/bin/direnv ]; then
      eval "$(/home/user/.nix-profile/bin/direnv export bash 2>/dev/null)" || true
    fi
    if [ $# -eq 0 ]; then
      zsh
    else
      "$@"
    fi
    exit $?
  '';

  # Whitelist /dev: replace buildFHSEnv's full /dev bind with a minimal
  # devtmpfs containing only standard nodes (null, zero, full, random,
  # urandom, tty, ptmx, pts, fd, stdin, stdout, stderr, console).
  # Anything else (cameras, mics, input events, GPU, hidraw etc.) is
  # absent unless the user explicitly adds it via extraBwrapArgs.
  minimalDev = ["--dev" "/dev"];

  claudeStateBind = optionals cfg.exposeClaudeState [
    "--bind"
    "${config.home.homeDirectory}/.claude"
    "/home/user/.claude"
    # ~/.claude.json holds auth + "user has been set up" state; without it
    # Claude Code treats every invocation as a first-run (theme picker etc).
    "--bind"
    "${config.home.homeDirectory}/.claude.json"
    "/home/user/.claude.json"
  ];

  tmpfsMasks = concatMap (p: ["--tmpfs" p]) cfg.mountTmpfs;
  roBinds = concatMap (p: ["--ro-bind" p p]) cfg.mountsRO;
  rwBinds = concatMap (p: ["--bind" p p]) cfg.mountsRW;

  fhs = pkgs.buildFHSEnv {
    name = "${cfg.name}-fhs";
    targetPkgs = cfg.targetPkgs;
    multiPkgs = pkgs: cfg.multiPkgs pkgs;
    # When network filtering is on, runScript points at the slirpWrapper.
    runScript =
      if cfg.network.enable
      then "${slirpWrapper}"
      else "${initScript}";
    # Namespace unshares passed straight to bwrap flags.
    # network.enable: we let bwrap unshare USER (so --cap-add can grant caps),
    # but we unshare NET ourselves inside the wrapper so the new netns is
    # cleanly owned by our user-ns (avoiding the nested-userns issue that
    # caused setns EPERM when bwrap did it).
    inherit (cfg) unshareIpc unsharePid unshareUts unshareCgroup privateTmp dieWithParent;
    unshareNet = cfg.unshareNet && !cfg.network.enable;
    unshareUser = cfg.network.enable;
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
      # When network filtering is on, grant slirp4netns the caps it needs.
      # setpriv drops these before running user code.
      (optionals cfg.network.enable [
        "--cap-add"
        "CAP_NET_ADMIN"
        "--cap-add"
        "CAP_SYS_ADMIN"
      ])
      # Hostname inside the UTS namespace (requires unshareUts).
      ++ (optionals (cfg.hostname != null && cfg.unshareUts) ["--hostname" cfg.hostname])
      # tmpfs masks must come FIRST so they hide buildFHSEnv's auto-binds;
      # then our explicit binds re-introduce only the subpaths we want.
      ++ tmpfsMasks
      # Dynamically mask the top-level of $PWD so siblings of cwd aren't visible.
      ++ ["--tmpfs" "$BOX_CWD_TOP"]
      # Replace host /dev with a minimal devtmpfs. No hidraw — YubiKey
      # operations (git push/pull/fetch, commit signing) all flow through
      # the host approval TUI, which owns the YubiKey itself.
      ++ minimalDev
      # /dev/net/tun must be added AFTER --dev /dev (which would wipe it).
      ++ (optionals cfg.network.enable [
        "--dev-bind-try"
        "/dev/net/tun"
        "/dev/net/tun"
      ])
      ++ [
        "--bind"
        "${cfg.stateDir}/home"
        "/home/user"
      ]
      ++ claudeStateBind
      ++ (optionals (cfg.githubTokenFile != null) [
        "--ro-bind"
        cfg.githubTokenFile
        cfg.githubTokenFile
      ])
      # /tmp/screenshots: read-only window into host's screenshot drop.
      # Lives on box's /tmp tmpfs (privateTmp). Silently skipped if absent.
      ++ ["--ro-bind-try" "/tmp/screenshots" "/tmp/screenshots"]
      # Broker IPC: box drops request files in ${cfg.brokerRoot}/request (RW),
      # reads response files from ${cfg.brokerRoot}/response (RO). Host
      # dispatcher (or approval TUI) holds the write-PAT and only invokes
      # whitelisted endpoints. agent-events/ is a separate stream of
      # fire-and-forget state notifications (working/ready), consumed by
      # the TUI's bottom pane + ready-notification.
      ++ (optionals cfg.githubPrBroker.enable [
        "--bind-try"
        "${cfg.brokerRoot}/request"
        "${cfg.brokerRoot}/request"
        "--ro-bind-try"
        "${cfg.brokerRoot}/response"
        "${cfg.brokerRoot}/response"
        "--bind-try"
        "${cfg.brokerRoot}/agent-events"
        "${cfg.brokerRoot}/agent-events"
      ])
      ++ roBinds
      ++ rwBinds
      ++ cfg.extraBwrapArgs
      ++ optionals (cfg.seccompFile != null) ["--seccomp" "9"]
      # Auto-bind the caller's cwd LAST so it survives every mask above.
      # Writable so active development inside the box works.
      ++ ["--bind-try" "$PWD" "$PWD"];
  };

  # Single entry-point — the FHS env wrapper. When network.enable=true the
  # FHS env's runScript is slirpWrapper (which sets up slirp4netns inside
  # bwrap's namespaces, drops caps, then execs initScript).
  runBox = "${fhs}/bin/${cfg.name}-fhs";

  box = pkgs.writeShellApplication {
    name = cfg.name;
    runtimeInputs = with pkgs; [coreutils trash-cli];
    inheritPath = false;
    text = ''
      if [ "''${1:-}" = "nuke" ]; then
        echo "Trashing ${cfg.stateDir}..."
        trash-put "${cfg.stateDir}" 2>/dev/null || echo "No state directory."
        exit 0
      fi
      mkdir -p "${cfg.stateDir}/home"
      ${optionalString cfg.githubPrBroker.enable ''
        # PR broker dirs: must exist on host before bwrap so bind-try'd
        # mounts actually attach.
        mkdir -p ${cfg.brokerRoot}/request ${cfg.brokerRoot}/response \
                 ${cfg.brokerRoot}/agent-events
      ''}

      # Auto-allow any .envrc in the launching cwd so direnv loads the
      # project devshell inside the box (initScript runs `direnv export
      # bash`, which only emits env when .envrc is trusted). Safe in this
      # context because the box itself is the sandbox — if someone cd's
      # into a malicious repo and runs `box`, the .envrc's code runs inside
      # the bwrap+nft jail, not on the host.
      if [ -f "$PWD/.envrc" ]; then
        ${pkgs.direnv}/bin/direnv allow "$PWD" 2>/dev/null || true
      fi

      # Auto-bootstrap on first run.
      if ${
        if cfg.homeManagerFlake != null
        then "true"
        else "false"
      } && [ ! -L "${cfg.stateDir}/home/.nix-profile" ]; then
        echo "First run — bootstrapping box home-manager (${cfg.homeManagerFlake})..."
        ${runBox} bash -lc 'home-manager switch --flake ${cfg.homeManagerFlake} -b backup --impure' || {
          echo "Bootstrap failed. Run '${cfg.name} hm-switch' manually."
          exit 1
        }
      fi

      exec ${runBox} "$@"
    '';
  };
in {
  options.kirk.box = {
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

    brokerRoot = mkOption {
      type = types.str;
      default = "/tmp/box-broker";
      description = ''
        Root directory for the host↔box broker IPC. Contains `request/`
        (box→host, RW in box) and `response/` (host→box, RO in box)
        subdirectories. The host-side approval TUI (or dispatcher,
        depending on broker) watches `request/` and writes back to
        `response/`. Must be the SAME path inside and outside the
        sandbox — the directories are bind-mounted.
      '';
    };

    targetPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = pkgs:
        with pkgs; [
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
          socat
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
          # GitHub MCP server (hosted on GitHub Copilot infra by Microsoft)
          ''^api\.githubcopilot\.com$''
          # Azure storage / Microsoft cloud: GitHub Actions log/artifact
          # downloads redirect here (productionresultssa5.blob.core.windows.net
          # and similar). Broad on purpose so future Azure-hosted GitHub
          # endpoints don't need allowlist updates.
          ''^.*\.windows\.net$''
          # Nix
          ''^cache\.nixos\.org$''
          ''^channels\.nixos\.org$''
          ''^.*\.cachix\.org$''
          # npm
          ''^registry\.npmjs\.org$''
          # cargo
          ''^crates\.io$''
          ''^index\.crates\.io$''
          ''^static\.crates\.io$''
          # Linear (MCP server + OAuth)
          ''^linear\.app$''
          ''^.*\.linear\.app$''
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
        # YubiKey PUBLIC key only — the box uses this to verify commit
        # signatures in the shared working tree (kirk.git builds
        # allowed_signers from it). The matching SK private blob lives
        # only on host; signing happens via the approval TUI.
        "/data/.secret/ssh/id_ed25519_yubi.pub"
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

    githubTokenFile = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "/data/.secret/github/pat";
      description = ''
        Host path to a file containing a GitHub PAT. When set, the file is
        bind-mounted read-only into the box and its contents (with surrounding
        whitespace stripped) are exported as GITHUB_PERSONAL_ACCESS_TOKEN.
        The official github MCP plugin reads this env var for its Bearer header.
      '';
    };

    brokerClient = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Install the in-box client scripts (`gh-pr-create`, `gh-pr-edit`)
          into this profile's `home.packages` so they end up in
          `~/.nix-profile/bin/` — which is reliably on PATH including
          through direnv/devenv shells. Enable this in the BOX's
          home-manager config (not the host's); the host doesn't need them.
        '';
      };
    };

    githubPrBroker = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Host-side capability broker for opening GitHub pull requests from
          inside the box. File-drop pattern: `gh-pr-create` (in the box)
          drops a JSON request at `''${brokerRoot}/request/`, the host
          approval TUI dispatches it via the GitHub API, and the response
          (PR URL) lands in `''${brokerRoot}/response/` for the in-box
          client to read.

          The write-scoped PAT lives at `writeTokenFile` on the host and is
          never bind-mounted into the box. The broker only ever invokes
          GitHub's create-PR endpoint — approve/close/comment/merge are not
          reachable from inside the box.
        '';
      };

      writeTokenFile = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "/data/.secret/github/pat-write";
        description = ''
          Host path to a file containing a GitHub PAT with
          `Pull requests: Read and Write` permission. Read by the dispatcher
          at request time. MUST NOT be inside any path that's bind-mounted
          into the box (don't put it under `mountsRO`/`mountsRW`).
        '';
      };
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
      example = ["--unshare-net"];
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

  config = mkMerge [
    # Box's in-box client. Independent of cfg.enable so the BOX's
    # home-manager (which never sets box.enable) can still install it.
    (mkIf cfg.brokerClient.enable {
      home.packages = [
        # `box-broker` (and `box-approver`, unused inside the box but
        # along for the ride). All in-box approval-gated actions go
        # through `box-broker SUB …`; see `box-broker --help`.
        boxBrokerPkg
        # Git wrapper shadows pkgs.git's bin/git for push/pull/fetch
        # only; other subcommands fall through to the real git binary.
        # hiPrio resolves the bin/git symlink collision in favour of
        # the wrapper.
        (lib.hiPrio gitWrapperScript)
      ];
    })
    (mkIf cfg.enable {
      home.packages = [box];

      # The PR broker dispatcher (bash + systemd path-unit) is retired: all
      # broker requests now go through the host-side approval-tui binary,
      # which watches ${cfg.brokerRoot}/request directly. The user launches
      # approval-tui in a terminal of their choice; bind-mounts + brokerRoot
      # remain available for it.

      systemd.user.services.sandbox-proxy = mkIf cfg.network.enable {
        Unit = {
          Description = "Domain-allowlist HTTP proxy for the sandbox";
          After = ["network-online.target"];
          Wants = ["network-online.target"];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.tinyproxy}/bin/tinyproxy -d -c ${proxyConfigFile}";
          Restart = "on-failure";
          RestartSec = "2s";
        };
        Install.WantedBy = ["default.target"];
      };
    })
  ];
}
