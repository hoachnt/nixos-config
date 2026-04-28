{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Настройки Nix
  nix = {
    settings = {
      # Экспериментальные функции
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Автоматическая оптимизация хранилища
      auto-optimise-store = true;

      # Настройки производительности сборки
      max-jobs = lib.mkDefault "auto";
      cores = 0; # Использовать все доступные ядра

      # Кэширование
      trusted-users = [
        "root"
        "hoachnt"
      ];
    };

    # Автоматическая сборка мусора
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Настройки daemon
    daemonIOSchedClass = "idle";
    daemonCPUSchedPolicy = "idle";
  };

  # Разрешить несвободные пакеты
  nixpkgs.config.allowUnfree = true;
}
