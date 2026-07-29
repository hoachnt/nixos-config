{ config, lib, pkgs, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      font-name = "Cantarell 11";
      document-font-name = "Cantarell 11";
      monospace-font-name = "JetBrainsMono Nerd Font Mono 10";
    };
    "org/gnome/settings-daemon/plugins/power" = {
      power-button-action = "interactive";
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "adwaita";
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "org.gnome.Nautilus.desktop" ];
    } // builtins.listToAttrs (map (mime: {
      name = mime;
      value = [ "org.gnome.Loupe.desktop" ];
    }) [
      "image/jpeg"
      "image/png"
      "image/gif"
      "image/webp"
      "image/tiff"
      "image/x-tga"
      "image/vnd-ms.dds"
      "image/x-dds"
      "image/bmp"
      "image/vnd.microsoft.icon"
      "image/vnd.radiance"
      "image/x-exr"
      "image/x-portable-bitmap"
      "image/x-portable-graymap"
      "image/x-portable-pixmap"
      "image/x-portable-anymap"
      "image/x-qoi"
      "image/qoi"
      "image/svg+xml"
      "image/svg+xml-compressed"
      "image/avif"
      "image/heic"
      "image/jxl"
    ]);
  };
}
