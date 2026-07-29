{
  config,
  lib,
  pkgs,
  ...
}:

{
  fonts = {
    enableDefaultPackages = true;

    packages = with pkgs; [
      # GTK / GNOME UI default
      cantarell-fonts
      inter
      roboto
      ubuntu-classic

      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji

      dejavu_fonts
      liberation_ttf
      corefonts

      # Monospace / Nerd Fonts
      jetbrains-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.iosevka
    ];

    fontconfig = {
      enable = true;
      allowBitmaps = false;
      antialias = true;
      hinting = {
        enable = true;
        style = "slight";
      };
      subpixel = {
        rgba = "rgb";
        lcdfilter = "default";
      };

      defaultFonts = {
        monospace = [
          "JetBrains Mono"
          "JetBrainsMono Nerd Font Mono"
          "Noto Color Emoji"
        ];
        sansSerif = [
          "Inter"
          "Cantarell"
          "Roboto"
          "Noto Sans"
          "Noto Color Emoji"
          "Noto Sans CJK SC"
          "Liberation Sans"
        ];
        serif = [
          "Noto Serif"
          "Noto Color Emoji"
          "Noto Serif CJK SC"
          "Liberation Serif"
        ];
      };
    };
  };
}
