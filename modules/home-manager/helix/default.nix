{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.helix;
  mostLsps = with pkgs; [
    # JSON, HTML, CSS, SCSS
    vscode-langservers-extracted
    # Bash
    bash-language-server
    # C-sharp
    omnisharp-roslyn
    # Docker files
    dockerfile-language-server
    # Typescript
    typescript-language-server
    # Nix
    nil
    # Scala
    metals
    # Markdown
    marksman
    # Latex
    texlab
    # Go
    gopls
    # Debugger: Rust/CPP/C/Zig
    lldb
    # Spellchecking
    harper
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
    home.packages = mkMerge [
      cfg.extraPackages
      (mkIf cfg.installMostLsps mostLsps)
    ];

    programs.helix = {
      enable = true;
      defaultEditor = true;

      languages = {
        language-server.harper-ls = {
          command = "harper-ls";
          args = ["--stdio"];
        };
        language-server.omnisharp = {
          command = "dotnet";
          args = ["${pkgs.omnisharp-roslyn}/bin/OmniSharp" "--languageserver"];
        };
        language-server.rust-analyzer.config = {
          inlayHints.parameterHints.enable = false;
          diagnostics.experimental.enable = true;
          diagnostics.styleLints.enable = true;
        };

        language = [
          {
            name = "markdown";
            language-servers = ["marksman" "harper-ls"];
          }
          {
            name = "rust";
            auto-format = true;
            roots = ["Cargo.toml" "Cargo.lock"];
            language-servers = [
              "rust-analyzer"
            ];
          }
          {
            name = "c-sharp";
            language-servers = ["omnisharp"];
          }
        ];
      };

      # Gruvbox renders whitespace at bg2 (#504945). bg1 sits closer to the
      # bg0 background, so the marks read as texture rather than characters.
      themes.gruvbox-dim-ws = {
        inherits = "gruvbox";
        "ui.virtual.whitespace" = "bg1";
      };

      settings = {
        theme = "gruvbox-dim-ws";

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
              space = "all";
              nbsp = "all";
              tab = "all";
              newline = "all";
            };
            characters = {
              newline = "⌄";
              space = "░";
            };
          };
        };

        # Make Helix more like kakoune
        keys.insert = {
          "A-s" = ":w";
          "A-w" = ":buffer-close";
          "C-r" = ":reload-all";

          "A-l" = "goto_next_buffer";
          "A-h" = "goto_previous_buffer";

          "C-h" = "jump_backward";
          "C-k" = "half_page_up";
          "C-j" = "half_page_down";
          "C-l" = "jump_forward";
        };

        keys.normal = {
          "A-s" = ":w";
          "A-w" = ":buffer-close";
          "C-r" = ":reload-all";

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
