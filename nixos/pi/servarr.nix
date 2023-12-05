# TODO: Dir creation and file permissions in nix
{ pkgs, config, ...}: let 
  yaml = pkgs.formats.yaml {};
  servarr-config = yaml.generate "servarr.yaml" {
    secrets = { 
      openvpn_user.file = config.age.secrets.mullvad.path;
    };

    services = {
      prowlarr = {
        container_name = "prowlarr";
        image = "ghcr.io/hotio/prowlarr";
        restart = "unless-stopped";
        network_mode = "service:gluetun";
        environment = [
          "PUID=1000"
          "PGID=1000"
          "UMASK=002"
          "TZ=Etc/UTC"
        ];
        volumes = [
          "/data/.state/servarr/prowlarr:/config"
        ];
      };

      rflood = {
        container_name = "rflood";
        image = "ghcr.io/hotio/rflood";
        restart = "unless-stopped";
        network_mode = "service:gluetun";
        environment = [
          "PUID=1000"
          "PGID=1000"
          "UMASK=002"
          "TZ=Etc/UTC"
          "FLOOD_AUTH=false"
        ];
        volumes = [
          "/data/media/torrents:/data/torrents"
          "/data/.state/servarr/rflood:/config"
        ];
      };

      radarr = {
        container_name = "radarr";
        image = "ghcr.io/hotio/radarr";
        restart = "unless-stopped";
        network_mode = "service:gluetun";
        environment = [
          "PUID=1000"
          "PGID=1000"
          "UMASK=002"
          "TZ=Etc/UTC"
        ];
        volumes = [
          "/data/media:/data"
          "/data/.state/servarr/radarr:/config"
        ];
      };

      sonarr = {
        container_name = "sonarr";
        image = "ghcr.io/hotio/sonarr";
        restart = "unless-stopped";
        network_mode = "service:gluetun";
        environment = [
          "PUID=1000"
          "PGID=1000"
          "UMASK=002"
          "TZ=Etc/UTC"
        ];
        volumes = [
          "/data/media:/data"
          "/data/.state/servarr/sonarr:/config"
        ];
      };

      jellyfin = {
        container_name = "jellyfin";
        image = "ghcr.io/hotio/jellyfin";
        restart = "unless-stopped";
        ports = [ "8096:8096" ];
        environment = [
          "PUID=1000"
          "PGID=1000"
          "UMASK=002"
          "TZ=Etc/UTC"
        ];
        volumes = [
          "/data/media/library:/data/library"
          "/data/.state/servarr/jellyfin:/config"
        ];
      };

    gluetun = {
      image = "qmcgaw/gluetun";
      container_name = "gluetun";
      cap_add = ["NET_ADMIN"];
      devices = [ "/dev/net/tun:/dev/net/tun"];
      ports = [
        "8888:8888/tcp" # HTTP proxy
        "8388:8388/tcp" # Shadowsocks
        "8388:8388/udp" # Shadowsocks
        "6001:3000" # rflood
        "6002:9696" # prowlarr
        "6003:8989" # sonarr
        "6004:7878" # radarr
      ];
      volumes = [ "/data/.state/servarr/gluetun:/gluetun" ];
      secrets = [ "openvpn_user" ];
      environment = [
        "VPN_SERVICE_PROVIDER=mullvad"
        "VPN_TYPE=openvpn"
        "OPENVPN_USER=/run/secrets/openvpn_user"
        "TZ=Etc/UTC"
        "UPDATER_PERIOD=24h"
      ];
    };
  };
};
in {
	virtualisation.docker = {
		enable = true;
		autoPrune.enable = true;
		extraPackages = [ pkgs.docker-compose ];
	};

	systemd.services.servarr-docker-compose = {
		script = ''
			${pkgs.docker-compose}/bin/docker-compose -f ${servarr-config} up --force-recreate --remove-orphans
		'';
		wantedBy = ["multi-user.target"];
		after = ["docker.service" "docker.socket"];
	};

	networking.firewall.allowedTCPPorts = [ 80 443 ];
	services.nginx = {
		enable = true;

		recommendedTlsSettings = true;
		recommendedOptimisation = true;
		recommendedGzipSettings = true;

		virtualHosts."glowiefin.com" = {
			enableACME = true;
      forceSSL = true;
			locations."/" = {
				recommendedProxySettings = true;
				proxyWebsockets = true;
				proxyPass = "http://127.0.0.1:8096";
			};
		};
	};
	security.acme = {
		acceptTerms = true;
		defaults.email = "slimness_bullish683@simplelogin.com";
	};
}
