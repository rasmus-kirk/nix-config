{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.ubuntuContainer;
  ubuntu = pkgs.writeShellApplication {
    name = "ubuntu";
    runtimeInputs = with pkgs; [podman trash-cli coreutils];
    inheritPath = true;
    text = ''
      CONTAINER_USER="ubuntu"
      MACHINE="ubuntu-container"
      STATE_DIR="/data/.state/ubuntu-container"
      HOME_DIR="/data/.state/ubuntu-container/home"
      DATA_DIR="/data/.state/ubuntu-container/data"
      CONFIG_DIR="/data/.system-configuration"
      SECRET_DIR="/data/.secret"
      HOST_NIX_BIN_DIR="$(dirname "$(readlink -f "$(command -v nix)")")"
      HOST_HOME_MANAGER_BIN="$(readlink "$(which home-manager)")"

      if [ "''${1:-}" == "nuke" ]; then
          echo "🗑️ Trashing $STATE_DIR..."
          trash-put "$STATE_DIR" || echo "No state directory found..."
          exit 0
      fi

      mkdir -p "$DATA_DIR"
      mkdir -p "$HOME_DIR"

      # --- Run the Environment ---
      podman run \
        -v /nix:/nix:ro \
        -v "$DATA_DIR:/data:rw" \
        -v "$HOME_DIR:/home/$CONTAINER_USER:rw" \
        -v "$SECRET_DIR:$SECRET_DIR:ro" \
        -v "$CONFIG_DIR:$CONFIG_DIR:ro" \
        -e "NIX_PATH=$NIX_PATH" \
        -e "NIX_REMOTE=daemon" \
        -e "COLORTERM=$COLORTERM" \
        -e "TERM=$TERM" \
        -e "SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt" \
        -e "GIT_SSL_CAINFO=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt" \
        --userns=keep-id \
        --workdir /data \
        --rm -it ubuntu \
        /bin/bash -c "
          export PATH=\"$HOST_NIX_BIN_DIR:\$PATH\"
          export HOME=/home/$CONTAINER_USER
          export USER=$CONTAINER_USER

          mkdir -p /data/.state
    
          if [ ! -f /data/.state/first-run ]; then
            echo '--- Bootstrapping Home Manager ---'
            $HOST_HOME_MANAGER_BIN switch --flake $CONFIG_DIR#$MACHINE && touch /data/.state/first-run
          fi

          exec /home/$CONTAINER_USER/.nix-profile/bin/zsh
        "
    '';
  };
in {
  options.kirk.ubuntuContainer.enable = mkEnableOption "Ubuntu container";

  config = mkIf cfg.enable {
    home.packages = [
      ubuntu
    ];
  };
}
