{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.git;
in {
  options.kirk.git = {
    enable = mkEnableOption "git";

    userEmail = mkOption {
      type = types.str;
      description = "What email address to use for git.";
    };

    userName = mkOption {
      type = types.str;
      description = "Username to use for git.";
    };
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;
      userEmail = cfg.userEmail;
      userName = cfg.userName;
      delta = {
        enable = true;
        options = {
          # TODO: Locked to gruvmax-fang, but hard to change
          features = "gruvmax-fang";
        };
      };
      includes = [
        # Delta plugins
        {
          path =
            pkgs.fetchFromGitHub {
              owner = "dandavison";
              repo = "delta";
              rev = "85e2f8e490498629a806af01b960e0510bff3973";
              sha256 = "sha256-vEv3HdLeI3ZXBCSmvd0x7DgEu+DiQqEwFf+WLDdL+4U=";
            }
            + "/themes.gitconfig";
        }
      ];
      aliases = {
        tree = "log --graph --decorate --pretty=oneline --abbrev-commit";
        unstage = "restore --staged";
        update = "submodule update --init --recursive";

        a = "add .";
        ca = "commit -a";
        c = "commit";
        co = "checkout --recurse-submodules";
        dc = "diff --cached";
        d = "diff";
        l = "log";
        s = "status";
        su = "status -uno";
      };
      extraConfig = {
        push = {
          autoSetupRemote = true;
        };
        pull = {
          rebase = true;
        };
      };
    };
  };
}
