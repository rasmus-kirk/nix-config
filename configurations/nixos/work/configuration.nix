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

  age.identityPaths = ["${secretDir}/ssh/${machine}"];

  kirk = {
    locale.enable = true;
    blockedHosts = {
      enable = true;
      file = ../../../age/shared/blocked-hosts.age;
    };
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
      extraNixOptions = true;
      remotes.desktop = {
        host = "desktop-builder";
        sshKey = "${secretDir}/ssh/${machine}";
      };
    };
    hardening.enable = true;
    devUser.enable = true;
    tokens = {
      user = ["CLAUDE_CODE_OAUTH_TOKEN" "GH_TOKEN" "LINEAR_API_KEY" "NOTION_TOKEN"];
      dev = ["CLAUDE_CODE_OAUTH_TOKEN" "GH_TOKEN" "LINEAR_API_KEY" "NOTION_TOKEN"];
    };
    yubikey = {
      enable = true;
      lockOnUnplug = true;
      lockOnlyWithDevices = ["17ef:6047"];
      sshAgent = true;
    };
    keyboardLayout.enable = true;
    remoteBuilds.client = {
      enable = true;
      sshKey = "${secretDir}/ssh/${machine}";
      signingKeyFile = ../../../age/work/nix-signing-key.age;
    };
  };

  programs.steam.enable = true;
  programs.steam.extraPackages = [pkgs.hidapi];
  hardware.steam-hardware.enable = true;

  networking.hostName = machine;
  networking.networkmanager.enable = true;

  services.xserver.enable = true;

  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "user";
  };

  services.logind.settings.Login.HandleLidSwitch = "ignore";
  services.fwupd.enable = true;
  services.tailscale.enable = true;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  programs.firefox.enable = true;

  systemd.tmpfiles.rules = [
    "d ${dataDir}                            0700 user users -"
    "d ${configDir}                          0700 user users -"
    "d ${secretDir}                          0700 user users -"
    "d ${secretDir}/ssh                      0700 user users -"
    "z ${secretDir}/ssh/${machine}           0400 root root  -"
    "d ${dataDir}/downloads                  0700 user users -"
    "d ${dataDir}/media                      0700 user users -"
    "d ${dataDir}/media/images/screenshots   0700 user users -"

    "d ${stateDir}                           0700 user users -"
    "d ${stateDir}/ssh                       0700 user users -"
    "d ${stateDir}/firefox                   0755 user users -"
    "d ${stateDir}/firefox/config            0755 user users -"
    "d ${stateDir}/firefox/home              0755 user users -"
    "d ${stateDir}/chromium                  0755 user users -"
    "d ${stateDir}/cosmic                    0755 user users -"
    "d ${stateDir}/cosmic/comp               0755 user users -"
    "d ${stateDir}/cosmic/local              0755 user users -"
    "d ${stateDir}/claude                    0755 user users -"
    "d ${stateDir}/claude/state              0755 user users -"

    "d /home/user/.config                    0755 user users -"
    "d /home/user/.local                     0755 user users -"
    "d /home/user/.local/state               0755 user users -"
    "L+ /home/user/.mozilla                  - - - - ${stateDir}/firefox/home"
    "L+ /home/user/.config/mozilla           - - - - ${stateDir}/firefox/config"
    "L+ /home/user/.config/chromium          - - - - ${stateDir}/chromium"
    "L+ /home/user/.local/state/cosmic       - - - - ${stateDir}/cosmic/local"
    "L+ /home/user/.local/state/cosmic-comp  - - - - ${stateDir}/cosmic/comp"
    "L+ /home/user/.claude                   - - - - ${stateDir}/claude/state"
    "L+ /home/user/.claude.json              - - - - ${stateDir}/claude/claude.json"

    # dev cannot reach /data, so secrets are copied.
    "d  /run/dev-secret                          0550 root dev -"
    "d  /run/dev-secret/ssh                      0550 root dev -"
    "C+ /run/dev-secret/ssh/id_ed25519_yubi      0440 root dev - ${secretDir}/ssh/id_ed25519_yubi"
    "C+ /run/dev-secret/ssh/id_ed25519_yubi.pub  0444 root dev - ${secretDir}/ssh/id_ed25519_yubi.pub"
  ];

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  users.mutableUsers = false;
  users.allowNoPasswordLogin = true;
  users.users.user = {
    isNormalUser = true;
    hashedPassword = "!";
    description = "Rasmus Kirk";
    extraGroups = ["networkmanager" "wheel" "yubikey"];
  };

  nixpkgs.config.allowUnfree = true;

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
    age-plugin-fido2-hmac
  ];

  system.stateVersion = "25.11";
}
