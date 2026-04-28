{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Общие системные настройки

  # Оптимизация производительности
  systemd = {
    # Улучшение производительности загрузки
    settings = {
      Manager = {
        DefaultTimeoutStopSec = "10s";
      };
    };
  };

  # Настройки для работы с файлами (опционально, можно добавить в hardware-configuration.nix)
  # fileSystems."/".options = lib.mkDefault [ "noatime" "nodiratime" ];

  # Настройки окружения
  environment = {
    # Переменные окружения
    variables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };

    # Настройки shell (bash всегда доступен)
    shells = with pkgs; [ bash ];
    defaultPackages = [ ];
  };

  # Настройки локализации (дополнительные)
  i18n = {
    supportedLocales = lib.mkDefault [
      "en_US.UTF-8/UTF-8"
      "ru_RU.UTF-8/UTF-8"
    ];
  };
}
