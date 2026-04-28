{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Настройки сети
  networking = {
    hostName = "nixos";
    networkmanager.enable = true;

    # Настройки firewall
    firewall = {
      enable = true;
      # WireGuard порт
      allowedUDPPorts = [ 51820 ];
      # Доверенные интерфейсы (WireGuard)
      trustedInterfaces = [ "wg-vps" ];
    };
  };
}
