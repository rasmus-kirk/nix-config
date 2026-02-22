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
    programs.delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        # TODO: Locked to gruvmax-fang, but hard to change
        side-by-side = true;
        features = "gruvmax-fang";
      };
    };

    programs.git = {
      enable = true;
      settings = {
        user.email = cfg.userEmail;
        user.name = cfg.userName;
        alias = {
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
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        include = {
          # Get delta color themes
            path = pkgs.fetchFromGitHub {
                owner = "dandavison";
                repo = "delta";
                rev = "ac396c3fdc5940c724e1f00a519358c27979b539";
                sha256 = "sha256-J7g1EMcWFSfcELCn/uDQxzat2zoAw+7PornptEPlNd8=";
              }
              + "/themes.gitconfig";
        };
        pull.rebase = false;
      };
    };
  };
}
