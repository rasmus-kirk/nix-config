# Handoff: prebuilt system upgrades for the Steam Decks

Status: plan approved, nothing implemented yet.

## Context

The Deck (`deck-oled`) upgrades with `system.autoUpgrade` from GitHub. It evaluates the flake on its own CPU, downloads cache hits itself and offloads the rest to the desktop. This is slow.

New model:

- The desktop builds each Deck's system as part of its own rebuild, from the same commit.
- The Deck asks the desktop for the store path, copies it and activates it.
- No evaluation and no building on the Deck. No timer, flake URL or signing key on the desktop.

A Deck gets a new system only after the desktop is rebuilt. This is intended.

Scope: `deck-oled` now. `deck-lcd` later with no module changes. `work` keeps plain remote builds.

## Changes

### `modules/nixos/remoteBuilds/default.nix`

Server:

- New option `server.prebuiltHosts` (list of str, default `[]`).
- Take `inputs` as a module arg (already in `specialArgs`, `inputs.self` is the flake).
- Build one directory of host to toplevel links:
  ```nix
  prebuilt = pkgs.linkFarm "prebuilt-systems" (map (host: {
    name = host;
    path = inputs.self.nixosConfigurations.${host}.config.system.build.toplevel;
  }) cfg.server.prebuiltHosts);
  ```
- Add one case to `dispatch`:
  ```
  "latest "*)
    host=''${SSH_ORIGINAL_COMMAND#latest }
    [[ $host =~ ^[a-z0-9-]+$ ]] && readlink ${prebuilt}/"$host" || { echo "denied" >&2; exit 1; } ;;
  ```
  The regex blocks path traversal. An unknown host fails `readlink`. The script references `prebuilt`, so the desktop builds every listed system and keeps them as GC roots through its own system closure. No `/etc` entry needed.

Client:

- New option `client.prebuilt.enable`.
- When set, add `nixos-prebuilt-upgrade` service and timer (`OnCalendar = "daily"`, `Persistent = true`, `After`/`Wants` `network-online.target`).
- Service script (root, `pkgs.writeShellScript`, `set -euo pipefail`):
  1. `path=$(ssh -i ${sshKey} desktop-builder latest ${config.networking.hostName})`
  2. Require `$path` to match `/nix/store/*-nixos-system-${hostName}-*`, else fail.
  3. Exit 0 if `$path` equals `readlink -f /nix/var/nix/profiles/system`. Compare against the profile, not `/run/current-system`, since `boot` does not change the running system.
  4. `nix copy --no-check-sigs --from "ssh-ng://desktop-builder?ssh-key=${sshKey}" "$path"`
  5. `nix build --no-link --profile /nix/var/nix/profiles/system "$path"`
  6. `"$path"/bin/switch-to-configuration boot`
- `ExecCondition` reachability check moves here, with `?ssh-key=${sshKey}` added. The current one in `deck-oled` has no key, so root's SSH probably has no identity and the check may always fail. Verify on the Deck.

### `configurations/nixos/desktop/configuration.nix`

```nix
kirk.remoteBuilds.server.prebuiltHosts = ["deck-oled"];
```

### `configurations/nixos/deck-oled/configuration.nix`

- Remove `system.autoUpgrade` and the `nixos-upgrade` `ExecCondition` line.
- Set `kirk.remoteBuilds.client.prebuilt.enable = true;`

### Adding `deck-lcd` later

1. Add `"deck-lcd"` to `prebuiltHosts`.
2. Add `ssh-keys/age/deck-lcd.pub` to `authorizedKeyFiles`.
3. Enable `kirk.remoteBuilds.client` and `client.prebuilt` in its config.

## Verification

1. `nix flake check` and `nix build .#nixosConfigurations.{desktop,deck-oled}.config.system.build.toplevel`.
2. Confirm the deck toplevel is in the desktop closure: `nix path-info -r <desktop toplevel> | grep nixos-system-deck-oled`.
3. Rebuild the desktop. From the Deck as root, `ssh -i <key> desktop-builder latest deck-oled` prints a store path. `latest desktop`, `latest ../x` and other commands print `denied`.
4. On the Deck, `systemctl start nixos-prebuilt-upgrade`, check `journalctl -u nixos-prebuilt-upgrade`, confirm a new generation in `/nix/var/nix/profiles/`.
5. Run it again. It exits early with no new generation.
6. Reboot the Deck, confirm `readlink /run/current-system` equals the printed path.

