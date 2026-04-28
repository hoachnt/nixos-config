{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Системные пакеты - базовые утилиты и инструменты разработки
  systemPackages = with pkgs; [
    # Редакторы
    neovim

    # Сетевые утилиты
    wget
    wireguard-tools
    nftables
    libnetfilter_queue
    iproute2

    # Инструменты разработки
    git
    go
    nodejs_20
    pnpm
    python3

    # Системные утилиты
    docker
    unzip
    zip
    htop-vim
    nixfmt
  ];
in
{
  # Программы с интеграцией в систему
  programs.dconf.enable = true;
  programs.firefox.enable = true;
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # Сервисы
  services.flatpak.enable = true;

  # GVfs: trash://, сеть в боковой панели Nautilus и т.д. Без этого на Hyprland часто «trash not supported».
  services.gvfs.enable = true;

  # Виртуализация
  virtualisation.docker.enable = true;

  # Системные пакеты
  environment.systemPackages = systemPackages;
}
