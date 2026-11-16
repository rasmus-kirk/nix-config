# Idea: Drop the posthog overlay

## Context

On 2026-10-19, nixpkgs marked `python3Packages.posthog` broken, because
one posthog test fails with mcp 2. Open WebUI needs posthog through
chromadb, so Open WebUI does not evaluate. On 2026-11-11, nixpkgs master
disabled that test and removed the broken flag in commit `71d91e12af8c`.
`modules/nixos/llmModules/chat/default.nix` applies the same fix as an
overlay. When the pinned `nixos-unstable` includes the commit, delete the
overlay.

## Changes

- `modules/nixos/llmModules/chat/default.nix`: delete the `nixpkgs.overlays`
  entry for posthog.
- `modules/nixos/llmModules/chat/README.md`: delete the "posthog overlay"
  section.

## Verification

1. Run `grep -c broken "$(nix eval --raw --inputs-from . nixpkgs#path)/pkgs/development/python-modules/posthog/default.nix"`. It must print 0.
2. Run `nix eval --raw .#nixosConfigurations.desktop.config.system.build.toplevel.drvPath`. It must print a store path.
