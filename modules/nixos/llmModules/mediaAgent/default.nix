{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.llmModules.mediaAgent;
  transmission = config.services.transmission;

  group = "media";
  agentDir = "${cfg.mediaDir}/.agent";
  queueDir = "${agentDir}/queue";
  libraryDir = "${cfg.mediaDir}/library";
  downloadDir = transmission.settings.download-dir;
  mcpUrl = "http://127.0.0.1:${toString cfg.port}/mcp";
  tmdbKey = "4219e299c89411838049ab0dab19ebd5";

  allowed = {
    mkv = ["video/x-matroska"];
    mp4 = ["video/mp4"];
    m4v = ["video/mp4" "video/x-m4v"];
    avi = ["video/x-msvideo"];
    srt = ["application/x-subrip" "text/plain"];
    ass = ["text/plain"];
    ssa = ["text/plain"];
    vtt = ["text/vtt" "text/plain"];
    sub = ["text/plain" "video/mpeg"];
    idx = ["text/plain"];
    flac = ["audio/flac" "audio/x-flac"];
    mp3 = ["audio/mpeg"];
    m4a = ["audio/x-m4a" "audio/mp4" "video/mp4"];
    m4b = ["audio/x-m4a" "audio/mp4" "video/mp4"];
    opus = ["audio/ogg"];
    ogg = ["audio/ogg"];
    epub = ["application/epub+zip"];
    pdf = ["application/pdf"];
    mobi = ["application/x-mobipocket-ebook"];
    azw3 = ["application/x-mobipocket-ebook"];
    jpg = ["image/jpeg"];
    png = ["image/png"];
  };

  importConfig = pkgs.writeText "media-import.json" (builtins.toJSON {
    agent = agentDir;
    queue = queueDir;
    torrents = downloadDir;
    library = libraryDir;
    inherit allowed;
    inherit (cfg) linkMode;
  });

  mediaImport = pkgs.writers.writePython3Bin "media-import" {
    libraries = [pkgs.python3Packages.python-magic];
  } (readFile ./media-import.py);

  mcpConfig = pkgs.writeText "media-mcp.json" (builtins.toJSON {
    agent = agentDir;
    library = libraryDir;
    allowed = attrNames allowed;
    transmission = cfg.transmissionAddress;
    prowlarr = cfg.prowlarrUrl;
    instructions = ./instructions.md;
    inherit (cfg) port;
    inherit tmdbKey;
  });

  mediaMcp = pkgs.writers.writePython3Bin "media-mcp" {
    libraries = [pkgs.python3Packages.mcp];
  } (readFile ./media-mcp.py);

  mcpJson = pkgs.writeText "mcp.json" (builtins.toJSON {
    mcpServers.media = {
      type = "http";
      url = mcpUrl;
    };
  });

  doneScript = pkgs.writeShellScript "media-agent-done" ''
    exec ${pkgs.coreutils}/bin/touch ${escapeShellArg queueDir}/"$TR_TORRENT_HASH"
  '';
in {
  options.kirk.llmModules.mediaAgent = {
    enable = mkEnableOption "the media agent, an MCP server whose tools find torrents and import them into the media library";

    user = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "User who runs Claude Code in the agent directory. Joins the media group.";
    };

    port = mkOption {
      type = types.port;
      default = 8765;
      description = "Port of the MCP server on 127.0.0.1.";
    };

    prowlarrApiKeyFile = mkOption {
      type = types.str;
      example = "/run/agenix/prowlarr-api-key";
      description = "File with the Prowlarr API key.";
    };

    mediaDir = mkOption {
      type = types.str;
      default = "/data/media";
      description = "Holds Transmission's download dir, library/ and the agent's workspace .agent/.";
    };

    linkMode = mkOption {
      type = types.enum ["reflink" "hardlink"];
      default = "reflink";
      description = "How media-import puts a finished download into the library. A reflink is an independent copy that shares disk blocks until either side changes, and needs btrfs or XFS. A hardlink shares the file, so an edit in the library also changes the seeded data.";
    };

    transmissionAddress = mkOption {
      type = types.str;
      default = "192.168.15.1:9091";
      description = "Transmission RPC address as host:port. The default is the address inside nixarr's VPN namespace.";
    };

    prowlarrUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:9696";
      description = "Prowlarr base URL.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = transmission.enable;
        message = "kirk.llmModules.mediaAgent needs services.transmission.";
      }
      {
        assertion = transmission.group == group;
        message = "kirk.llmModules.mediaAgent needs services.transmission.group = \"${group}\", because the Transmission unit maps only its own group.";
      }
      {
        assertion = hasPrefix "${cfg.mediaDir}/" downloadDir;
        message = "kirk.llmModules.mediaAgent needs Transmission's download-dir inside ${cfg.mediaDir}, so media-import sees it and the library on one mount.";
      }
    ];

    users.groups.${group} = {};
    users.users = mkIf (cfg.user != null) {
      ${cfg.user}.extraGroups = [group];
    };

    systemd.tmpfiles.rules = [
      "d ${agentDir}          2770 root ${group} -"
      "d ${agentDir}/queue    2770 root ${group} -"
      "d ${agentDir}/done     2770 root ${group} -"
      "d ${agentDir}/rejected 2770 root ${group} -"
      "L+ ${agentDir}/.mcp.json - - - - ${mcpJson}"
    ];

    services.transmission.settings = {
      script-torrent-done-enabled = mkForce true;
      script-torrent-done-filename = mkForce "${doneScript}";
    };
    systemd.services.transmission.serviceConfig.BindPaths = [queueDir];

    systemd.paths.media-import = {
      wantedBy = ["paths.target"];
      pathConfig.DirectoryNotEmpty = queueDir;
    };
    systemd.services.media-import = {
      description = "Import finished torrents into the media library";
      serviceConfig = {
        Type = "oneshot";
        User = transmission.user;
        Group = group;
        ExecStart = "${mediaImport}/bin/media-import ${importConfig}";
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.mediaDir];
        PrivateTmp = true;
        PrivateNetwork = true;
        NoNewPrivileges = true;
      };
    };

    systemd.services.media-mcp = {
      description = "MCP server with the media agent tools";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];
      serviceConfig = {
        ExecStart = "${mediaMcp}/bin/media-mcp ${mcpConfig}";
        LoadCredential = "prowlarr:${cfg.prowlarrApiKeyFile}";
        DynamicUser = true;
        SupplementaryGroups = [group];
        UMask = "0002";
        Restart = "on-failure";
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [agentDir];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    services.open-webui.environment = {
      TOOL_SERVER_CONNECTIONS = builtins.toJSON [
        {
          type = "mcp";
          url = mcpUrl;
          path = "";
          auth_type = "none";
          key = "";
          config = {
            enable = true;
            access_grants = [
              {
                principal_type = "user";
                principal_id = "*";
                permission = "read";
              }
            ];
          };
          info = {
            id = "media";
            name = "Media";
            description = "Find torrents and import them into the media library.";
          };
        }
      ];
      DEFAULT_MODEL_METADATA = builtins.toJSON {toolIds = ["server:mcp:media"];};
    };
  };
}
