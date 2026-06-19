theme: { config, lib, pkgs, ... }:
{
  home.sessionVariables = {
    FONTCONFIG_FILE = "/etc/fonts/fonts.conf";
    ICON_THEME = theme.icon;
    GTK_USE_PORTAL = "1";
    XDG_DATA_DIRS = lib.concatStringsSep ":" [
      "${config.home.homeDirectory}/.icons"
      "${config.home.profileDirectory}/share"
      "/etc/profiles/per-user/${config.home.username}/share"
      "/run/current-system/sw/share"
      "${config.home.homeDirectory}/.local/share/flatpak/exports/share"
      "/var/lib/flatpak/exports/share"
      "/usr/share"
    ];
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      font-name = "Cantarell 11";
      document-font-name = "Cantarell 11";
      monospace-font-name = "JetBrainsMono Nerd Font Mono 10";
      gtk-theme = theme.gtk;
      icon-theme = theme.icon;
      color-scheme = theme.colorScheme;
    };
  };

  gtk = {
    enable = true;
    font = {
      name = "Cantarell";
      size = 11;
    };
    theme = {
      name = theme.gtk;
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = theme.icon;
      package = pkgs.adwaita-icon-theme;
    };
    gtk4.theme = config.gtk.theme;
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 0;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 0;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
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
