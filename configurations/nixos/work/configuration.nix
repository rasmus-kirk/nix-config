{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  machine = "work";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  stateDir = "${dataDir}/.state";
  secretDir = "${dataDir}/.secret";
in {
  imports = [./hardware-configuration.nix];

  kirk = {
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
      pure = true;
      extraNixOptions = true;
    };
    hardening.enable = true;
    devUser.enable = true;
    yubikey = {
      enable = true;
      lockOnUnplug = true;
      lockOnlyWithDevices = ["17ef:6047"];
      sshAgent = true;
    };
    keyboardLayout = {
      enable = true;
      package = inputs.keyboard-layout.packages.${pkgs.stdenv.hostPlatform.system}.rk;
    };
  };

  programs.steam.enable = true;
  programs.steam.extraPackages = [pkgs.hidapi];
  hardware.steam-hardware.enable = true;

  networking.hostName = machine;
  networking.networkmanager.enable = true;
  networking.extraHosts = "";

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

  services.xserver.enable = true;

  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "user";
  };

  services.logind.settings.Login.HandleLidSwitch = "ignore";
  services.fwupd.enable = true;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  programs.firefox.enable = true;

  # -------------------- Remote builder (client) -------------------- #
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

  systemd.tmpfiles.rules = [
    "d ${dataDir}                            0700 user users -"
    "d ${configDir}                          0700 user users -"
    "d ${secretDir}                          0700 user users -"
    "d ${secretDir}/ssh                      0700 user users -"
    "d ${dataDir}/downloads                  0700 user users -"
    "d ${dataDir}/media                      0700 user users -"
    "d ${dataDir}/media/images/screenshots   0700 user users -"

    "d ${stateDir}                           0700 user users -"
    "d ${stateDir}/ssh                       0700 user users -"
    "d ${stateDir}/ssh/root-remotes          0700 root root  -"
    "d ${stateDir}/ssh/remotes               0700 user users -"
    "d ${stateDir}/firefox                   0755 user users -"
    "d ${stateDir}/firefox/config            0755 user users -"
    "d ${stateDir}/firefox/home              0755 user users -"
    "d ${stateDir}/chromium                  0755 user users -"
    "d ${stateDir}/cosmic                    0755 user users -"
    "d ${stateDir}/cosmic/comp               0755 user users -"
    "d ${stateDir}/cosmic/local              0755 user users -"
    "d ${stateDir}/claude                    0755 user users -"
    "d ${stateDir}/claude/state              0755 user users -"

    # dev cannot reach /data, so the sk handle is copied into its own home.
    "d /home/dev/.ssh                        0700 dev dev -"
    "C /home/dev/.ssh/id_ed25519_yubi        0600 dev dev - ${secretDir}/ssh/id_ed25519_yubi"
    "C /home/dev/.ssh/id_ed25519_yubi.pub    0644 dev dev - ${secretDir}/ssh/id_ed25519_yubi.pub"
  ];

  programs.ssh.extraConfig = ''
    Include ${stateDir}/ssh/root-remotes/*.conf
  '';

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  users.users.user = {
    isNormalUser = true;
    description = "Rasmus Kirk";
    extraGroups = ["networkmanager" "wheel" "yubikey"];
  };

  nixpkgs.config.allowUnfree = true;

  security.sudo = {
    package = pkgs.sudo.override {withInsults = true;}; # For insults lol
    extraConfig = ''
      Defaults insults
    '';
  };

  environment.systemPackages = with pkgs; [
    usbutils
    pciutils
    sshfs
    python3
    gptfdisk
    dig
    finamp
    spotify
    scrcpy
    android-tools

    chromium

    signal-desktop

    wl-clipboard
    wtype
    yt-dlp

    inputs.agenix.packages."${stdenv.hostPlatform.system}".default
  ];

  system.stateVersion = "25.11";
}
