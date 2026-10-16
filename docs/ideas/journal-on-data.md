# Idea: Journal on /data

## Context

On 2026-10-13 around 03:57 the root NVMe drive (`cryptroot`) stopped
responding. The journal is on that drive, so no log of the failure was
saved, and the cause is unknown. `/data` is on a separate SATA drive that
stayed up. If the journal is on `/data`, the next dropout records its own
kernel messages.

Limit: journald's binary is in `/nix/store` on the root drive. If journald
dies after a dropout, it cannot restart.

## Changes

- `configurations/nixos/desktop/hardware-configuration.nix`: bind-mount
  `/data/.state/journal` onto `/var/log/journal`, with
  `x-systemd.requires-mounts-for=/data`. `systemd-journal-flush.service`
  waits for the mount through its `RequiresMountsFor=/var/log/journal`.
- One-time step before the switch: `sudo mkdir -p /data/.state/journal`.
  The old journal stays on root, hidden under the mount.

## Verification

1. `findmnt /var/log/journal` shows `crypt_ssd1[/.state/journal]`.
2. `ls /data/.state/journal` shows a directory named by the machine ID.
3. After a second reboot, `journalctl -b -1` shows the previous boot.
