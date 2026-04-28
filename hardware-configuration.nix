# Аппаратная конфигурация системы
# Этот файл был сгенерирован 'nixos-generate-config', но его можно и нужно редактировать
# для оптимизации и настройки под конкретное железо.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    # Автоматическое определение оборудования
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Модули ядра для initrd (начальная загрузка)
  boot.initrd = {
    availableKernelModules = [
      "xhci_pci" # USB 3.0 контроллер
      "ahci" # SATA контроллер
      "nvme" # NVMe SSD
      "usb_storage" # USB накопители
      "sd_mod" # SD карты
    ];
    kernelModules = [ ];
  };

  # Модули ядра для основной системы
  boot.kernelModules = [
    "kvm-intel" # Виртуализация Intel (KVM)
  ];
  boot.extraModulePackages = [ ];

  # Файловые системы
  fileSystems = {
    # Корневая файловая система
    "/" = {
      device = "/dev/disk/by-uuid/ddf05ada-fc79-4f2c-ae78-3fe4dbfcbb76";
      fsType = "ext4";
      # Оптимизации производительности
      # noatime - не обновлять время доступа (улучшает производительность)
      # nodiratime - не обновлять время доступа для директорий
      options = [
        "noatime"
        "nodiratime"
        "discard"
      ];
    };

    # EFI раздел загрузки
    "/boot" = {
      device = "/dev/disk/by-uuid/F750-49D8";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
  };

  # Устройства подкачки (swap)
  # Если нужен swap, можно добавить:
  # swapDevices = [ { device = "/dev/disk/by-uuid/..."; } ];
  # Или использовать zram (более эффективно для SSD):
  # zramSwap.enable = true;
  swapDevices = [ ];

  # Сетевые настройки
  # Включает DHCP на всех ethernet и wireless интерфейсах
  # При использовании NetworkManager это настройка обычно не нужна,
  # но оставлена для совместимости
  networking.useDHCP = lib.mkDefault true;

  # Если нужно настроить конкретные интерфейсы:
  # networking.interfaces.enp8s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp7s0.useDHCP = lib.mkDefault true;

  # Платформа для сборки пакетов
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Обновление микрокода Intel (исправления безопасности и стабильности)
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
