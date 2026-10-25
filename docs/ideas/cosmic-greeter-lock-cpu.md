# Idea: Fix cosmic-greeter CPU busy loop while locked

## Context

On `work`, `cosmic-greeter` 1.9.1 holds one CPU core at 100% for the whole
time the screen is locked, and `cosmic-comp` adds about 20%. The fans spin up.
A `top` log of a 5 minute lock shows total CPU go from 1.5% to 8.4%, nearly
all of it in these two processes. Upstream 1.10.0 has no fix. The open issue
pop-os/cosmic-greeter#491 reports the same symptom and has no response.

Hot path, from a `perf` profile and the source at `epoch-1.9.1`:

- `src/locker.rs:936-976` runs `pam_thread` in a `loop`. On `Err` it sends
  `Message::Error` and calls `pam_authenticate` again at once, with no delay
  and no wait for user input.
- On `work` the `cosmic-greeter` PAM stack is `pam_u2f` only
  (`modules/nixos/yubikey/default.nix`, `unixAuth = false`). Without a key
  touch, `pam_u2f` fails in milliseconds. `pam_unix` sets a 2 s fail delay,
  which hides the loop on default stacks.
- The journal shows `authentication error: Authentication failure` every
  6 ms, about 150 times per second. Each cycle reloads the PAM modules, scans
  all udev devices in `fido_dev_info_manifest`, and makes the UI redraw.

Fix in the greeter: start a new `pam_thread` at most once per second.
Attempts that wait for input or run `pam_unix` already take longer and see no
extra delay. Do not work around it with `pam_faildelay` in this repo.

Plan:

1. Clone `pop-os/cosmic-greeter` to `.scratchpad/cosmic-greeter`.
2. Fix the loop in one unsigned commit on branch `fix-pam-retry-busy-loop`
   on top of `master`. Amend that commit, never stack more. Claude commits
   in no other repo.
3. Build `work` with the local source.
4. The user opens a PR upstream from a fork. Claude drafts the PR text with
   the `pr-description` skill and does not push or post.

## Changes

- `flake.nix`: add a non-flake input
  `cosmic-greeter-src.url = "git+file:///data/.system-configuration/.scratchpad/cosmic-greeter?ref=fix-pam-retry-busy-loop"`
  with `flake = false`. The input locks the committed `rev`, so run
  `nix flake update cosmic-greeter-src` after each amend. After the PR
  exists, point it at the fork branch. Remove the input when nixpkgs ships
  the fix.
- `configurations/nixos/work/configuration.nix`: add a `nixpkgs.overlays`
  entry that overrides `cosmic-greeter` with:
  - `src = inputs.cosmic-greeter-src`.
  - `cargoDeps` from `rustPlatform.fetchCargoVendor`, because `master` has
    a different `Cargo.lock` than the 1.9.1 package.
  - `env.VERGEN_GIT_SHA` from the input `rev`, because the package reads
    `src.tag`, which a git input lacks.

## Verification

1. Record a profile while locked:
   `nix shell nixpkgs#perf -c perf record -F 99 --call-graph dwarf -p <greeter pid> -o greeter.perf.data -- sleep 180`,
   then `perf report -i greeter.perf.data --no-children` names the hot loop.
2. `readlink /proc/<greeter pid>/exe` points to the overridden store path
   after a rebuild and a re-login.
3. `top -b -d 5 -n 60 -o %CPU` while locked shows `.cosmic-greeter` below
   5% CPU and total CPU near the unlocked baseline of about 1.5%.
4. Unlock with a YubiKey touch still works, also when the key is plugged
   in after the lock.
