{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Разрешаем запускать unprivileged sandboxes без SUID
  boot.kernel.sysctl = {
    "kernel.unprivileged_userns_clone" = 1;
  };

  security = {
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };

    protectKernelImage = true;
  };
}
