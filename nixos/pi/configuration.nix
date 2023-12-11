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
in {
  # Load secrets
  age = {
    identityPaths = [ "${secretDir}/pi/ssh/id_ed25519" ];
    secrets = {
      wifi.file = ./age/wifi.age;
      user.file = ./age/user.age;
      mullvad.file = ./age/mullvad.age;
      domain.file = ./age/domain.age;
    };
  };

  # Load kirk modules
  kirk = {
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = "pi";
    };
    servarr = {
      enable = true;
      domainName = builtins.readFile config.age.secrets.domain.path;
      acmeMail = "slimness_bullish683@simplelogin.com";
      mullvadAcc = config.age.secrets.mullvad.path;
      mediaDir = "${dataDir}/media";
      stateDir = stateDir;

      rflood.ulimits = {
        enable = true;
        hard = 1024;
        soft = 1024;
      };
    };
  };

  # Forces full colors in terminal over SSH
  environment.variables = {
    COLORTERM = "truecolor";
    TERM = "xterm-256color";
  };

  # Enable some HW-acceleration, idk
  hardware.raspberry-pi."4".fkms-3d.enable = true;

  services.syncthing = {
    enable = true;
    configDir = "${stateDir}/syncthing";
    dataDir = "${dataDir}/sync";
    guiAddress = "127.0.0.1:7000";
  };

  networking = {
    hostName = machine;
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
    users."${username}" = {
      shell = pkgs.zsh;
      isNormalUser = true;
      hashedPasswordFile = config.age.secrets.user.path;
      extraGroups = [ "wheel" "docker" ];
    };
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    ports = [ 6000 ];
  };
  users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
    "${./pubkeys/work.pub}"
    "${./pubkeys/laptop.pub}"
    "${./pubkeys/steam-deck.pub}"
  ];

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

  # Assuming this is installed on top of the disk image.
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
  };

  environment.systemPackages = with pkgs; [
    # Compression
    zip
    unar
    unzip
    p7zip
    # Terminal programs
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

