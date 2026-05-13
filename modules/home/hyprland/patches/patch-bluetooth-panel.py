#!/usr/bin/env python3
"""
Patch bluetooth_panel_logic.sh so that every `bluetoothctl` invocation
is piped through stdin (echo "cmd" | bluetoothctl) instead of using
the non-interactive CLI form (bluetoothctl cmd).

Without a TTY, `bluetoothctl list`, `bluetoothctl show`, etc. return
empty output, which causes the widget to report present=false and
fall back to Wi-Fi/Ethernet.
"""
import pathlib, sys, re

out = pathlib.Path(sys.argv[1])
p = out / "quickshell/network/bluetooth_panel_logic.sh"
if not p.is_file():
    sys.exit("bluetooth_panel_logic.sh not found")

t = p.read_text()

# 1. Fix controller detection: `bluetoothctl list` → pipe form
old_controller = 'controller=$(timeout 1 bluetoothctl list 2>/dev/null | head -n1)'
new_controller = 'controller=$(echo "list" | timeout 1 bluetoothctl 2>/dev/null | grep "^Controller" | head -n1)'
if old_controller in t:
    t = t.replace(old_controller, new_controller, 1)
else:
    print("Warning: controller line not found (already patched?)", file=sys.stderr)

# 2. Fix power detection: `bluetoothctl show` → pipe form
old_power = 'if timeout 1 bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then power="on"; fi'
new_power = 'if echo "show" | timeout 1 bluetoothctl 2>/dev/null | grep -q "Powered: yes"; then power="on"; fi'
if old_power in t:
    t = t.replace(old_power, new_power, 1)
else:
    print("Warning: power line not found (already patched?)", file=sys.stderr)

# 3. Fix `bluetoothctl devices Paired` → pipe form
old_paired = 'paired_macs=$(bluetoothctl devices Paired)'
new_paired = 'paired_macs=$(echo "devices Paired" | bluetoothctl 2>/dev/null | grep "^Device")'
if old_paired in t:
    t = t.replace(old_paired, new_paired, 1)
else:
    print("Warning: paired_macs line not found (already patched?)", file=sys.stderr)

# 4. Fix `bluetoothctl devices` → pipe form
old_devices = 'mapfile -t devices < <(bluetoothctl devices)'
new_devices = 'mapfile -t devices < <(echo "devices" | bluetoothctl 2>/dev/null | grep "^Device")'
if old_devices in t:
    t = t.replace(old_devices, new_devices, 1)
else:
    print("Warning: devices line not found (already patched?)", file=sys.stderr)

# 5. Fix `bluetoothctl devices Connected` → pipe form
old_connected = 'mapfile -t connected_info_lines < <(bluetoothctl devices Connected)'
new_connected = 'mapfile -t connected_info_lines < <(echo "devices Connected" | bluetoothctl 2>/dev/null | grep "^Device")'
if old_connected in t:
    t = t.replace(old_connected, new_connected, 1)
else:
    print("Warning: connected devices line not found (already patched?)", file=sys.stderr)

# 6. Fix `bluetoothctl info "$mac"` → pipe form (multiple occurrences)
t = t.replace(
    'info=$(bluetoothctl info "$mac")',
    'info=$(echo "info $mac" | bluetoothctl 2>/dev/null)'
)
t = t.replace(
    'bat=$(bluetoothctl info "$mac"',
    'bat=$(echo "info $mac" | bluetoothctl 2>/dev/null'
)

# 7. Fix toggle_power function
old_toggle_show = 'if bluetoothctl show | grep -q "Powered: yes"; then'
new_toggle_show = 'if echo "show" | bluetoothctl 2>/dev/null | grep -q "Powered: yes"; then'
t = t.replace(old_toggle_show, new_toggle_show)

old_power_off = '        bluetoothctl power off'
new_power_off = '        echo "power off" | bluetoothctl 2>/dev/null'
t = t.replace(old_power_off, new_power_off)

old_power_on = '        bluetoothctl power on'
new_power_on = '        echo "power on" | bluetoothctl 2>/dev/null'
t = t.replace(old_power_on, new_power_on)

# 8. Fix connect_dev function
t = t.replace(
    'bluetoothctl trust "$mac"',
    'echo "trust $mac" | bluetoothctl'
)
t = t.replace(
    'bluetoothctl connect "$mac"',
    'echo "connect $mac" | bluetoothctl'
)

# 9. Fix disconnect_dev function
t = t.replace(
    'bluetoothctl disconnect "$mac"',
    'echo "disconnect $mac" | bluetoothctl'
)

# 10. Fix bt_fetch.sh-called scan off in qs_manager (not in this file, but
#     there's a `bluetoothctl scan off` in qs_manager.sh — handled separately)

p.write_text(t)
print("bluetooth_panel_logic.sh patched successfully")
