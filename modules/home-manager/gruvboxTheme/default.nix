{lib, ...}: {
  options.kirk.gruvbox = {
    colorscheme = lib.mkOption {
      description = "A definition for the gruvbox dark theme.";

      type = lib.types.attrs;
      default = {
        bg = "282828";
        fg = "ebdbb2";

        black = "1d2021";
        white = "d5c4a1";
        orange = "d65d0e";
        red = "cc241d";
        green = "98971a";
        yellow = "d79921";
        blue = "458588";
        purple = "b16286";
        teal = "689d6a";

        bright = {
          bg = "504945";
          fg = "fbf8e4";
          black = "928374";
          white = "fbf1c7";
          orange = "fe8019";
          red = "fb4934";
          green = "b8bb26";
          yellow = "fabd2f";
          blue = "83a598";
          purple = "d3869b";
          teal = "8ec07c";
        };
      };
    };

    lightColorscheme = lib.mkOption {
      description = "A definition for the gruvbox light theme.";

      type = lib.types.attrs;
      default = {
        bg = "fbf1c7";
        fg = "3c3836";

        black = "fbf1c7";
        white = "7c6f64";
        orange = "d65d0e";
        red = "cc241d";
        green = "98971a";
        yellow = "d79921";
        blue = "458588";
        purple = "b16286";
        teal = "689d6a";

        bright = {
          bg = "ebdbb2";
          fg = "3c3836";
          black = "928374";
          white = "3c3836";
          orange = "af3a03";
          red = "9d0006";
          green = "79740e";
          yellow = "b57614";
          blue = "076678";
          purple = "8f3f71";
          teal = "427b58";
        };
      };
    };
  };
}
