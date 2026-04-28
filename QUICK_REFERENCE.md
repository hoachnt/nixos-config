# 🚀 Быстрая справка по вашей конфигурации NixOS

## 📁 Структура файлов

```
nix/
├── flake.nix              # Точка входа, определяет inputs/outputs
├── flake.lock             # Закрепленные версии (автоматически)
├── configuration.nix       # Главный файл, импортирует модули
├── hardware-configuration.nix  # Настройки железа (UUID, модули ядра)
├── home.nix               # Реэкспорт Home Manager → modules/home/
└── modules/               # Модули конфигурации
    ├── nix.nix           # Настройки Nix (GC, кэш, производительность)
    ├── boot.nix          # Boot loader (systemd-boot)
    ├── system.nix        # Системные настройки (systemd, env vars)
    ├── security.nix       # Безопасность (sudo, защита ядра)
    ├── networking.nix     # Сеть (NetworkManager, firewall)
    ├── locale.nix         # Локализация (timezone, язык)
    ├── graphics.nix       # Графика (NVIDIA, X server, Hyprland session, GNOME)
    ├── hypr-inputs.nix    # Пакет Hyprland + Hyprspace (общий для graphics.nix и HM)
    ├── audio.nix          # Аудио (Pipewire, Bluetooth)
    ├── programs.nix       # Системные программы
    ├── users.nix          # Пользователи и группы
    ├── fonts.nix          # Шрифты
    └── home/              # Home Manager (пакеты, тема GTK/Qt, Hyprland+Quickshell)
        ├── default.nix
        ├── packages.nix
        ├── desktop.nix
        └── hyprland/
            ├── default.nix
            ├── window-manager.nix
            ├── quickshell-options.nix
            ├── quickshell.nix
            ├── patches/
            └── scripts/
```

## 🔧 Основные команды

### Применение конфигурации

```bash
# Применить изменения
sudo nixos-rebuild switch --flake .

# Проверить без применения
sudo nixos-rebuild dry-run --flake .

# Собрать без применения
sudo nixos-rebuild build --flake .

# Откатиться к предыдущей версии
sudo nixos-rebuild switch --rollback
```

### Проверка конфигурации

```bash
# Проверить синтаксис и валидность
nix flake check --no-build

# Посмотреть что изменится
nixos-rebuild list-generations

# Посмотреть опции
nixos-option services.pipewire
```

### Работа с пакетами

```bash
# Поиск пакета
nix search nixpkgs название-пакета

# Установить пакет временно (для теста)
nix-shell -p название-пакета

# Обновить flake.lock
nix flake update
```

## 📝 Где что настраивать

### Системные настройки (требуют sudo)

- **Пакеты для всех**: `modules/programs.nix` → `environment.systemPackages`
- **Сервисы**: соответствующий модуль → `services.название.enable = true`
- **Пользователи**: `modules/users.nix`
- **Сеть**: `modules/networking.nix`
- **Безопасность**: `modules/security.nix`

### Пользовательские настройки (не требуют sudo)

- **Пакеты для пользователя**: `home.nix` → `home.packages`
- **Конфиги приложений**: `home.nix` → `xdg.configFile`
- **Переменные окружения**: `home.nix` → `home.sessionVariables`
- **GTK темы**: `home.nix` → `gtk`

## 🎯 Типичные задачи

### Добавить системный пакет

```nix
# modules/programs.nix
environment.systemPackages = with pkgs; [
  новый-пакет
];
```

```bash
sudo nixos-rebuild switch --flake .
```

### Добавить пользовательский пакет

```nix
# home.nix
home.packages = with pkgs; [
  новый-пакет
];
```

```bash
home-manager switch --flake .#hoachnt
# или
sudo nixos-rebuild switch --flake .  # если интегрирован в flake
```

### Включить новый сервис

```nix
# В соответствующем модуле или создать новый
services.название-сервиса = {
  enable = true;
  настройки = "значения";
};
```

### Изменить переменные окружения

```nix
# modules/system.nix (системные)
environment.variables = {
  EDITOR = "nvim";
};

# home.nix (пользовательские)
home.sessionVariables = {
  EDITOR = "nvim";
};
```

### Настроить firewall

```nix
# modules/networking.nix
networking.firewall = {
  allowedTCPPorts = [ 8080 3000 ];
  allowedUDPPorts = [ 51820 ];
};
```

## 🔍 Полезные места в системе

### Конфигурационные файлы

- `/etc/nixos/` - системная конфигурация (генерируется)
- `/run/current-system/` - текущая активная конфигурация
- `~/.config/` - пользовательские конфиги (Home Manager)
- `/boot/EFI/nixos/` - старые конфигурации для отката

### Логи и отладка

```bash
# Логи systemd
journalctl -u название-сервиса

# Логи загрузки
journalctl -b

# Проверить статус сервиса
systemctl status название-сервиса
```

## ⚠️ Важные моменты

1. **Не редактировать `/etc/nixos/configuration.nix`** - он генерируется автоматически
2. **Всегда использовать `--flake .`** для работы с flake конфигурацией
3. **`system.stateVersion`** не менять без необходимости (влияет на совместимость)
4. **После изменений** всегда проверять: `nix flake check --no-build`
5. **Старые конфигурации** сохраняются в `/boot` для отката

## 🆘 Решение проблем

### Конфигурация не применяется

```bash
# Проверить ошибки
nix flake check --no-build

# Посмотреть детальный вывод
sudo nixos-rebuild switch --flake . --show-trace
```

### Откатиться к рабочей версии

```bash
# Из boot меню выбрать старую конфигурацию
# Или:
sudo nixos-rebuild switch --rollback
```

### Очистить кэш сборки

```bash
# Очистить старые сборки
sudo nix-collect-garbage -d

# Очистить все кроме текущей системы
sudo nix-collect-garbage --delete-old
```

### Обновить пакеты

```bash
# Обновить flake inputs
nix flake update

# Применить обновления
sudo nixos-rebuild switch --flake . --upgrade
```

## 📚 Дополнительная информация

- **ARCHITECTURE.md** - подробное объяснение архитектуры
- **EXAMPLES.md** - практические примеры из вашей конфигурации
- [NixOS Manual](https://nixos.org/manual/nixos/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
