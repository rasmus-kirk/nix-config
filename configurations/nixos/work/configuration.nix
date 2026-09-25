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

  kirk.nixosScripts = {
    enable = true;
    configDir = configDir;
    stateDir = stateDir;
    machine = machine;
    pure = true;
  };

  kirk.hardening.enable = true;
  kirk.devUser.enable = true;
  kirk.keyboardLayout = {
    enable = true;
    package = inputs.keyboard-layout.packages.${pkgs.stdenv.hostPlatform.system}.rk;
  };

  services.udev.extraRules = ''
    # YubiKey FIDO interface, group-owned so the yubikey group can open it.
    # systemd's uaccess ACLs this device to whoever holds the active seat
    # session (user), which leaves dev — in the group precisely so it can use
    # the sk-ssh key — holding a key handle it cannot talk to, so both signing
    # and SSH auth fail for it. Using the key still needs a physical touch and
    # the matching handle; this only decides who may open the device node.
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050", GROUP="yubikey", MODE="0660"

    ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/*", RUN+="${pkgs.writeShellScript "yubikey-lock-on-unplug" ''
      if ${pkgs.usbutils}/bin/lsusb -d 17ef:6047 > /dev/null; then
        ${pkgs.systemd}/bin/loginctl lock-sessions
      fi
    ''}"
  '';

  programs.steam.enable = true;
  programs.steam.extraPackages = [pkgs.hidapi];
  hardware.steam-hardware.enable = true;

  # Enable networking
  networking.hostName = machine;
  networking.networkmanager.enable = true;
  networking.extraHosts = "";

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
  services.xserver.enable = true;

  # Enable the Cosmic Desktop Environment.
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  services.gnome.gnome-keyring.enable = false;
  services.gnome.gcr-ssh-agent.enable = false;
  services.displayManager.autoLogin = {
    enable = true;
    user = "user";
  };
  services.logind.settings.Login.HandleLidSwitch = "ignore";

  services.hardware.bolt.enable = true;
  services.fwupd.enable = true;

  hardware.enableRedistributableFirmware = true;

  hardware.graphics.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  programs.ssh.startAgent = true;
  programs.ssh.askPassword = "";
  environment.variables.SSH_ASKPASS = "";

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
    # root-owned: ssh rejects an Include owned by neither root nor the caller.
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
    # Useless without the physical YubiKey, so duplicating it costs nothing.
    "d /home/dev/.ssh                        0700 dev dev -"
    "C /home/dev/.ssh/id_ed25519_yubi        0600 dev dev - ${secretDir}/ssh/id_ed25519_yubi"
    "C /home/dev/.ssh/id_ed25519_yubi.pub    0644 dev dev - ${secretDir}/ssh/id_ed25519_yubi.pub"
  ];

  programs.ssh.extraConfig = ''
    Include ${stateDir}/ssh/root-remotes/*.conf
  '';

  services.fprintd.enable = true;

  security.pam.services = {
    login.u2fAuth = true;
    login.fprintAuth = true;
    sudo.u2fAuth = true;
    sudo.fprintAuth = true;
    cosmic-greeter.u2fAuth = true;
    cosmic-greeter.fprintAuth = false;
    cosmic-greeter.unixAuth = false;
  };

  security.pam.u2f.settings = {
    cue = true;
    authfile = "${secretDir}/ssh/id_ed25519_yubi";
    sshformat = true;
    origin = "ssh:rasmus";
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Dedicated group for YubiKey hidraw access (see services.udev.extraRules).
  users.groups.yubikey = {};

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.user = {
    isNormalUser = true;
    description = "Rasmus Kirk";
    extraGroups = ["networkmanager" "wheel" "yubikey"];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  security.sudo = {
    package = pkgs.sudo.override {withInsults = true;}; # For insults lol
    extraConfig = ''
      Defaults insults
    '';
  };

  environment.systemPackages = with pkgs; [
    # Misc
    yubioath-flutter
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

    # Browsers
    chromium

    # Chat
    signal-desktop

    # Misc Terminal Tools
    wl-clipboard
    wtype
    yt-dlp

    inputs.agenix.packages."${stdenv.hostPlatform.system}".default
  ];

  system.stateVersion = "25.11"; # Did you read the comment?
}
