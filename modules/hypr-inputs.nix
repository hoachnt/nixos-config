# Единая точка для пакетов Hyprland из flake inputs (NixOS `programs.hyprland` + HM `wayland.windowManager.hyprland`).
{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  hyprlandPackage = inputs.hyprland.packages.${system}.hyprland;
  hyprspacePlugin = inputs.Hyprspace.packages.${system}.Hyprspace;
}
