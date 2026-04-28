# Практические примеры из вашей конфигурации

## 🔍 Разбор конкретных примеров

### Пример 1: Как работает модуль `nix.nix`

```nix
# modules/nix.nix
{ config, lib, pkgs, ... }:
{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
}
```

**Что происходит:**

1. При `nixos-rebuild switch` этот модуль загружается
2. NixOS видит `nix.settings.experimental-features`
3. Автоматически генерирует `/etc/nix/nix.conf`:
    ```
    experimental-features = nix-command flakes
    auto-optimise-store = true
    ```
4. Nix daemon перечитывает конфигурацию
5. Теперь можно использовать `nix` команды и flakes

**Где это используется:**

- Всякий раз когда вы запускаете `nix` команды
- При сборке пакетов
- При работе с flakes

---

### Пример 2: Модуль `graphics.nix` - настройка NVIDIA

```nix
# modules/graphics.nix
hardware.nvidia = {
  modesetting.enable = true;
  package = config.boot.kernelPackages.nvidiaPackages.production;
};

services.xserver.videoDrivers = [ "nvidia" ];
```

**Что происходит:**

1. NixOS видит `hardware.nvidia` и:
    - Устанавливает драйверы NVIDIA из `nvidiaPackages.production`
    - Загружает модуль ядра `nvidia`
    - Настраивает `/etc/modprobe.d/nvidia.conf`

2. `services.xserver.videoDrivers = [ "nvidia" ]`:
    - Генерирует `/etc/X11/xorg.conf` с настройками NVIDIA
    - Создает systemd сервис `display-manager.service`
    - Настраивает переменные окружения (`__GL_SYNC_TO_VBLANK`, etc.)

3. При загрузке:
    - Ядро загружает модуль `nvidia`
    - X server использует драйвер NVIDIA
    - GDM запускается с поддержкой NVIDIA

**Результат:**

- Работает ускорение GPU
- Поддержка Wayland через Xwayland
- Настройки в `nvidia-settings` работают

---

### Пример 3: Разница между System и Home пакетами

**System пакеты** (`modules/programs.nix`):

```nix
environment.systemPackages = with pkgs; [
  neovim
  git
  docker
];
```

**Что происходит:**

- Устанавливаются в `/nix/store/` (системный уровень)
- Доступны всем пользователям
- Требуют `sudo` для установки
- Пути в `/run/current-system/sw/bin/`

**Home пакеты** (`home.nix`):

```nix
home.packages = with pkgs; [
  waybar
  kitty
  vscode
];
```

**Что происходит:**

- Устанавливаются в `/nix/store/` (но для пользователя)
- Доступны только пользователю `hoachnt`
- Не требуют `sudo`
- Пути в `~/.nix-profile/bin/`
- Симлинки в `~/.local/state/home-manager/gcroots/`

**Когда что использовать:**

- **System**: системные утилиты, серверные программы, драйверы
- **Home**: GUI приложения, редакторы, пользовательские инструменты

---

### Пример 4: Как работает Pipewire (`modules/audio.nix`)

```nix
services.pipewire = {
  enable = true;
  alsa.enable = true;
  pulse.enable = true;
  jack.enable = true;
};
```

**Что происходит:**

1. NixOS создает systemd сервисы:
    - `pipewire.service` - основной сервис
    - `pipewire-pulse.service` - совместимость с PulseAudio
    - `pipewire-jack.service` - совместимость с JACK

2. Генерирует конфигурационные файлы:
    - `/etc/pipewire/pipewire.conf`
    - `/etc/pipewire/pipewire-pulse.conf`

3. Создает симлинки для совместимости:
    - `/usr/bin/pactl` → pipewire-pulse
    - ALSA приложения работают через pipewire

4. При запуске системы:
    - Pipewire стартует автоматически
    - Приложения видят его как PulseAudio или JACK
    - Работает с Bluetooth наушниками

**Результат:**

- Один аудио сервер вместо трех (PulseAudio, JACK, ALSA)
- Низкая задержка
- Работают все старые приложения

---

### Пример 5: Home Manager настройки (`home.nix`)

```nix
gtk = {
  enable = true;
  theme = {
    name = "Kanagawa-BL-LB-Dark-Dragon";
    package = pkgs.kanagawa-gtk-theme;
  };
};

xdg.configFile."gtk-4.0/gtk.css" = {
  source = ./dotfiles/gtk-4.0/gtk.css;
  force = true;
};
```

**Что происходит:**

1. Home Manager видит `gtk.enable = true`:
    - Генерирует `~/.config/gtk-3.0/settings.ini`
    - Генерирует `~/.config/gtk-4.0/settings.ini`
    - Устанавливает тему из `kanagawa-gtk-theme`

2. `xdg.configFile`:
    - Копирует `./dotfiles/gtk-4.0/gtk.css` → `~/.config/gtk-4.0/gtk.css`
    - `force = true` означает перезаписать если существует

3. При применении:
    - Home Manager создает симлинки в `~/.config/`
    - GTK приложения автоматически подхватывают тему
    - Не нужно вручную копировать файлы

