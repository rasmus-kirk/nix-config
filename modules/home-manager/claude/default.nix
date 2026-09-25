{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.claude;

  settings = {
    enabledPlugins = {
      "rust-analyzer-lsp@claude-plugins-official" = true;
    };
    effortLevel = cfg.effortLevel;
    theme = "dark";
    autoMemoryEnabled = false;
    autoDreamEnabled = false;
    hooks.UserPromptSubmit = [
      {
        hooks = [
          {
            type = "command";
            command = ''${getExe pkgs.jq} -n --rawfile c "$HOME/.claude/style-rules.md" '{suppressOutput:true,hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}' 2>/dev/null || true'';
            timeout = 5;
          }
        ];
      }
    ];
    outputStyle = "Concise";
  };
in {
  options.kirk.claude = {
    enable = mkEnableOption "Claude Code configuration";

    effortLevel = mkOption {
      type = types.enum ["low" "medium" "high" "xhigh" "max"];
      default = "low";
      description = "Default Claude Code effort level.";
    };
  };

  config = mkIf cfg.enable {
    home.file = {
      ".claude/settings.json" = {
        text = builtins.toJSON settings;
        force = true;
      };
      ".claude/style-rules.md" = {
        source = ./style-rules.md;
        force = true;
      };
      ".claude/skills/ask/SKILL.md" = {
        source = ./skills/ask/SKILL.md;
        force = true;
      };
    };
  };
}
