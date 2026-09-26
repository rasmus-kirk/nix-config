{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.kernelModules = ["kvm-intel"];
  boot.extraModulePackages = [];

  boot.initrd = {
    availableKernelModules = ["nvme" "xhci_pci" "usb_storage" "usbhid" "sd_mod" "sdhci_pci"];
    kernelModules = [];
    systemd.enable = true;
    luks.fido2Support = false;
    luks.devices = {
      cryptroot = {
        device = "/dev/disk/by-partlabel/cryptroot";
        crypttabExtraOpts = ["fido2-device=auto"];
      };
      crypt_ssd1 = {
        device = "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5SSNF0WA10922R";
        crypttabExtraOpts = ["fido2-device=auto"];
      };
    };
  };

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = ["subvol=@root" "noatime" "nodiratime" "compress=zstd"];
  };

  fileSystems."/nix" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = ["subvol=@nix" "noatime" "nodiratime" "compress=zstd"];
  };

  # Large, re-downloadable data. It survives the @root rollback but is not backed up like /data.
  fileSystems."/persist" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = ["subvol=@persist" "noatime" "nodiratime" "compress=zstd"];
  };

  # No compression, so swap pages map 1:1 to disk. The swapDevices module sets NOCOW on the swapfile.
  fileSystems."/var/swap" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = ["subvol=@swap" "noatime"];
  };

  fileSystems."/boot" = {
    # Label set at install time with `mkfs.vfat -n BOOT`.
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  swapDevices = [
    {
      device = "/var/swap/swapfile";
      size = 16 * 1024; # 16 GiB
    }
  ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.npu.enable = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
