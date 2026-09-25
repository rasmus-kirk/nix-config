# Setup Guide

## NixOS Install

- TO-DO

## Home Manager Install

1. Install Nix with the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer).

   ```sh
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. Clone the repository to `~/.system-configuration`.

   ```sh
   cd "$HOME"
   nix run nixpkgs#git -- clone https://github.com/rasmus-kirk/nix-config.git .system-configuration
   cd .system-configuration
   ```

3. Apply the home-manager configuration. Replace `<machine>` with the configuration name.

   ```sh
   nix run home-manager/master -- switch -b backup --flake .#<machine>
   ```

## YubiKey

The SSH key is a resident FIDO key on the YubiKey. SSH, git signing and pam_u2f read the key handle from `/data/.secret/ssh/id_ed25519_yubi`.

To recover the handle files from the YubiKey, run the commands below. `ssh-keygen -K` asks for the FIDO PIN and a touch.

```sh
mkdir -p /data/.secret/ssh
cd /data/.secret/ssh
ssh-keygen -K
mv id_ed25519_sk_rk_rasmus id_ed25519_yubi
mv id_ed25519_sk_rk_rasmus.pub id_ed25519_yubi.pub
chmod 600 id_ed25519_yubi
```
