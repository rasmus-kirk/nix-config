{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.claudeConfig;

  settings = {
    enabledPlugins = {
      "rust-analyzer-lsp@claude-plugins-official" = true;
    };
    effortLevel = cfg.effortLevel;
    model = cfg.model;
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

  mattpocockSkills = pkgs.fetchFromGitHub {
    owner = "mattpocock";
    repo = "skills";
    rev = "d81f3a183412e71a5b1e84ca21bc1a35eea03a60";
    hash = "sha256-zQ/wVrcHjIC+UjP4nDw3HARMqZd6LIDFmHKlp8AADYI=";
  };

  userScript = pkgs.symlinkJoin {
    name = "user-script";
    paths = [(pkgs.writers.writePython3Bin "user-script" {libraries = [pkgs.python3Packages.typer];} (builtins.readFile ./user-script/user-script.py))];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/user-script \
        --set USER_SCRIPT_BASH ${getExe pkgs.bash} \
        --set USER_SCRIPT_SCRIPT ${pkgs.util-linux}/bin/script
    '';
  };

  mcpConfig = pkgs.writeText "claude-mcp.json" (builtins.toJSON {mcpServers = cfg.mcpServers;});

  claudeWithMcp = pkgs.symlinkJoin {
    name = "claude-code-mcp";
    paths = [pkgs.claude-code];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/claude --add-flags "--mcp-config=${mcpConfig}"
    '';
  };
in {
  options.kirk.claudeConfig = {
    enable = mkEnableOption "Claude Code configuration";

    effortLevel = mkOption {
      type = types.enum ["low" "medium" "high" "xhigh" "max"];
      default = "low";
      description = "Default Claude Code effort level.";
    };

    model = mkOption {
      type = types.str;
      default = "claude-opus-5-5";
      description = "Default Claude Code model.";
    };

    mcpServers = mkOption {
      type = with types; attrsOf anything;
      default = {};
      example = literalExpression ''
        {
          linear = {
            type = "http";
            url = "https://mcp.linear.app/mcp";
            headers.Authorization = "Bearer ''${LINEAR_API_KEY}";
          };
        }
      '';
      description = "MCP servers passed to Claude Code via `--mcp-config`. If set, a wrapped `claude` is added to `home.packages`. Works without `enable`.";
    };

    notion.enable = mkEnableOption "the Notion MCP server. Reads the token from `$NOTION_TOKEN`";

    slack.enable = mkEnableOption "the Slack MCP server. Reads a user token (`xoxp-...`) from `$SLACK_TOKEN`";
  };

  config = mkMerge [
    (mkIf cfg.notion.enable {
      kirk.claudeConfig.mcpServers.notion = {
        type = "stdio";
        command = "${pkgs.nodejs}/bin/npx";
        args = ["-y" "@notionhq/notion-mcp-server@2.5.2"];
        env = {
          NOTION_TOKEN = "\${NOTION_TOKEN}";
          PATH = "${pkgs.nodejs}/bin:\${PATH}";
        };
      };
    })
    (mkIf cfg.slack.enable {
      kirk.claudeConfig.mcpServers.slack = {
        type = "stdio";
        command = "${pkgs.nodejs}/bin/npx";
        args = ["-y" "slack-mcp-server@1.3.0" "--transport" "stdio"];
        env = {
          SLACK_MCP_XOXP_TOKEN = "\${SLACK_TOKEN}";
          PATH = "${pkgs.nodejs}/bin:\${PATH}";
        };
      };
    })
    (mkIf (cfg.mcpServers != {}) {
      home.packages = [claudeWithMcp];
    })
    (mkIf cfg.enable {
      home.packages = [userScript];
      home.file = {
        ".claude/settings.json" = {
          text = builtins.toJSON settings;
          force = true;
        };
        ".claude/style-rules.md" = {
          source = ./style-rules.md;
          force = true;
        };
        ".claude/CLAUDE.md" = {
          source = ./CLAUDE.md;
          force = true;
        };
        ".claude/skills/ask/SKILL.md" = {
          source = ./skills/ask/SKILL.md;
          force = true;
        };
        ".claude/skills/pr-comments/SKILL.md" = {
          source = ./skills/pr-comments/SKILL.md;
          force = true;
        };
        ".claude/skills/pr-docs/SKILL.md" = {
          source = ./skills/pr-docs/SKILL.md;
          force = true;
        };
        ".claude/skills/pr-review/SKILL.md" = {
          source = ./skills/pr-review/SKILL.md;
          force = true;
        };
        ".claude/skills/pr-workflow/SKILL.md" = {
          source = ./skills/pr-workflow/SKILL.md;
          force = true;
        };
        ".claude/skills/quiz/SKILL.md" = {
          source = ./skills/quiz/SKILL.md;
          force = true;
        };
        ".claude/skills/pr-description/SKILL.md" = {
          source = ./skills/pr-description/SKILL.md;
          force = true;
        };
        ".claude/skills/user-script/SKILL.md" = {
          source = ./skills/user-script/SKILL.md;
          force = true;
        };
        ".claude/skills/manual/SKILL.md" = {
          source = ./skills/manual/SKILL.md;
          force = true;
        };
        ".claude/skills/writing-style/SKILL.md" = {
          source = ./skills/writing-style/SKILL.md;
          force = true;
        };
        ".claude/skills/eli5/SKILL.md" = {
          source = ./skills/eli5/SKILL.md;
          force = true;
        };
        ".claude/skills/botbabble/SKILL.md" = {
          source = ./skills/botbabble/SKILL.md;
          force = true;
        };
        ".claude/skills/whip/SKILL.md" = {
          source = ./skills/whip/SKILL.md;
          force = true;
        };
        ".claude/skills/grill-me/SKILL.md" = {
          source = "${mattpocockSkills}/skills/productivity/grill-me/SKILL.md";
          force = true;
        };
        ".claude/skills/grilling/SKILL.md" = {
          source = "${mattpocockSkills}/skills/productivity/grilling/SKILL.md";
          force = true;
        };
      };
    })
  ];
}
