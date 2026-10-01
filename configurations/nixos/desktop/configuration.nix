{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  username = "user";
  gameUser = "steam";
  machine = "desktop";
  dataDir = "/data";
  configDir = "${dataDir}/.system-configuration";
  secretDir = "${dataDir}/.secret";
  stateDir = "${dataDir}/.state";
  transmissionPort = 33915;

  # ExecStart for the systemd-{suspend,hibernate,hybrid-sleep} drop-ins below:
  # on this always-on box a suspend request (notably Steam's power-menu "Sleep")
  # must not actually suspend, so signal the CEC daemon (SIGUSR1) to put the TV
  # to standby instead. The empty first entry resets systemd's ExecStart; the
  # second is ours.
  sleepToTv = [
    ""
    "${pkgs.writeShellScript "sleep-to-tv-standby" ''
      ${pkgs.procps}/bin/pkill -USR1 -f cec-tv-liveness || true
    ''}"
  ];

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
  jellyfin-kiosk =
    mkChromiumTile "jellyfin-kiosk"
    "--user-data-dir=${stateDir}/${gameUser}/jellyfin-web --app=http://localhost:8096 --kiosk --no-first-run --window-size=3840,2160 --force-device-scale-factor=2.0";
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
    "--user-data-dir=${stateDir}/${gameUser}/${profile} --window-size=3840,2160 --start-fullscreen --force-device-scale-factor=2.0";
  chromium-rasmus = mkChromiumBrowser "chromium-rasmus" "chromium-rasmus";
  chromium-naja = mkChromiumBrowser "chromium-naja" "chromium-naja";
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
    identityPaths = ["${secretDir}/ssh/${machine}"];
    secrets = {
      "airvpn-wg.conf".file = ./age/airvpn-wg.conf.age;
      mam.file = ./age/mam.age;
      mam-vpn.file = ./age/mam-vpn.age;
      domain.file = ./age/domain.age;
      nineteenEightyFour.file = ./age/1984.age;
    };
  };

  # agenix decrypts secrets from an *activation script* into a ramfs at
  # /run/agenix.d. A soft-reboot (the power-button recovery below) re-execs PID 1
  # WITHOUT re-running activation scripts, and tears down that ramfs — so
  # /run/agenix vanishes and never comes back, killing wg (hence transmission),
  # ddns, and mam-vpn until the next real boot or `nixos-rebuild switch`.
  #
  # Fix: reinstall the secrets from a oneshot *service*. This mirrors agenix's own
  # `agenix-install-secrets` unit (only wired up when systemd.sysusers/userborn is
  # enabled, which we don't use) by replaying the exact install snippets agenix
  # generates for the activation-script path. Ordered before the VPN so confined
  # services find their secrets.
  #
  # CRITICAL: for this to re-run on a soft-reboot the unit must be *stopped* during
  # the soft-reboot's shutdown transition, so sysinit.target re-pulls it (and thus
  # re-fires ExecStart) on the way back up. `DefaultDependencies = no` is required
  # here — a plain oneshot pulled into sysinit.target can't also be ordered After
  # it — but that flag strips the automatic `Conflicts/Before=shutdown.target`, so
  # nothing ever stopped the unit and RemainAfterExit kept it active(exited) across
  # soft-reboots forever (secrets silently vanished; see 2026-08-02 regression).
  # `systemd-soft-reboot.service` Requires+After `shutdown.target`, so adding the
  # conflict/ordering below guarantees the stop-then-restart cycle. Idempotent — on
  # a real boot activation already ran, so this just makes a fresh generation.
  systemd.services.agenix-reinstall = {
    description = "Reinstall agenix secrets (survives soft-reboot)";
    wantedBy = ["sysinit.target"];
    before = ["wg.service" "shutdown.target"];
    conflicts = ["shutdown.target"];
    unitConfig.DefaultDependencies = "no";
    path = [pkgs.mount];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "agenix-reinstall" ''
        ${config.system.activationScripts.agenixNewGeneration.text}
        ${config.system.activationScripts.agenixInstall.text}
        ${config.system.activationScripts.agenixChown.text}
      '';
    };
  };

  # -------------------- Kirk Modules -------------------- #

  kirk = {
    nixosScripts = {
      enable = true;
      configDir = configDir;
      machine = machine;
      extraNixOptions = true;
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
      package = inputs.nixpkgs-2405.legacyPackages.${pkgs.stdenv.hostPlatform.system}.transmission_4;
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

    # -------------------- VPN self-healing watchdog -------------------- #
    # nixarr's wg.service is Type=oneshot: it runs wg-up and exits, so there is
    # no live process for systemd to watch and a dead tunnel goes unnoticed.
    # AirVPN's endpoint (se3.vpn.airdns.org) rotates IPs; WireGuard resolves the
    # hostname only at bring-up and pins the IP, and the config has no
    # PersistentKeepalive -- so when AirVPN moves the server the tunnel silently
    # black-holes all traffic until wg.service is restarted (which re-resolves
    # DNS to a live IP). transmission BindsTo wg.service and mam-vpn re-enters
    # the namespace, so restarting wg alone pulls everything back up.
    # Long-running loop: sleep, probe real connectivity through the namespace,
    # and restart wg.service whenever the tunnel stops passing packets.
    services.wg-watchdog = {
      wantedBy = ["multi-user.target"];
      after = ["wg.service"];
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        ExecStart = pkgs.writeShellScript "wg-watchdog" ''
          while true; do
            sleep 600
            # 10 pings, succeed if any one returns -- rides out lost packets.
            if ${pkgs.iproute2}/bin/ip netns exec wg \
                 ${pkgs.iputils}/bin/ping -c10 -W3 -q 1.1.1.1 >/dev/null 2>&1; then
              continue
            fi
            echo "wg tunnel probe failed; restarting wg.service to re-resolve endpoint" >&2
            ${pkgs.systemd}/bin/systemctl restart wg.service
            sleep 30 # let the tunnel re-establish before the next probe
          done
        '';
      };
    };
  };

  # -------------------- Desktop / Gaming -------------------- #

  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
    kate
    elisa
    khelpcenter
    kwallet-pam
    kwalletmanager
  ];
  services.orca.enable = lib.mkForce false;

  kirk.keyboardLayout = {
    enable = true;
    package = inputs.keyboard-layout.packages.${pkgs.stdenv.hostPlatform.system}.rk;
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
      user = gameUser;
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
  # to (the tmpfiles link below), not its parent: pointing it one level up
  # writes a phantom userdata/ tree Steam never reads, which was the
  # long-standing "shortcuts never apply" bug.
  kirk.steamShortcuts = {
    enable = true;
    user = gameUser;
    steamRoot = "${stateDir}/${gameUser}/steam";
    # Authoritative: any non-Steam shortcut NOT declared here is removed.
    pruneUnmanaged = true;
    shortcuts = {
      "Jellyfin" = {
        exe = "${jellyfin-kiosk}/bin/jellyfin-kiosk";
        portrait = ../../../images/steam/jellyfin-portrait.png; # 600x900 library capsule
        landscape = ../../../images/steam/jellyfin-landscape.png; # 920x430 big grid
        hero = ../../../images/steam/jellyfin-hero.png; # 1920x620 banner
        logo = ../../../images/steam/jellyfin-logo.png; # transparent logo
        icon = ../../../images/steam/jellyfin-icon.png; # 256x256 list icon
      };
      "Chromium" = {
        exe = "${chromium-rasmus}/bin/chromium-rasmus";
        portrait = ../../../images/steam/chromium-portrait.png; # 600x900
        landscape = ../../../images/steam/chromium-landscape.png; # 920x430
        hero = ../../../images/steam/chromium-hero.png; # 1920x620
        logo = ../../../images/steam/chromium-logo.png; # 4315x1024
        icon = ../../../images/steam/chromium-icon.png; # 256x256
      };
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

  # Console emulation (kirk.emulation, modules/nixos). Games declared below are
  # auto-registered as game-mode tiles via kirk.steamShortcuts above (they merge
  # into its shortcut set). Everything needed to play lives in one syncable tree
  # under /data/.state/games/<system> (ROMs + BIOS + saves), so Syncthing'ing it
  # mirrors the library and saves to the Steam Deck.
  kirk.emulation = {
    enable = true;
    user = gameUser;
    group = gameUser;
    stateDir = "${stateDir}/${gameUser}";
    ps1.enable = true;
    switch.enable = true;
    # Declare games here to get a tile each (rom + SteamGridDB artwork); same
    # shape for both systems, e.g.:
    #   ps1.games."Final Fantasy VII" = {
    #     rom = "Final Fantasy VII (Disc 1).m3u";   # under /data/.state/games/ps1/games
    #     portrait = ../../../images/steam/ff7-portrait.png;
    #     landscape = ../../../images/steam/ff7-landscape.png;
    #   };
    #   switch.games."Tears of the Kingdom" = {
    #     rom = "totk.nsp";                          # under /data/.state/games/switch/games
    #     portrait = ../../../images/steam/totk-portrait.png;
    #   };
  };

  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Thunderbolt + firmware update daemons.
  services.hardware.bolt.enable = true;
  services.fwupd.enable = true;

  services.hardware.openrgb = {
    enable = true;
    motherboard = "intel";
  };

  systemd.services.openrgb-color = {
    description = "Apply static case RGB colour (candlelight)";
    requires = ["openrgb.service"];
    after = ["openrgb.service" "systemd-modules-load.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 3;
      ExecStart = [
        "${config.services.hardware.openrgb.package}/bin/openrgb --mode static --color 0E0200"
      ];
    };
  };

  powerManagement.resumeCommands = ''
    ${config.services.hardware.openrgb.package}/bin/openrgb --mode static --color 0E0200
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
  # mkBefore: systemd-tmpfiles honours the FIRST line for a path, and nixarr
  # also declares /data/media (2775). Ours has to come first to win.
  systemd.tmpfiles.rules = lib.mkBefore [
    # /data and /data/.state keep o+x so `steam` can traverse to its own two
    # subdirs; everything else is closed to other, which is `steam`.
    "d /data                        0755 root  root  -"
    "d /data/.state                 0755 root  root  -"
    "d /data/.state/user            0700 user  users -"
    "d /data/.state/steam           0755 steam steam -"
    "d /data/.secret                0700 user  users -"
    "d /data/monero                 0700 user  users -"
    "d /data/tmp                    0700 user  users -"
    "d /data/cold-storage           0750 root  users -"
    "d /data/media                  2770 root  media -"
    "d /data/downloads              0750 user  users -"

    # @persist NVMe subvol (mounted at /persist). The AI flake at
    # /data/ai/flake.nix runs as 'user' and writes models/caches here, so the
    # dir must be user-owned. (/persist/monero is created+owned by the monero
    # module's createHome, so it needs no rule.)
    "d /persist/ai                  0755 user users -"

    # Steam libraries: parent + the samsung dir (a plain dir on the root NVMe).
    # /persist/games/sandisk is a mountpoint (the SanDisk), handled by fileSystems.
    "d /persist/games               0755 steam steam -"
    "d /persist/games/samsung       0755 steam steam -"

    # `steam` home persistence. The ~/.config and ~/.local/share "d" rules
    # must precede the links, or tmpfiles creates those parents root-owned
    # and home-manager's linkGeneration then fails.
    "d /data/.state/steam/steam              0755 steam steam -"
    "d /data/.state/steam/steam-compat       0755 steam steam -"
    "d /data/.state/steam/gamescope          0755 steam steam -"
    "d /data/.state/steam/steamos-manager    0755 steam steam -"
    "d /data/.state/steam/jellyfin-web       0700 steam steam -"
    "d /data/.state/steam/chromium-rasmus    0700 steam steam -"
    "d /data/.state/steam/chromium-naja      0700 steam steam -"
    "d /data/.state/steam/jellyfinmediaplayer 0755 steam steam -"
    "d /home/steam/.config          0755 steam steam -"
    "d /home/steam/.local           0755 steam steam -"
    "d /home/steam/.local/share     0755 steam steam -"
    "L+ /home/steam/.local/share/Steam               - - - - /data/.state/steam/steam"
    "L+ /home/steam/.steam                           - - - - /data/.state/steam/steam-compat"
    "L+ /home/steam/.config/gamescope                - - - - /data/.state/steam/gamescope"
    "L+ /home/steam/.config/steamos-manager          - - - - /data/.state/steam/steamos-manager"
    "L+ /home/steam/.local/share/jellyfinmediaplayer - - - - /data/.state/steam/jellyfinmediaplayer"
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

  # Steam's power-menu "Sleep" issues a *software* suspend (login1 Suspend ->
  # systemd-suspend.service), which HandleSuspendKey=ignore does NOT catch (that
  # only covers the hardware key). This box must never actually suspend, so
  # replace the suspend action (and hibernate/hybrid) with sleepToTv -> a SIGUSR1
  # to the CEC daemon, which standbys the TV. Drop-ins (systemd ships the units).
  systemd.services.systemd-suspend.serviceConfig.ExecStart = lib.mkForce sleepToTv;
  systemd.services.systemd-hibernate.serviceConfig.ExecStart = lib.mkForce sleepToTv;
  systemd.services.systemd-hybrid-sleep.serviceConfig.ExecStart = lib.mkForce sleepToTv;

  # Power button -> soft-reboot. Out-of-band recovery for when Steam OR gamescope
  # (or the display itself) wedges and the in-Steam power menu is unreachable, so
  # a hung box can be fixed *physically* (e.g. by Naja) without SSH. Restarting
  # only steam-launcher (the old behaviour) relaunches Steam *inside* the existing
  # gamescope session — useless when gamescope/the compositor is what's stuck.
  #
  # `systemctl soft-reboot` (systemd-soft-reboot.service) tears down ALL of
  # userspace and re-execs PID 1, restarting everything — gamescope, Steam, and
  # the always-on services (monero/minecraft/jellyfin/syncthing) — as close to a
  # real reboot as possible. Crucially it keeps the running KERNEL and never
  # touches firmware/bootloader/initrd, so the dm-crypt mappings and mounts in
  # that kernel persist: NO FDE re-unlock (no YubiKey touch, no /data passphrase).
  # Two consequences of skipping initrd: (1) the @root impermanence rollback
  # (boot.initrd.systemd.services.rollback) does NOT run, so this is a userspace
  # restart, not a clean-slate wipe — for that you need a real reboot; (2) a new
  # kernel from a system update won't take effect until the next real reboot.
  #
  # acpid reads the power-button evdev directly at the system level, so it fires
  # even when the user session is frozen. Jovian's steamos-powerbuttond
  # (short-press suspend / long-press Steam menu) is neutered so it can't also
  # fire, and logind ignores the key so nothing races. Trade-off (chosen): the
  # power button no longer sleeps — sleep is now STEAM -> Power -> Sleep on the
  # controller, which still standbys the TV via the systemd-suspend hook above.
  #
  # Neuter powerbuttond by overriding its ExecStart to a no-op (a plain
  # enable=false won't mask it — Jovian ships it via a package, not
  # systemd.user.services, so the /etc/systemd/user symlink still points at the
  # real unit). ExecStart="" resets the package's line; `true` exits 0 so it
  # never reads the power-button evdev. Drop-in, like the systemd-suspend override.
  systemd.user.services.steamos-powerbuttond.serviceConfig.ExecStart =
    lib.mkForce ["" "${pkgs.coreutils}/bin/true"];
  services.logind.settings.Login.HandlePowerKey = "ignore";
  services.logind.settings.Login.HandlePowerKeyLongPress = "ignore";
  services.acpid = {
    enable = true;
    handlers.power-soft-reboot = {
      event = "button/power.*";
      action = "${pkgs.systemd}/bin/systemctl soft-reboot";
    };
  };

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
      hostKeys = [
        {
          path = "${secretDir}/ssh/${machine}";
          type = "ed25519";
        }
      ];
    };
  };

  networking.firewall = {
    allowedTCPPorts = [8384 8123];
  };

  users.extraUsers."${username}".openssh.authorizedKeys.keyFiles = [
    ../../../pubkeys/yubi-key.pub
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

  nix.settings.trusted-users = ["root" "nixremote"];

  # -------------------- Remote builder -------------------- #
  # Build offload over SSH (port 6000) as the trusted `nixremote` user.
  # These must stay NON-sk: nix-daemon cannot wait for a YubiKey touch.
  users.groups.nixremote = {};
  users.users.nixremote = {
    isNormalUser = true;
    group = "nixremote";
    openssh.authorizedKeys.keyFiles = [
      ../../../ssh-keys/age/work.pub
      ../../../ssh-keys/age/deck-oled.pub
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
  # No password on either account: auth is the YubiKey (pam_u2f) only, so a
  # locked `!` hash is the correct and only credential state.
  users.users."${username}" = {
    isNormalUser = true;
    extraGroups = ["networkmanager" "wheel" "sync"];
  };

  # Graphical seat. Not in wheel, no SSH keys. cectv is the CEC daemon's
  # entire privileged surface; deliberately NOT in `input`/`video`/`render`.
  users.groups."${gameUser}" = {};
  users.users."${gameUser}" = {
    isNormalUser = true;
    group = gameUser;
    extraGroups = ["networkmanager" "cectv"];
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
  # Touch-to-authenticate for sudo, TTY login, the SDDM greeter and the Plasma
  # lock screen. pam_u2f and pam_rssh are stacked "sufficient"; rssh is tried
  # first, so a forwarded SSH agent satisfies sudo without a key.
  #
  # System-wide authfile, not per-home: /home is wiped every boot. Public
  # credentials only, so not a secret. Both lines are the same YubiKey (U2F
  # binds to the origin, not the account). Register: `pamu2fcfg -o pam://desktop`.
  environment.etc."u2f_keys".text = ''
    user:TYg4k09qkMagOBBfoTdCgGo9Az7v/PiIV4wvEuMd2IK+BBicWtkiSexaDfnndS77+QW96YBnfdcrfPd1tzJH0w==,36ZOFFeRKCBl6SEEbw31Xw7tS8H+bRP7ZTBUmYlq6WMbNhdXfwfkHOL7J7WOQvvvxlcW0eEzNAjex1QIPnzjJQ==,es256,+presence
    steam:TYg4k09qkMagOBBfoTdCgGo9Az7v/PiIV4wvEuMd2IK+BBicWtkiSexaDfnndS77+QW96YBnfdcrfPd1tzJH0w==,36ZOFFeRKCBl6SEEbw31Xw7tS8H+bRP7ZTBUmYlq6WMbNhdXfwfkHOL7J7WOQvvvxlcW0eEzNAjex1QIPnzjJQ==,es256,+presence
  '';
  security.pam.u2f.settings.authfile = "/etc/u2f_keys";
  security.pam.services.sudo.u2fAuth = true;
  security.pam.services.login.u2fAuth = true;
  security.pam.services.sddm.u2fAuth = true;
  security.pam.services.kde.u2fAuth = true; # Plasma screen locker
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
    extraConfig = ''
      Defaults insults
      Defaults timestamp_timeout=0
    '';
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
