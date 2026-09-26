# Declarative EmuDeck replacement, because EmuDeck is an imperative installer that does not fit impermanence.
# The shortcut appid is crc32(exe + AppName), so tiles that share a launcher still get unique artwork.
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

  # An --appendconfig overlay moves data dirs into the synced tree without owning the mutable retroarch.cfg.
  retroarchDirs = pkgs.writeText "retroarch-dirs.cfg" ''
    system_directory = "${ps1Bios}"
    savefile_directory = "${ps1Games}"
    savestate_directory = "${ps1Games}"
    sort_savefiles_enable = "false"
    sort_savestates_enable = "false"
  '';

  emu-psx = pkgs.writeShellScriptBin "emu-psx" ''
    exec ${retroarchWithCores}/bin/retroarch -f --appendconfig ${retroarchDirs} -L ${swanstationCore} "$@"
  '';

  emu-switch = pkgs.writeShellScriptBin "emu-switch" ''
    exec ${pkgs.ryubing}/bin/Ryujinx "$@"
  '';

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

  romPath = sysGames: rom:
    if hasPrefix "/" rom
    then rom
    else "${sysGames}/${rom}";

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
        Syncable tree holding everything a device needs to play (ROMs, BIOS and
        saves), laid out per system (ps1/, switch/). Point Syncthing at this (or a
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

    # Ryujinx cannot split saves from its data dir, so the whole data dir is synced.
    systemd.tmpfiles.rules =
      [
        "d ${cfg.gamesDir}                     0755 ${cfg.user} users -"
        # Create ~/.config as the user first, else the L+ rules create it root-owned and home-manager fails.
        "d /home/${cfg.user}/.config           0755 ${cfg.user} users -"
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

    kirk.steamShortcuts.shortcuts = mkMerge [
      (mkIf cfg.ps1.enable ps1Shortcuts)
      (mkIf cfg.switch.enable switchShortcuts)
    ];
  };
}
