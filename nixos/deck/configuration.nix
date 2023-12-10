{ inputs, config, pkgs, ... }:
let
  # This is dumb, but it works. Nix caches failures so changing this unbound
  # variable to anything else forces a rebuild
  force-rebuild = 0;
  username = "user";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  secretDir = "${dataDir}/.secret";
  stateDir = "${dataDir}/.state";
in {
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
      machine = "deck";
    };
  };

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
      extraGroups = [ "wheel" ];
    };
  };

  services.xserver = {
    enable = true;
    displayManager.enable = true;
    desktopManager.gnome.enable = true;
  };

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
  services.getty.autologinUser = username;

  # Set zsh as default shell
  programs.zsh.enable = true;

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

  system.stateVersion = "20.09";
}

