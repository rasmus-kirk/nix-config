{
  inputs,
  config,
  pkgs,
  ...
}: let
  x = "x";
in {
  vpnNamespaces.wg = {
    enable = true;
    accessibleFrom = [
      "192.168.1.0/24"
      "10.0.0.0/8"
      "127.0.0.1"
    ];
    wireguardConfigFile = config.age.secrets."airvpn-wg.conf".path;
  };

  # Test service
  systemd.services.vpn-test-service = {
    enable = true;

    vpnConfinement = {
      enable = true;
      vpnNamespace = "wg";
    };

    script = let
      vpn-test = pkgs.writeShellApplication {
        name = "vpn-test";

        runtimeInputs = with pkgs; [util-linux unixtools.ping coreutils curl bash libressl netcat-gnu openresolv dig];

        text =
          ''
            cd "$(mktemp -d)"

            # DNS information
            dig google.com

            # Print resolv.conf
            echo "/etc/resolv.conf contains:"
            cat /etc/resolv.conf

            # Query resolvconf
            echo "resolvconf output:"
            resolvconf -l
            echo ""

            # Get ip
            echo "Getting IP:"
            curl -s ipinfo.io

            echo -ne "DNS leak test:"
            curl -s https://raw.githubusercontent.com/macvk/dnsleaktest/b03ab54d574adbe322ca48cbcb0523be720ad38d/dnsleaktest.sh -o dnsleaktest.sh
            chmod +x dnsleaktest.sh
            ./dnsleaktest.sh
          '';
      };
    in "${vpn-test}/bin/vpn-test";
  };
}

