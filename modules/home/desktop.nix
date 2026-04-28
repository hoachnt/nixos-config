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
    };
  };
}
