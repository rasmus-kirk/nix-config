{ config, lib, ... }:

with lib;

let
	cfg = config.kirk.kakoune;
in {
	meta.maintainers = [ ];

	options.kirk.kakoune = {
		enable = mkEnableOption "kakoune text editor";
	};

	config = mkIf cfg.enable {
		programs.kakoune = {
			enable = true;
			config = {
				colorScheme = "gruvbox-dark";
				indentWidth = 0;
				tabStop = 2;
				ui.enableMouse = true;
				wrapLines = {
					enable = true;
					word = true;
					marker = "₪";
				};
				numberLines = {
					enable = true;
					highlightCursor = true;
					relative = true;
				};
			};
			extraConfig = ''
				# Highlight whitespace
				add-highlighter global/ show-whitespaces -spc \  -lf ⌄
			
				# Line wrapping
				set global autowrap_column 73
				map global user w '|fmt -w $kak_opt_autowrap_column<ret>' -docstring "Wrap to $kak_opt_autowrap_column columns"
				add-highlighter global/ column '%sh{echo $(($kak_opt_autowrap_column + 1))}' default,black

				# User mappings
				map -docstring "Yank the selection into the clipboard." global user y "<a-|> wl-copy <ret>"
				map -docstring "Paste the clipboard (append)." global user p "<a-!> wl-paste<ret>"
				map -docstring "Paste the clipboard (insert)." global user P "<!> wl-paste<ret>"
				map -docstring "Replace with the clipboard (insert)." global user R "d<!> wl-paste<ret>"
				map -docstring "Replace all space indents with tabs." global user @ "s^ +<ret><a-@>;xs\t\t<ret>;d"
			
				# Differentiate insert and normal mode using colors
				set-face global PrimarySelection white,blue+F
				set-face global SecondarySelection black,blue+F
				set-face global PrimaryCursor black,bright-cyan+F
				set-face global SecondaryCursor black,bright-blue+F
				set-face global PrimaryCursorEol black,bright-cyan
				set-face global SecondaryCursorEol black,bright-blue
			
				hook global ModeChange ".*:insert" %{
					set-face window PrimarySelection white,green+F
					set-face window SecondarySelection black,green+F
					set-face window PrimaryCursor black,bright-yellow+F
					set-face window SecondaryCursor black,bright-green+F
					set-face window PrimaryCursorEol black,bright-yellow
					set-face window SecondaryCursorEol black,bright-green
				}
			
				hook global ModeChange ".*:normal" %{
					unset-face window PrimarySelection
					unset-face window SecondarySelection
					unset-face window PrimaryCursor
					unset-face window SecondaryCursor
					unset-face window PrimaryCursorEol
					unset-face window SecondaryCursorEol
				}
			'';
		};
	};
}
