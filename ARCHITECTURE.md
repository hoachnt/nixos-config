# Архитектура конфигурации NixOS

## 🏗️ Общая структура

```
flake.nix (точка входа)
    ↓
configuration.nix (главный файл)
    ↓
    ├── hardware-configuration.nix (железо)
    └── modules/ (модули конфигурации)
        ├── nix.nix
        ├── boot.nix
        ├── system.nix
        ├── security.nix
        ├── networking.nix
        ├── locale.nix
        ├── graphics.nix     # Hyprland (NixOS): `programs.hyprland` — пакет из modules/hypr-inputs.nix
        ├── hypr-inputs.nix  # Общие inputs Hyprland + Hyprspace (NixOS + Home Manager)
        ├── audio.nix
        ├── programs.nix
        ├── users.nix
        ├── fonts.nix
        └── home/            # Home Manager
            ├── default.nix
            ├── packages.nix
            ├── desktop.nix
            └── hyprland/      # Hyprland + Quickshell (HM); ~/.config/hypr — пользовательский base + сгенер. скрипты
                ├── default.nix
                ├── window-manager.nix
                ├── quickshell-options.nix
                ├── quickshell.nix
                ├── patches/
                └── scripts/
    ↓
home.nix → импортирует modules/home/default.nix
```

## 📦 Как это работает

### 1. Flake система (`flake.nix`)

**Что делает:**

- Определяет входные данные (inputs): nixpkgs, home-manager
- Создает выходные данные (outputs): конфигурация NixOS
- Управляет версиями и зависимостями

**Процесс:**

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";  # Репозиторий пакетов
  home-manager = { ... };                              # Менеджер пользовательских настроек
}

outputs = {
  nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
    modules = [ ./configuration.nix ... ];  # Список модулей для сборки системы
  };
}
```

**При выполнении `nixos-rebuild switch --flake .`:**

1. Nix читает `flake.nix`
2. Загружает указанные версии nixpkgs и home-manager
3. Собирает все модули в единую конфигурацию
4. Генерирует системные файлы и сервисы
5. Применяет изменения к системе

---

### 2. Модульная система (`configuration.nix` + `modules/`)

**Принцип работы:**

- Каждый модуль - это функция, которая принимает конфигурацию и возвращает новые настройки
- Модули объединяются через `imports`
- NixOS автоматически мержит все настройки из всех модулей

**Пример работы модуля:**

```nix
# modules/nix.nix
{ config, lib, pkgs, ... }:  # Параметры модуля
{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };
}
```

**Что происходит:**

1. `configuration.nix` импортирует все модули
2. NixOS проходит по каждому модулю
3. Собирает все настройки в один большой атрибут
4. Разрешает конфликты (если есть)
5. Генерирует финальную конфигурацию системы

**Порядок выполнения:**

```
configuration.nix
  → hardware-configuration.nix (железо)
  → modules/nix.nix (настройки Nix)
  → modules/boot.nix (загрузчик)
  → modules/system.nix (системные настройки)
  → ... (все остальные модули)
  → Мерж всех настроек
  → Генерация /etc/nixos/configuration.nix
