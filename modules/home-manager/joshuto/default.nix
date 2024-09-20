{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kirk.joshuto;
  #joshuto-with-flags = pkgs.joshuto.overrideAttrs (o: {cargoBuildFlags = [ "--features=syntax_highlight" ];});
in {
  options.kirk.joshuto = {
    enable = mkEnableOption "joshuto file manager";

    enableZshIntegration = mkOption {
      type = types.bool;
      default = true;

      description = ''
        Adds the auto-cd `j` command to zsh.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.zsh = mkIf cfg.enableZshIntegration {
      envExtra = "export EDITOR=hx";

      initExtra = ''
        function j() {
        	ID="$$"
        	mkdir -p /tmp/$USER
        	OUTPUT_FILE="/tmp/$USER/joshuto-cwd-$ID"
        	env joshuto --output-file "$OUTPUT_FILE" $@
        	exit_code=$?

        	case "$exit_code" in
        		# regular exit
        		0)
        			;;
        		# output contains current directory
        		101)
        			JOSHUTO_CWD=$(cat "$OUTPUT_FILE")
        			cd "$JOSHUTO_CWD"
        			;;
        		# output selected files
        		102)
        			;;
        		*)
        			echo "Exit code: $exit_code"
        			;;
        	esac
        }
      '';
    };

    home.packages = with pkgs; [
      atool
      bat
      catdoc
      feh
      jq
      libsixel
      mediainfo
      mu
      odt2txt
      p7zip
      poppler_utils
      transmission-qt
      unar
      w3m-nox
    ];

    programs.joshuto = {
      enable = true;

      settings = {
        preview = {
          max_preview_size = 100000000000; # ~100 GiB
          preview_script = ./preview_script.sh;
        };
        display = {
          automatically_count_lines = true;
          show_icons = true;
        };
      };

      keymap = {
        default_view.keymap = [
          #{ keys = [ "escape" ]; command = "escape"; }
          {
            keys = ["q"];
            command = "quit --output-current-directory";
          }
          {
            keys = ["Q"];
            command = "close_tab";
          }

          {
            keys = ["R"];
            command = "reload_dirlist";
          }
          {
            keys = ["."];
            command = "toggle_hidden";
          }
          {
            keys = ["e"];
            command = "shell hx %s";
          }

          {
            keys = ["1"];
            command = "tab_switch_index 1";
          }
          {
            keys = ["2"];
            command = "tab_switch_index 2";
          }
          {
            keys = ["3"];
            command = "tab_switch_index 3";
          }
          {
            keys = ["4"];
            command = "tab_switch_index 4";
          }
          {
            keys = ["5"];
            command = "tab_switch_index 5";
          }

          # arrow keys
          {
            keys = ["arrow_up"];
            command = "cursor_move_up";
          }
          {
            keys = ["arrow_down"];
            command = "cursor_move_down";
          }
          {
            keys = ["arrow_left"];
            command = "cd ..";
          }
          {
            keys = ["arrow_right"];
            command = "open";
          }
          {
            keys = ["\n"];
            command = "open";
          }
          {
            keys = ["home"];
            command = "cursor_move_home";
          }
          {
            keys = ["end"];
            command = "cursor_move_end";
          }
          {
            keys = ["page_up"];
            command = "cursor_move_page_up";
          }
          {
            keys = ["page_down"];
            command = "cursor_move_page_down";
          }
          {
            keys = ["ctrl+u"];
            command = "cursor_move_page_up 0.5";
          }
          {
            keys = ["ctrl+d"];
            command = "cursor_move_page_down 0.5";
          }

          # vim-like keybindings
          {
            keys = ["j"];
            command = "cursor_move_down";
          }
          {
            keys = ["k"];
            command = "cursor_move_up";
          }
          {
            keys = ["h"];
            command = "cd ..";
          }
          {
            keys = ["l"];
            command = "open";
          }
          {
            keys = ["g" "g"];
            command = "cursor_move_home";
          }
          {
            keys = ["g" "k"];
            command = "cursor_move_home";
          }
          {
            keys = ["g" "j"];
            command = "cursor_move_end";
          }
          {
            keys = ["g" "e"];
            command = "cursor_move_end";
          }

          {
            keys = ["K"];
            command = "parent_cursor_move_up";
          }
          {
            keys = ["J"];
            command = "parent_cursor_move_down";
          }

          {
            keys = ["c" "d"];
            command = ":cd ";
          }
          {
            keys = ["d" "d"];
            command = "cut_files";
          }
          {
            keys = ["y" "y"];
            command = "copy_files";
          }
          {
            keys = ["y" "n"];
            command = "copy_filename";
          }
          {
            keys = ["y" "."];
            command = "copy_filename_without_extension";
          }
          {
            keys = ["y" "p"];
            command = "copy_filepath";
          }
          {
            keys = ["y" "d"];
            command = "copy_dirpath";
          }

          {
            keys = ["d" "D"];
            command = "delete_files";
          }

          {
            keys = ["p" "p"];
            command = "paste_files";
          }
          {
            keys = ["p" "o"];
            command = "paste_files --overwrite=true";
          }

          {
            keys = ["a"];
            command = "rename_append";
          }
          {
            keys = ["A"];
            command = "rename_prepend";
          }

          {
            keys = [" "];
            command = "select --toggle=true";
          }
          {
            keys = ["%"];
            command = "select --all=true --toggle=true";
          }

          {
            keys = ["t"];
            command = "show_tasks --exit-key=t";
          }
          {
            keys = ["b" "b"];
            command = "bulk_rename";
          }
          {
            keys = ["="];
            command = "set_mode";
          }

          {
            keys = [":"];
            command = ":";
          }
          {
            keys = [";"];
            command = ":";
          }

          {
            keys = ["'"];
            command = ":shell ";
          }
          {
            keys = ["m" "d"];
            command = ":mkdir ";
          }
          {
            keys = ["m" "j"];
            command = "shell sh -c 'foot zsh -is eval j > /dev/null 2>&1 &'";
          }
          {
            keys = ["m" "t"];
            command = "shell sh -c 'foot zsh > /dev/null 2>&1 &'";
          }

          {
            keys = ["m" "f"];
            command = ":touch ";
          }

          {
            keys = ["r"];
            command = "bulk_rename";
          }
          {
            keys = ["ctrl+r"];
            command = ":rename ";
          }

          {
            keys = ["/"];
            command = ":search_inc ";
          }
          {
            keys = ["|"];
            command = "search_fzf";
          }
          {
            keys = ["\\"];
            command = "subdir_fzf";
          }

          {
            keys = ["n"];
            command = "search_next";
          }
          {
            keys = ["alt+n"];
            command = "search_prev";
          }

          {
            keys = ["s" "r"];
            command = "sort reverse";
          }
          {
            keys = ["s" "l"];
            command = "sort lexical";
          }
          {
            keys = ["s" "m"];
            command = "sort mtime";
          }
          {
            keys = ["s" "n"];
            command = "sort natural";
          }
          {
            keys = ["s" "s"];
            command = "sort size";
          }
          {
            keys = ["s" "e"];
            command = "sort ext";
          }

          {
            keys = ["~"];
            command = "cd ~/";
          }
          {
            keys = ["`"];
            command = "cd /";
          }
          {
            keys = ["?"];
            command = "help";
          }
        ];

        task_view.keymap = [
          # arrow keys
          {
            keys = ["arrow_up"];
            command = "cursor_move_up";
          }
          {
            keys = ["arrow_down"];
            command = "cursor_move_down";
          }
          {
            keys = ["home"];
            command = "cursor_move_home";
          }
          {
            keys = ["end"];
            command = "cursor_move_end";
          }

          # vim-like keybindings
          {
            keys = ["j"];
            command = "cursor_move_down";
          }
          {
            keys = ["k"];
            command = "cursor_move_up";
          }
          {
            keys = ["g" "g"];
            command = "cursor_move_home";
          }
          {
            keys = ["g" "k"];
            command = "cursor_move_home";
          }
          {
            keys = ["g" "j"];
            command = "cursor_move_end";
          }
          {
            keys = ["g" "e"];
            command = "cursor_move_end";
          }

          {
            keys = ["w"];
            command = "show_tasks";
          }
          {
            keys = ["escape"];
            command = "show_tasks";
          }
          {
            keys = ["q"];
            command = "show_tasks";
          }
        ];

        help_view.keymap = [
          # arrow keys
          {
            keys = ["arrow_up"];
            command = "cursor_move_up";
          }
          {
            keys = ["arrow_down"];
            command = "cursor_move_down";
          }
          {
            keys = ["home"];
            command = "cursor_move_home";
          }
          {
            keys = ["end"];
            command = "cursor_move_end";
          }

          # vim-like keybindings
          {
            keys = ["j"];
            command = "cursor_move_down";
          }
          {
            keys = ["k"];
            command = "cursor_move_up";
          }
          {
            keys = ["g" "g"];
            command = "cursor_move_home";
          }
          {
            keys = ["g" "k"];
            command = "cursor_move_home";
          }
          {
            keys = ["g" "j"];
            command = "cursor_move_end";
          }
          {
            keys = ["g" "e"];
            command = "cursor_move_end";
          }

          {
            keys = ["w"];
            command = "show_tasks";
          }
          {
            keys = ["escape"];
            command = "show_tasks";
          }
          {
            keys = ["q"];
            command = "show_tasks";
          }
        ];
      };

      mimetype = {
        class = {
          audio_default = [
            {
              command = "mpv";
              args = ["--"];
            }
            {
              command = "mediainfo";
              confirm_exit = true;
            }
          ];
          video_default = [
            {
              command = "mpv";
              args = ["--"];
            }
            {
              command = "mediainfo";
              confirm_exit = true;
            }
          ];
          image_default = [
            {
              command = "feh";
              fork = true;
              silent = true;
            }
          ];
          text_default = [
            {command = "hx";}
            {command = "nano";}
          ];
          reader_default = [
            {
              command = "zathura";
              fork = true;
              silent = true;
            }
          ];
          libreoffice_default = [
            {
              command = "libreoffice";
              fork = true;
              silent = true;
            }
          ];
        };

        extension = {
          # Document
          pdf."inherit" = "reader_default";

          # Images
          avif."inherit" = "image_default";
          bmp."inherit" = "image_default";
          gif."inherit" = "image_default";
          heic."inherit" = "image_default";
          jpeg."inherit" = "image_default";
          jpe."inherit" = "image_default";
          jpg."inherit" = "image_default";
          pgm."inherit" = "image_default";
          png."inherit" = "image_default";
          ppm."inherit" = "image_default";
          webp."inherit" = "image_default";

          # Audio
          flac."inherit" = "audio_default";
          m4a."inherit" = "audio_default";
          mp3."inherit" = "audio_default";
          ogg."inherit" = "audio_default";
          wav."inherit" = "audio_default";

          # Video
          avi."inherit" = "video_default";
          av1."inherit" = "video_default";
          flv."inherit" = "video_default";
          mkv."inherit" = "video_default";
          m4v."inherit" = "video_default";
          mov."inherit" = "video_default";
          mp4."inherit" = "video_default";
          webm."inherit" = "video_default";
          wmv."inherit" = "video_default";

          # Text
          build."inherit" = "text_default";
          c."inherit" = "text_default";
          cmake."inherit" = "text_default";
          conf."inherit" = "text_default";
          cpp."inherit" = "text_default";
          css."inherit" = "text_default";
          csv."inherit" = "text_default";
          cu."inherit" = "text_default";
          ebuild."inherit" = "text_default";
          eex."inherit" = "text_default";
          env."inherit" = "text_default";
          ex."inherit" = "text_default";
          exs."inherit" = "text_default";
          go."inherit" = "text_default";
          h."inherit" = "text_default";
          hpp."inherit" = "text_default";
          hs."inherit" = "text_default";
          html."inherit" = "text_default";
          ini."inherit" = "text_default";
          java."inherit" = "text_default";
          js."inherit" = "text_default";
          json."inherit" = "text_default";
          kt."inherit" = "text_default";
          lua."inherit" = "text_default";
          log."inherit" = "text_default";
          md."inherit" = "text_default";
          micro."inherit" = "text_default";
          ninja."inherit" = "text_default";
          nix."inherit" = "text_default";
          py."inherit" = "text_default";
          rkt."inherit" = "text_default";
          rs."inherit" = "text_default";
          scss."inherit" = "text_default";
          sh."inherit" = "text_default";
          srt."inherit" = "text_default";
          svelte."inherit" = "text_default";
          toml."inherit" = "text_default";
          ts."inherit" = "text_default";
          tsx."inherit" = "text_default";
          txt."inherit" = "text_default";
          vim."inherit" = "text_default";
          xml."inherit" = "text_default";
          yaml."inherit" = "text_default";
          yml."inherit" = "text_default";
        };

        mimetype = {
          mimetype.text = {
            "inherit" = "text_default";
          };
        };
      };
    };
  };
}
