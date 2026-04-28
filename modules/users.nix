{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Настройки пользователя
  users.users.hoachnt = {
    isNormalUser = true;
    description = "hoachnt";
    extraGroups = [
      "wheel" # sudo доступ
      "networkmanager" # управление сетью
      "docker" # работа с Docker
    ];
  };
}
