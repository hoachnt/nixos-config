{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Настройки Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Аудио система (Pipewire заменяет PulseAudio и JACK)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Менеджер Bluetooth
  services.blueman.enable = true;

  # RTKit для работы с реальным временем (требуется для Pipewire)
  security.rtkit.enable = true;
}
