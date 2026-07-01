{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  username = "user";
  machine = "desktop";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  secretDir = "${dataDir}/.secret";
  stateDir = "${dataDir}/.state";
  transmissionPort = 33915;

  # Chromium-based non-Steam tiles run as launcher SCRIPTS, not raw `chromium` +
  # launch options, for two reasons that bite every Chromium/Electron app started
  # from Steam game mode:
  #   1. Steam's %command% expands to EMPTY for non-Steam shortcuts, so a
  #      launch-options command line loses its exe (/bin/sh then runs the first
  #      flag as a program). The args must live in the script.
  #   2. Steam injects its overlay via LD_PRELOAD=gameoverlayrenderer.so, which
  #      crashes Chromium's zygote/sandbox (SIGABRT in ZygoteHostImpl::
  #      LaunchZygote, gameoverlayrenderer.so frames on the stack); Steam then
  #      limps up only after retrying — the long startup. Unsetting LD_PRELOAD
  #      drops the overlay from chromium and its subprocesses and KEEPS the
  #      sandbox intact (unlike --no-sandbox). --ozone-platform=x11 uses
  #      gamescope's XWayland.
  mkChromiumTile = name: args:
    pkgs.writeShellScriptBin name ''
      unset LD_PRELOAD
      exec ${pkgs.chromium}/bin/chromium --ozone-platform=x11 ${args} "$@"
    '';
  # Jellyfin web UI: fullscreen kiosk on its own profile (independent instance,
  # never attaches to the plain Chromium tile).
  jellyfin-kiosk = mkChromiumTile "jellyfin-kiosk"
    "--user-data-dir=${stateDir}/user/jellyfin-web --app=http://localhost:8096 --kiosk --no-first-run --window-size=3840,2160 --force-device-scale-factor=2.0";
  # Per-person Chromium browser tiles, fullscreen + scaled for the 4K TV. Each
  # has its OWN --user-data-dir so each person gets their own logins/YouTube
  # account. Use --start-fullscreen, NOT --window-size: Chromium treats
  # --window-size as LOGICAL px and multiplies by the device scale, so
  # --window-size=3840,2160 + scale 2.0 makes a 7680x4320 window that gamescope
  # then downscales 0.5x to fit the output — cancelling the scale (looked 1x).
  # Fullscreen sizes the window to the output, so scale 2.0 renders cleanly (this
  # is why the --kiosk JF tile scaled fine and the windowed browser didn't).
  mkChromiumBrowser = name: profile:
    mkChromiumTile name
    "--user-data-dir=${stateDir}/user/${profile} --window-size=3840,2160 --start-fullscreen --force-device-scale-factor=2.0";
  chromium-rasmus = mkChromiumBrowser "chromium-rasmus" "chromium-rasmus";
  chromium-naja = mkChromiumBrowser "chromium-naja" "chromium-naja";

  # JFv3 — the new CEF/mpv Jellyfin Desktop client, wrapped from its prebuilt
  # nightly AppImage. nixpkgs only ships the old Qt 2.0.0 (broken by qtwebengine
  # 6.11.0, nixpkgs#519073), and v3 has no versioned release to package from
  # source. The nightly.link URL always serves "latest main", so this hash goes
  # stale whenever upstream CI rebuilds — when a rebuild fails on a hash
  # mismatch, refresh `version` + `hash`:
  #   nix-prefetch-url --print-path <url>
  #   nix hash convert --hash-algo sha256 --to sri <printed-hash>
  # Replace with a clean appimageTools wrap of a tagged release once upstream
  # cuts one with stable asset URLs.
  # DISABLED — switched to the old Qt5 jellyfin-media-player (nixpkgs-2405, see
  # systemPackages). Uncomment this block AND its systemPackages line to switch
  # back to JFv3.
  # jellyfinDesktopV3 = let
  #   version = "3.0.0-dev+7ecfcdf";
  #   zip = pkgs.fetchurl {
  #     url = "https://nightly.link/jellyfin/jellyfin-desktop/workflows/build-linux-appimage/main/linux-appimage-x86_64.zip";
  #     hash = "sha256-FT9DoIBV3dwG3cDS1gG1IAK8vyO2kjnOpQQgOuVZoyU=";
  #   };
  #   appimage = pkgs.runCommandLocal "jellyfin-desktop-${version}.AppImage" {
  #     nativeBuildInputs = [pkgs.unzip];
  #   } ''
  #     unzip ${zip} '*.AppImage'
  #     mv *.AppImage $out
  #   '';
  # in
  #   pkgs.appimageTools.wrapType2 {
  #     pname = "jellyfin-desktop";
  #     inherit version;
  #     src = appimage;
  #   };
in {
  imports = [
    ./hardware-configuration.nix
    # Re-enable together with the ballbrawl input in flake.nix and the
    # services.ballbrawl block below. Commented out during the first
    # FDE install because the live ISO can't fetch the private SSH input.
    # inputs.ballbrawl.nixosModules.default
  ];

  # -------------------- Secrets -------------------- #

  age = {
    identityPaths = ["${secretDir}/server/ssh/id_ed25519"];
    secrets = {
      "airvpn-wg.conf".file = ./age/airvpn-wg.conf.age;
      mam.file = ./age/mam.age;
      mam-vpn.file = ./age/mam-vpn.age;
      user.file = ./age/user.age;
      domain.file = ./age/domain.age;
      nineteenEightyFour.file = ./age/1984.age;
    };
  };

  # -------------------- Kirk Modules -------------------- #

  kirk = {
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
    };
  };

  # -------------------- Nixarr -------------------- #

  nixarr = {
    enable = true;
    mediaUsers = [username];

    vpn = {
      enable = true;
      wgConf = config.age.secrets."airvpn-wg.conf".path;
      vpnTestService.enable = false;
      # exposeOnLAN defaults to true, which (since nixarr PR #171) puts the
      # whole RFC1918 range — including 10.0.0.0/8 — in the namespace's
      # accessibleFrom. AirVPN's in-tunnel DNS is 10.128.0.1 (inside 10/8),
      # so that range gets routed out the LAN bridge instead of the tunnel,
      # killing DNS for confined services (transmission couldn't resolve
      # trackers -> FD-exhaustion "too many open files"; mam-vpn -> curl
      # exit 6). Disable the broad default and re-add only the real LAN.
      exposeOnLAN = false;
      accessibleFrom = ["192.168.1.0/24"];
    };

    ddns.nineteenEightyFour = {
      enable = true;
      keysFile = config.age.secrets.nineteenEightyFour.path;
    };

    jellyfin = {
      enable = true;
      openFirewall = true;
      expose.https.enable = true;
      expose.https.acmeMail = "slimness_bullish683@simplelogin.com";
      expose.https.domainName = "jellyfin." + (lib.removeSuffix "\n" (builtins.readFile config.age.secrets.domain.path));
    };

    audiobookshelf = {
      enable = true;
      host = "0.0.0.0";
      openFirewall = true;
      expose.https.enable = true;
      expose.https.acmeMail = "slimness_bullish683@simplelogin.com";
      expose.https.domainName = "audiobookshelf." + (lib.removeSuffix "\n" (builtins.readFile config.age.secrets.domain.path));
    };

    transmission = {
      enable = true;
      openFirewall = true;
      privateTrackers.cross-seed.enable = false;
      extraSettings = {
        incomplete-dir-enabled = false;
        ratio-limit-enabled = true;
        ratio-limit = 20.0;
      };
      package = inputs.nixpkgs-2405.legacyPackages.${pkgs.system}.transmission_4;
      vpn.enable = true;
      peerPort = transmissionPort;
    };

    sonarr.enable = true;
    sonarr.openFirewall = true;
    bazarr.enable = true;
    bazarr.openFirewall = true;
    radarr.enable = true;
    radarr.openFirewall = true;
    shelfmark.enable = true;
    shelfmark.openFirewall = true;
    shelfmark.host = "0.0.0.0";
    lidarr.enable = true;
    lidarr.openFirewall = true;
    prowlarr.enable = true;
    prowlarr.openFirewall = true;
  };

  # nixarr creates *-sync-config oneshots unconditionally when each *arr
  # is enabled (there's no settings-sync enable toggle), and they were
  # failing on boot. We don't manage indexers / download clients
  # declaratively, so disable the generated units directly.
  systemd.services.prowlarr-sync-config.enable = false;
  systemd.services.radarr-sync-config.enable = false;
  systemd.services.sonarr-sync-config.enable = false;

  # Syncthing creates dirs 750 / files 640 (group `sync` read-only). See
  # services.syncthing.group above.
  systemd.services.syncthing.serviceConfig.UMask = "0027";

  # nixarr runs audiobookshelf with ProtectSystem=strict and only its state
  # dir in ReadWritePaths, so /data/media is read-only to it. Fine for
  # audiobooks (playback only reads), but it breaks PODCASTS, which need ABS to
  # write episodes into the library -> "ENOENT mkdir .../podcasts/<show>".
  # Grant the podcasts library write access. TODO: fix upstream in nixarr.
  systemd.services.audiobookshelf.serviceConfig.ReadWritePaths =
    lib.mkForce ["/data/.state/nixarr/audiobookshelf" "/data/media/library/podcasts"];

  # -------------------- Ballbrawl -------------------- #
  # game.<bare-domain> served by the ballbrawl flake module. The DDNS
  # entry (nixarr.ddns.nineteenEightyFour) already keeps subdomains of
  # the bare domain pointing at this host, same path jellyfin and
  # audiobookshelf use.
  # Temporarily disabled while the ballbrawl input is commented out for
  # the first FDE install (see flake.nix). Re-enable together with the
  # input + the ./hardware-configuration.nix import line above.
  # services.ballbrawl = {
  #   enable = true;
  #   domain = "game." + (lib.removeSuffix "\n" (builtins.readFile config.age.secrets.domain.path));
  #   acmeMail = "slimness_bullish683@simplelogin.com";
  # };

  # MAM
  systemd = {
    timers.mam-vpn = {
      timerConfig = {
        OnBootSec = "120"; # Run 30 seconds after system boot
        OnCalendar = "hourly";
        Persistent = true; # Run service immediately if last window was missed
        RandomizedDelaySec = "15min"; # Run service OnCalendar +- 5min
      };
      wantedBy = ["multi-user.target"];
    };
    services.mam-vpn = {
      serviceConfig = {
        Environment = "PATH=${pkgs.curl}/bin:$PATH";
        ExecStart = "${pkgs.lib.getExe pkgs.bash} ${config.age.secrets.mam-vpn.path}";
        Type = "oneshot";
      };
      vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
    };
  };

  # -------------------- Desktop / Gaming -------------------- #

  services.xserver.enable = true;
  # KDE Plasma 6 desktop. History: Cosmic -> GNOME -> Plasma. The DE churn was
  # mostly chasing a frozen-video bug that turned out to be the Jellyfin client
  # (qtwebengine 6.11.0), not the compositor; GNOME then kept enabling underscan
  # on the TV and hiding its own display controls. Plasma gives explicit,
  # predictable per-output display settings, which suits this TV box. Plasma is
  # the Switch-to-Desktop target; Jovian's gamescope game-mode stays the boot
  # session (no separate display manager — SDDM comes from jovian.steam).
  services.desktopManager.plasma6.enable = true;
  # Trim the Plasma app suite (we use foot + helix, not konsole/kate). These are
  # filtered from the optional set; add/remove freely via kdePackages.*.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
    kate
    elisa
    khelpcenter
    kwallet-pam # no autologin-unlockable wallet; KWallet is disabled (see home.nix)
    kwalletmanager
  ];
  # jovian's Steam (Deck) module sets services.orca.enable = true (screen
  # reader). We don't want one — force it off.
  services.orca.enable = lib.mkForce false;

  # Custom klfc keyboard layout (kirk.keyboardLayout module). Same layout the
  # deck-oled / work machines use, pulled from the keyboard-layout flake input.
  kirk.keyboardLayout = {
    enable = true;
    package = inputs.keyboard-layout.packages.${pkgs.system}.rk;
  };

  # Steam in gamescope, Cosmic as the fallback session. AMD Radeon RX 9070
  # (Navi 48 / RDNA4) is well supported here: kernel 6.18 + Mesa 25+ +
  # redistributable firmware (RDNA4 needs kernel >= 6.12 / Mesa >= 25.0).
  #
  # NOTE: steamos.useSteamOSConfig must be explicitly FALSE. It defaults to
  # jovian.steam.enable (= true here), and gates jovian's SteamOS modules —
  # including boot.nix, which injects Deck-tuned amdgpu params
  # (amdgpu.lockup_timeout, ttm.pages_min=8G, sched_hw_submission,
  # amdgpu.dcdebugmask=0x20000) — the very params suspected for the initrd
  # hang — plus SteamOS sysctl/earlyoom/automount/cec. Those target the
  # Deck's APU and a SteamOS appliance, wrong for a desktop dGPU that's
  # primarily a server. We want only the Steam + gamescope session.
  jovian = {
    steamos.useSteamOSConfig = false;
    steam = {
      enable = true;
      autoStart = true;
      desktopSession = "plasma";
      user = "user";
    };
    hardware.has.amd.gpu = true;
  };
  programs.steam.extraPackages = [pkgs.hidapi];
  hardware.steam-hardware.enable = true;

  # Multi-GPU box: Intel iGPU (8086:7D67) + AMD RX 9070XT (1002:7550, Navi 48).
  # The iGPU drives no displays (the monitor is on the AMD HDMI) and exists
  # only for potential media transcode (VAAPI, unaffected by this). Without a
  # hint, DXVK/vkd3d under Proton enumerate the Intel GPU first and render
  # games on it — dGPU stays idle/silent at ~40MHz while the weak iGPU pegs at
  # ~1.5GHz, giving terrible framerates. Pin games to the AMD card by name.
  #
  # Two non-obvious requirements, both learned the hard way:
  #   1. MUST be sessionVariables, not `environment.variables`: the latter only
  #      lands in /etc/set-environment (sourced by login *shells*), which the
  #      Wayland/Cosmic graphical session never reads, so Steam never saw it.
  #      sessionVariables writes /etc/pam/environment, loaded by pam_env for
  #      every session (graphical login included). Confirmed reaching Steam.
  #   2. MESA_VK_DEVICE_SELECT does NOT work here: it relies on the
  #      VkLayer_MESA_device_select implicit layer, which exists on the host
  #      but is NOT imported into Steam's pressure-vessel runtime, so Proton
  #      ignores it. DXVK_FILTER_DEVICE_NAME / VKD3D_FILTER_DEVICE_NAME are
  #      read directly by DXVK (DX9-11) and vkd3d-proton (DX12), needing no
  #      layer. "Radeon" matches "AMD Radeon RX 9070 XT (RADV ...)" and
  #      excludes the Intel iGPU. (Verified: game VRAM landed on card1 and
  #      gpu_busy ramped to 84% while the iGPU dropped to 0MHz.)
  environment.sessionVariables = {
    DXVK_FILTER_DEVICE_NAME = "Radeon";
    VKD3D_FILTER_DEVICE_NAME = "Radeon";
  };

  # Declarative non-Steam shortcuts (kirk.steamShortcuts, modules/nixos). A
  # per-user oneshot runs before Jovian's steam-launcher (re)starts Steam — on
  # every game-mode entry, so it applies on desktop<->game-mode switches without
  # a reboot — and reconciles shortcuts.vdf to the declared set.
  #
  # steamRoot MUST be the real Steam data dir that ~/.local/share/Steam resolves
  # to. home.nix persists that at ${stateDir}/steam/steam (the /steam container
  # also holds steam-compat/gamescope/steamos-manager siblings), so it's nested
  # one level under ${stateDir}/steam. Pointing steamRoot at the parent writes to
  # a phantom userdata/ tree Steam never reads (the long-standing "shortcuts
  # never apply" bug) — it needs the trailing /steam.
  kirk.steamShortcuts = {
    enable = true;
    user = "user";
    steamRoot = "/data/.state/user/steam/steam";
    # Authoritative: any non-Steam shortcut NOT declared here is removed.
    pruneUnmanaged = true;
    shortcuts = {
      # Jellyfin tile = the JF web UI in a Chromium kiosk. The native
      # xaltsc/jellyfin-desktop client was dropped: it CANNOT run under gamescope
      # (its renderer composites mpv as a wayland subsurface sized via
      # wp_viewporter over a single_pixel_buffer backdrop, and gamescope
      # implements none of wl_subcompositor / wp_viewporter /
      # wp_single_pixel_buffer_manager_v1; its x11 backend dies with a wgpu
      # swapchain DEVICE LOST). Chromium renders fine under gamescope, so the tile
      # opens the web client — and it works identically in desktop mode. Dedicated
      # --user-data-dir (own persisted profile, see home.nix tmpfiles) so it's a
      # tracked standalone process and never attaches to the Chromium tile.
      "Jellyfin" = {
        exe = "${jellyfin-kiosk}/bin/jellyfin-kiosk";
        portrait = ../../../images/steam/jellyfin-portrait.png; # 600x900 library capsule
        landscape = ../../../images/steam/jellyfin-landscape.png; # 920x430 big grid
        hero = ../../../images/steam/jellyfin-hero.png; # 1920x620 banner
        logo = ../../../images/steam/jellyfin-logo.png; # transparent logo
        icon = ../../../images/steam/jellyfin-icon.png; # 256x256 list icon
      };
      "Firefox" = {
        exe = "/run/current-system/sw/bin/firefox";
        portrait = ../../../images/steam/firefox-portrait.png; # 600x900
        landscape = ../../../images/steam/firefox-landscape.png; # 920x430
        hero = ../../../images/steam/firefox-hero.png; # 3840x1240
        logo = ../../../images/steam/firefox-logo.png; # 1363x480
        icon = ../../../images/steam/firefox-icon.png; # 1024x1024
      };
      "Chromium" = {
        # Wrapper (strips Steam's overlay LD_PRELOAD, fills the 4K TV, own
        # profile); raw chromium + %command% launch options fails from game mode.
        exe = "${chromium-rasmus}/bin/chromium-rasmus";
        portrait = ../../../images/steam/chromium-portrait.png; # 600x900
        landscape = ../../../images/steam/chromium-landscape.png; # 920x430
        hero = ../../../images/steam/chromium-hero.png; # 1920x620
        logo = ../../../images/steam/chromium-logo.png; # 4315x1024
        icon = ../../../images/steam/chromium-icon.png; # 256x256
      };
      # Naja's browser — separate profile (own logins/YouTube). Uses Google
      # Chrome artwork (chrome-*, from SteamGridDB) so it's visually distinct from
      # Rasmus's Chromium tile above.
      "Chromium (Naja)" = {
        exe = "${chromium-naja}/bin/chromium-naja";
        portrait = ../../../images/steam/chrome-portrait.png; # 600x900
        landscape = ../../../images/steam/chrome-landscape.png; # 920x430
        hero = ../../../images/steam/chrome-hero.png; # 1920x620
        logo = ../../../images/steam/chrome-logo.png; # 1271x337
        icon = ../../../images/steam/chrome-icon.png; # 256x256
      };
    };
  };

  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Thunderbolt + firmware update daemons.
  services.hardware.bolt.enable = true;
  services.fwupd.enable = true;

  # Case / motherboard RGB (ASRock Z890 Pro-A, Polychrome over SMBus).
  # motherboard = "intel" loads i2c-dev + i2c-i801 so OpenRGB can reach the
  # SMBus controllers. Run `openrgb` to detect devices and set colours; save
  # a profile, then set `startupProfile` here to persist it across reboots.
  services.hardware.openrgb = {
    enable = true;
    motherboard = "intel";
    # ASRock RX 9070 (GPU subvendor 0x1849) GPU RGB is NOT in OpenRGB
    # 1.0rc2 (what nixpkgs ships). Build OpenRGB master + the still-unmerged
    # ASRock GPU controller patch from upstream issue #5225 (download the
    # .patch into ./patches/ and `git add` it — flakes only see tracked
    # files). We replace nixpkgs' two rc2-era patches: one is an upstream
    # commit already present in master, the other is a plugin-path tweak we
    # don't use — both would break against master.
    package = pkgs.openrgb.overrideAttrs (old: {
      version = "git-asrock-4306603";
      src = pkgs.fetchFromGitLab {
        owner = "CalcProgrammer1";
        repo = "OpenRGB";
        rev = "4306603a28c86e91f4dd4f89b41efd3005f0b810";
        sha256 = "0idkmwxkzw7681zdz57sd0r9z11bjvh7ixls1dlzjkgblnpshpjk";
      };
      patches = [./patches/0001-asrock-gpu.patch];
    });
  };

  # No NixOS option sets a specific colour (only startupProfile, which needs
  # an interactively-saved profile that wouldn't survive the @root rollback).
  # So apply the colour declaratively via the CLI once at boot. Applies to
  # all detected controllers (add `--device N` to target one).
  # 1A0500 = rgb(26,5,0), warm candlelight. Dimmer: 0D0300 (13,3,0), 070100 (7,1,0).
  # Disable the persistent OpenRGB SERVER: idle, it keeps the GPU i2c bus
  # claimed, and that bus is shared with the display's DDC — which stutters
  # the desktop (confirmed: `systemctl stop openrgb` cleared it). We don't
  # need a running server; openrgb-color sets the colour once at boot and
  # exits, and both controllers hold it (GPU Direct, board Static).
  # systemd.services.openrgb.enable = lib.mkForce false;

  systemd.services.openrgb-color = {
    description = "Apply static case RGB colour (candlelight)";
    # No persistent openrgb.service to wait on now — just need i2c-dev loaded.
    # The oneshot sets the colour and exits, releasing the GPU i2c bus.
    after = ["systemd-modules-load.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        # Steady candlelight, same colour on both. 0E0200 = rgb(14,2,0).
        "${config.services.hardware.openrgb.package}/bin/openrgb --mode static --color 0E0200"
        "${config.services.hardware.openrgb.package}/bin/openrgb --device \"ASRock GPU\" --mode direct --color 0E0200"
      ];
    };
  };

  # The GPU (Taichi) RGB resets to its default on resume from sleep — Direct
  # is software-driven, not a stored hardware mode — so re-apply on wake.
  # (The board's Static mode survives sleep, but re-applying is harmless.)
  # NOTE: keep these colours in sync with the openrgb-color oneshot above.
  powerManagement.resumeCommands = ''
    ${config.services.hardware.openrgb.package}/bin/openrgb --mode static --color 0E0200
    ${config.services.hardware.openrgb.package}/bin/openrgb --device "ASRock GPU" --mode direct --color 0E0200
  '';

  # schedutil scales dynamically without `powersave`'s aggressive power-down.
  # Better for gaming spikes, still ramps down at idle.
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "schedutil";

  # -------------------- user state subtree -------- #
  # /data/.state stays root-owned (nixarr + other system services keep
  # their own service-user-owned subdirs there). All home-manager USER
  # state instead lives under a single user-owned subtree,
  # /data/.state/user, created here once. home.nix then manages the
  # per-app subdirs under it via its own user-tmpfiles (which work now
  # that the parent is writable by 'user').
  systemd.tmpfiles.rules = [
    "d /data                        0755 root root  -"
    "d /data/.state                 0755 root root  -"
    "d /data/.state/user            0755 user users -"

    # XDG user dirs (kirk.userDirs.rootDir = /data): downloads sits
    # directly in root-owned /data — not under /data/.state/user — so it
    # is created here. The /data/media/* XDG dirs already work via the
    # setgid 'media' group on /data/media.
    "d /data/downloads              0755 user users -"

    # @persist NVMe subvol (mounted at /persist). The AI flake at
    # /data/ai/flake.nix runs as 'user' and writes models/caches here, so the
    # dir must be user-owned. (/persist/monero is created+owned by the monero
    # module's createHome, so it needs no rule.)
    "d /persist/ai                  0755 user users -"

    # Steam libraries: parent + the samsung dir (a plain dir on the root NVMe).
    # /persist/games/sandisk is a mountpoint (the SanDisk), handled by fileSystems.
    "d /persist/games               0755 user users -"
    "d /persist/games/samsung       0755 user users -"
  ];

  # -------------------- Server Defaults -------------------- #

  # If the system runs out of ram, then journald crashes and the server will be down.
  # This should force systemd to restart, no matter what.
  systemd.services.systemd-journald.unitConfig.StartLimitIntervalSec = 0;

  # Kill services if we run out of ram
  # services.earlyoom = {
  #   enable = true;
  #   freeMemThreshold = 3; # In percent
  # };

  boot.kernelParams = [
    "panic=10" # Reboot after 10 seconds of kernel panic
    "panic_on_oops=1" # Reboot on any kernel oops
  ];

  # Forces full colors in terminal over SSH
  environment.variables = {
    COLORTERM = "truecolor";
    TERM = "xterm-256color";
  };

  # cosmic-greeter handles login; no getty auto-login.
  services.logind.settings.Login.HandleLidSwitch = "ignore";
  # Always-on server: the suspend/sleep key must never suspend it. This also
  # frees that key to be repurposed as a "wake TV" button (see kirk.cec).
  services.logind.settings.Login.HandleSuspendKey = "ignore";
  services.logind.settings.Login.HandleSuspendKeyLongPress = "ignore";

  # -------------------- Syncthing -------------------- #

  services = {
    syncthing = {
      enable = true;
      # Run as group `sync` (which `user` is in) so synced data is
      # group-readable. UMask 0027 -> new dirs 750, files 640: the sync group
      # can enter/read but not write (see systemd.services.syncthing below).
      group = "sync";
      configDir = "${stateDir}/syncthing";
      dataDir = "${dataDir}/sync";
      guiAddress = "0.0.0.0:8384";
      overrideDevices = false;
      overrideFolders = false;
    };
    tuptime.enable = true;
    btrfs.autoScrub = {
      enable = true;
      fileSystems = ["/data"];
    };
    fstrim = {
      enable = true;
      interval = "weekly";
    };
    monero = {
      enable = true;
      # Blockchain (~200 GB) lives on the @persist NVMe subvol, not the default
      # /var/lib/monero. The module uses dataDir as the monero user's home and
      # createHome makes it; migrated data keeps its monero:monero ownership.
      dataDir = "/persist/monero";
    };
    minecraft-server = {
      enable = true;
      openFirewall = true;
      declarative = true;
      eula = true;
      dataDir = "${stateDir}/minecraft";
      whitelist = {
        Augustenborg = "97389804-1e10-48f6-8a72-fdd854a37feb";
        migmedstort = "6993065e-1c24-475a-9388-6578d9002e4e";
        Jakob290a = "b9150a18-d471-4952-b3d3-c824cfdfdd26";
        mtface = "ae39f9e6-dd5a-4f70-baff-f8ff725886c5";
      };
      serverProperties = {
        motd = "Kirk's NixOS minecraft server";
        server-port = 25565;
        difficulty = "normal";
        max-players = 20;
        white-list = true;
      };
    };
    home-assistant = {
      enable = true;
      openFirewall = true;
      configDir = "${stateDir}/home-assistant";
      extraComponents = [
        "analytics"
        "google_translate"
        "met"
        "radio_browser"
        "shopping_list"
        "zha"
        "usb"
        "isal"
      ];
      configWritable = true;
      config = {
        default_config = {};
        automation = "!include automations.yaml";
      };
    };
    openssh = {
      enable = true;
      openFirewall = true;
      settings.PasswordAuthentication = false;
      ports = [6000];
    };
  };

  programs.mosh.enable = true;
  networking.firewall = {
    allowedUDPPorts = [ 6000 ];
    allowedTCPPorts = [ 8384 ];
  };

  users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
    ../../../pubkeys/deck-oled.pub
  ];

  # -------------------- Impermanence -------------------- #
  # The NVMe root is ephemeral (rolled back to @root-blank each boot, see
  # the rollback service in the Machine Specific section). These paths
  # are bind-mounted from /data/.state/persist so they survive reboots.
  # Default policy: anything that can be redirected via NixOS module
  # config goes to /data/.state/<service> directly; this list is only
  # for state whose owning module does not expose a path override.
  # NOTE: /var/log is intentionally persisted here so boot/initrd logs
  # (cryptsetup/FIDO2 unlock, the rollback itself) survive the @root wipe
  # and remain available for debugging.
  environment.persistence."/data/.state/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos" # stable uid/gid map across rebuilds
      "/var/lib/acme" # Let's Encrypt certs — avoid rate limits
      "/var/lib/tuptime" # uptime history
      "/var/lib/systemd/timers" # Persistent=true timer stamps (mam-vpn)
      "/var/log" # journald + non-journald logs (kept across rollback)
      "/var/lib/bluetooth" # paired-device DB (future-proof)
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  # -------------------- Boilerplate -------------------- #

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

  nix = {
    package = pkgs.nixVersions.latest;
    settings = {
      experimental-features = ["nix-command" "flakes"];
      download-buffer-size = 500000000; # 500 MB
      # Faster builds: run derivations in parallel (max-jobs = auto = #cores)
      # and let each use all cores. Oversubscribes on big parallel builds but
      # maximizes throughput, which suits this box (it's also the remote builder).
      max-jobs = "auto";
      cores = 0;
      # Return more information when errors happen
      show-trace = true;
      # Let the nixremote build user (work + deck offload here) write the store.
      trusted-users = ["root" "nixremote"];
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

  # -------------------- Remote builder -------------------- #
  # work + deck offload builds here over SSH (port 6000), authenticating as the
  # dedicated `nixremote` user with each machine's key from /pubkeys. nixremote
  # is a trusted nix user (see nix.settings.trusted-users) so it may populate
  # the store. WAN/work case needs port 6000 forwarded at the router.
  users.groups.nixremote = {};
  users.users.nixremote = {
    isNormalUser = true;
    group = "nixremote";
    openssh.authorizedKeys.keyFiles = [
      ../../../pubkeys/work.pub
      ../../../pubkeys/deck-oled.pub
    ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # -------------------- Machine Specific -------------------- #

  users.mutableUsers = false;
  # Shared group for syncthing data: `user` is a member (extraGroups below)
  # and syncthing runs as this group, so synced files are group-readable.
  users.groups.sync = {};
  users.groups.cectv = {};

  # The CEC daemon's narrow access: the CEC adapter + the keystroke-free
  # "System Control" node (the remote's sleep key, hijacked as a wake button).
  # Nothing in `input`/`video` — so no user process can read keyboards.
  services.udev.extraRules = ''
    SUBSYSTEM=="cec", KERNEL=="cec[0-9]*", GROUP="cectv", MODE="0660"
    SUBSYSTEM=="input", KERNEL=="event[0-9]*", ATTRS{name}=="*System Control*", GROUP="cectv", MODE="0660"
    SUBSYSTEM=="input", KERNEL=="event[0-9]*", ATTRS{name}=="*Consumer Control*", GROUP="cectv", MODE="0660"
  '';
  users.users."user" = {
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets.user.path;
    # cectv is the CEC TV-liveness daemon's entire privileged surface: a udev
    # rule (below) puts /dev/cec0 and the keystroke-free "System Control"
    # sleep-key node into it, and nothing else. Deliberately NOT in `input`
    # (no keyboard access -> no keylogging), `video` (no screen/scanout or
    # webcam), or `render`. sync: syncthing data access.
    extraGroups = ["networkmanager" "wheel" "sync" "cectv"];
  };

  hardware.graphics.enable = true; # Wayland / Cosmic / Vulkan
  # Intel iGPU (0x7d67) media stack, for Jellyfin hardware transcoding on the
  # render node (renderD129) — keeps the AMD dGPU free for gaming. Without these
  # only the AMD radeonsi VA-API driver is present (no iHD), so the iGPU can't
  # transcode. intel-media-driver = iHD VA-API; vpl-gpu-rt = oneVPL runtime for
  # Jellyfin's preferred Intel QSV path.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
  ];
  networking = {
    hostName = machine;
    networkmanager.enable = true;
  };

  # Intentionally no system `programs.zsh` (matches work). Login shell is
  # bash -> `exec zsh` (home-manager), so /etc/zsh* aren't needed. Enabling
  # it generates /etc/zshenv|zshrc|zprofile, which buildFHSEnv then symlinks
  # into the `box` sandbox (its hardcoded /etc list) where the host's
  # `prompt suse` + `hostname --fqdn` break the box shell.

  # -------------------- YubiKey (U2F) -------------------- #
  # Touch-to-authenticate for local sudo, TTY login, and the Cosmic
  # greeter. Both pam_u2f and pam_rssh below are stacked "sufficient";
  # in the auth order rssh is tried first, so an SSH session with a
  # forwarded agent still satisfies sudo without a key (see rssh block),
  # and U2F is the local fallback. Password remains the final fallback.
  # Key mapping lives in ~/.config/Yubico/u2f_keys (symlinked to
  # /data/.state/yubico in home.nix); register with `pamu2fcfg`.
  security.pam.services.sudo.u2fAuth = true;
  security.pam.services.login.u2fAuth = true;
  security.pam.services.cosmic-greeter.u2fAuth = true;
  security.pam.u2f.settings.cue = true; # prints "touch your key" prompt

  # 1. Enable the module globally
  security.pam.rssh.enable = true;

  # 2. Tell it to use standard SSH keys for validation
  security.pam.rssh.settings.auth_key_file = "/etc/ssh/authorized_keys.d/user";

  # 3. Apply it specifically to sudo
  security.pam.services.sudo.rssh = true;

  security.sudo = {
    execWheelOnly = true; # For security
    package = pkgs.sudo.override {withInsults = true;}; # For insults lol
    extraConfig = "Defaults insults";
  };

  # systemd in initrd: cleaner cryptsetup passphrase prompts and
  # hosts the snapshot-rollback unit below.
  boot.initrd.systemd.enable = true;

  # /data LUKS — passphrase prompted at console (no more SD-card keyfile).
  # Root LUKS (cryptroot) is declared in hardware-configuration.nix.
  boot.initrd.luks.devices.crypt_ssd1 = {
    device = "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5SSNF0WA10922R";
    allowDiscards = true; # Allows SSD trim commands for better performance
    # YubiKey FIDO2 unlock (systemd initrd). Enroll once with:
    #   sudo systemd-cryptenroll --fido2-device=auto \
    #     /dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5SSNF0WA10922R
    # The existing passphrase stays as a fallback.
    crypttabExtraOpts = ["fido2-device=auto"];
  };

  # Impermanence: roll @root back to a pristine state on every boot,
  # archiving the previous @root under /old_roots/<timestamp> and
  # GCing anything older than 30 days.
  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = ["initrd.target"];
    after = ["dev-mapper-cryptroot.device"];
    before = ["sysroot.mount"];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /btrfs_tmp
      mount -o subvol=/ /dev/mapper/cryptroot /btrfs_tmp

      if [[ -e /btrfs_tmp/@root ]]; then
        mkdir -p /btrfs_tmp/old_roots
        ts=$(date --date="@$(stat -c %Y /btrfs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
        mv /btrfs_tmp/@root "/btrfs_tmp/old_roots/$ts"
      fi

      delete_subvolume_recursively() {
        IFS=$'\n'
        for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
          delete_subvolume_recursively "/btrfs_tmp/$i"
        done
        btrfs subvolume delete "$1"
      }
      for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30 2>/dev/null); do
        delete_subvolume_recursively "$i"
      done

      btrfs subvolume snapshot /btrfs_tmp/@root-blank /btrfs_tmp/@root
      umount /btrfs_tmp
    '';
  };

  fileSystems."/data" = {
    device = "/dev/mapper/crypt_ssd1";
    fsType = "btrfs";
    neededForBoot = true;
    options = [
      "defaults"
      "noatime"
      "nodiratime"
      "compress=zstd"
      "discard=async"
    ];
  };

  # Steam libraries, to keep games off the 8TB /data pool:
  #  - /persist/games/sandisk: the dedicated SanDisk SSD (unencrypted btrfs,
  #    label "games", @games subvol). Loaded late (not neededForBoot).
  #  - /persist/games/samsung: a plain dir on the root NVMe's free space
  #    (encrypted via cryptroot) -- no separate device, just declared below.
  fileSystems."/persist/games/sandisk" = {
    device = "/dev/disk/by-label/games";
    fsType = "btrfs";
    options = [
      "defaults"
      "noatime"
      "nodiratime"
      "compress=zstd"
      "discard=async"
      "subvol=@games"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    (writeShellApplication {
      name = "monero";
      runtimeInputs = [monero-cli coreutils];
      inheritPath = false;
      text = ''
        wallet_dir="/data/monero"
        mkdir -p "$wallet_dir"
        monero-wallet-cli \
          --wallet-file "$wallet_dir"/user.keys \
          --log-file "$wallet_dir"/log.log
      '';
    })
    claude-code
    firefox
    chromium
    openrgb
    v4l-utils # cec-ctl: HDMI-CEC control (TV power/input over /dev/cec0)
    # No native Jellyfin desktop client. xaltsc/jellyfin-desktop can't run under
    # gamescope game mode (its wgpu/subsurface renderer needs wl_subcompositor /
    # wp_viewporter, which gamescope lacks; its x11 backend dies with a wgpu
    # DEVICE LOST), so the JF web UI in a Chromium kiosk is used for both game
    # and desktop mode (see kirk.steamShortcuts). plezy kept as a light fallback.
    plezy

    # Compression
    zip
    unar
    unzip
    p7zip

    # Terminal programs
    iotop
    tuptime # Uptime doesn't work lol
    yt-dlp
    git
    smartmontools
    fzf
    ffmpeg
    nmap
    trash-cli
    wget

    # Agenix
    inputs.agenix.packages."${system}".default
    inputs.submerger.packages."${system}".default
  ];

  system.stateVersion = "24.05";
}
