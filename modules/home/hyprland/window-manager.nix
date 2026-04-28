# Сессия Hyprland: пакет и плагины совпадают с `modules/graphics.nix` (см. `modules/hypr-inputs.nix`).
# Пользовательский конфиг лежит в ~/.config/hypr/hyprland-base.conf; интеграции — через mkAfter в quickshell.nix.
theme:
{ config, lib, pkgs, inputs, ... }:
let
  hypr = import ../../hypr-inputs.nix { inherit inputs pkgs; };
in
{
  wayland.windowManager.hyprland = {
    enable = true;

    package = hypr.hyprlandPackage;

    plugins = [ hypr.hyprspacePlugin ];

    extraConfig = ''
      env = GTK_USE_PORTAL,1
      env = ICON_THEME,${theme.icon}
      exec-once = ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd --all
      source = ~/.config/hypr/hyprland-base.conf
    '';
  };
}
