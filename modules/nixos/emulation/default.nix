# Console emulation for the game-mode desktop, EmuDeck-style but declarative.
#
# EmuDeck itself is an imperative SteamOS installer and doesn't fit NixOS +
# impermanence, so we assemble the same pieces from nixpkgs, gated per system:
#   - ps1    -> RetroArch with the SwanStation core (the maintained open-source
#              DuckStation fork; standalone DuckStation was dropped from nixpkgs
#              after its 2024 non-free relicense).
#   - switch -> Ryubing (the community continuation of Ryujinx, which Nintendo
#              forced offline in 2024).
#
# Instead of the imperative Steam ROM Manager, games are declared here (ROM path
# + SteamGridDB artwork) and fed straight into kirk.steamShortcuts, so each game
# becomes a game-mode tile on rebuild — no GUI parse/save step. Every tile of a
# system shares one launcher (emu-psx/emu-switch) and passes its ROM via
# LaunchOptions; the shortcut appid is crc32(exe+AppName), so a shared exe still
# yields a unique tile + artwork per game.
#
# Storage layout — everything a device needs to *play* (ROMs, BIOS, saves) lives
# in one syncable tree per system under gamesDir, so Syncthing'ing a single dir
# (e.g. gamesDir/ps1) mirrors the whole library — and the saves — to the Deck:
#
#   ${gamesDir}/ps1/bios          RetroArch system dir (PS1 BIOS)
#   ${gamesDir}/ps1/games         ROMs + .srm/.state saves (RetroArch saves
#                                 next-to-content, forced via --appendconfig)
#   ${gamesDir}/switch/games      ROMs
#   ${gamesDir}/switch/data       Ryujinx data dir — saves (emulated NAND) live
#                                 here alongside keys/firmware/config, since
#                                 Ryujinx can't split saves out (~/.config/Ryujinx)
#
# Device-specific RetroArch config (retroarch.cfg, cores, input maps) stays LOCAL
# under stateDir, NOT in the synced tree. Switch is all-or-nothing: its data dir
# holds saves+keys+firmware+config together, so those sync too.
#
# BIOS/keys/firmware and the ROMs themselves are user-supplied (copyrighted,
# dumped from your own hardware).
{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.emulation;

  ps1Dir = "${cfg.gamesDir}/ps1";
  ps1Bios = "${ps1Dir}/bios";
  ps1Games = "${ps1Dir}/games";
  switchDir = "${cfg.gamesDir}/switch";
  switchGames = "${switchDir}/games";
  switchData = "${switchDir}/data";

  retroarchWithCores = pkgs.retroarch.withCores (cores: [
    cores.swanstation
    cores.beetle-psx-hw
  ]);

  swanstationCore = "${pkgs.libretro.swanstation}/lib/retroarch/cores/swanstation_libretro.so";

  # Force RetroArch's data dirs into the syncable tree without owning the mutable
  # main retroarch.cfg: an --appendconfig overlay (its values take priority).
  # Saves/states go next-to-content (= the ROM dir), so they sync with the ROMs.
  retroarchDirs = pkgs.writeText "retroarch-dirs.cfg" ''
    system_directory = "${ps1Bios}"
    savefile_directory = "${ps1Games}"
    savestate_directory = "${ps1Games}"
    sort_savefiles_enable = "false"
    sort_savestates_enable = "false"
  '';

  # Shared launchers Steam tiles point at: `emu-psx <rom>` boots RetroArch on the
  # SwanStation core fullscreen; `emu-switch <rom>` boots Ryubing.
  emu-psx = pkgs.writeShellScriptBin "emu-psx" ''
    exec ${retroarchWithCores}/bin/retroarch -f --appendconfig ${retroarchDirs} -L ${swanstationCore} "$@"
  '';

  emu-switch = pkgs.writeShellScriptBin "emu-switch" ''
    exec ${pkgs.ryubing}/bin/Ryujinx "$@"
  '';

  # Per-game artwork, mirroring kirk.steamShortcuts' shortcut artwork fields.
  gameType = types.submodule {
    options = {
      rom = mkOption {
        type = types.str;
        description = ''
          ROM path. Absolute, or a name/relative path resolved under this
          system's ROM dir ("''${gamesDir}/ps1/games" or
          "''${gamesDir}/switch/games"). The launcher receives it as its sole
          argument.
        '';
        example = "Final Fantasy VII (Disc 1).chd";
      };
      icon = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Icon image, shown in list view.";
      };
      portrait = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Library capsule (portrait, ~600x900).";
      };
      landscape = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Grid image (landscape, ~920x430).";
      };
      hero = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Hero banner (~1920x620).";
      };
      logo = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Logo (transparent PNG).";
      };
    };
  };

  # Resolve a bare ROM name/relative path against its system's ROM dir; keep
  # absolute paths as-is.
  romPath = sysGames: rom:
    if hasPrefix "/" rom
    then rom
    else "${sysGames}/${rom}";

  # Map declared games to kirk.steamShortcuts entries: shared launcher exe, the
  # ROM (quoted) in LaunchOptions, and the game's artwork.
  mkShortcuts = sysGames: exe:
    mapAttrs (_name: g: {
      inherit exe;
      launchOptions = "\"${romPath sysGames g.rom}\"";
      inherit (g) icon portrait landscape hero logo;
    });

  ps1Shortcuts = mkShortcuts ps1Games "${emu-psx}/bin/emu-psx" cfg.ps1.games;
  switchShortcuts = mkShortcuts switchGames "${emu-switch}/bin/emu-switch" cfg.switch.games;
