{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Скрипт captive portal — открывает Firefox при обнаружении портала
  captivePortalScript = pkgs.writeShellScript "captive-portal-dispatcher" ''
    set -euo pipefail
    
    LOG_FILE="/tmp/captive-portal.log"
    echo "$(date): Dispatcher called with arg1=$1 arg2=$2" >> "$LOG_FILE"

    # Реагируем только на изменение connectivity
    [ "''${2:-}" = "connectivity-change" ] || exit 0

    # Принудительная перепроверка статуса
    STATUS=$(${pkgs.networkmanager}/bin/nmcli networking connectivity check 2>/dev/null || echo "unknown")
    echo "$(date): Connectivity status is $STATUS" >> "$LOG_FILE"

    # Если статус не portal, возможно он none/limited. Если это так, мы всё равно не сможем
    # прогрузить портал по DNS. Но если это portal, идём дальше.
    # Добавим обработку "limited" на всякий случай? Нет, пока оставим portal.
    [ "$STATUS" = "portal" ] || exit 0

    # Защита от повторного открытия (lock на 60 секунд)
    LOCK="/tmp/captive-portal-dispatcher.lock"
    if [ -f "$LOCK" ]; then
      LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK") ))
      if [ "$LOCK_AGE" -lt 60 ]; then
        echo "$(date): Locked, exiting" >> "$LOG_FILE"
        exit 0
      fi
    fi
    touch "$LOCK"
    echo "$(date): Lock created, finding user session" >> "$LOG_FILE"

    # Находим активную графическую сессию
    REAL_USER=$(${pkgs.systemd}/bin/loginctl list-sessions --no-legend \
      | ${pkgs.gawk}/bin/awk '$6 == "user" {print $3}' | head -1)
    [ -n "$REAL_USER" ] || { echo "$(date): No real user found" >> "$LOG_FILE"; exit 0; }

    REAL_UID=$(${pkgs.coreutils}/bin/id -u "$REAL_USER" 2>/dev/null || exit 0)

    # Определяем Wayland display из окружения пользователя
    WAYLAND=$(find "/run/user/$REAL_UID" -maxdepth 1 \( -name "wayland-[0-9]" -o -name "wayland-[0-9][0-9]" \) -printf '%f\n' 2>/dev/null | head -1)
    [ -n "$WAYLAND" ] || WAYLAND="wayland-1"

    export WAYLAND_DISPLAY="$WAYLAND"
    export XDG_RUNTIME_DIR="/run/user/$REAL_UID"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus"

    echo "$(date): Sending notification to user $REAL_USER" >> "$LOG_FILE"
    # Уведомление
    ${pkgs.sudo}/bin/sudo -u "$REAL_USER" \
      env WAYLAND_DISPLAY="$WAYLAND" \
          XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
      ${pkgs.libnotify}/bin/notify-send \
        -u critical \
        -i network-wireless \
        "Captive Portal" \
        "Требуется авторизация Wi-Fi. Открываю браузер..." 2>/dev/null || true

    echo "$(date): Launching browser" >> "$LOG_FILE"
    # Открываем браузер
    ${pkgs.sudo}/bin/sudo -u "$REAL_USER" \
      env WAYLAND_DISPLAY="$WAYLAND" \
          XDG_RUNTIME_DIR="/run/user/$REAL_UID" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
      ${pkgs.firefox}/bin/firefox "http://nmcheck.gnome.org" &
  '';
in
{
  # Настройки сети
  networking = {
    hostName = "nixos";

    networkmanager = {
      enable = true;
      
      # Отключаем рандомизацию MAC-адресов, так как она часто ломает
      # авторизацию в captive portals (портал запоминает один MAC, 
      # а NM после сканирования или переподключения использует другой)
      wifi.scanRandMacAddress = false;
      wifi.macAddress = "preserve";

      # Connectivity check — NM определяет состояние "portal"
      settings.connectivity = {
        uri = "http://nmcheck.gnome.org/check_network_status.txt";
        response = "NetworkManager is online";
        interval = 300;
      };

      # Dispatcher: при обнаружении captive portal открывает основной браузер
      dispatcherScripts = [
        {
          source = captivePortalScript;
          type = "basic";
        }
      ];
    };

    # Настройки firewall
    firewall = {
      enable = true;
    };
  };

  # systemd-resolved для корректной работы DNS в публичных сетях.
  # Разделяет DNS-запросы по интерфейсам — captive portal может
  # подменить DNS через DHCP, а resolved это корректно обработает.
  # Отключаем DNSSEC, так как captive-порталы подменяют DNS-ответы,
  # что вызывает сбои проверки подписей DNSSEC и блокирует работу сети.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "no";
      # Убрали FallbackDNS, чтобы принудительно использовать только
      # DNS от DHCP (иначе systemd-resolved может пытаться достучаться
      # до 1.1.1.1, который заблокирован порталом, и DNS полностью ломается).
    };
  };
}
