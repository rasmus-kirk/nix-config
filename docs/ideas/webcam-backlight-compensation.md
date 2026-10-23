# Idea: Persist Lenovo webcam backlight compensation

## Context

Lenovo FHD Webcams make skin look too white. The cause is the firmware default
`backlight_compensation=3`. Setting it to `0` with `v4l2-ctl` fixes the image,
but the camera keeps controls in RAM, so a replug, reboot or suspend resets the
value. A udev rule sets the control each time a Lenovo FHD Webcam connects.

## Changes

- `configurations/nixos/work/configuration.nix`: add the rule below. The file
  has no udev config yet. The rule matches the USB product string, so it
  applies to every Lenovo FHD Webcam model, not one product ID.
  `ATTR{index}=="0"` matches only the capture node, not the metadata node.

  ```nix
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="video4linux", ATTRS{idVendor}=="17ef", ATTRS{product}=="Lenovo FHD Webcam*", ATTR{index}=="0", RUN+="${pkgs.v4l-utils}/bin/v4l2-ctl -d $devnode --set-ctrl backlight_compensation=0"
  '';
  ```
