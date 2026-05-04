{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  username = "user";
  machine = "server";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  secretDir = "${dataDir}/.secret";
  stateDir = "${dataDir}/.state";
  transmissionPort = 33915;
in {
  imports = [./hardware-configuration.nix];

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

  # MAM
  systemd = {
    # timers.mam = {
    #   timerConfig = {
    #     OnBootSec = "120"; # Run 30 seconds after system boot
    #     OnCalendar = "hourly";
    #     Persistent = true; # Run service immediately if last window was missed
    #     RandomizedDelaySec = "15min"; # Run service OnCalendar +- 5min
    #   };
    #   wantedBy = ["multi-user.target"];
    # };
    # services.mam.serviceConfig = {
    #   Environment = "PATH=${pkgs.curl}/bin:$PATH";
    #   ExecStart = "${pkgs.lib.getExe pkgs.bash} ${config.age.secrets.mam.path}";
    #   Type = "oneshot";
    # };

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

  # -------------------- Power Saving -------------------- #

  powerManagement.enable = true;
  powerManagement.powertop.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "power";
      # Disable wake-on-lan and bluetooth to save power
      WOL_DISABLE = "Y";
      DEVICES_TO_DISABLE_ON_STARTUP = "bluetooth wifi wwan"; 
    };
  };

  hardware.bluetooth.enable = false;
  hardware.bluetooth.powerOnBoot = false;

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

  services.getty.autologinUser = username; # Enable auto-login
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
      fileSystems = [ "/data" ];
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

  networking.firewall.allowedTCPPorts = [ 8384 ];

  users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
    ../../../pubkeys/deck-oled.pub
  ];

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

  # -------------------- Machine Specific -------------------- #

  users.mutableUsers = false;
  users.users."user" = {
    shell = pkgs.zsh;
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets.user.path;
    extraGroups = ["networkmanager" "wheel"];
  };

  hardware.graphics.enable = true; # Needed for sway to boot
  networking = {
    hostName = machine;
    networkmanager.enable = true;
  };

  programs.zsh.enable = true;

  # security.pam.services.sudo.u2fAuth = true;

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

  boot.initrd.kernelModules = [ "usb_storage" "uas" "sd_mod" ];
  boot.initrd.luks.devices = {
    crypt_ssd1 = {
      device = "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5SSNF0WA10922R";
      keyFile = "/dev/disk/by-id/usb-Generic-_SD_MMC_20120501030900000-0:0";
      keyFileSize = 34;
      allowDiscards = true; # Allows SSD trim commands for better performance
    };
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
      runtimeInputs = [ monero-cli coreutils ];
      inheritPath = false;
      text = ''
        wallet_dir="/data/monero"
        mkdir -p "$wallet_dir"
        monero-wallet-cli \
          --wallet-file "$wallet_dir"/user.keys \
          --log-file "$wallet_dir"/log.log
      '';
    })

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