**Результат:**

- Все GTK приложения используют тему Kanagawa
- Кастомный CSS применяется
- При переустановке системы настройки восстановятся автоматически

---

### Пример 6: Как работает Hyprland конфигурация

```nix
# home.nix
wayland.windowManager.hyprland = {
  enable = true;
  extraConfig = ''
    source = /home/hoachnt/.config/hypr/hyprland-base.conf
  '';
};
```

**Что происходит:**

1. Home Manager генерирует `~/.config/hypr/hyprland.conf`:

    ```ini
    # Этот файл управляется Home Manager
    source = /home/hoachnt/.config/hypr/hyprland-base.conf
    ```

2. Hyprland при запуске:
    - Читает `~/.config/hypr/hyprland.conf`
    - Видит `source = ...`
    - Загружает ваш кастомный конфиг из `hyprland-base.conf`

3. Преимущества:
    - Home Manager управляет базовой структурой
    - Вы управляете деталями в `hyprland-base.conf`
    - При обновлении Home Manager не перезапишет ваш конфиг

---

## 🔄 Полный цикл: от изменения до применения

### Сценарий: Добавление нового пакета

**Шаг 1:** Редактируем `modules/programs.nix`

```nix
environment.systemPackages = with pkgs; [
  neovim
  новый-пакет  # ← добавляем
];
```

**Шаг 2:** Выполняем команду

```bash
sudo nixos-rebuild switch --flake .
```

**Шаг 3:** Что происходит внутри:

1. **Evaluation (оценка)**

    ```
    Nix читает flake.nix
    → Загружает все модули
    → Видит "новый-пакет" в programs.nix
    → Проверяет что пакет существует в nixpkgs
    → Валидирует все опции
    ```

2. **Build (сборка)**

    ```
    Nix создает "derivation" для нового-пакета
    → Проверяет есть ли в кэше (cache.nixos.org)
    → Если нет - скачивает или собирает
    → Создает симлинки в /nix/store/.../bin/новый-пакет
    ```

3. **Switch (применение)**
    ```
    Активирует новую конфигурацию
    → Создает /run/current-system (симлинк)
    → Обновляет /etc/static/systemd/system/
    → Перезапускает измененные сервисы
    → Старая конфигурация остается в /boot/EFI/nixos/
    ```

**Шаг 4:** Результат

- Пакет установлен и доступен в PATH
- Можно использовать `новый-пакет` в терминале
- При следующей загрузке будет доступен автоматически

---

## 🎯 Ключевые моменты

### 1. Декларативность

Вы не говорите "установи пакет", а говорите "хочу чтобы пакет был доступен":

```nix
# Не команда: "apt install neovim"
# А декларация: "в системе должен быть neovim"
environment.systemPackages = [ pkgs.neovim ];
```

### 2. Идемпотентность

Многократное применение безопасно:

```bash
# Можно запускать сколько угодно раз
sudo nixos-rebuild switch --flake .
# Результат всегда одинаковый
```

### 3. Откат

Всегда можно вернуться:

```bash
# В boot меню выбрать старую конфигурацию
# Или:
sudo nixos-rebuild switch --rollback
```

### 4. Модульность

Легко управлять:

```nix
# Отключить модуль - просто закомментировать
imports = [
  # ./modules/audio.nix  # ← отключен
];
```

---

## 🛠️ Типичные задачи

### Задача: Добавить новый сервис

1. Найти соответствующий модуль или создать новый
2. Добавить настройки:
    ```nix
    services.новый-сервис = {
      enable = true;
      настройки = "значения";
    };
    ```
3. Применить: `sudo nixos-rebuild switch --flake .`
4. Сервис автоматически запустится

### Задача: Изменить переменные окружения

```nix
# modules/system.nix
environment.variables = {
  EDITOR = "nvim";
  CUSTOM_VAR = "значение";
};
```

### Задача: Настроить firewall

```nix
# modules/networking.nix
networking.firewall = {
  allowedTCPPorts = [ 8080 3000 ];
  allowedUDPPorts = [ 51820 ];
};
```

---

## 📊 Визуализация потока данных

```
flake.nix
  │
  ├─→ nixpkgs (репозиторий пакетов)
  │   └─→ Все пакеты: neovim, git, docker, ...
  │
  ├─→ home-manager
  │   └─→ Пользовательские настройки
  │
  └─→ configuration.nix
      │
      ├─→ hardware-configuration.nix
      │   └─→ UUID дисков, модули ядра
      │
      └─→ modules/
          │
          ├─→ nix.nix → /etc/nix/nix.conf
          ├─→ boot.nix → /boot/loader/entries/
          ├─→ networking.nix → /etc/systemd/network/
          ├─→ graphics.nix → /etc/X11/xorg.conf
          ├─→ audio.nix → /etc/pipewire/
          ├─→ programs.nix → /run/current-system/sw/
          └─→ ... → различные системные файлы
      │
      └─→ home.nix
          └─→ ~/.config/, ~/.local/, ~/.nix-profile/
```

**Результат:** Единая конфигурация → Вся система настроена
