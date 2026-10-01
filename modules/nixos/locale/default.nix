{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kirk.locale;
in {
  options.kirk.locale.enable = mkEnableOption "the Copenhagen time zone, English language and Danish formats";

  config = mkIf cfg.enable {
    time.timeZone = "Europe/Copenhagen";
    i18n.defaultLocale = "en_DK.UTF-8";
    i18n.extraLocaleSettings = genAttrs [
      "LC_ADDRESS"
      "LC_IDENTIFICATION"
      "LC_MEASUREMENT"
      "LC_MONETARY"
      "LC_NAME"
      "LC_NUMERIC"
      "LC_PAPER"
      "LC_TELEPHONE"
      "LC_TIME"
    ] (_: "da_DK.UTF-8");
  };
}
