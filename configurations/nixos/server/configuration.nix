{
  inputs,
  config,
  pkgs,
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
      user.file = ./age/user.age;
      domain.file = ./age/domain.age;
      njalla.file = ./age/njalla.age;
    };
  };

  # -------------------- Kirk Modules -------------------- #

  kirk.nixosScripts = {
    enable = true;
    configDir = configDir;
    machine = machine;
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

    ddns.njalla = {
      enable = true;
      keysFile = config.age.secrets.njalla.path;
    };

    jellyfin = {
      enable = true;
      expose.https = {
        enable = true;
        domainName = builtins.readFile config.age.secrets.domain.path;
        acmeMail = "slimness_bullish683@simplelogin.com";
      };
    };

    transmission = {
      enable = true;
      package = inputs.nixpkgs-2405.legacyPackages.${pkgs.system}.transmission_4;
      vpn.enable = true;
      peerPort = transmissionPort;
    };

    sonarr.enable = true;
    bazarr.enable = true;
    radarr.enable = true;
    lidarr.enable = true;
    prowlarr.enable = true;
  };

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
  services.logind.lidSwitch = "ignore"; # Ignore laptop lid closing

  # -------------------- Syncthing -------------------- #

  services = {
    syncthing = {
      enable = true;
      configDir = "${stateDir}/syncthing";
      dataDir = "${dataDir}/sync";
      guiAddress = "127.0.0.1:7000";
      overrideDevices = false;
      overrideFolders = false;
    };
    openssh = {
      enable = true;
      openFirewall = true;
      settings.PasswordAuthentication = false;
      ports = [6000];
    };
  };
  users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
    ../../../pubkeys/work.pub
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
      experimental-features = [ "nix-command" "flakes" ];
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

  # Enable sound with pipewire.
  # services.pulseaudio.enable = false;
  # security.rtkit.enable = true;
  # services.pipewire = {
  #   enable = true;
  #   alsa.enable = true;
  #   alsa.support32Bit = true;
  #   pulse.enable = true;
  # };

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
    # nameservers = [ "1.1.1.1" "1.1.1.2" ];
  };

  programs.zsh.enable = true;

  security.sudo = {
    execWheelOnly = true; # For security
    # For insults lol
    package = pkgs.sudo.override {withInsults = true;};
    extraConfig = "Defaults insults";
  };

  fileSystems."/data/media" = {
    device = "/dev/disk/by-label/media";
    fsType = "ext4";
    options = ["noatime"];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    # Compression
    zip
    unar
    unzip
    p7zip

    # Terminal programs
    iotop
    tuptime # Uptime doesn't work lol
    git
    smartmontools
    fzf
    ffmpeg
    nmap
    trash-cli
    wget

    # Agenix
    inputs.agenix.packages."${system}".default
  ];

  system.stateVersion = "24.05";
}
