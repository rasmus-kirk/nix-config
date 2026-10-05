# Untrusted Windows games, declared exactly like kirk.steamShortcuts tiles but
# with the exe run through umu and Proton inside bubblewrap.
#
# No network, so a stolen Steam token cannot leave. No bind of the Steam data
# root, so there is nothing to steal. The session X socket is bound, so the game
# can see other X11 clients. Same uid as the session is only acceptable
# because ptrace_scope=1 stops the game attaching to the Steam client. Nothing
# here defends against a kernel or GPU-driver exploit.
#
# TODO After the first working launch on the desktop, remove these binds one at
# a time and keep only the ones the game needs.
# - /etc/passwd, /etc/group, /etc/machine-id, /etc/localtime
# - /run/opengl-driver-32
# - $XAUTHORITY
{
  config,
  options,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.sandboxedGames;

  owner = config.kirk.steamShortcuts.user;
  group = config.users.users.${owner}.group;
  home = config.users.users.${owner}.home;

  # Leading dot, so no sanitized game name can collide with it.
  runtimeRoot = "${cfg.stateDir}/.runtime";

  sanitize = name: toLower (strings.sanitizeDerivationName name);

  proton = pkgs.proton-ge-bin.steamcompattool;

  # No string shorthand.
  shortcutType = options.kirk.steamShortcuts.shortcuts.type.nestedTypes.elemType.nestedTypes.right;

  sandboxedProton = pkgs.writeShellApplication {
    name = "sandboxed-proton";
    runtimeInputs = with pkgs; [argc bubblewrap coreutils];
    inheritPath = false;
    text = ''
      # @describe Run a Windows exe inside the sandbox of a game.
      # @meta version 0.1.0
      # @arg game!  Dir name in ${cfg.stateDir}.
      # @arg exe!   Exe path relative to the game dir.
      # @arg args~  Arguments for the exe.

      main() {
        local home=${escapeShellArg home}
        local game="''${argc_game:-}"
        local exe="''${argc_exe:-}"
        local state=${escapeShellArg cfg.stateDir}/"$game"
        local runtime=${escapeShellArg runtimeRoot}

        if [[ $game == "" || $game == */* || $game == .* || ! -d $state ]]; then
          echo "sandboxed-proton: no game dir $state" >&2
          exit 1
        fi

        mkdir -p "$runtime/logs"
        exec > >(tee "$runtime/logs/$game.log") 2>&1

        local debug=()
        [[ -v PROTON_LOG ]] && debug+=(--setenv PROTON_LOG "$PROTON_LOG")
        [[ -v WINEDEBUG ]] && debug+=(--setenv WINEDEBUG "$WINEDEBUG")

        # Installs or updates the runtime. Only step with network, so outside the sandbox.
        # Games cannot write here, so no planted symlinks to follow.
        mkdir -p "$runtime/home"
        env -i HOME="$runtime/home" \
          XDG_DATA_HOME="$runtime" \
          XDG_CACHE_HOME="$runtime/cache" \
          PRESSURE_VESSEL_VARIABLE_DIR="$runtime/var" \
          UMU_NO_PROTON=1 PROTONPATH=${proton} \
          ${pkgs.umu-launcher}/bin/umu-run /usr/bin/true

        # Runtime overlay is a throwaway layer in RAM. umu and pressure-vessel write
        # into the runtime, but games must not change the shared copy.
        # No TZ, because unset host vars arrive empty and empty TZ means UTC.
        exec bwrap \
          --unshare-net --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup \
          --new-session --die-with-parent \
          --proc /proc --dev /dev --ro-bind /sys /sys \
          --ro-bind /nix/store /nix/store \
          --ro-bind /run/opengl-driver /run/opengl-driver \
          --ro-bind-try /run/opengl-driver-32 /run/opengl-driver-32 \
          --dev-bind /dev/dri /dev/dri \
          --dev-bind-try /dev/input /dev/input \
          --ro-bind-try /run/udev /run/udev \
          --ro-bind-try /etc/passwd /etc/passwd \
          --ro-bind-try /etc/group /etc/group \
          --ro-bind-try /etc/machine-id /etc/machine-id \
          --ro-bind-try /etc/localtime /etc/localtime \
          --tmpfs /tmp \
          --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix \
          --tmpfs "$XDG_RUNTIME_DIR" \
          --ro-bind-try "$XDG_RUNTIME_DIR/pipewire-0" "$XDG_RUNTIME_DIR/pipewire-0" \
          --ro-bind-try "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/pulse" \
          --ro-bind-try "''${XAUTHORITY-/nonexistent}" "''${XAUTHORITY-/nonexistent}" \
          --bind "$state" "$home" \
          --overlay-src "$runtime/umu" --tmp-overlay "$home/.local/share/umu" \
          --chdir "$home/$(dirname "$exe")" \
          --clearenv \
          --setenv PATH /usr/bin:/bin \
          --setenv PROTONPATH ${proton} \
          --setenv HOME "$home" \
          --setenv USER ${escapeShellArg owner} \
          --setenv XDG_DATA_HOME "$home/.local/share" \
          --setenv XDG_CACHE_HOME "$home/.cache" \
          --setenv WINEPREFIX "$home/prefix" \
          --setenv GAMEID "umu-$game" \
          --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" \
          --setenv DISPLAY "''${DISPLAY-}" \
          --setenv XAUTHORITY "''${XAUTHORITY-}" \
          --setenv LANG "''${LANG-}" \
          --setenv LANGUAGE "''${LANGUAGE-}" \
          --setenv LC_ALL "''${LC_ALL-}" \
          --setenv XDG_CURRENT_DESKTOP "''${XDG_CURRENT_DESKTOP-}" \
          --setenv XDG_SESSION_DESKTOP "''${XDG_SESSION_DESKTOP-}" \
          --setenv STEAM_MULTIPLE_XWAYLANDS "''${STEAM_MULTIPLE_XWAYLANDS-}" \
          --setenv SteamGameId "''${SteamGameId-}" \
          --setenv DXVK_FILTER_DEVICE_NAME "''${DXVK_FILTER_DEVICE_NAME-}" \
          --setenv VKD3D_FILTER_DEVICE_NAME "''${VKD3D_FILTER_DEVICE_NAME-}" \
          "''${debug[@]}" \
          -- ${pkgs.umu-launcher}/bin/umu-run "$home/$exe" "''${@:3}"
      }

      eval "$(argc --argc-eval "$0" "$@")"
    '';
  };

  mkLauncher = name: exe:
    pkgs.writeShellScriptBin "sandboxed-${name}" ''
      exec ${sandboxedProton}/bin/sandboxed-proton ${escapeShellArg name} ${escapeShellArg exe} "$@"
    '';
in {
  options.kirk.sandboxedGames = {
    enable = mkEnableOption "sandboxed Windows games and the sandboxed-proton command";

    stateDir = mkOption {
      type = types.str;
      example = "/data/.state/steam/sandboxed";
      description = "Holds one dir per game (game files, Wine prefix, saves) and the shared Steam Runtime in .runtime. Must not be inside the Steam root, or a game's home bind could expose Steam's data.";
    };

    games = mkOption {
      type = types.attrsOf shortcutType;
      default = {};
      description = "Untrusted Windows games. Same shape as the attrset form of kirk.steamShortcuts.shortcuts, except each exe is a Windows executable relative to the game's dir in stateDir. The tile launches a sandboxed wrapper instead.";
      example = literalExpression ''
        {
          "Some Itch Game" = {
            exe = "game/Game.exe";
            portrait = ../images/steam/some-game-portrait.png;
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    # Tile launches the wrapper, by a path that survives rebuilds.
    # Steam derives the appid from it.
    kirk.steamShortcuts.shortcuts =
      mapAttrs (name: s: s // {exe = "/run/current-system/sw/bin/sandboxed-${sanitize name}";}) cfg.games;

    environment.systemPackages = [sandboxedProton] ++ mapAttrsToList (name: s: mkLauncher (sanitize name) s.exe) cfg.games;

    systemd.tmpfiles.rules =
      ["d ${cfg.stateDir} 0770 ${owner} ${group} -"]
      ++ mapAttrsToList (name: _: "d ${cfg.stateDir}/${sanitize name} 0770 ${owner} ${group} -") cfg.games
      ++ ["A+ ${cfg.stateDir} - - - - g:${group}:rwX,d:g:${group}:rwX,m::rwx,d:m::rwx"];
  };
}
