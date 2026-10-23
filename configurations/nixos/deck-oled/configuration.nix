{
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

  age.identityPaths = ["${secretDir}/deck-oled" "${secretDir}/age_ed25519"];

  kirk = {
    locale.enable = true;
    hardening.enable = true;
    blockedHosts = {
      enable = true;
      file = ../../../age/shared/blocked-hosts.age;
    };
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
    keyboardLayout.enable = true;
    remoteBuilds.client = {
      enable = true;
      sshKey = "${secretDir}/deck-oled";
      prebuilt.enable = true;
    };
  };

  services.udev.packages = [pkgs.ledger-udev-rules];
  services.tailscale.enable = true;

  networking.hostName = "deck-oled";
  networking.networkmanager.enable = true;

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

  users.mutableUsers = false;
  users.allowNoPasswordLogin = true;
  users.users.user = {
    isNormalUser = true;
    hashedPassword = "!";
    description = "Rasmus Kirk";
    extraGroups = ["networkmanager" "wheel"];
  };

  nixpkgs.config.allowUnfree = true;

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
