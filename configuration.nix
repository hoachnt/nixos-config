{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # Аппаратная конфигурация (сгенерирована автоматически)
    ./hardware-configuration.nix

    # Системные модули
    ./modules/nix.nix # Настройки Nix
    ./modules/boot.nix # Boot loader
    ./modules/system.nix # Общие системные настройки
    ./modules/security.nix # Настройки безопасности

    # Сеть и локализация
    ./modules/networking.nix # Сеть, firewall
    ./modules/locale.nix # Часовой пояс, локализация

    # Аппаратное обеспечение
    ./modules/graphics.nix # NVIDIA, X server, Hyprland, GNOME
    ./modules/audio.nix # Pipewire, Bluetooth

    # Программы и пользователи
    ./modules/programs.nix # Системные программы
    ./modules/users.nix # Пользователи
    ./modules/fonts.nix # Шрифты
  ];

  # Версия состояния системы (не менять без необходимости)
  system.stateVersion = "25.05";
}
