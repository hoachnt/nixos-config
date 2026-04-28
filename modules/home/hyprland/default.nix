# Hyprland (Home Manager) + Quickshell: один каталог, без дублирования версий пакета с NixOS.
theme:
{ ... }:
{
  imports = [
    (import ./window-manager.nix theme)
    ./quickshell-options.nix
    ./quickshell.nix
  ];
}
