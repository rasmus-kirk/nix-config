# Idea: Unlock LUKS over SSH with the YubiKey

## Context

After a reboot without a person at the desktop, `cryptroot` and
`crypt_ssd1` wait for a local FIDO2 touch or a passphrase, so all services
stay down. The FIDO2 keyslots need the YubiKey on the desktop's own USB, and
SSH cannot forward that.

Model: a third keyslot with a random key on both devices. The key is stored
in the repo, encrypted to the YubiKey with `age-plugin-fido2-hmac`. A client
decrypts it with the YubiKey and sends it to an SSH server in the initrd,
which answers the pending password prompt. systemd-cryptsetup caches the
passphrase and tries it on the second device. Wiping the keyslot revokes
remote unlock and keeps the console FIDO2 slot.

Limits:

- Tailscale does not run in the initrd. The client must be on the LAN, or
  port 2222 must be forwarded at the router.
- After a power cut, the BIOS option "Restore on AC power loss: Power On"
  must be set, or the desktop stays off.
- The client needs the YubiKey and `age-plugin-fido2-hmac`, so a laptop or
  the Deck works. A phone does not.

## Changes

- `modules/nixos/server/default.nix`: add `kirk.server.sshUnlock` with
  - `enable`
  - `port`, default 2222. A separate port keeps the initrd host key out of
    the `known_hosts` entry for port 6000.
  - `hostKey`, a path to a passphrase-less ed25519 key. The initrd is on the
    unencrypted ESP, so this key must not be `/data/.secret/desktop`, which
    is also the age identity.
  - `authorizedKeyFiles`. OpenSSH in the systemd initrd accepts
    `sk-ssh-ed25519` keys, so `ssh-keys/yubi.pub` works.
  - `networkModules`, the NIC driver for the initrd.

  It sets `boot.initrd.network.ssh` with these values, adds
  `networkModules` to `boot.initrd.availableKernelModules`, and gives the
  initrd DHCP on `en*` through `boot.initrd.systemd.network`. The SSH key
  gets a forced command that reads one line from stdin, finds the `Socket=`
  of the pending `/run/systemd/ask-password/ask.*` request, and passes the
  line to `systemd-reply-password 1 <socket>`.
- `configurations/nixos/desktop/configuration.nix`: set
  `kirk.server.sshUnlock` with `hostKey = "${secretDir}/desktop-initrd"`,
  `authorizedKeyFiles = [../../../ssh-keys/yubi.pub]` and
  `networkModules = ["r8169"]`.
- `modules/home-manager/scripts/default.nix`: add `unlock-desktop`. It runs
  `age -d` on `age/desktop/luks-remote.age` with the YubiKey identity and
  pipes the result to `ssh -p 2222 root@desktop`.
- `age/desktop/luks-remote.age`: the encrypted keyslot key.
- One-time user script, because the steps need sudo and LUKS access:
  1. `ssh-keygen -t ed25519 -N "" -f /data/.secret/desktop-initrd`
  2. Generate a random key into a tmpfs file.
  3. `cryptsetup luksAddKey` the key file to `cryptroot` and `crypt_ssd1`.
  4. Encrypt the key file to `age/desktop/luks-remote.age` with the
     `age-plugin-fido2-hmac` recipient.
  5. Delete the plaintext key file.

## Verification

1. `cryptsetup luksDump /dev/disk/by-partlabel/cryptroot` lists one more
   keyslot than before. The same holds for `crypt_ssd1`.
2. `lsinitrd` or `nix-store -qR` on the initrd shows `sshd` and `r8169`.
3. Reboot and wait at the LUKS prompt. From a laptop on the LAN,
   `unlock-desktop` asks for two YubiKey touches and the desktop boots to
   the login.
4. `journalctl -b -u systemd-cryptsetup@cryptroot` shows the unlock.
