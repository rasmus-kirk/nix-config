# Setup Guide

## NixOS Install

Every host keeps the repository in `/data/.system-configuration` and its
host key in `/data/.secret/ssh/<host>`. Boot the installer ISO, set up the
disks to match the host's `hardware-configuration.nix` and mount them under
`/mnt`. Then run:

```sh
  export NIX_CONFIG="experimental-features = nix-command flakes"
  nix run nixpkgs#git -- clone https://github.com/rasmus-kirk/nix-config.git /mnt/data/.system-configuration
  cd /mnt/data/.system-configuration
  nix run .#ssh-bootstrap -- <host> /mnt/data/.secret/ssh
  nixos-install --flake .#<host> --no-root-passwd
```

No account has a password, and login reads the YubiKey handle. Recover it into
`/mnt/data/.secret/ssh` before you reboot, as in [YubiKey](#yubikey).

After the first boot, `nos rebuild` rebuilds the host.

## YubiKey

SSH, git signing and pam_u2f read the handle of the resident FIDO key from
`/data/.secret/ssh/id_ed25519_yubi`. To recover it, run the commands below.
`ssh-keygen -K` asks for the FIDO PIN and a touch. From the installer, use
`/mnt/data/.secret/ssh`.

```sh
  mkdir -p /data/.secret/ssh
  cd /data/.secret/ssh
  ssh-keygen -K
  mv id_ed25519_sk_rk_rasmus id_ed25519_yubi
  mv id_ed25519_sk_rk_rasmus.pub id_ed25519_yubi.pub
  chmod 600 id_ed25519_yubi
```

## Host Key

Each host has an SSH key at `/data/.secret/ssh/<host>`. The host uses this key
to decrypt its agenix secrets. `work` and `deck-oled` also use it to log in to
the remote builder on `desktop`.

The repository keeps each key in `ssh-keys/age/<host>.age`, encrypted to the
YubiKey. Run `ssh-bootstrap` from the repository to decrypt it.

```sh
  nix run .#ssh-bootstrap -- <host> /data/.secret/ssh
```
