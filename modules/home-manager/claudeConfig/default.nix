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
  };

  config = mkMerge [
    (mkIf cfg.notion.enable {
      kirk.claudeConfig.mcpServers.notion = {
        type = "stdio";
        command = "${pkgs.nodejs}/bin/npx";
        args = ["-y" "@notionhq/notion-mcp-server@2.5.2"];
        env.NOTION_TOKEN = "\${NOTION_TOKEN}";
      };
    })
    (mkIf (cfg.mcpServers != {}) {
      home.packages = [claudeWithMcp];
    })
    (mkIf cfg.enable {
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
        ".claude/skills/update-docs/SKILL.md" = {
          source = ./skills/update-docs/SKILL.md;
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
