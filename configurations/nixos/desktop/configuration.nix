{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  username = "user";
  machine = "desktop";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  secretDir = "${dataDir}/.secret";
  stateDir = "${dataDir}/.state";
  transmissionPort = 33915;
in {
  imports = [
    ./hardware-configuration.nix
    # Re-enable together with the ballbrawl input in flake.nix and the
    # services.ballbrawl block below. Commented out during the first
    # FDE install because the live ISO can't fetch the private SSH input.
    # inputs.ballbrawl.nixosModules.default
  ];

  # -------------------- Secrets -------------------- #

  age = {
    identityPaths = ["${secretDir}/server/ssh/id_ed25519"];
    secrets = {
      "airvpn-wg.conf".file = ./age/airvpn-wg.conf.age;
      mam.file = ./age/mam.age;
      mam-vpn.file = ./age/mam-vpn.age;
      user.file = ./age/user.age;
      domain.file = ./age/domain.age;
      nineteenEightyFour.file = ./age/1984.age;
    };
  };

  # -------------------- Kirk Modules -------------------- #

  kirk = {
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
    };
  };

  # -------------------- Nixarr -------------------- #

  nixarr = {
    enable = true;
    mediaUsers = [username];

    vpn = {
      enable = true;
      wgConf = config.age.secrets."airvpn-wg.conf".path;
      vpnTestService.enable = false;
      # exposeOnLAN defaults to true, which (since nixarr PR #171) puts the
      # whole RFC1918 range — including 10.0.0.0/8 — in the namespace's
      # accessibleFrom. AirVPN's in-tunnel DNS is 10.128.0.1 (inside 10/8),
      # so that range gets routed out the LAN bridge instead of the tunnel,
      # killing DNS for confined services (transmission couldn't resolve
      # trackers -> FD-exhaustion "too many open files"; mam-vpn -> curl
      # exit 6). Disable the broad default and re-add only the real LAN.
      exposeOnLAN = false;
      accessibleFrom = ["192.168.1.0/24"];
    };

    ddns.nineteenEightyFour = {
      enable = true;
      keysFile = config.age.secrets.nineteenEightyFour.path;
    };

    jellyfin = {
      enable = true;
      openFirewall = true;
      expose.https.enable = true;
      expose.https.acmeMail = "slimness_bullish683@simplelogin.com";
      expose.https.domainName = "jellyfin." + (lib.removeSuffix "\n" (builtins.readFile config.age.secrets.domain.path));
    };

    audiobookshelf = {
      enable = true;
      host = "0.0.0.0";
      openFirewall = true;
      expose.https.enable = true;
      expose.https.acmeMail = "slimness_bullish683@simplelogin.com";
      expose.https.domainName = "audiobookshelf." + (lib.removeSuffix "\n" (builtins.readFile config.age.secrets.domain.path));
    };

    transmission = {
      enable = true;
      openFirewall = true;
      privateTrackers.cross-seed.enable = false;
      extraSettings = {
        incomplete-dir-enabled = false;
        ratio-limit-enabled = true;
        ratio-limit = 20.0;
      };
      package = inputs.nixpkgs-2405.legacyPackages.${pkgs.system}.transmission_4;
      vpn.enable = true;
      peerPort = transmissionPort;
    };

    sonarr.enable = true;
    sonarr.openFirewall = true;
    bazarr.enable = true;
    bazarr.openFirewall = true;
    radarr.enable = true;
    radarr.openFirewall = true;
    shelfmark.enable = true;
    shelfmark.openFirewall = true;
    shelfmark.host = "0.0.0.0";
    lidarr.enable = true;
    lidarr.openFirewall = true;
    prowlarr.enable = true;
    prowlarr.openFirewall = true;
  };

  # nixarr creates *-sync-config oneshots unconditionally when each *arr
  # is enabled (there's no settings-sync enable toggle), and they were
  # failing on boot. We don't manage indexers / download clients
  # declaratively, so disable the generated units directly.
  systemd.services.prowlarr-sync-config.enable = false;
  systemd.services.radarr-sync-config.enable = false;
  systemd.services.sonarr-sync-config.enable = false;

  # -------------------- Ballbrawl -------------------- #
  # game.<bare-domain> served by the ballbrawl flake module. The DDNS
  # entry (nixarr.ddns.nineteenEightyFour) already keeps subdomains of
  # the bare domain pointing at this host, same path jellyfin and
  # audiobookshelf use.
  # Temporarily disabled while the ballbrawl input is commented out for
  # the first FDE install (see flake.nix). Re-enable together with the
  # input + the ./hardware-configuration.nix import line above.
  # services.ballbrawl = {
  #   enable = true;
  #   domain = "game." + (lib.removeSuffix "\n" (builtins.readFile config.age.secrets.domain.path));
  #   acmeMail = "slimness_bullish683@simplelogin.com";
  # };

  # MAM
  systemd = {
    timers.mam-vpn = {
      timerConfig = {
        OnBootSec = "120"; # Run 30 seconds after system boot
        OnCalendar = "hourly";
        Persistent = true; # Run service immediately if last window was missed
        RandomizedDelaySec = "15min"; # Run service OnCalendar +- 5min
      };
      wantedBy = ["multi-user.target"];
    };
    services.mam-vpn = {
      serviceConfig = {
        Environment = "PATH=${pkgs.curl}/bin:$PATH";
        ExecStart = "${pkgs.lib.getExe pkgs.bash} ${config.age.secrets.mam-vpn.path}";
        Type = "oneshot";
      };
      vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
    };
  };

  # -------------------- Desktop / Gaming -------------------- #

  # Cosmic + cosmic-greeter. Boot lands on the greeter; jovian.steam
  # configures Steam autostart with Cosmic as the fallback session.
  services.xserver.enable = true;
  services.desktopManager.cosmic.enable = true;
  # cosmic-greeter is DISABLED: jovian.steam.autoStart enables its own SDDM
  # (wayland) with autoLogin into the gamescope-wayland session and wires
  # Switch-to-Desktop -> desktopSession ("cosmic"). cosmic-greeter conflicts
  # with that SDDM and was hijacking boot into Cosmic. We keep the Cosmic
  # DESKTOP (desktopManager.cosmic above) as the switch-to-desktop target.
  services.displayManager.cosmic-greeter.enable = false;
  services.gnome.gnome-keyring.enable = false;
  services.gnome.gcr-ssh-agent.enable = false;

  # Steam in gamescope, Cosmic as the fallback session. AMD Radeon RX 9070
  # (Navi 48 / RDNA4) is well supported here: kernel 6.18 + Mesa 25+ +
  # redistributable firmware (RDNA4 needs kernel >= 6.12 / Mesa >= 25.0).
  #
  # NOTE: steamos.useSteamOSConfig must be explicitly FALSE. It defaults to
  # jovian.steam.enable (= true here), and gates jovian's SteamOS modules —
  # including boot.nix, which injects Deck-tuned amdgpu params
  # (amdgpu.lockup_timeout, ttm.pages_min=8G, sched_hw_submission,
  # amdgpu.dcdebugmask=0x20000) — the very params suspected for the initrd
  # hang — plus SteamOS sysctl/earlyoom/automount/cec. Those target the
  # Deck's APU and a SteamOS appliance, wrong for a desktop dGPU that's
  # primarily a server. We want only the Steam + gamescope session.
  jovian = {
    steamos.useSteamOSConfig = false;
    steam = {
      enable = true;
      autoStart = true;
      desktopSession = "cosmic";
      user = "user";
    };
    hardware.has.amd.gpu = true;
  };

  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Thunderbolt + firmware update daemons.
  services.hardware.bolt.enable = true;
  services.fwupd.enable = true;

  # Case / motherboard RGB (ASRock Z890 Pro-A, Polychrome over SMBus).
  # motherboard = "intel" loads i2c-dev + i2c-i801 so OpenRGB can reach the
  # SMBus controllers. Run `openrgb` to detect devices and set colours; save
  # a profile, then set `startupProfile` here to persist it across reboots.
  services.hardware.openrgb = {
    enable = true;
    motherboard = "intel";
    # ASRock RX 9070 (GPU subvendor 0x1849) GPU RGB is NOT in OpenRGB
    # 1.0rc2 (what nixpkgs ships). Build OpenRGB master + the still-unmerged
    # ASRock GPU controller patch from upstream issue #5225 (download the
    # .patch into ./patches/ and `git add` it — flakes only see tracked
    # files). We replace nixpkgs' two rc2-era patches: one is an upstream
    # commit already present in master, the other is a plugin-path tweak we
    # don't use — both would break against master.
    package = pkgs.openrgb.overrideAttrs (old: {
      version = "git-asrock-4306603";
      src = pkgs.fetchFromGitLab {
        owner = "CalcProgrammer1";
        repo = "OpenRGB";
        rev = "4306603a28c86e91f4dd4f89b41efd3005f0b810";
        sha256 = "0idkmwxkzw7681zdz57sd0r9z11bjvh7ixls1dlzjkgblnpshpjk";
      };
      patches = [./patches/0001-asrock-gpu.patch];
    });
  };

  # No NixOS option sets a specific colour (only startupProfile, which needs
  # an interactively-saved profile that wouldn't survive the @root rollback).
  # So apply the colour declaratively via the CLI once at boot. Applies to
  # all detected controllers (add `--device N` to target one).
  # 1A0500 = rgb(26,5,0), warm candlelight. Dimmer: 0D0300 (13,3,0), 070100 (7,1,0).
  # Disable the persistent OpenRGB SERVER: idle, it keeps the GPU i2c bus
  # claimed, and that bus is shared with the display's DDC — which stutters
  # the desktop (confirmed: `systemctl stop openrgb` cleared it). We don't
  # need a running server; openrgb-color sets the colour once at boot and
  # exits, and both controllers hold it (GPU Direct, board Static).
  # systemd.services.openrgb.enable = lib.mkForce false;

  systemd.services.openrgb-color = {
    description = "Apply static case RGB colour (candlelight)";
    # No persistent openrgb.service to wait on now — just need i2c-dev loaded.
    # The oneshot sets the colour and exits, releasing the GPU i2c bus.
    after = ["systemd-modules-load.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        # Steady candlelight, same colour on both. 0D0300 = rgb(13,3,0).
        "${config.services.hardware.openrgb.package}/bin/openrgb --mode static --color 0D0300"
        "${config.services.hardware.openrgb.package}/bin/openrgb --device \"ASRock GPU\" --mode direct --color 0D0300"
      ];
    };
  };

  # The GPU (Taichi) RGB resets to its default on resume from sleep — Direct
  # is software-driven, not a stored hardware mode — so re-apply on wake.
  # (The board's Static mode survives sleep, but re-applying is harmless.)
  # NOTE: keep these colours in sync with the openrgb-color oneshot above.
  powerManagement.resumeCommands = ''
    ${config.services.hardware.openrgb.package}/bin/openrgb --mode static --color 0D0300
    ${config.services.hardware.openrgb.package}/bin/openrgb --device "ASRock GPU" --mode direct --color 0D0300
  '';

  # schedutil scales dynamically without `powersave`'s aggressive power-down.
  # Better for gaming spikes, still ramps down at idle.
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "schedutil";

  # -------------------- user state subtree -------- #
  # /data/.state stays root-owned (nixarr + other system services keep
  # their own service-user-owned subdirs there). All home-manager USER
  # state instead lives under a single user-owned subtree,
  # /data/.state/user, created here once. home.nix then manages the
  # per-app subdirs under it via its own user-tmpfiles (which work now
  # that the parent is writable by 'user').
  systemd.tmpfiles.rules = [
    "d /data                        0755 root root  -"
    "d /data/.state                 0755 root root  -"
    "d /data/.state/user            0755 user users -"

    # XDG user dirs (kirk.userDirs.rootDir = /data): downloads sits
    # directly in root-owned /data — not under /data/.state/user — so it
    # is created here. The /data/media/* XDG dirs already work via the
    # setgid 'media' group on /data/media.
    "d /data/downloads              0755 user users -"
  ];

  # -------------------- Server Defaults -------------------- #

  # If the system runs out of ram, then journald crashes and the server will be down.
  # This should force systemd to restart, no matter what.
  systemd.services.systemd-journald.unitConfig.StartLimitIntervalSec = 0;

  # Kill services if we run out of ram
  # services.earlyoom = {
  #   enable = true;
  #   freeMemThreshold = 3; # In percent
  # };

  boot.kernelParams = [
    "panic=10" # Reboot after 10 seconds of kernel panic
    "panic_on_oops=1" # Reboot on any kernel oops
  ];

  # Forces full colors in terminal over SSH
  environment.variables = {
    COLORTERM = "truecolor";
    TERM = "xterm-256color";
  };

  # cosmic-greeter handles login; no getty auto-login.
  services.logind.settings.Login.HandleLidSwitch = "ignore";

  # -------------------- Syncthing -------------------- #

  services = {
    syncthing = {
      enable = true;
      configDir = "${stateDir}/syncthing";
      dataDir = "${dataDir}/sync";
      guiAddress = "0.0.0.0:8384";
      overrideDevices = false;
      overrideFolders = false;
    };
    tuptime.enable = true;
    btrfs.autoScrub = {
      enable = true;
      fileSystems = ["/data"];
    };
    fstrim = {
      enable = true;
      interval = "weekly";
    };
    monero.enable = true;
    minecraft-server = {
      enable = true;
      openFirewall = true;
      declarative = true;
      eula = true;
      dataDir = "${stateDir}/minecraft";
      whitelist = {
        Augustenborg = "97389804-1e10-48f6-8a72-fdd854a37feb";
        migmedstort = "6993065e-1c24-475a-9388-6578d9002e4e";
        Jakob290a = "b9150a18-d471-4952-b3d3-c824cfdfdd26";
        mtface = "ae39f9e6-dd5a-4f70-baff-f8ff725886c5";
      };
      serverProperties = {
        motd = "Kirk's NixOS minecraft server";
        server-port = 25565;
        difficulty = "normal";
        max-players = 20;
        white-list = true;
      };
    };
    home-assistant = {
      enable = true;
      openFirewall = true;
      configDir = "${stateDir}/home-assistant";
      extraComponents = [
        "analytics"
        "google_translate"
        "met"
        "radio_browser"
        "shopping_list"
        "zha"
        "usb"
        "isal"
      ];
      configWritable = true;
      config = {
        default_config = {};
        automation = "!include automations.yaml";
      };
    };
    openssh = {
      enable = true;
      openFirewall = true;
      settings.PasswordAuthentication = false;
      ports = [6000];
    };
  };

  networking.firewall.allowedTCPPorts = [8384];

  users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
    ../../../pubkeys/deck-oled.pub
  ];

  # -------------------- Impermanence -------------------- #
  # The NVMe root is ephemeral (rolled back to @root-blank each boot, see
  # the rollback service in the Machine Specific section). These paths
  # are bind-mounted from /data/.state/persist so they survive reboots.
  # Default policy: anything that can be redirected via NixOS module
  # config goes to /data/.state/<service> directly; this list is only
  # for state whose owning module does not expose a path override.
  # NOTE: /var/log is intentionally persisted here so boot/initrd logs
  # (cryptsetup/FIDO2 unlock, the rollback itself) survive the @root wipe
  # and remain available for debugging.
  environment.persistence."/data/.state/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos" # stable uid/gid map across rebuilds
      "/var/lib/acme" # Let's Encrypt certs — avoid rate limits
      "/var/lib/tuptime" # uptime history
      "/var/lib/systemd/timers" # Persistent=true timer stamps (mam-vpn)
      "/var/log" # journald + non-journald logs (kept across rollback)
      "/var/lib/bluetooth" # paired-device DB (future-proof)
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  # -------------------- Boilerplate -------------------- #

  # Set your time zone.
  time.timeZone = "Europe/Copenhagen";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_DK.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "da_DK.UTF-8";
    LC_IDENTIFICATION = "da_DK.UTF-8";
    LC_MEASUREMENT = "da_DK.UTF-8";
    LC_MONETARY = "da_DK.UTF-8";
    LC_NAME = "da_DK.UTF-8";
    LC_NUMERIC = "da_DK.UTF-8";
    LC_PAPER = "da_DK.UTF-8";
    LC_TELEPHONE = "da_DK.UTF-8";
    LC_TIME = "da_DK.UTF-8";
  };

  nix = {
    package = pkgs.nixVersions.latest;
    settings = {
      experimental-features = ["nix-command" "flakes"];
      download-buffer-size = 500000000; # 500 MB
      # Faster builds
      cores = 0;
      # Return more information when errors happen
      show-trace = true;
    };
    # Use the pinned nixpkgs version that is already used, when using `nix shell nixpkgs#package`
    registry.nixpkgs = {
      from = {
        id = "nixpkgs";
        type = "indirect";
      };
      flake = inputs.nixpkgs;
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # -------------------- Machine Specific -------------------- #

  users.mutableUsers = false;
  users.users."user" = {
    shell = pkgs.zsh;
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets.user.path;
    extraGroups = ["networkmanager" "wheel" "render"];
  };

  hardware.graphics.enable = true; # Wayland / Cosmic / Vulkan
  networking = {
    hostName = machine;
    networkmanager.enable = true;
  };

  programs.zsh.enable = true;

  # -------------------- YubiKey (U2F) -------------------- #
  # Touch-to-authenticate for local sudo, TTY login, and the Cosmic
  # greeter. Both pam_u2f and pam_rssh below are stacked "sufficient";
  # in the auth order rssh is tried first, so an SSH session with a
  # forwarded agent still satisfies sudo without a key (see rssh block),
  # and U2F is the local fallback. Password remains the final fallback.
  # Key mapping lives in ~/.config/Yubico/u2f_keys (symlinked to
  # /data/.state/yubico in home.nix); register with `pamu2fcfg`.
  security.pam.services.sudo.u2fAuth = true;
  security.pam.services.login.u2fAuth = true;
  security.pam.services.cosmic-greeter.u2fAuth = true;
  security.pam.u2f.settings.cue = true; # prints "touch your key" prompt

  # 1. Enable the module globally
  security.pam.rssh.enable = true;

  # 2. Tell it to use standard SSH keys for validation
  security.pam.rssh.settings.auth_key_file = "/etc/ssh/authorized_keys.d/user";

  # 3. Apply it specifically to sudo
  security.pam.services.sudo.rssh = true;

  security.sudo = {
    execWheelOnly = true; # For security
    package = pkgs.sudo.override {withInsults = true;}; # For insults lol
    extraConfig = "Defaults insults";
  };

  # systemd in initrd: cleaner cryptsetup passphrase prompts and
  # hosts the snapshot-rollback unit below.
  boot.initrd.systemd.enable = true;

  # /data LUKS — passphrase prompted at console (no more SD-card keyfile).
  # Root LUKS (cryptroot) is declared in hardware-configuration.nix.
  boot.initrd.luks.devices.crypt_ssd1 = {
    device = "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5SSNF0WA10922R";
    allowDiscards = true; # Allows SSD trim commands for better performance
    # YubiKey FIDO2 unlock (systemd initrd). Enroll once with:
    #   sudo systemd-cryptenroll --fido2-device=auto \
    #     /dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5SSNF0WA10922R
    # The existing passphrase stays as a fallback.
    crypttabExtraOpts = ["fido2-device=auto"];
  };

  # Impermanence: roll @root back to a pristine state on every boot,
  # archiving the previous @root under /old_roots/<timestamp> and
  # GCing anything older than 30 days.
  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = ["initrd.target"];
    after = ["dev-mapper-cryptroot.device"];
    before = ["sysroot.mount"];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /btrfs_tmp
      mount -o subvol=/ /dev/mapper/cryptroot /btrfs_tmp

      if [[ -e /btrfs_tmp/@root ]]; then
        mkdir -p /btrfs_tmp/old_roots
        ts=$(date --date="@$(stat -c %Y /btrfs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
        mv /btrfs_tmp/@root "/btrfs_tmp/old_roots/$ts"
      fi

      delete_subvolume_recursively() {
        IFS=$'\n'
        for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
          delete_subvolume_recursively "/btrfs_tmp/$i"
        done
        btrfs subvolume delete "$1"
      }
      for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30 2>/dev/null); do
        delete_subvolume_recursively "$i"
      done

      btrfs subvolume snapshot /btrfs_tmp/@root-blank /btrfs_tmp/@root
      umount /btrfs_tmp
    '';
  };

  fileSystems."/data" = {
    device = "/dev/mapper/crypt_ssd1";
    fsType = "btrfs";
    neededForBoot = true;
    options = [
      "defaults"
      "noatime"
      "nodiratime"
      "compress=zstd"
      "discard=async"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    (writeShellApplication {
      name = "monero";
      runtimeInputs = [monero-cli coreutils];
      inheritPath = false;
      text = ''
        wallet_dir="/data/monero"
        mkdir -p "$wallet_dir"
        monero-wallet-cli \
          --wallet-file "$wallet_dir"/user.keys \
          --log-file "$wallet_dir"/log.log
      '';
    })
    claude-code
    firefox
    chromium
    openrgb
    jellyfin-media-player

    # Compression
    zip
    unar
    unzip
    p7zip

    # Terminal programs
    iotop
    tuptime # Uptime doesn't work lol
    yt-dlp
    git
    smartmontools
    fzf
    ffmpeg
    nmap
    trash-cli
    wget

    # Agenix
    inputs.agenix.packages."${system}".default
    inputs.submerger.packages."${system}".default
  ];

  system.stateVersion = "24.05";
}
