{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot = {
    kernelModules = ["kvm-amd"];
    extraModulePackages = [];

    loader = {
      timeout = 1;
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    resumeDevice = "/dev/mapper/luks-a98709c6-6528-48b6-8a3c-e98f103032fd";
    kernelParams = ["resume_offset=55775232"];

    initrd = {
      availableKernelModules = ["nvme" "xhci_pci" "thunderbolt" "usb_storage" "usbhid" "sd_mod" "sdhci_pci"];
      kernelModules = [];
      systemd.enable = true;
      luks.fido2Support = false;
      luks.devices = {
        "luks-a98709c6-6528-48b6-8a3c-e98f103032fd" = {
          device = "/dev/disk/by-uuid/a98709c6-6528-48b6-8a3c-e98f103032fd";
          crypttabExtraOpts = [
            "fido2-device=auto"
          ];
        };
      };
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/mapper/luks-a98709c6-6528-48b6-8a3c-e98f103032fd";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/49C9-4311";
      fsType = "vfat";
      options = ["fmask=0077" "dmask=0077"];
    };
  };

  swapDevices = [
    {
      device = "/swapfile";
      size = 32 * 1024;
    }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
