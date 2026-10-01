{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  username = "user";
  gameUser = "steam";
  machine = "desktop";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  secretDir = "${dataDir}/.secret";
  stateDir = "${dataDir}/.state";
  transmissionPort = 33915;

  # This always-on box must not suspend, so a suspend request puts the TV in standby.
  # The empty first entry resets the unit's ExecStart.
  sleepToTv = [
    ""
    "${pkgs.writeShellScript "sleep-to-tv-standby" ''
      ${pkgs.procps}/bin/pkill -USR1 -f cec-tv-liveness || true
    ''}"
  ];

  # Steam's %command% is empty for non-Steam shortcuts, so the args live in a script.
  # Steam's overlay LD_PRELOAD crashes the Chromium zygote; unsetting it keeps the sandbox.
  mkChromiumTile = name: args:
    pkgs.writeShellScriptBin name ''
      unset LD_PRELOAD
      exec ${pkgs.chromium}/bin/chromium --ozone-platform=x11 ${args} "$@"
    '';
  # Own profile, so it never attaches to the plain Chromium tile.
  jellyfin-kiosk =
    mkChromiumTile "jellyfin-kiosk"
    "--user-data-dir=${stateDir}/${gameUser}/jellyfin-web --app=http://localhost:8096 --kiosk --no-first-run --window-size=3840,2160 --force-device-scale-factor=2.0";
  # --start-fullscreen is required because Chromium multiplies --window-size by the
  # scale factor, and gamescope then downscales the oversized window.
  mkChromiumBrowser = name: profile:
    mkChromiumTile name
    "--user-data-dir=${stateDir}/${gameUser}/${profile} --window-size=3840,2160 --start-fullscreen --force-device-scale-factor=2.0";
  chromium-rasmus = mkChromiumBrowser "chromium-rasmus" "chromium-rasmus";
  chromium-naja = mkChromiumBrowser "chromium-naja" "chromium-naja";
