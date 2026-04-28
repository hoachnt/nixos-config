{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Настройки загрузчика
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10; # Ограничение количества записей в boot меню
        editor = false; # Отключить редактор в boot меню (безопасность)
      };
      efi.canTouchEfiVariables = true;
    };

    # Оптимизация загрузки
    initrd.systemd.enable = true;

    kernelModules = [ "nfnetlink_queue" ];
  };
}
