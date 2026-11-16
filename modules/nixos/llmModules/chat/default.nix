{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.llmModules.chat;
  ollama = getExe config.services.ollama.package;
in {
  options.kirk.llmModules.chat = {
    enable = mkEnableOption "local models in Ollama, with the Open WebUI chat on the LAN";

    models = mkOption {
      type = types.nonEmptyListOf types.str;
      default = ["qwen3.6-heretic:35b"];
      description = "Models that Open WebUI offers. The first one is the default. Ollama pulls each model that has no entry in `modelfiles`.";
    };

    modelfiles = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          from = mkOption {
            type = types.str;
            description = "Model that Ollama pulls and builds this model from.";
          };

          settings = mkOption {
            type = types.lines;
            default = "";
            description = "Modelfile lines after `FROM`.";
          };
        };
      });
      default = {
        "qwen3.6-heretic:35b" = {
          from = "hf.co/llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF:Q4_K_M";
          settings = ''
            TEMPLATE {{ .Prompt }}
            RENDERER qwen3.5
            PARSER qwen3.5
            PARAMETER temperature 1
            PARAMETER top_k 20
            PARAMETER top_p 0.95
            PARAMETER min_p 0
            PARAMETER presence_penalty 1.5
            PARAMETER repeat_penalty 1
            PARAMETER draft_num_predict 2
          '';
        };
      };
      description = "Models that Ollama creates from a Modelfile.";
    };

    contextLength = mkOption {
      type = types.ints.positive;
      default = 32768;
      description = "Context window of each model, in tokens.";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Open WebUI port. The firewall opens it.";
    };

    tailscaleServe = mkEnableOption "Tailscale Serve, which serves Open WebUI at `https://<host>.<tailnet>.ts.net`";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.tailscaleServe -> config.services.tailscale.enable;
        message = "kirk.llmModules.chat.tailscaleServe requires services.tailscale.enable.";
      }
    ];

    nixpkgs.overlays = [
      (final: prev: {
        pythonPackagesExtensions =
          prev.pythonPackagesExtensions
          ++ [
            (pyFinal: pyPrev: {
              posthog = pyPrev.posthog.overridePythonAttrs (old: {
                disabledTests = old.disabledTests ++ ["test_prepare_tool_result_delivers_into_call_tool_result_models"];
                meta = old.meta // {broken = false;};
              });
            })
          ];
      })
    ];

    services.ollama = {
      enable = true;
      package = mkDefault pkgs.ollama-vulkan;
      loadModels = filter (name: !(cfg.modelfiles ? ${name})) cfg.models;
      environmentVariables.OLLAMA_CONTEXT_LENGTH = toString cfg.contextLength;
    };

    systemd.services.ollama-modelfiles = mkIf (cfg.modelfiles != {}) {
      description = "Create Ollama models from Modelfiles";
      wantedBy = ["multi-user.target" "ollama.service"];
      wants = ["network-online.target"];
      after = ["ollama.service" "network-online.target"];
      bindsTo = ["ollama.service"];
      environment = config.systemd.services.ollama.environment;
      serviceConfig = {
        Type = "exec";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "1s";
        RestartMaxDelaySec = "2h";
        RestartSteps = "10";
      };
      script = concatStrings (mapAttrsToList (name: model: ''
          '${ollama}' pull ${escapeShellArg model.from}
          '${ollama}' create ${escapeShellArg name} -f ${pkgs.writeText "Modelfile" "FROM ${model.from}\n${model.settings}"}
        '')
        cfg.modelfiles);
    };

    systemd.services.open-webui-tailscale-serve = mkIf cfg.tailscaleServe {
      description = "Serve Open WebUI over HTTPS on the tailnet";
      wantedBy = ["multi-user.target"];
      wants = ["tailscaled.service"];
      after = ["tailscaled.service" "tailscaled-autoconnect.service" "open-webui.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "30s";
        ExecStart = "${getExe config.services.tailscale.package} serve --bg --yes http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${getExe config.services.tailscale.package} serve --https=443 off";
      };
    };

    services.open-webui = {
      enable = true;
      host = "0.0.0.0";
      inherit (cfg) port;
      openFirewall = true;
      environment = {
        SCARF_NO_ANALYTICS = "True";
        DO_NOT_TRACK = "True";
        ANONYMIZED_TELEMETRY = "False";
        OLLAMA_BASE_URL = "http://127.0.0.1:${toString config.services.ollama.port}";
        OLLAMA_API_CONFIGS = builtins.toJSON {
          "0" = {
            enable = true;
            model_ids = cfg.models;
          };
        };
        ENABLE_OPENAI_API = "False";
        DEFAULT_MODELS = head cfg.models;
        BYPASS_MODEL_ACCESS_CONTROL = "True";
        ENABLE_PERSISTENT_CONFIG = "False";
        USER_PERMISSIONS_CHAT_TEMPORARY_ENFORCED = "True";
        ENABLE_MEMORIES = "False";
      };
    };
  };
}
