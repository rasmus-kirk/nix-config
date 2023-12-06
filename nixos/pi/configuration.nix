{ config, pkgs, ... }:
let
  force-rebuild = 0;
  username = "user";
  secretDir = "/data/.secret";
in {
  imports = [
    ./servarr.nix
  ];

  # Forces full colors in terminal over SSH
  environment.variables = {
    COLORTERM = "truecolor";
    TERM = "xterm-256color";
  };

  hardware.raspberry-pi."4".fkms-3d.enable = true;
  age = {
    identityPaths = [ "${secretDir}/pi/ssh/id_ed25519" ];
    secrets = {
      wifi.file = ./age/wifi.age;
      user.file = ./age/user.age;
      mullvad.file = ./age/mullvad.age;
    };
  };

  networking = {
    hostName = "pi";
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

  services.getty.autologinUser = username;

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
  ];

	nixpkgs.config.allowUnfree = true;

	powerManagement.cpuFreqGovernor = "ondemand";

	system.stateVersion = "20.09";
}

