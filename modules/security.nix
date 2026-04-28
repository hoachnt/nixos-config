{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Настройки безопасности
  security = {
    # Sudo настройки для группы wheel
    sudo = {
      enable = true;
      wheelNeedsPassword = false; # sudo без пароля для wheel группы
    };

    # Защита образа ядра от модификации
    protectKernelImage = true;
  };
}
