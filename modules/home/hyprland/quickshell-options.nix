{ config, lib, ... }:

{
  options.quickshellShell = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Quickshell-based shell (ilyamiro-style panels/widgets) via flake input `ilyamiro-config`.
        Uses CTRL+ALT binds so SUPER shortcuts in hyprland-base.conf stay yours.
      '';
    };

    wallpaperDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Pictures/Wallpapers";
      description = "Wallpaper folder for swww / wallpaper picker (env WALLPAPER_DIR).";
    };

    gtkMatugenTheme = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        GTK3/4 load ~/.cache/matugen/colors-gtk.css (after `matugen image …`).
      '';
    };
  };
}
