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
      # GTK / GNOME UI default (dconf org.gnome.desktop.interface font-name)
      cantarell-fonts

      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji

      dejavu_fonts
      liberation_ttf
      corefonts

      # Upstream TopBar.qml uses plain "JetBrains Mono" for clock/labels (see ilyamiro repo).
      jetbrains-mono
      nerd-fonts.jetbrains-mono
      # Icons / NF glyphs use "Iosevka Nerd Font" in QML.
      nerd-fonts.iosevka
    ];

    fontconfig = {
      enable = true;

      defaultFonts = {
        monospace = [
          # fc-match family names from JetBrains Mono + NFM (Quickshell TopBar asks for "JetBrains Mono")
          "JetBrains Mono"
          "JetBrainsMono Nerd Font Mono"
          "Noto Color Emoji"
        ];
        sansSerif = [
          "Cantarell"
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
