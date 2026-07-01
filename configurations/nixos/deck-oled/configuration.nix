# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
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
      # user.file = ./age/user.age;
      hosts.file = ./age/hosts.age;
      "wg.conf".file = ./age/wg.conf.age;
    };
  };

  vpnNamespaces.wg = {
    enable = true;
    wireguardConfigFile = config.age.secrets."wg.conf".path;
    accessibleFrom = [
      "192.168.1.0/24"
      # "192.168.0.0/24"
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

  # Add systemd service to VPN network namespace
  systemd.services.transmission.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  services.transmission = {
    enable = true;
    package = inputs.nixpkgs-2405.legacyPackages.${pkgs.system}.transmission_4;
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
    # ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/*", RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
    extraRules = ''
      ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/*", RUN+="${pkgs.systemd}/bin/systemctl sleep"
      ACTION=="add", SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/*", ATTR{power/wakeup}="enabled"
    '';
  };

  # Enable networking
  networking.hostName = "deck-oled"; # Define your hostname.
  networking.networkmanager.enable = true;
  networking.extraHosts = builtins.readFile config.age.secrets.hosts.path;

  # Set your time zone.
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

  # Enable the X11 windowing system.
  # TODO: Why???
  services.xserver.enable = true;

  # Enable the Cosmic Desktop Environment.
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

  # Custom klfc keyboard layout (kirk.keyboardLayout module).
  kirk.keyboardLayout = {
    enable = true;
    package = inputs.keyboard-layout.packages.${pkgs.system}.rk;
  };

  # -------------------- Remote builder (client) -------------------- #
  # Offload builds to the desktop (nixremote@desktop, SSH port 6000). Fill in
  # the two commented values in the ssh block, then rebuild. Until then nix just
  # falls back to building locally, so this is safe to leave half-configured.
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
  programs.ssh.knownHosts."desktop-builder".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEpERjcyDtvKx2UV9K2ErAX+60xr83yQjqOjlnGL9O29 root@desktop";
  programs.ssh.extraConfig = ''
    Host desktop-builder
      HostKeyAlias desktop-builder
      Port 6000
      User nixremote
      # FILL IN: the desktop's reachable address (your DDNS domain for WAN, or a
      # LAN IP/hostname). Left out of the repo since the domain is an agenix secret.
      # HostName your-builder-address
      # FILL IN: this machine's private key for offload auth. NOTE: pubkeys/
      # deck-oled.pub (authorized on the desktop) is a YubiKey-backed sk- key, so
      # an unattended nix-daemon can't use it (blocks on a touch). Point this at a
      # NON-sk key and authorize that key's pub on the desktop instead.
      # IdentityFile /path/to/deck-private-key
  '';

  security.pam.services = {
    login.u2fAuth = true;
    sudo.u2fAuth = true;
    cosmic-greeter.u2fAuth = true;
    cosmic-greeter.unixAuth = false;
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.user = {
    isNormalUser = true;
    description = "Rasmus Kirk";
    extraGroups = ["networkmanager" "wheel"];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  security.sudo = {
    execWheelOnly = true; # For security
    package = pkgs.sudo.override {withInsults = true;}; # For insults lol
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

    inputs.agenix.packages."${system}".default
  ];

  system.stateVersion = "25.11"; # Did you read the comment?
}