```

---

### 3. Home Manager (`home.nix`)

**Что делает:**

- Управляет пользовательскими настройками (не системными)
- Настройки в `~/.config/`, `~/.local/`, переменные окружения
- Пакеты для конкретного пользователя

**Интеграция:**

```nix
# В flake.nix
home-manager.nixosModules.home-manager
{
  home-manager.users.hoachnt = import ./home.nix;
}
```

**Разница:**

- **System packages** (`modules/programs.nix`): доступны всем пользователям, требуют sudo
- **Home packages** (`home.nix`): только для пользователя hoachnt, не требуют sudo

---

### 4. Процесс сборки и применения

**Команда:** `sudo nixos-rebuild switch --flake .`

**Что происходит:**

1. **Оценка (Evaluation)**

    ```
    Nix читает flake.nix
    → Загружает все модули
    → Проверяет синтаксис
    → Валидирует опции
    ```

2. **Сборка (Build)**

    ```
    Создает "derivation" для каждого пакета
    → Скачивает/собирает недостающие пакеты
    → Генерирует конфигурационные файлы
    → Создает системные unit файлы (systemd)
    ```

3. **Применение (Switch)**
    ```
    Активирует новую конфигурацию
    → Перезапускает измененные сервисы
    → Обновляет системные файлы
    → Старая конфигурация остается в /boot (для отката)
    ```

**Результат:**

- Новая конфигурация активна
- Старая доступна в boot меню (если что-то сломалось)
- Все изменения атомарны (либо все применено, либо ничего)

---

## 🔄 Как модули взаимодействуют

### Пример: Настройка NVIDIA

```nix
# modules/graphics.nix
hardware.nvidia = { ... };
services.xserver.videoDrivers = [ "nvidia" ];
```

**Что происходит:**

1. Модуль `graphics.nix` определяет настройки NVIDIA
2. NixOS видит `hardware.nvidia` и автоматически:
    - Загружает нужные драйверы
    - Настраивает X server
    - Создает systemd сервисы
3. При применении конфигурации:
    - Устанавливаются пакеты драйверов
    - Генерируется `/etc/X11/xorg.conf`
    - Настраиваются переменные окружения

### Пример: Пользователь и группы

```nix
# modules/users.nix
users.users.hoachnt = {
  extraGroups = [ "wheel" "docker" ];
};

# modules/security.nix
security.sudo.wheelNeedsPassword = false;
```

**Взаимодействие:**

1. `users.nix` создает пользователя с группами
2. `security.nix` настраивает sudo для группы `wheel`
3. Результат: пользователь может использовать sudo без пароля

---

## 📝 Типичный workflow

### Добавление нового пакета:

1. **Системный пакет** (для всех):

    ```nix
    # modules/programs.nix
    environment.systemPackages = with pkgs; [
      новый-пакет
    ];
    ```

2. **Пользовательский пакет** (только для hoachnt):

    ```nix
    # home.nix
    home.packages = with pkgs; [
      новый-пакет
    ];
    ```

3. Применить:
    ```bash
    sudo nixos-rebuild switch --flake .
    ```

### Изменение настройки сервиса:

1. Найти соответствующий модуль (например, `modules/audio.nix`)
2. Изменить настройки
3. Применить конфигурацию
4. Сервис автоматически перезапустится если нужно

---

## 🎯 Ключевые концепции

### 1. Декларативность

Вы описываете **желаемое состояние**, а не команды для его достижения:

```nix
services.pipewire.enable = true;  # "Хочу Pipewire включен"
# NixOS сам знает КАК это сделать
```

### 2. Идемпотентность

Многократное применение одной конфигурации дает одинаковый результат:

```bash
sudo nixos-rebuild switch --flake .  # Результат всегда одинаковый
```

### 3. Откат

Старые конфигурации сохраняются в `/boot`:

- Можно загрузиться в старую версию из boot меню
- Или откатиться командой: `sudo nixos-rebuild switch --rollback`

### 4. Модульность

Каждый модуль независим и может быть переиспользован:

- Легко добавить новый модуль
- Легко отключить существующий (закомментировать в `configuration.nix`)

---

## 🔍 Полезные команды

```bash
# Проверить конфигурацию без применения
nix flake check --no-build

# Посмотреть что изменится
sudo nixos-rebuild dry-run --flake .

# Откатиться к предыдущей конфигурации
sudo nixos-rebuild switch --rollback

# Собрать конфигурацию без применения
sudo nixos-rebuild build --flake .

# Посмотреть все опции
nixos-option services.pipewire
```

---

## 📚 Дополнительные ресурсы

- [NixOS Manual](https://nixos.org/manual/nixos/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [NixOS Wiki](https://nixos.wiki/)
