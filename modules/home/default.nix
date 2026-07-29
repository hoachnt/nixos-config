{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:

{
  imports = [
    (import ./packages.nix { inherit pkgs; })
    ./desktop.nix
  ];

  home.username = "hoachnt";
  home.homeDirectory = "/home/hoachnt";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
