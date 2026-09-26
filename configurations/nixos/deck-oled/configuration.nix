{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  stateDir = "${dataDir}/.state";
  secretDir = "${dataDir}/.secret";
in {
  imports = [./hardware-configuration.nix];

  age = {
    identityPaths = ["${secretDir}/ssh/age_ed25519"];
    secrets = {
      hosts.file = ./age/hosts.age;
      "wg.conf".file = ./age/wg.conf.age;
    };
  };

  vpnNamespaces.wg = {
    enable = true;
    wireguardConfigFile = config.age.secrets."wg.conf".path;
    accessibleFrom = [
      "192.168.1.0/24"
      "127.0.0.1"
    ];
    portMappings = [
      {
        from = 9091;
        to = 9091;
      }
    ];
    openVPNPorts = [
      {
        port = 24745;
        protocol = "both";
      }
    ];
  };

  systemd.services.transmission.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  services.transmission = {
    enable = true;
    package = inputs.nixpkgs-2405.legacyPackages.${pkgs.stdenv.hostPlatform.system}.transmission_4;
    openPeerPorts = true;
    user = "user";
    settings = {
      peer-port = 24745;
      download-dir = "/data/downloads/torrents";
      rpc-bind-address = "192.168.15.1";
      rpc-whitelist-enabled = false;
    };
  };

  kirk.nixosScripts = {
    enable = true;
    configDir = configDir;
    stateDir = stateDir;
    machine = "deck-oled";
  };

  services.udev = {
    packages = [pkgs.ledger-udev-rules];
    extraRules = ''
      ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/*", RUN+="${pkgs.systemd}/bin/systemctl sleep"
      ACTION=="add", SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/*", ATTR{power/wakeup}="enabled"
    '';
  };

  networking.hostName = "deck-oled";
  networking.networkmanager.enable = true;
  networking.extraHosts = builtins.readFile config.age.secrets.hosts.path;

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

  nix = {
    package = pkgs.nixVersions.latest;
    settings = {
      experimental-features = ["nix-command" "flakes"];
      download-buffer-size = 500000000; # 500 MB
      # 0 uses all available cores.
      cores = 0;
      show-trace = true;
    };
    # Make `nix shell nixpkgs#package` use the same pinned nixpkgs as the system.
    registry.nixpkgs = {
      from = {
        id = "nixpkgs";
        type = "indirect";
      };
      flake = inputs.nixpkgs;
    };
  };

  # TODO: find out why this is needed.
  services.xserver.enable = true;

  services.desktopManager.cosmic.enable = true;
  services.gnome.gnome-keyring.enable = false;
  services.gnome.gcr-ssh-agent.enable = false;

  jovian = {
    devices.steamdeck.enable = true;
    steamos.useSteamOSConfig = true;
    steam = {
      enable = true;
      autoStart = true;
      desktopSession = "cosmic";
      user = "user";
    };
    hardware.has.amd.gpu = true;
  };
  hardware.enableRedistributableFirmware = true;

  programs.ssh.startAgent = true;
  environment.variables.SSH_ASKPASS = "";

  programs.ssh.askPassword = "";
  programs.firefox.enable = true;

  kirk.keyboardLayout = {
    enable = true;
    package = inputs.keyboard-layout.packages.${pkgs.stdenv.hostPlatform.system}.rk;
  };

  # Offload builds to the desktop. Nix builds locally until the ssh block has a HostName
  # and an IdentityFile for a non-sk key, because nix-daemon cannot wait for a YubiKey touch.
  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "desktop-builder"; # SSH alias, configured below
      sshUser = "nixremote";
      systems = ["x86_64-linux"];
      protocol = "ssh-ng";
      maxJobs = 8;
      speedFactor = 2;
      supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
    }
  ];
  programs.ssh.knownHosts."desktop-builder".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEpERjcyDtvKx2UV9K2ErAX+60xr83yQjqOjlnGL9O29 root@desktop";
  programs.ssh.extraConfig = ''
    Host desktop-builder
      HostKeyAlias desktop-builder
      Port 6000
      User nixremote
  '';

  security.pam.services = {
    login.u2fAuth = true;
    sudo.u2fAuth = true;
    cosmic-greeter.u2fAuth = true;
    cosmic-greeter.unixAuth = false;
  };

  security.pam.u2f.settings = {
    authfile = "${secretDir}/ssh/id_ed25519_yubi";
    sshformat = true;
    origin = "ssh:rasmus";
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir}                 0700 user users -"
    "d ${stateDir}/thunderbird     0755 user users -"
    "d ${stateDir}/cosmic          0755 user users -"
    "d ${stateDir}/cosmic/config   0755 user users -"
    "d ${stateDir}/cosmic/comp     0755 user users -"
    "d ${stateDir}/cosmic/local    0755 user users -"
    "d ${stateDir}/firefox         0755 user users -"
    "d ${stateDir}/firefox/config  0755 user users -"
    "d ${stateDir}/firefox/home    0755 user users -"
    "d ${stateDir}/chromium        0755 user users -"
    "d ${stateDir}/syncthing       0755 user users -"
    "d ${stateDir}/syncthing/state 0755 user users -"
    "d ${stateDir}/syncthing/sync  0755 user users -"
    "d ${stateDir}/claude          0755 user users -"
    "d ${stateDir}/claude/state    0755 user users -"
  ];

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users.user = {
    isNormalUser = true;
    description = "Rasmus Kirk";
    extraGroups = ["networkmanager" "wheel"];
  };

  nixpkgs.config.allowUnfree = true;

  security.sudo = {
    execWheelOnly = true;
    package = pkgs.sudo.override {withInsults = true;};
    extraConfig = ''
      Defaults insults
      Defaults timestamp_timeout=15
    '';
  };

  environment.systemPackages = with pkgs; [
    (writeShellApplication {
      name = "monero";
      runtimeInputs = [monero-cli coreutils];
      inheritPath = false;
      text = ''
        wallet_dir="/data/media/documents/wallets/monero/ledger"
        mkdir -p "$wallet_dir"
        cd "$wallet_dir"
        monero-wallet-cli \
          --wallet-file ./wallet.keys \
          --log-file ./wallet.log
      '';
    })

    # Misc
    keepassxc
    thunderbird
    feishin
    yubioath-flutter
    ledger-live-desktop
    claude-code

    # Browsers
    chromium

    # Chat
    signal-desktop

    # Misc Terminal Tools
    wl-clipboard
    yt-dlp

    inputs.agenix.packages."${stdenv.hostPlatform.system}".default
  ];

  system.stateVersion = "25.11";
}
