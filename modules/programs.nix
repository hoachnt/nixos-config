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
    nftables
    libnetfilter_queue
    iproute2

    # Инструменты разработки
    git
    go
    nodejs
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

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      glib
      nspr
      nss
      atk
      at-spi2-core
      dbus
      cups
      expat
      libxkbcommon
      alsa-lib
      libgbm
      cairo
      pango
      systemd
      libdrm
      libxcb
      libx11
      libxext
      libxcomposite
      libxdamage
      libxfixes
      libxrandr
      libxshmfence
      libGL
    ];
  };


  # Сервисы
  services.flatpak.enable = true;

  # GVfs: trash://, сеть в боковой панели Nautilus и т.д.
  services.gvfs.enable = true;

  # Виртуализация
  virtualisation.docker.enable = true;

  # Системные пакеты
  environment.systemPackages = systemPackages;
}
