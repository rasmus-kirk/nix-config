{
  lib,
  writeShellApplication,
  argc,
  age,
  age-plugin-fido2-hmac,
  coreutils,
}: let
  hosts = map (lib.removeSuffix ".age") (builtins.filter (lib.hasSuffix ".age") (builtins.attrNames (builtins.readDir ./age)));
in
  writeShellApplication {
    name = "ssh-bootstrap";
    runtimeInputs = [argc age age-plugin-fido2-hmac coreutils];
    inheritPath = false;
    text = ''
      # @describe Decrypt a host's SSH key from ssh-keys/age with the YubiKey.
      # @meta version 0.1.0
      # @arg host![${lib.concatStringsSep "|" hosts}]  Host whose key to decrypt.
      # @arg dir!  Directory to write the key to.

      main() {
        local dest="''${argc_dir:?}/''${argc_host:?}"
        local key

        if [ -e "$dest" ]; then
          echo "ssh-bootstrap: $dest already exists, refusing to overwrite" >&2
          exit 1
        fi

        key="$(age -d -j fido2-hmac "${./age}/$argc_host.age")"
        umask 077
        mkdir -p "$argc_dir"
        printf '%s\n' "$key" > "$dest"
        chmod 0400 "$dest"
        echo "ssh-bootstrap: wrote $dest"
      }

      eval "$(argc --argc-eval "$0" "$@")"
    '';
  }
