{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  # Helix expects the `haskell-language-server-wrapper` to be named `haskell-language-server`
  #hs-wrapper = pkgs.writeShellApplication {
  #  name = "haskell-language-server";
  #  text = ''
  #    haskell-language-server-wrapper
  #  '';
  #};
  cfg = config.kirk.helix;
  mostLsps = with pkgs; [
    # JSON, HTML, CSS, SCSS
    nodePackages_latest.vscode-langservers-extracted
    # Bash
    nodePackages_latest.bash-language-server
    # C-sharp
    omnisharp-roslyn
    # Docker files
    dockerfile-language-server
    # Typescript
    nodePackages_latest.typescript-language-server
    # Nix
    nil
    # Scala
    metals
    # Makdown
    marksman
    # Latex
    texlab
    # Haskell
    #hs-wrapper
    #haskell-language-server
    #ghc
    # Go
    gopls
    # Debugger: Rust/CPP/C/Zig
    lldb
  ];
in {
  options.kirk.helix = {
    enable = mkEnableOption "helix text editor";

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Extra packages to install, for example LSP's.";
    };

    installMostLsps = mkOption {
      type = types.bool;
      default = true;
      description = "Whether or not to install most of the LSP's that helix supports.";
    };
  };

  config = mkIf cfg.enable {
    # Install specified packages
    home.packages = mkMerge [
      cfg.extraPackages
      (mkIf cfg.installMostLsps mostLsps)
    ];

    programs.helix = {
      enable = true;
      defaultEditor = true;

      languages = {
        rust = {
          auto-format = true;
          roots = [
            "Cargo.toml"
            "Cargo.lock"
          ];
          language-server.rust-analyzer.config = {
            inlayHints.parameterHints.enable = false;
            diagnostics.experimental.enable = true;
            diagnostics.styleLints.enable = true;
          };
        };
        c-sharp = {
          language-server = {
            command = "dotnet";
            args = ["${pkgs.omnisharp-roslyn}/bin/OmniSharp" "--languageserver"];
          };
        };
      };

      settings = {
        theme = "gruvbox";

        editor = {
          mouse = true;
          auto-format = true;
          line-number = "relative";
          shell = ["zsh" "-c"];
          bufferline = "always";

          lsp = {
            display-messages = true;
            display-inlay-hints = true;
          };

          end-of-line-diagnostics = "hint";
          inline-diagnostics.cursor-line = "error";

          cursor-shape = {
            insert = "bar";
            normal = "block";
          };

          file-picker = {
            hidden = false;
          };

          whitespace = {
            render = {
              space = "none";
              nbsp = "all";
              tab = "all";
              newline = "all";
            };
            characters = {
              newline = "⌄";
            };
          };
        };

        # Make Helix more like kakoune
        keys.insert = {
          # Alt-s to save
          "A-s" = ":w";
          # Alt-w to close buffer
          "A-w" = ":buffer-close";

          "A-l" = "goto_next_buffer";
          "A-h" = "goto_previous_buffer";

          "C-h" = "jump_backward";
          "C-k" = "half_page_up";
          "C-j" = "half_page_down";
          "C-l" = "jump_forward";
        };

        keys.normal = {
          # Alt-s to save
          "A-s" = ":w";
          # Alt-w to close buffer
          "A-w" = ":buffer-close";

          W = "extend_next_word_end";
          B = "extend_prev_word_start";
          L = "extend_char_right";
          H = "extend_char_left";
          J = "extend_line_down";
          K = "extend_line_up";
          N = "extend_search_next";
          X = "extend_line_above";

          "A-x" = "extend_line_down";
          "A-X" = "extend_line_up";
          "A-n" = "search_prev";
          "A-N" = "extend_search_prev";
          "A-o" = "add_newline_below";
          "A-O" = "add_newline_above";
          "A-l" = "goto_next_buffer";
          "A-h" = "goto_previous_buffer";

          "C-h" = "jump_backward";
          "C-k" = "half_page_up";
          "C-j" = "half_page_down";
          "C-l" = "jump_forward";

          g = {
            k = "goto_file_start";
            j = "goto_file_end";
            i = "goto_first_nonwhitespace";
          };

          G = {
            l = "extend_to_line_end";
            h = "extend_to_line_start";
            i = "extend_to_first_nonwhitespace";
          };

          # TODO: make this depend on the helix max-width
          " " = {
            W = ":pipe fmt -w 80";
          };
        };
      };
    };
  };
}
