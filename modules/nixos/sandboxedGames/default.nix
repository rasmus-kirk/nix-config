# Untrusted game binaries, declared exactly like kirk.steamShortcuts tiles but
# with the exe wrapped in bubblewrap before being handed on.
#
# No network, so a stolen Steam token cannot leave. No bind of the Steam data
# root, so there is nothing to steal. No X socket: Wayland clients cannot see
# each other, X11 clients can. Same uid as the session is only acceptable
# because ptrace_scope=1 stops the game attaching to the Steam client. Nothing
# here defends against a kernel or GPU-driver exploit.
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
  # Sandbox state sits beside the Steam root it is being kept away from.
  stateRoot = "${builtins.dirOf config.kirk.steamShortcuts.steamRoot}/sandboxed";

  binOf = name: "sandboxed-${replaceStrings [" "] ["-"] name}";
  stateOf = name: "${stateRoot}/${replaceStrings [" "] ["-"] name}";

  mkLauncher = name: exe:
    pkgs.writeShellScriptBin (binOf name) ''
      exec ${pkgs.bubblewrap}/bin/bwrap \
        --unshare-net --unshare-pid --unshare-ipc --unshare-uts --unshare-cgroup \
        --new-session --die-with-parent --clearenv \
        --proc /proc --dev /dev --dev-bind /dev/dri /dev/dri \
        --ro-bind /sys /sys \
        --ro-bind /nix/store /nix/store \
        --ro-bind /run/opengl-driver /run/opengl-driver \
        --ro-bind-try /etc/fonts /etc/fonts \
        --tmpfs /tmp \
        --tmpfs "$XDG_RUNTIME_DIR" \
        --ro-bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" \
        --ro-bind-try "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/pulse" \
        --bind ${stateOf name} "$HOME" \
        --ro-bind ${builtins.dirOf exe} ${builtins.dirOf exe} \
        --setenv HOME "$HOME" \
        --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" \
        --setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY" \
        --setenv LANG "''${LANG:-C.UTF-8}" \
        --setenv SDL_VIDEODRIVER wayland \
        -- ${exe} "$@"
    '';

  sandbox = name: s: let
    shortcut =
      if isString s
      then {exe = s;}
      else s;
  in
    shortcut // {exe = "${mkLauncher name shortcut.exe}/bin/${binOf name}";};
in {
  options.kirk.sandboxedGames = mkOption {
    type = options.kirk.steamShortcuts.shortcuts.type;
    default = {};
    description = "Untrusted games. Same shape as kirk.steamShortcuts.shortcuts, except each exe is replaced by a sandboxed wrapper before the tile is registered.";
    example = literalExpression ''
      {
        "Some Itch Game" = {
          exe = "/persist/games/untrusted/some-game/game.x86_64";
          portrait = ../images/steam/some-game-portrait.png;
        };
      }
    '';
  };

  config = mkIf (cfg != {}) {
    kirk.steamShortcuts.shortcuts = mapAttrs sandbox cfg;

    systemd.tmpfiles.rules =
      ["d ${stateRoot} 0700 ${owner} ${group} -"]
      ++ mapAttrsToList (name: _: "d ${stateOf name} 0700 ${owner} ${group} -") cfg;
  };
}
