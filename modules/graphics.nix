{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Графическая подсистема
  hardware.graphics.enable = true;

  # Настройки NVIDIA
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  # X Server (требуется для GDM и некоторых приложений)
  services.xserver = {
    enable = true;
    videoDrivers = [ "nvidia" ];

    # Настройки клавиатуры
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  # Display Manager
  services.displayManager.gdm.enable = true;

  # Включаем сам GNOME (Desktop Environment)
  services.desktopManager.gnome.enable = true;

  # Переменные окружения для Wayland/Ozone (Chromium, Electron: Chrome, Cursor, Antigravity) и NVIDIA
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  # GTK file chooser / «открыть папку» из браузера — те же шрифты и тема, что у GTK
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
    config.common = {
      default = [
        "gnome"
        "gtk"
      ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
      "org.freedesktop.impl.portal.OpenURI" = [ "gtk" ];
      # Тёмная тема / accent для порталов и части Flatpak без полного GNOME Shell
      "org.freedesktop.impl.portal.Settings" = [ "gnome" ];
    };
  };
}
