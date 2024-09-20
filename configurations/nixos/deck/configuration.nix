{ inputs, config, pkgs, ... }:
let
  # This is dumb, but it works. Nix caches failures so changing this unbound
  # variable to anything else forces a rebuild
  force-rebuild = 0;
  username = "user";
  machine = "deck";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  secretDir = "${dataDir}/.secret";
  stateDir = "${dataDir}/.state";
in {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Load secrets
  age = {
    identityPaths = [ "${secretDir}/deck/ssh/id_ed25519" ];
    secrets = {
      user.file = ./age/user.age;
    };
  };

  # Load kirk modules
  kirk = {
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
    };
  };

  jovian = {
    steam = {
      enable = true;
      user = username;
      autoStart = true;
      desktopSession = "gnome";
    };
    decky-loader = {
      enable = false;
      stateDir = "${stateDir}/decky";
      extraPythonPackages = [];
      extraPackages = [];
    };
    devices.steamdeck.enable = true;
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = machine;
  networking.networkmanager.enable = true;

  services.syncthing = {
    enable = true;
    configDir = "${stateDir}/syncthing";
    dataDir = "${dataDir}/sync";
    guiAddress = "127.0.0.1:7000";
  };

  users = {
    mutableUsers = false;
    users."${username}" = {
      shell = pkgs.zsh;
      isNormalUser = true;
      password = "test";
      #hashedPasswordFile = config.age.secrets.user.path;
      extraGroups = [ "networkmanager" "wheel" ];
    };
  };

  #services.xserver = {
  #  enable = true;
  #  displayManager.enable = true;
  #  desktopManager.gnome.enable = true;
  #};

  #services.openssh = {
  #  enable = true;
  #  openFirewall = true;
  #  settings.PasswordAuthentication = false;
  #  ports = [ 6000 ];
  #};
  #users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
  #  "${./pubkeys/work.pub}"
  #  "${./pubkeys/laptop.pub}"
  #  "${./pubkeys/steam-deck.pub}"
  #];

  # Autologin

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Set zsh as default shell
  programs.zsh.enable = true;

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

  # Configure keymap in X11
  services.xserver = {
    enable = true;
    layout = "us";
    xkbVariant = "";
    displayManager = {
      gdm.enable = false;
      autoLogin.enable = true;
      autoLogin.user = "user";
    };
    desktopManager.gnome.enable = true;
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  nix = {
    settings.auto-optimise-store = true;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    package = pkgs.nixUnstable;
    extraOptions = ''
      experimental-features = nix-command flakes
      min-free = ${toString (100 * 1024 * 1024)}
      max-free = ${toString (1024 * 1024 * 1024)}
    '';
  };

  environment.systemPackages = with pkgs; [
    # Compression
    zip
    unar
    unzip
    p7zip
    # Terminal programs
    git
    wget
    inputs.agenix.packages."${system}".default
  ];

  nixpkgs.config.allowUnfree = true;

  powerManagement.cpuFreqGovernor = "ondemand";

  system.stateVersion = "23.11";
}
