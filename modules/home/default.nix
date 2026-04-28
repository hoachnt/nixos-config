{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:

# Hyprland: пользовательский `~/.config/hypr/hyprland-base.conf` + сгенерированные HM файлы
# (`hyprland.conf`, скрипты Quickshell) — см. `hyprland/`.
let
  theme = {
    gtk = "Adwaita";
    icon = "Adwaita";
    colorScheme = "prefer-light";
  };
in

{
  imports = [
    (import ./packages.nix { inherit pkgs; })
    (import ./desktop.nix theme)
    (import ./hyprland theme)
  ];

  home.username = "hoachnt";
  home.homeDirectory = "/home/hoachnt";
  home.stateVersion = "25.05";

  # Quickshell wallpaper picker + qs_manager / matugen (same as default, explicit for your layout).
  quickshellShell.wallpaperDirectory = "${config.home.homeDirectory}/Pictures/Wallpapers";

  programs.home-manager.enable = true;
}
