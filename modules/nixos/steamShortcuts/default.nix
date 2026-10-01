# Steam reads shortcuts.vdf at startup and rewrites it on exit, so the worker edits it only while Steam is down.
{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.steamShortcuts;
  pyEnv = pkgs.python3.withPackages (ps: [ps.vdf]);

  shortcutType = types.submodule {
    options = {
      exe = mkOption {
        type = types.str;
        description = "Absolute path to the executable to launch.";
      };
      launchOptions = mkOption {
        type = types.str;
        default = "";
        description = "Steam launch options (env vars, %command%, etc.).";
      };
      icon = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Icon image, shown in list view.";
      };
      portrait = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Library capsule (portrait, ~600x900), installed as <appid>p.png.";
      };
      landscape = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Grid image (landscape, ~920x430), installed as <appid>.png.";
      };
      hero = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Hero banner (~1920x620), installed as <appid>_hero.png.";
      };
      logo = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Logo (transparent PNG), installed as <appid>_logo.png.";
      };
    };
  };

  normalize = _name: v:
    if isString v
    then {
      exe = v;
      launchOptions = "";
      icon = null;
      portrait = null;
      landscape = null;
      hero = null;
      logo = null;
    }
    else {inherit (v) exe launchOptions icon portrait landscape hero logo;};

  desiredFile = pkgs.writeText "steam-shortcuts.json" (builtins.toJSON {
    prune = cfg.pruneUnmanaged;
    shortcuts = mapAttrs normalize cfg.shortcuts;
  });
in {
  options.kirk.steamShortcuts = {
    enable = mkEnableOption "declaratively-managed non-Steam shortcuts";

    pruneUnmanaged = mkEnableOption "removal of any non-Steam shortcut not declared here (fully authoritative, also de-duplicates)";

    user = mkOption {
      type = types.str;
      example = "user";
      description = "User whose Steam shortcuts.vdf is managed (the worker runs as this user).";
    };

    steamRoot = mkOption {
      type = types.str;
      default = "/home/${cfg.user}/.local/share/Steam";
      defaultText = literalExpression "\"/home/\${cfg.user}/.local/share/Steam\"";
      description = ''
        Steam data root containing userdata/. Set this to the real persisted
        location when ~/.local/share/Steam is a symlink (impermanence), so the
        service doesn't depend on home-manager activation ordering.
      '';
    };

    shortcuts = mkOption {
      type = types.attrsOf (types.either types.str shortcutType);
      default = {};
      example = literalExpression ''
        {
          # shorthand: name = exe
          "Firefox" = "/run/current-system/sw/bin/firefox";
          # rich: exe + optional launch options + SteamGridDB artwork
          "Jellyfin Desktop" = {
            exe = "/run/current-system/sw/bin/jellyfin-desktop";
            portrait = ./art/jellyfin-capsule.png;          # repo file
            hero = pkgs.fetchurl {                            # or a pinned fetch
              url = "https://cdn2.steamgriddb.com/.../hero.png";
              hash = "sha256-...";
            };
            logo = ./art/jellyfin-logo.png;
            icon = ./art/jellyfin-icon.png;
          };
        }
      '';
      description = ''
        Non-Steam shortcuts to ensure exist. Each entry is either an executable
        path (string shorthand) or an attrset with `exe` plus optional
        `launchOptions` and SteamGridDB artwork (`icon`, `portrait`, `landscape`,
        `hero`, `logo`). Artwork may be a repo file (./foo.png) or a pinned fetch
        (pkgs.fetchurl { ... }); it's installed into userdata/<id>/config/grid/
        under the shortcut's computed appid. The working directory defaults to
        the executable's directory.
      '';
    };
  };

  config = mkIf cfg.enable {
    # A user service, because on Jovian only the user instance restarts on each gaming-session entry.
    # No RemainAfterExit, so the unit re-runs each session.
    systemd.user.services.steam-shortcuts = {
      description = "Apply declarative non-Steam shortcuts + artwork to Steam";
      wantedBy = ["steam-launcher.service"];
      before = ["steam-launcher.service"];
      path = [pkgs.procps]; # pgrep, for the "is Steam running?" guard
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pyEnv}/bin/python3 ${./apply-steam-shortcuts.py} ${desiredFile} ${cfg.steamRoot}";
      };
    };
  };
}