in {
  imports = [
    ./hardware-configuration.nix
    # TODO: re-enable the ballbrawl module and services.ballbrawl with the ballbrawl input in flake.nix.
  ];

  # -------------------- Secrets -------------------- #

  age = {
    identityPaths = ["${secretDir}/ssh/${machine}"];
    secrets = {
      "airvpn-wg.conf".file = ../../../age/desktop/airvpn-wg.conf.age;
      mam.file = ../../../age/desktop/mam.age;
      mam-vpn.file = ../../../age/desktop/mam-vpn.age;
    };
  };

  # Soft-reboot skips activation scripts and clears the agenix ramfs, so a service reinstalls the secrets.
  # DefaultDependencies=no drops the shutdown.target conflict; it is set again so soft-reboot restarts this unit.
  systemd.services.agenix-reinstall = {
    description = "Reinstall agenix secrets (survives soft-reboot)";
    wantedBy = ["sysinit.target"];
    before = ["wg.service" "shutdown.target"];
    conflicts = ["shutdown.target"];
    unitConfig.DefaultDependencies = "no";
    path = [pkgs.mount];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "agenix-reinstall" ''
        ${config.system.activationScripts.agenixNewGeneration.text}
        ${config.system.activationScripts.agenixInstall.text}
        ${config.system.activationScripts.agenixChown.text}
      '';
    };
  };

  # -------------------- Kirk Modules -------------------- #

  kirk = {
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
      extraNixOptions = true;
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
      # exposeOnLAN routes all of 10.0.0.0/8 to the LAN, which includes AirVPN's
      # in-tunnel DNS at 10.128.0.1. Expose only the real LAN.
      exposeOnLAN = false;
      accessibleFrom = ["192.168.1.0/24"];
    };

    jellyfin = {
      enable = true;
      openFirewall = true;
    };

    audiobookshelf = {
      enable = true;
      host = "0.0.0.0";
      openFirewall = true;
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
      package = inputs.nixpkgs-2405.legacyPackages.${pkgs.stdenv.hostPlatform.system}.transmission_4;
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

  # nixarr always creates these units and they fail at boot. Indexers and
  # download clients are not managed declaratively.
  systemd.services.prowlarr-sync-config.enable = false;
  systemd.services.radarr-sync-config.enable = false;
  systemd.services.sonarr-sync-config.enable = false;

  # Syncthing creates dirs 750 and files 640, so group `sync` is read-only.
  systemd.services.syncthing.serviceConfig.UMask = "0027";

  # nixarr makes /data/media read-only to audiobookshelf, but podcasts write episodes into the library.
  # TODO: fix upstream in nixarr.
  systemd.services.audiobookshelf.serviceConfig.ReadWritePaths =
    lib.mkForce ["/data/.state/nixarr/audiobookshelf" "/data/media/library/podcasts"];

  systemd = {
    timers.mam-vpn = {
      timerConfig = {
        OnBootSec = "120";
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "15min";
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

    # AirVPN rotates endpoint IPs and WireGuard resolves the hostname only at bring-up.
    # Restarting the oneshot wg.service re-resolves it, and dependent services follow.
    services.wg-watchdog = {
      wantedBy = ["multi-user.target"];
      after = ["wg.service"];
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        ExecStart = pkgs.writeShellScript "wg-watchdog" ''
          while true; do
            sleep 600
            # One reply out of 10 counts as success, to tolerate packet loss.
            if ${pkgs.iproute2}/bin/ip netns exec wg \
                 ${pkgs.iputils}/bin/ping -c10 -W3 -q 1.1.1.1 >/dev/null 2>&1; then
              continue
            fi
            echo "wg tunnel probe failed; restarting wg.service to re-resolve endpoint" >&2
            ${pkgs.systemd}/bin/systemctl restart wg.service
            sleep 30 # let the tunnel re-establish before the next probe
          done
        '';
      };
    };
  };

  # -------------------- Desktop / Gaming -------------------- #

  services.xserver.enable = true;
  # Plasma is the Switch-to-Desktop target; gamescope game mode is the boot session.
  # jovian.steam provides SDDM, so no separate display manager is set.
  services.desktopManager.plasma6.enable = true;
  # foot and helix replace konsole and kate.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
    kate
    elisa
    khelpcenter
    kwallet-pam
    kwalletmanager
  ];
  # jovian's Steam module enables the Orca screen reader.
  services.orca.enable = lib.mkForce false;

  kirk.keyboardLayout = {
    enable = true;
    package = inputs.keyboard-layout.packages.${pkgs.stdenv.hostPlatform.system}.rk;
  };

  # useSteamOSConfig defaults to true with jovian.steam and adds Deck APU amdgpu params
  # and SteamOS services, which are wrong for a desktop dGPU server.
  jovian = {
    steamos.useSteamOSConfig = false;
    steam = {
      enable = true;
      autoStart = true;
      desktopSession = "plasma";
      user = gameUser;
    };
    hardware.has.amd.gpu = true;
  };
  programs.steam.extraPackages = [pkgs.hidapi];
  hardware.steam-hardware.enable = true;

  # Proton picks the Intel iGPU first, so pin DXVK and vkd3d to the AMD card. Only
  # sessionVariables reach Steam, and Steam's runtime lacks the MESA_VK_DEVICE_SELECT layer.
  environment.sessionVariables = {
    DXVK_FILTER_DEVICE_NAME = "Radeon";
    VKD3D_FILTER_DEVICE_NAME = "Radeon";
  };

  # steamRoot must be the dir that ~/.local/share/Steam resolves to (see the tmpfiles links).
  # Its parent holds a userdata/ tree that Steam never reads.
  kirk.steamShortcuts = {
    enable = true;
    user = gameUser;
    steamRoot = "${stateDir}/${gameUser}/steam";
    pruneUnmanaged = true;
    shortcuts = {
      # The native Jellyfin client needs Wayland protocols that gamescope does not implement.
      "Jellyfin" = {
        exe = "${jellyfin-kiosk}/bin/jellyfin-kiosk";
        portrait = ../../../images/steam/jellyfin-portrait.png; # 600x900
        landscape = ../../../images/steam/jellyfin-landscape.png; # 920x430
        hero = ../../../images/steam/jellyfin-hero.png; # 3840x1240
        logo = ../../../images/steam/jellyfin-logo.png; # 1363x480
        icon = ../../../images/steam/jellyfin-icon.png; # 1024x1024
      };
      "Chromium" = {
        exe = "${chromium-rasmus}/bin/chromium-rasmus";
        portrait = ../../../images/steam/chromium-portrait.png; # 600x900
        landscape = ../../../images/steam/chromium-landscape.png; # 920x430
        hero = ../../../images/steam/chromium-hero.png; # 1920x620
        logo = ../../../images/steam/chromium-logo.png; # 4315x1024
        icon = ../../../images/steam/chromium-icon.png; # 256x256
      };
      # Chrome artwork distinguishes this tile from the Chromium tile.
      "Chromium (Naja)" = {
        exe = "${chromium-naja}/bin/chromium-naja";
        portrait = ../../../images/steam/chrome-portrait.png; # 600x900
        landscape = ../../../images/steam/chrome-landscape.png; # 920x430
        hero = ../../../images/steam/chrome-hero.png; # 1920x620
        logo = ../../../images/steam/chrome-logo.png; # 1271x337
        icon = ../../../images/steam/chrome-icon.png; # 256x256
      };
    };
  };

  # ROMs, BIOS and saves live in /data/.state/games/<system>, so Syncthing mirrors
  # them to the Steam Deck. Declared games become tiles through kirk.steamShortcuts.
  kirk.emulation = {
    enable = true;
    user = gameUser;
    group = gameUser;
    stateDir = "${stateDir}/${gameUser}";
    ps1.enable = true;
    switch.enable = true;
  };

  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.hardware.bolt.enable = true;
  services.fwupd.enable = true;

  # The ASRock Z890 Pro-A board RGB is on SMBus; "intel" loads i2c-dev and i2c-i801.
  services.hardware.openrgb = {
    enable = true;
    motherboard = "intel";
  };

  # No NixOS option sets a colour, and a saved startupProfile would not survive the @root rollback.
  systemd.services.openrgb-color = {
    description = "Apply static case RGB colour (candlelight)";
    # Run as a client of openrgb.service. Its own early-boot hardware detection
    # races the server and the amdgpu i2c bus, and segfaults.
    requires = ["openrgb.service"];
    after = ["openrgb.service" "systemd-modules-load.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # The server can open its socket after this unit starts.
      Restart = "on-failure";
      RestartSec = 3;
      ExecStart = [
        "${config.services.hardware.openrgb.package}/bin/openrgb --mode static --color 0E0200"
      ];
    };
  };

  powerManagement.resumeCommands = ''
    ${config.services.hardware.openrgb.package}/bin/openrgb --mode static --color 0E0200
  '';

  # schedutil follows gaming load spikes and still ramps down at idle.
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "schedutil";

  # -------------------- user state subtree -------- #
  # /data/.state stays root-owned for system services. User state lives in the
  # user-owned /data/.state/user, and home.nix creates its subdirs.
  # mkBefore because tmpfiles honours the first line for a path, and nixarr also declares /data/media.
  systemd.tmpfiles.rules = lib.mkBefore [
    # /data and /data/.state keep o+x so `steam` can reach its own subdirs.
    "d /data                        0755 root  root  -"
    "d /data/.state                 0755 root  root  -"
    "d /data/.state/user            0700 user  users -"
    "d /data/.state/steam           0755 steam steam -"
    "d /data/.secret                0700 user  users -"
    "d /data/monero                 0700 user  users -"
    "d /data/tmp                    0700 user  users -"
    "d /data/cold-storage           0750 root  users -"
    "d /data/media                  2770 root  media -"
    "d /data/downloads              0750 user  users -"

    # The AI flake at /data/ai runs as `user` and writes models and caches here.
    "d /persist/ai                  0755 user users -"

    # /persist/games/sandisk is a mountpoint, declared in fileSystems.
    "d /persist/games               0755 steam steam -"
    "d /persist/games/samsung       0755 steam steam -"

    # The ~/.config and ~/.local/share rules must precede the links, or tmpfiles
    # creates those parents root-owned and home-manager's linkGeneration fails.
    "d /data/.state/steam/steam              0755 steam steam -"
    "d /data/.state/steam/steam-compat       0755 steam steam -"
    "d /data/.state/steam/gamescope          0755 steam steam -"
    "d /data/.state/steam/steamos-manager    0755 steam steam -"
    "d /data/.state/steam/jellyfin-web       0700 steam steam -"
    "d /data/.state/steam/chromium-rasmus    0700 steam steam -"
    "d /data/.state/steam/chromium-naja      0700 steam steam -"
    "d /data/.state/steam/jellyfinmediaplayer 0755 steam steam -"
    "d /home/steam/.config          0755 steam steam -"
    "d /home/steam/.local           0755 steam steam -"
    "d /home/steam/.local/share     0755 steam steam -"
    "L+ /home/steam/.local/share/Steam               - - - - /data/.state/steam/steam"
    "L+ /home/steam/.steam                           - - - - /data/.state/steam/steam-compat"
    "L+ /home/steam/.config/gamescope                - - - - /data/.state/steam/gamescope"
    "L+ /home/steam/.config/steamos-manager          - - - - /data/.state/steam/steamos-manager"
    "L+ /home/steam/.local/share/jellyfinmediaplayer - - - - /data/.state/steam/jellyfinmediaplayer"
  ];

  # -------------------- Server Defaults -------------------- #

  # journald can crash when memory runs out; never rate-limit its restart.
  systemd.services.systemd-journald.unitConfig.StartLimitIntervalSec = 0;

  boot.kernelParams = [
    "panic=10" # Reboot after 10 seconds of kernel panic
    "panic_on_oops=1" # Reboot on any kernel oops
  ];

  # Forces full colors in terminal over SSH
  environment.variables = {
    COLORTERM = "truecolor";
    TERM = "xterm-256color";
  };

  services.logind.settings.Login.HandleLidSwitch = "ignore";
  # The suspend key is repurposed as a TV wake button (see kirk.cec).
  services.logind.settings.Login.HandleSuspendKey = "ignore";
  services.logind.settings.Login.HandleSuspendKeyLongPress = "ignore";

  # HandleSuspendKey covers only the hardware key. Steam's power-menu "Sleep" is a
  # software suspend through login1.
  systemd.services.systemd-suspend.serviceConfig.ExecStart = lib.mkForce sleepToTv;
  systemd.services.systemd-hibernate.serviceConfig.ExecStart = lib.mkForce sleepToTv;
  systemd.services.systemd-hybrid-sleep.serviceConfig.ExecStart = lib.mkForce sleepToTv;

  # The power button soft-reboots, for physical recovery when Steam or gamescope hangs.
  # Soft-reboot keeps the kernel, so FDE stays unlocked, but the @root rollback does not run.
  # Jovian ships powerbuttond in a package, so enable = false does not disable it.
  systemd.user.services.steamos-powerbuttond.serviceConfig.ExecStart =
    lib.mkForce ["" "${pkgs.coreutils}/bin/true"];
  services.logind.settings.Login.HandlePowerKey = "ignore";
  services.logind.settings.Login.HandlePowerKeyLongPress = "ignore";
  services.acpid = {
    enable = true;
    handlers.power-soft-reboot = {
      event = "button/power.*";
      action = "${pkgs.systemd}/bin/systemctl soft-reboot";
    };
  };

  services = {
    syncthing = {
      enable = true;
      # Group `sync` makes synced data readable by `user`.
      group = "sync";
      configDir = "${stateDir}/syncthing";
      dataDir = "${dataDir}/sync";
      guiAddress = "0.0.0.0:8384";
      overrideDevices = false;
      overrideFolders = false;
    };
    tuptime.enable = true;
    tailscale = {
      enable = true;
      openFirewall = true;
    };
    btrfs.autoScrub = {
      enable = true;
      fileSystems = ["/data"];
    };
    fstrim = {
      enable = true;
      interval = "weekly";
    };
    monero = {
      enable = true;
      # The ~200 GB blockchain is re-downloadable, so it lives on @persist, not /data.
      dataDir = "/persist/monero";
    };
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
      hostKeys = [
        {
          path = "${secretDir}/ssh/${machine}";
          type = "ed25519";
        }
      ];
    };
  };

  networking.firewall = {
    allowedTCPPorts = [8384 8123];
  };

  users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
    ../../../ssh-keys/yubi.pub
  ];

  # -------------------- Impermanence -------------------- #
  # List only state whose module has no path option; other state goes to /data/.state/<service>.
  environment.persistence."/data/.state/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos" # stable uid/gid map across rebuilds
      "/var/lib/tailscale"
      "/var/lib/tuptime"
      "/var/lib/systemd/timers" # Persistent=true timer stamps (mam-vpn)
      "/var/log" # keeps initrd unlock and rollback logs for debugging
      "/var/lib/bluetooth"
    ];
    files = [
      "/etc/machine-id"
    ];
  };

  # -------------------- Boilerplate -------------------- #

  time.timeZone = "Europe/Copenhagen";

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

  nix.settings.trusted-users = ["root" "nixremote"];

  # -------------------- Remote builder -------------------- #
  # work and deck offload builds here over SSH on port 6000.
  # Builds over WAN need port 6000 forwarded at the router.
  # These keys must not be sk keys, because nix-daemon cannot wait for a YubiKey touch.
  users.groups.nixremote = {};
  users.users.nixremote = {
    isNormalUser = true;
    group = "nixremote";
    openssh.authorizedKeys.keyFiles = [
      ../../../ssh-keys/age/work.pub
      ../../../ssh-keys/age/deck-oled.pub
    ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # -------------------- Machine Specific -------------------- #

  users.mutableUsers = false;
  users.groups.sync = {};
  users.groups.cectv = {};

  # The CEC daemon gets the CEC adapter and the keystroke-free control nodes, so no
  # user process needs `input` access to keyboards.
  services.udev.extraRules = ''
    SUBSYSTEM=="cec", KERNEL=="cec[0-9]*", GROUP="cectv", MODE="0660"
    SUBSYSTEM=="input", KERNEL=="event[0-9]*", ATTRS{name}=="*System Control*", GROUP="cectv", MODE="0660"
    SUBSYSTEM=="input", KERNEL=="event[0-9]*", ATTRS{name}=="*Consumer Control*", GROUP="cectv", MODE="0660"
  '';
  # No password on either account: auth is the YubiKey (pam_u2f) only, so a
  # locked `!` hash is the correct and only credential state.
  users.users."${username}" = {
    isNormalUser = true;
    extraGroups = ["networkmanager" "wheel" "sync"];
  };

  # Graphical seat. Not in wheel, no SSH keys. cectv is the CEC daemon's
  # entire privileged surface; deliberately NOT in `input`/`video`/`render`.
  users.groups."${gameUser}" = {};
  users.users."${gameUser}" = {
    isNormalUser = true;
    group = gameUser;
    extraGroups = ["networkmanager" "cectv"];
  };

  hardware.graphics.enable = true;
  # Intel iGPU VA-API and QSV drivers let Jellyfin transcode without the AMD dGPU.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
  ];
  networking = {
    hostName = machine;
    networkmanager.enable = true;
  };

  # No system `programs.zsh`. Its /etc/zsh* files leak into the buildFHSEnv `box`
  # sandbox and break the shell there.

  # -------------------- YubiKey (U2F) -------------------- #
  # Touch-to-authenticate for sudo, TTY login, the SDDM greeter and the Plasma lock screen.
  # /home is wiped every boot, so the authfile is system-wide. It holds public credentials only.
  # Both lines are the same YubiKey. Register with `pamu2fcfg -o pam://desktop`.
  environment.etc."u2f_keys".text = ''
    user:TYg4k09qkMagOBBfoTdCgGo9Az7v/PiIV4wvEuMd2IK+BBicWtkiSexaDfnndS77+QW96YBnfdcrfPd1tzJH0w==,36ZOFFeRKCBl6SEEbw31Xw7tS8H+bRP7ZTBUmYlq6WMbNhdXfwfkHOL7J7WOQvvvxlcW0eEzNAjex1QIPnzjJQ==,es256,+presence
    steam:TYg4k09qkMagOBBfoTdCgGo9Az7v/PiIV4wvEuMd2IK+BBicWtkiSexaDfnndS77+QW96YBnfdcrfPd1tzJH0w==,36ZOFFeRKCBl6SEEbw31Xw7tS8H+bRP7ZTBUmYlq6WMbNhdXfwfkHOL7J7WOQvvvxlcW0eEzNAjex1QIPnzjJQ==,es256,+presence
  '';
  security.pam.u2f.settings.authfile = "/etc/u2f_keys";
  security.pam.services.sudo.u2fAuth = true;
  security.pam.services.login.u2fAuth = true;
  security.pam.services.sddm.u2fAuth = true;
  security.pam.services.kde.u2fAuth = true;
  security.pam.u2f.settings.cue = true;

  # rssh is tried before U2F, so sudo over SSH with a forwarded agent needs no key.
  security.pam.rssh.enable = true;

  security.pam.rssh.settings.auth_key_file = "/etc/ssh/authorized_keys.d/user";

  security.pam.services.sudo.rssh = true;

  security.sudo = {
    execWheelOnly = true;
    package = pkgs.sudo.override {withInsults = true;};
    extraConfig = ''
      Defaults insults
      Defaults timestamp_timeout=0
    '';
  };

  # The rollback unit below needs systemd in initrd.
  boot.initrd.systemd.enable = true;

  # Root LUKS (cryptroot) is in hardware-configuration.nix.
  boot.initrd.luks.devices.crypt_ssd1 = {
    device = "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5SSNF0WA10922R";
    allowDiscards = true;
    # Enroll with `systemd-cryptenroll --fido2-device=auto <device>`; the passphrase stays as fallback.
    crypttabExtraOpts = ["fido2-device=auto"];
  };

  # Archive the previous @root under /old_roots and delete archives older than 30 days.
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

  # Steam library on an unencrypted SanDisk SSD, to keep games off the 8TB /data pool.
  fileSystems."/persist/games/sandisk" = {
    device = "/dev/disk/by-label/games";
    fsType = "btrfs";
    options = [
      "defaults"
      "noatime"
      "nodiratime"
      "compress=zstd"
      "discard=async"
      "subvol=@games"
    ];
  };

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
    v4l-utils # cec-ctl: HDMI-CEC control (TV power/input over /dev/cec0)

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
    inputs.agenix.packages."${stdenv.hostPlatform.system}".default
    age-plugin-fido2-hmac
    inputs.submerger.packages."${stdenv.hostPlatform.system}".default
  ];

  system.stateVersion = "24.05";
}
