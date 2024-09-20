{ inputs, config, pkgs, ... }:
let
  # This is dumb, but it works. Nix caches failures so changing this unbound
  # variable to anything else forces a rebuild
  force-rebuild = 0;
  machine = "pi";
  username = "user";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  secretDir = "${dataDir}/.secret";
  stateDir = "${dataDir}/.state";

  vpntestPort = 24745;
  xmrP2PPort = 8001; # 24746;
  xmrRpcPort = 8000; # 24747;
  transmissionPort = 33915;
in {
  # Load secrets
  age = {
    identityPaths = [ "${secretDir}/pi/ssh/id_ed25519" ];
    secrets = {
      "airvpn-wg.conf".file = ./age/airvpn-wg.conf.age;
      wifi.file = ./age/wifi.age;
      user.file = ./age/user.age;
      domain.file = ./age/domain.age;
      njalla.file = ./age/njalla.age;
      njalla-vpn.file = ./age/njalla-vpn.age;
    };
  };

  # Load kirk modules
  kirk.nixosScripts = {
    enable = true;
    configDir = configDir;
    machine = "pi";
  };

  nixarr = {
    enable = true;
    mediaUsers = [ username ];

    vpn = {
      enable = true;
      vpnTestService = {
        enable = true;
        #port = vpntestPort;
      };
      wgConf = config.age.secrets."airvpn-wg.conf".path;
    };

    ddns.njalla = {
      enable = true;
      keysFile = config.age.secrets.njalla.path;
      vpn = {
        enable = true;
        keysFile = config.age.secrets.njalla-vpn.path;
      };
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
      flood.enable = true;
      extraSettings = {
        download-queue-enabled = true;
        download-queue-size = 3;
      };
      privateTrackers = {
        cross-seed = {
          enable = false;
          indexIds = [
            3  # DB
            10 # AB
          ];
        };
      };
    };

    sonarr.enable = true;
    bazarr.enable = true;
    radarr.enable = true;
    prowlarr.enable = true;
  };

  # Forces full colors in terminal over SSH
  environment.variables = {
    COLORTERM = "truecolor";
    TERM = "xterm-256color";
  };

  hardware.raspberry-pi."4" = {
    # disable LEDS
    leds = {
      #eth.disable = true;
      #act.disable = true;
      #pwr.disable = true;
    };
    # Enable some HW-acceleration, idk
    fkms-3d.enable = true;
  };

  # If the system runs out of ram, then journald crashes and the server will be down
  # This should force systemd to restart, no matter what.
  systemd.services.systemd-journald.unitConfig.StartLimitIntervalSec = 0;

  # Setup swap ram for stability
  swapDevices = [ {
     device = "/var/lib/swapfile";
     size = 6*1024;
  } ];

  services = {
    syncthing = {
      enable = true;
      configDir = "${stateDir}/syncthing";
      dataDir = "${dataDir}/sync";
      guiAddress = "127.0.0.1:7000";
      overrideDevices = false;
      overrideFolders = false;
    };

    monero = {
      enable = false;
      dataDir = "${dataDir}/monero";
      extraConfig = ''
        p2p-bind-ip=0.0.0.0
        p2p-bind-port=${builtins.toString xmrP2PPort}

        rpc-restricted-bind-ip=0.0.0.0
        rpc-restricted-bind-port=${builtins.toString xmrRpcPort}

        # Disable UPnP port mapping
        no-igd=1

        # Public-node
        public-node=1

        # ZMQ configuration
        no-zmq=1

        # Block known-malicious nodes from a DNSBL
        enable-dns-blocklist=1
      '';
    };
  };

  networking = {
    nameservers = [ 
      # "91.239.100.100" # Uncensored DNS
      # "1.1.1.2" # Cloudflare
    ];
    hostName = machine;
    firewall.allowedTCPPorts = [
      xmrP2PPort
      xmrRpcPort
    ];
    wireless = {
      enable = true;
      environmentFile = config.age.secrets.wifi.path;
      networks = {
        "dd-wrt" = { psk = "@HOME@"; };
      };
    };
  };

  users = {
    mutableUsers = false;
    users.git = {
      isNormalUser = true;
      hashedPasswordFile = config.age.secrets.user.path;
      group = "git";
      home = "${stateDir}/git";
    };
    users."${username}" = {
      shell = pkgs.zsh;
      isNormalUser = true;
      hashedPasswordFile = config.age.secrets.user.path;
      extraGroups = [ "wheel" ];
    };
    groups.git = {};
  };

  systemd.tmpfiles.rules = [
    # Media dirs
    "d /data/git 0700 git git - -"
  ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    ports = [ 6000 ];
  };
  users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
    ./pubkeys/work.pub
  ];
  users.extraUsers.git.openssh.authorizedKeys.keyFiles = [
    ./pubkeys/work.pub
    ./pubkeys/pi.pub
  ];

  # Autologin
  services.getty.autologinUser = username;

  # Set zsh as default shell
  programs.zsh.enable = true;

  # Good default nix options to have
  nix = {
    settings.auto-optimise-store = true;
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
      min-free = ${toString (100 * 1024 * 1024)}
      max-free = ${toString (1024 * 1024 * 1024)}
    '';
  };

  security.sudo = {
    # For security
    execWheelOnly = true;
    # For insults lol
    package = pkgs.sudo.override { withInsults = true; };
    extraConfig = ''
      Defaults insults
    '';
  };

  # Assuming this is installed on top of the disk image.
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
    "/data/media" = {
      device = "/dev/disk/by-label/media";
      fsType = "ext4";
      options = [ "noatime" ];
    };
  };

  # Force reboot on kernel panics
  boot.kernelParams = [
    "panic=10"             # Reboot after 10 seconds of kernel panic
    "panic_on_oops=1"      # Reboot on any kernel oops (optional)
  ];

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
    inputs.agenix.packages."${system}".default
  ];

  nixpkgs.config.allowUnfree = true;

  powerManagement.cpuFreqGovernor = "ondemand";

  system.stateVersion = "20.09";
}

