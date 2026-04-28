#!/usr/bin/env bash
# Carousel: 1..workspaceCount; 1 → end; active>end → end. Non-numeric active: e-1 (not r-).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="${HERE}/sync_qs_workspaces.sh"
SETTINGS="${HOME}/.config/hypr/settings.json"
HYPRCTL="@HYPRCTL@"
JQ="@JQ@"

__trim() {
  local x="${1:-}"
  x="${x//$'\r'/}"
  x="${x//$'\n'/}"
  printf '%s' "$x"
}

aw_json=$(${HYPRCTL} activeworkspace -j 2>/dev/null || true)
active=$(printf '%s' "$aw_json" | ${JQ} -r '
  (if (.id | type) == "number" then .id
   elif (.id | type) == "string" and (.id | test("^[0-9]+$")) then (.id | tonumber)
   elif (.name | type) == "string" and (.name | test("^[0-9]+$")) then (.name | tonumber)
   else empty end) // empty | if . == null then empty else . end | tostring
' 2>/dev/null || true)
active=$(__trim "$active")

if ! [[ "$active" =~ ^[0-9]+$ ]]; then
  ${HYPRCTL} dispatch workspace e-1
  exit 0
fi

if [ ! -f "$SETTINGS" ]; then
  end=8
else
  end=$(__trim "$(${JQ} -r '.workspaceCount // 8' "$SETTINGS" 2>/dev/null || printf '8')")
  [[ "$end" =~ ^[0-9]+$ ]] || end=8
  [ "$end" -lt 1 ] && end=1
fi

if [ "$active" -le 1 ]; then
  prev=$end
elif [ "$active" -gt "$end" ]; then
  prev=$end
else
  prev=$((active - 1))
fi

[ -x "$SYNC" ] && "$SYNC" 2>/dev/null || true

${HYPRCTL} dispatch workspace "$prev"