in {
  options.kirk.emulation = {
    enable = mkEnableOption "console emulation (enable per-system stacks below)";

    user = mkOption {
      type = types.str;
      default = "user";
      description = "User whose Steam library gets the tiles and whose ~/.config holds the emulator config.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/data/.state/user";
      description = "User's state root for device-local emulator config (RetroArch's ~/.config/retroarch), kept out of the synced games tree.";
    };

    gamesDir = mkOption {
      type = types.str;
      default = "/data/.state/games";
      description = ''
        Syncable tree holding everything a device needs to play — ROMs, BIOS and
        saves — laid out per system (ps1/, switch/). Point Syncthing at this (or a
        single system subdir) to mirror the library + saves to another device.
      '';
    };

    ps1 = {
      enable = mkEnableOption "PS1 emulation via RetroArch + the SwanStation core";

      games = mkOption {
        type = types.attrsOf gameType;
        default = {};
        description = ''
          Declarative PS1 games. Each attribute name is the Steam tile title; the
          value gives the ROM path and optional SteamGridDB artwork. Each becomes
          a non-Steam shortcut (via kirk.steamShortcuts) launched with emu-psx.
        '';
        example = literalExpression ''
          {
            "Final Fantasy VII" = {
              rom = "Final Fantasy VII (Disc 1).m3u";
              portrait = ../images/steam/ff7-portrait.png;
              landscape = ../images/steam/ff7-landscape.png;
            };
          }
        '';
      };
    };

    switch = {
      enable = mkEnableOption "Nintendo Switch emulation via Ryubing (Ryujinx fork)";

      games = mkOption {
        type = types.attrsOf gameType;
        default = {};
        description = ''
          Declarative Switch games. Each attribute name is the Steam tile title;
          the value gives the ROM path and optional SteamGridDB artwork. Each
          becomes a non-Steam shortcut (via kirk.steamShortcuts) launched with
          emu-switch. Requires prod.keys + firmware installed under Ryubing.
        '';
        example = literalExpression ''
          {
            "The Legend of Zelda: Tears of the Kingdom" = {
              rom = "totk.nsp";
              portrait = ../images/steam/totk-portrait.png;
            };
          }
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages =
      optionals cfg.ps1.enable [retroarchWithCores emu-psx]
      ++ optionals cfg.switch.enable [pkgs.ryubing emu-switch];

    # Create the syncable game tree and link device-local/emulator-fixed config
    # paths into their state homes. RetroArch config stays local under stateDir;
    # Ryujinx's whole data dir lives in the synced tree (saves can't be split out).
    systemd.tmpfiles.rules =
      [
        "d ${cfg.gamesDir}                     0755 ${cfg.user} users -"
      ]
      ++ optionals cfg.ps1.enable [
        "d ${ps1Dir}                           0755 ${cfg.user} users -"
        "d ${ps1Bios}                          0755 ${cfg.user} users -"
        "d ${ps1Games}                         0755 ${cfg.user} users -"
        "d ${cfg.stateDir}/retroarch           0755 ${cfg.user} users -"
        "L+ /home/${cfg.user}/.config/retroarch - - - - ${cfg.stateDir}/retroarch"
      ]
      ++ optionals cfg.switch.enable [
        "d ${switchDir}                        0755 ${cfg.user} users -"
        "d ${switchGames}                      0755 ${cfg.user} users -"
        "d ${switchData}                       0755 ${cfg.user} users -"
        "L+ /home/${cfg.user}/.config/Ryujinx   - - - - ${switchData}"
      ];

    # Auto-register the declared games as game-mode tiles. Merges with any
    # shortcuts declared elsewhere (attrset merge); steamShortcuts is enabled in
    # configuration.nix and reconciles shortcuts.vdf before each Steam launch.
    kirk.steamShortcuts.shortcuts = mkMerge [
      (mkIf cfg.ps1.enable ps1Shortcuts)
      (mkIf cfg.switch.enable switchShortcuts)
    ];
  };
}
