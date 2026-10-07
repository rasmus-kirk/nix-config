# Idea: gradual migration to the dendritic pattern

## Context

The repo uses the conventional layout:

- `modules/nixos/default.nix` and `modules/home-manager/default.nix` list every feature by hand.
- A feature that needs both classes (`ssh`, `yubikey`, `claudeConfig`) is split across the two trees.
- `flake.nix` holds three near-identical `nixosSystem` blocks and wires `inputs` through `specialArgs`, `extraSpecialArgs` and `config._module.args`.
- Hosts live in `configurations/{nixos,home-manager}/<host>/`, apart from where they are composed.

Dendritic pattern:

- Every `.nix` file under one directory is a top-level flake-parts module, loaded with `import-tree`.
- A file owns one feature and declares it per class, for example `flake.modules.nixos.ssh` and `flake.modules.homeManager.ssh`.
- A host is a file that defines `flake.nixosConfigurations.<name>`, lists the feature modules it wants and holds its own settings.
- Modules reach each other through the top-level config, so `specialArgs` plumbing goes away.
- File location carries no meaning.

flake-parts is not required. A plain `lib.evalModules` with a `lazyAttrsOf deferredModule` option does the same job. flake-parts is the cheaper choice unless its ecosystem is unwanted.

The existing `kirk.*` option design stays unchanged. Only the wiring moves.

Scope: all three hosts and the sandbox home configs, done gradually. A half-migrated repo is a valid end state.

A feature lives in exactly one tree. Move it, never copy it, or its options are declared twice and evaluation fails.

## Steps

### 1. Skeleton and bridge

- Add `flake-parts` and `import-tree` as inputs.
- Make `outputs` a `flake-parts.lib.mkFlake {inherit inputs;} (import-tree ./flake-modules)` call and import `flake-parts.flakeModules.modules`.
- Move the existing outputs into files under `flake-modules/`, unchanged. Keep `devShells`, `packages` and `formatter` on `forAllSystems` through `flake.*` so nothing changes.
- Add one bridge file exposing the old trees:
  ```nix
  {
    flake.modules.nixos.base = ../modules/nixos;
    flake.modules.homeManager.base = ../modules/home-manager;
  }
  ```
- Keep `nixosModules.default` and `homeManagerModules.default`, since `mkSandbox` and other flakes use them.
- Hosts stay as they are.

### 2. Next new feature, written dendritic

- Pick a feature that is being added anyway.
- Put it in one file under `flake-modules/` with both the nixos and home-manager parts.
- Touch nothing old. This is the practice run.

### 3. Migrate on touch

- First point `website-builder` at the evaluated modules. It takes `./modules/home-manager` and `./modules/nixos` as paths, so the option docs shrink once features leave those trees.
- When an old feature needs an edit, move it into the new style first, then make the edit.
- Delete its line from the old `default.nix`.
- Start with the paired features.

### 4. Hosts, one at a time

- Move one `nixosSystem` block to `flake-modules/hosts/<name>.nix`.
- It imports the existing `configuration.nix` and `home.nix` unchanged and lists `base`.
- Drop the `specialArgs` wiring for that host.
- Order: `work` or `deck-oled` first, `desktop` last.

### 5. Cleanup

- When the old import lists are empty, delete them and the old trees.
- Convert the sandbox and installer home configs last. They use `extraSpecialArgs` and are not NixOS hosts.

## Verification

1. After each step, this prints the same path as before the step for `desktop`, `deck-oled` and `work`, and likewise for the `homeConfigurations`. A changed path means the step was not a pure move.
   ```
   nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
   ```
2. `nix flake check` passes.
3. After step 3, the option documentation site still lists every option.
