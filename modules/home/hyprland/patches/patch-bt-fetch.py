#!/usr/bin/env python3
"""
Patch bt_fetch.sh so that all bluetoothctl calls use pipe form
and properly handle ANSI escape codes.
Without a TTY, bluetoothctl returns empty output when called directly.
"""
import pathlib, sys

out = pathlib.Path(sys.argv[1])
p = out / "quickshell/watchers/bt_fetch.sh"
if not p.is_file():
    sys.exit("bt_fetch.sh not found")

# Rewrite the entire script with correct pipe-based bluetoothctl calls
# and ANSI stripping via sed
t = r'''#!/usr/bin/env bash
_btctl() {
    echo "$1" | timeout 1 bluetoothctl 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -v '^\[' | grep -v '^Agent' | grep -v '^Waiting' | grep -v 'SupportedUUIDs'
}
get_bt_status() {
    if _btctl "show" | grep -q "Powered: yes"; then echo "on"; else echo "off"; fi
}
get_bt_connected_device() {
    if [ "$(get_bt_status)" = "on" ]; then
        local device=$(_btctl "devices Connected" | grep "^Device" | head -n1 | cut -d' ' -f3-)
        if [ -n "$device" ]; then echo "$device"; else echo "Disconnected"; fi
    else echo "Off"; fi
}
get_bt_icon() {
    if [ "$(get_bt_status)" = "on" ]; then
        if _btctl "devices Connected" | grep -q "^Device"; then echo "󰂱"; else echo "󰂯"; fi
    else echo "󰂲"; fi
}
toggle_bt() {
    if [ "$(get_bt_status)" = "on" ]; then
        _btctl "power off" > /dev/null
        notify-send -u low -i bluetooth-disabled "Bluetooth" "Disabled"
    else
        _btctl "power on" > /dev/null
        notify-send -u low -i bluetooth-active "Bluetooth" "Enabled"
    fi
}
case $1 in
    --toggle) toggle_bt ;;
    *) jq -n -c --arg status "$(get_bt_status)" --arg icon "$(get_bt_icon)" --arg connected "$(get_bt_connected_device)" '{status: $status, icon: $icon, connected: $connected}' ;;
esac
'''

p.write_text(t)
print("bt_fetch.sh patched successfully")
