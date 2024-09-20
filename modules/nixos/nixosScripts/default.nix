{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.nixosScripts;

  nos-update = pkgs.writeShellApplication {
    name = "nos-update";
    text = ''
      nix flake update --flake ${cfg.configDir}
    '';
  };

  nos-upgrade = pkgs.writeShellApplication {
    name = "nos-upgrade";
    text = ''
      # Update, switch to new config, and cleanup
      ${nos-update}/bin/nos-update &&
      ${nos-rebuild}/bin/nos-rebuild &&
      ${nos-clean}/bin/nos-clean &&
      hm-upgrade || echo "Couldn't run home-manager upgrade script, perhaphs you don't have home-manager scripts enabled? Upgrade otherwise successful."
    '';
  };

  nos-clean = pkgs.writeShellApplication {
    name = "nos-clean";
    text = ''
      # Delete old home-manager profiles
      nix-env --delete-generations 30d &&
      # Delete old nix profiles
      nix profile wipe-history --older-than 30d &&
      # Optimize space
      nix store gc &&
      nix store optimise
    '';
  };

  nos-rebuild = pkgs.writeShellApplication {
    name = "nos-rebuild";
    text = ''
      nix flake update nixarr --flake ${cfg.configDir}
      # Update the inputs of this repo on every rebuild
      nix flake update kirk-modules --flake ${cfg.configDir} &&
      # Switch configuration, backing up files
      # impure is a little disgusting, but will cause issues otherwise
      nixos-rebuild switch --flake ${cfg.configDir}#${cfg.machine} --show-trace --impure
    '';
  };
in {
  options.kirk.nixosScripts = {
    enable = mkEnableOption ''
      Nixos scripts

      Required options:
      - `machine`
    '';

    machine = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "REQUIRED! The machine to run on.";
    };

    configDir = mkOption {
      type = types.path;
      default = "/etc/nixos";
      description = "Path to the nixos configuration.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      nos-update
      nos-upgrade
      nos-clean
      nos-rebuild
    ];
  };
}
