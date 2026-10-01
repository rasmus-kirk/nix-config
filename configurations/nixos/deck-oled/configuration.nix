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
    identityPaths = ["${secretDir}/ssh/deck-oled" "${secretDir}/ssh/age_ed25519"];
    secrets = {
      hosts.file = ./age/hosts.age;
      "wg.conf".file = ./age/wg.conf.age;
    };
  };

  kirk = {
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = "deck-oled";
      extraNixOptions = true;
    };
    yubikey = {
      enable = true;
      lockOnUnplug = true;
      sshAgent = true;
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

  services.udev.packages = [pkgs.ledger-udev-rules];

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

  # TODO: find out why this is needed.
  services.xserver.enable = true;

  services.desktopManager.cosmic.enable = true;

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
      sshKey = "${secretDir}/ssh/deck-oled";
      systems = ["x86_64-linux"];
      protocol = "ssh-ng";
      maxJobs = 8;
      speedFactor = 2;
      supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
    }
  ];
  programs.ssh.knownHosts."desktop-builder".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEpERjcyDtvKx2UV9K2ErAX+60xr83yQjqOjlnGL9O29 root@desktop";
  # TODO Add HostName. Auto-upgrades skip until then.
  programs.ssh.extraConfig = ''
    Host desktop-builder
      HostKeyAlias desktop-builder
      Port 6000
      User nixremote
  '';

  system.autoUpgrade = {
    enable = true;
    flake = "github:rasmus-kirk/nix-config#deck-oled";
    flags = ["--impure" "--refresh" "--option" "max-jobs" "0"];
    operation = "boot";
    dates = "daily";
    persistent = true;
  };
  systemd.services.nixos-upgrade.serviceConfig.ExecCondition =
    "${config.nix.package}/bin/nix store info --store ssh-ng://desktop-builder";

  systemd.tmpfiles.rules = [
    "d ${stateDir}                 0700 user users -"
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
    age-plugin-fido2-hmac
  ];

  system.stateVersion = "25.11";
}
