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
  };

  age = {
    identityPaths = ["${secretDir}/ssh/age_ed25519"];
    secrets = {
      hosts.file = ./age/hosts.age;
    };
  };

  services.udev.extraRules = ''
    ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="1050/*", RUN+="${pkgs.writeShellScript "yubikey-lock-on-unplug" ''
      if ${pkgs.usbutils}/bin/lsusb -d 17ef:6047 > /dev/null; then
        ${pkgs.systemd}/bin/loginctl lock-sessions
      fi
    ''}"

    # Stop the lid switch from waking the laptop. The lid uses a Hall-effect
    # (magnetic) sensor; magnetic objects placed on the closed laptop (e.g. an
    # Onyx Boox cover) can flicker the sensor and cause spurious wake-ups.
    # Trade-off: opening the lid no longer auto-wakes — press a key instead.
    ACTION=="add", SUBSYSTEM=="platform", KERNEL=="PNP0C0D:00", ATTR{power/wakeup}="disabled"

    # Yubico FIDO HID: persistent group-based access (mode 0660, group yubikey).
    # The default systemd-logind uaccess mechanism uses ACLs whose mask doesn't
    # carry correctly into bwrap's user namespace (open() fails with EACCES
    # inside the box). Group-based perms bypass ACLs and work everywhere.
    # Security: still gated by physical YubiKey touch for any signing op.
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050", MODE="0660", GROUP="yubikey"
  '';

  programs.steam.enable = true;
  programs.steam.extraPackages = [pkgs.hidapi];
  hardware.steam-hardware.enable = true;
  programs.nh.enable = true;

  # Enable networking
  networking.hostName = machine;
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

  # Lenovo + MediaTek MT7925: the BT half of the chip enters a state during
  # suspend that no runtime reset (USB authorized cycle, PCIe remove+rescan,
  # module reload) can clear — only a full reboot recovers it. Workaround:
  # detach the btusb driver before the chip sleeps so it isn't stuck in
  # mid-transaction at resume time, then reload on wake.
  # If BT is still broken after this (rare boot-time failure), only reboot
  # helps — no userland recovery script exists for that case.
  powerManagement = {
    powerDownCommands = ''
      ${pkgs.kmod}/bin/modprobe -r btusb || true
    '';
    resumeCommands = ''
      ${pkgs.kmod}/bin/modprobe btusb || true
    '';
  };

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
      # FILL IN: this machine's private key whose public half is pubkeys/work.pub
      # (authorized on the desktop's nixremote user). Read by nix-daemon as root.
      # IdentityFile /path/to/work-private-key
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

  security.pam.u2f.settings.cue = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
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
    execWheelOnly = true; # For security
    package = pkgs.sudo.override {withInsults = true;}; # For insults lol
    extraConfig = ''
      Defaults insults
      Defaults timestamp_timeout=0
    '';
  };

  environment.systemPackages = with pkgs; [
    # Misc
    keepassxc
    yubioath-flutter
    claude-code
    poppler-utils
    usbutils
    pciutils
    sshfs
    python3
    gptfdisk
    dig
    finamp
    spotify

    # Browsers
    chromium

    # Chat
    signal-desktop

    # Misc Terminal Tools
    wl-clipboard
    wtype
    yt-dlp

    inputs.agenix.packages."${system}".default
  ];

  environment.etc."systemd/system-sleep/unlock-after-hibernate" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      if [ "$1" = "post" ] && [ "$2" = "hibernate" ]; then
        ${pkgs.systemd}/bin/loginctl unlock-sessions
      fi
    '';
  };

  system.stateVersion = "25.11"; # Did you read the comment?
}
