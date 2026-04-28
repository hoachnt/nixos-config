#!/usr/bin/env bash
# One-off refresh of /tmp/qs_workspaces.json (same logic as print_workspaces in workspaces.sh).
# Quickshell Apply chains this so the top bar list matches settings.json when workspace count changes
# and the long-running inotify in workspaces.sh does not fire in time.
# Bar uses workspaceCount slots; last pill id is always workspaceCount (active tooltip if focused ws > end).
set -euo pipefail

SETTINGS_FILE="$HOME/.config/hypr/settings.json"
SEQ_END=$("@JQ@" -r '.workspaceCount // 8' "$SETTINGS_FILE" 2>/dev/null) || true
[ -z "$SEQ_END" ] && SEQ_END=8
if ! [[ "$SEQ_END" =~ ^[0-9]+$ ]]; then
  SEQ_END=8
fi
if [ "$SEQ_END" -lt 1 ] 2>/dev/null; then
  SEQ_END=1
fi

spaces=$("@TIMEOUT@" 2 @HYPRCTL@ workspaces -j 2>/dev/null) || true
if [ -z "$spaces" ]; then
  exit 0
fi

aw=$("@TIMEOUT@" 2 @HYPRCTL@ activeworkspace -j 2>/dev/null) || true
active=$(printf '%s' "$aw" | @JQ@ -r 'try (.id|tonumber) catch 0' 2>/dev/null) || true
if ! [[ "$active" =~ ^[0-9]+$ ]]; then
  active=0
fi

echo "$spaces" | @JQ@ --unbuffered --argjson a "$active" --arg end "$SEQ_END" -c '
  (map( { (.id|tostring): . } ) | add) as $s
  |
  ($end|tonumber) as $end
  | ($a|tonumber) as $a
  |
  [range(1; $end + 1)] | map(
      . as $slot |
      (if $slot < $end then $slot else $end end) as $wid |
      (if $a == $wid then "active"
       elif ($a > $end) and ($slot == $end) then "active"
       elif ($s[$wid|tostring] != null and $s[$wid|tostring].windows > 0) then "occupied"
       elif ($a > $end) and ($slot == $end) and ($s[$a|tostring] != null and $s[$a|tostring].windows > 0) then "occupied"
       else "empty" end) as $state |
      (if ($slot == $end) and ($a > $end) and ($s[$a|tostring] != null) then $s[$a|tostring].lastwindowtitle
       elif $s[$wid|tostring] != null then $s[$wid|tostring].lastwindowtitle
       else "Empty" end) as $win |
      { id: $wid, state: $state, tooltip: $win }
  )
' > /tmp/qs_workspaces.tmp
mv -f /tmp/qs_workspaces.tmp /tmp/qs_workspaces.json
