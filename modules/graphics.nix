{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  hypr = import ./hypr-inputs.nix { inherit inputs pkgs; };
in

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

  # Desktop Manager
  # services.desktopManager.gnome.enable = true;

  # Quickshell battery widget calls `powerprofilesctl`; needs daemon + client in PATH.
  services.power-profiles-daemon.enable = true;

  # Wayland композитор
  programs.hyprland = {
    enable = true;
    package = hypr.hyprlandPackage;
    
    xwayland.enable = true;
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
      default = [ "hyprland" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
      "org.freedesktop.impl.portal.OpenURI" = [ "gtk" ];
      # Тёмная тема / accent для порталов и части Flatpak без полного GNOME Shell
      "org.freedesktop.impl.portal.Settings" = [ "gnome" ];
    };
  };
}
