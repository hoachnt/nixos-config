{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  config = lib.mkIf config.quickshellShell.enable (
    let
      qs = config.quickshellShell;
      hm = config.home.homeDirectory;

      # ilyamiro flake `matugen/templates` has no hyprland.conf.template; matugen 4.x also needs a TTY or
      # `--source-color-index` for `matugen image` (Quickshell runs without a PTY).
      hyprlandMatugenTemplate =
        pkgs.writeText "hyprland.conf.template" ''
          $active_border = rgba({{colors.primary.default.hex_stripped}}ee)
          $inactive_border = rgba({{colors.on_primary_fixed_variant.default.hex_stripped}}aa)

          general {
              col.active_border = $active_border
              col.inactive_border = $inactive_border
          }
        '';

      # WallpaperPicker imports QtMultimedia; the stock quickshell binary has no QML_IMPORT_PATH for it,
      # so StackView replace fails ("module QtMultimedia is not installed") and only the dim/blur shows.
      quickshellWrapped = pkgs.runCommand "quickshell-with-qt6-multimedia"
        {
          nativeBuildInputs = [ pkgs.makeWrapper ];
          passthru.unwrapped = pkgs.quickshell;
        }
        ''
          mkdir -p $out/bin
          makeWrapper ${pkgs.quickshell}/bin/quickshell $out/bin/quickshell \
            --prefix QML_IMPORT_PATH : "${pkgs.qt6.qtmultimedia}/lib/qt-6/qml" \
            --prefix QT_PLUGIN_PATH : "${lib.makeSearchPath "lib/qt-6/plugins" [
              pkgs.qt6.qtmultimedia
              pkgs.qt6.qtbase
            ]}"
        '';

      ilya = inputs.ilyamiro-config;
      scriptsSrc = "${ilya}/config/sessions/hyprland/scripts";
      matugenProgramsSrc = "${ilya}/config/programs/matugen";

      # Patches upstream Main.qml after copy; argv[1] = $out (store path of hypr scripts).
      patchMainQmlPy =
        pkgs.writeText "patch-main-qml.py" ''
          import pathlib
          import sys
          import re

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/Main.qml"
          t = p.read_text()

          # 1. Patch topBarHole
          top_hole_rx = re.compile(r'(?P<indent>[ \t]*)Item\s*\{\s*id:\s*topBarHole.*?height:\s*\d+.*?\n(?P=indent)\}', re.DOTALL)
          if not top_hole_rx.search(t):
              sys.exit("Main.qml: topBarHole block not recognized (regex failed).")

          new_top_hole = (
              "    Item {\n"
              "        id: topBarHole\n"
              "        anchors.top: parent.top\n"
              "        anchors.left: parent.left\n"
              "        anchors.right: parent.right\n"
              "        height: Math.max(1, Math.round(54 * masterWindow.globalUiScale))\n"
              "    }\n\n"
              "    Rectangle {\n"
              "        anchors {\n"
              "            left: parent.left\n"
              "            right: parent.right\n"
              "            top: topBarHole.bottom\n"
              "            bottom: parent.bottom\n"
              "        }\n"
              "        color: Qt.rgba(0, 0, 0, 0.45)\n"
              "        z: -1\n"
              "    }"
          )
          t = top_hole_rx.sub(new_top_hole, t, count=1)

          # 2. Inject overlayDismissReady property
          prop_rx = re.compile(r'(property\s+bool\s+isVisible:\s*false\s*\n)')
          if not prop_rx.search(t):
              sys.exit("Main.qml: isVisible property not found")
          t = prop_rx.sub(r'\g<1>    property bool overlayDismissReady: false\n', t, count=1)

          # 3. Inject overlayDismissCooldown Timer
          scale_rx = re.compile(r'(property\s+real\s+globalUiScale:\s*[\d.]+\s*\n)')
          if not scale_rx.search(t):
              sys.exit("Main.qml: globalUiScale property not found")
          timer_block = (
              "    Timer {\n"
              "        id: overlayDismissCooldown\n"
              "        interval: 380\n"
              "        repeat: false\n"
              "        onTriggered: masterWindow.overlayDismissReady = true\n"
              "    }\n"
          )
          t = scale_rx.sub(r'\g<1>\n' + timer_block + '\n', t, count=1)

          # 4. Patch onIsVisibleChanged
          vis_rx = re.compile(r'(onIsVisibleChanged:\s*\{)(.*?)(^\s*\})', re.DOTALL | re.MULTILINE)
          def replace_vis(match):
              inner = match.group(2)
              focus = "            widgetStack.forceActiveFocus();\n" if "forceActiveFocus" in inner else ""
              new_inner = (
                  "\n        overlayDismissCooldown.stop()\n"
                  "        if (isVisible) {\n"
                  "            masterWindow.overlayDismissReady = false\n"
                  "            overlayDismissCooldown.start()\n"
                  "            masterWindow.requestActivate()\n"
                  f"{focus}"
                  "        } else {\n"
                  "            masterWindow.overlayDismissReady = false\n"
                  "        }\n"
              )
              return match.group(1) + new_inner + match.group(3)

          if not vis_rx.search(t):
              sys.exit("Main.qml: onIsVisibleChanged not found")
          t = vis_rx.sub(replace_vis, t, count=1)

          # 5. Patch dismiss MouseArea
          mouse_rx = re.compile(r'(MouseArea\s*\{.*?enabled:\s*masterWindow\.isVisible)(.*?onClicked:\s*switchWidget\("hidden",\s*""\).*?\})', re.DOTALL)
          if not mouse_rx.search(t):
              sys.exit("Main.qml: dismiss MouseArea not found")
          t = mouse_rx.sub(r'\g<1> && masterWindow.overlayDismissReady\g<2>', t, count=1)

          # 6. Patch PanelWindow sizing
          size_rx = re.compile(r'width:\s*(Screen\.width|masterWindow\.screen\.width)\s*\n\s*height:\s*(Screen\.height|masterWindow\.screen\.height)')
          new_size = (
              r"implicitWidth: Math.max(1, \g<1>)\n"
              r"    implicitHeight: Math.max(1, \g<2>)\n"
              r"    width: implicitWidth\n"
              r"    height: implicitHeight"
          )
          t = size_rx.sub(new_size, t, count=1)

          p.write_text(t)
        '';

      # GuidePopup.qml lists upstream SUPER hotkeys; Hyprland binds use CTRL+ALT — fix displayed keys.
      patchGuidePopupPy =
        pkgs.writeText "patch-guide-popup.py" ''
          import pathlib
          import sys
          import re

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/guide/GuidePopup.qml"
          if not p.is_file():
              sys.exit("GuidePopup.qml not found")
          t = p.read_text()

          updates = [
              ("D", r"SUPER", "CTRL+ALT", "App Launcher (Drun)", "bash ~/.config/hypr/scripts/rofi_show.sh drun"),
              ("TAB", r"ALT", "CTRL+ALT", "Window Switcher (Rofi)", "bash ~/.config/hypr/scripts/rofi_show.sh window"),
              ("C", r"SUPER", "CTRL+ALT", "Clipboard History", "bash ~/.config/hypr/scripts/rofi_clipboard.sh"),
              ("W", r"SUPER", "CTRL+ALT", "Toggle Wallpaper", "bash ~/.config/hypr/scripts/qs_manager.sh toggle wallpaper"),
              ("Q", r"SUPER", "CTRL+ALT", "Toggle Music", "bash ~/.config/hypr/scripts/qs_manager.sh toggle music"),
              ("B", r"SUPER", "CTRL+ALT", "Toggle Battery", "bash ~/.config/hypr/scripts/qs_manager.sh toggle battery"),
              ("S", r"SUPER", "CTRL+ALT", "Toggle Calendar", "bash ~/.config/hypr/scripts/qs_manager.sh toggle calendar"),
              ("N", r"SUPER", "CTRL+ALT", "Toggle Network", "bash ~/.config/hypr/scripts/qs_manager.sh toggle network"),
              ("V", r"SUPER", "CTRL+ALT", "Toggle Volume", "bash ~/.config/hypr/scripts/qs_manager.sh toggle volume"),
              ("M", r"SUPER", "CTRL+ALT", "Toggle Monitors", "bash ~/.config/hypr/scripts/qs_manager.sh toggle monitors"),
              ("H", r"SUPER", "CTRL+ALT", "Toggle Guide", "bash ~/.config/hypr/scripts/qs_manager.sh toggle guide"),
              ("S", r"SUPER\+SHIFT", "CTRL+ALT+SHIFT", "Toggle Settings", "bash ~/.config/hypr/scripts/qs_manager.sh toggle settings"),
              ("R", r"SUPER", "SUPER", "App Launcher (Rofi)", "bash ~/.config/hypr/scripts/rofi_show.sh drun"),
              ("T", r"SUPER\+SHIFT", "CTRL+ALT+SHIFT", "Toggle FocusTime", "bash ~/.config/hypr/scripts/qs_manager.sh toggle focustime"),
              ("A", r"SUPER", "CTRL+ALT", "Toggle SwayNC Panel", "swaync-client -t -sw"),
          ]

          for k2, old_k1_rx, new_k1, new_act, new_cmd in updates:
              pattern = re.compile(
                  r'\{\s*k1:\s*"' + old_k1_rx + r'"\s*,\s*k2:\s*"' + re.escape(k2) + r'".*?\}',
                  re.DOTALL | re.IGNORECASE
              )
              replacement = f'{{ k1: "{new_k1}", k2: "{k2}", action: "{new_act}", cmd: "{new_cmd}" }}'
              t = pattern.sub(replacement, t, count=1)

          p.write_text(t)
        '';

      patchWallpaperPickerPy =
        pkgs.writeText "patch-wallpaper-picker.py" ''
          import os
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/wallpaper/WallpaperPicker.qml"
          if not p.is_file():
              sys.exit("WallpaperPicker.qml not found")
          t = p.read_text()
          candidates = [
              "    property bool isReady: visible && localFolderModel.status === FolderListModel.Ready\n",
              "    property bool isReady: visible && (localFolderModel.status === FolderListModel.Ready || srcModel.status === FolderListModel.Ready)\n",
          ]
          new = "    property bool isReady: true\n"
          replaced = False
          for old in candidates:
              if old in t:
                  t = t.replace(old, new, 1)
                  replaced = True
                  break
          if not replaced:
              sys.exit("WallpaperPicker.qml: no known isReady line to patch")

          root_block_old = (
              "Item {\n"
              "    id: window\n"
              "    width: Screen.width\n"
              "\n"
              "    Caching { id: paths }\n"
              "\n"
              "    Scaler {\n"
              "        id: scaler\n"
              "        currentWidth: Screen.width\n"
              "    }\n"
          )
          root_block_new = (
              "Item {\n"
              "    id: window\n"
              "    anchors.fill: parent\n"
              "\n"
              "    Caching { id: paths }\n"
              "\n"
              "    // --- Responsive Scaling Logic ---\n"
              "    Scaler {\n"
              "        id: scaler\n"
              "        currentWidth: Math.max(window.width, Screen.width) || 1920\n"
              "    }\n"
          )
          if root_block_old not in t:
              sys.exit("WallpaperPicker.qml: root Item / Scaler block not found")
          t = t.replace(root_block_old, root_block_new, 1)

          home_needle = '    readonly property string homeDir: "file://" + Quickshell.env("HOME")\n'
          home_insert = (
              "    property string wallpaperDirFromJson: \"\"\n"
              "\n"
              "    Process {\n"
              "        id: wallpaperSettingsReader\n"
              "        command: [\"bash\", \"-c\", \"cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'\"]\n"
              "        running: true\n"
              "        stdout: StdioCollector {\n"
              "            onStreamFinished: {\n"
              "                try {\n"
              "                    let txt = this.text.trim();\n"
              "                    if (!txt || txt === \"{}\") return;\n"
              "                    let parsed = JSON.parse(txt);\n"
              "                    if (parsed.wallpaperDir !== undefined && parsed.wallpaperDir !== \"\")\n"
              "                        window.wallpaperDirFromJson = String(parsed.wallpaperDir);\n"
              "                } catch (e) {}\n"
              "            }\n"
              "        }\n"
              "    }\n"
              "\n"
              "    Process {\n"
              "        id: wallpaperSettingsWatcher\n"
              "        command: [\"bash\", \"-c\", \"while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; @INOTIFYWAIT@ -qq -e modify,close_write ~/.config/hypr/settings.json\"]\n"
              "        running: true\n"
              "        stdout: StdioCollector {\n"
              "            onStreamFinished: {\n"
              "                wallpaperSettingsReader.running = false;\n"
              "                wallpaperSettingsReader.running = true;\n"
              "                wallpaperSettingsWatcher.running = false;\n"
              "                wallpaperSettingsWatcher.running = true;\n"
              "            }\n"
              "        }\n"
              "    }\n"
              "\n"
              "    readonly property string homeDir: \"file://\" + Quickshell.env(\"HOME\")\n"
          )
          if home_needle not in t:
              sys.exit("WallpaperPicker.qml: homeDir line not found")
          src_old = '    readonly property string srcDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"\n'
          src_new = (
              "    readonly property string srcDir: {\n"
              "        let d = String(window.wallpaperDirFromJson || \"\")\n"
              "        if (!d || d === \"\") d = String(Quickshell.env(\"WALLPAPER_DIR\") || \"\")\n"
              '        if (d.indexOf("file://") === 0)\n'
              '            d = decodeURIComponent(d.substring(7))\n'
              '        if (!d || d === "")\n'
              '            d = Quickshell.env("HOME") + "/Pictures/Wallpapers"\n'
              "        return d\n"
              "    }\n"
          )
          src_old_2 = (
              "    readonly property string srcDir: {\n"
              "        const dir = Quickshell.env(\"WALLPAPER_DIR\")\n"
              "        return (dir && dir !== \"\") \n"
              "        ? dir \n"
              "        : Quickshell.env(\"HOME\") + \"/Pictures/Wallpapers\"\n"
              "    }\n"
          )

          if src_old in t:
              t = t.replace(src_old, src_new, 1)
          elif src_old_2 in t:
              t = t.replace(src_old_2, src_new, 1)
          else:
              sys.exit("WallpaperPicker.qml: srcDir block not found")

          lv_old = (
              "        highlightRangeMode: ListView.StrictlyEnforceRange\n"
              "        preferredHighlightBegin: (width / 2) - ((window.itemWidth * 1.5 + window.spacing) / 2)\n"
              "        preferredHighlightEnd: (width / 2) + ((window.itemWidth * 1.5 + window.spacing) / 2)\n"
          )
          lv_new = (
              "        highlightRangeMode: width > (window.itemWidth * 3)\n"
              "            ? ListView.StrictlyEnforceRange\n"
              "            : ListView.ApplyRange\n"
              "        preferredHighlightBegin: Math.max(0, (width / 2) - ((window.itemWidth * 1.5 + window.spacing) / 2))\n"
              "        preferredHighlightEnd: Math.min(width, (width / 2) + ((window.itemWidth * 1.5 + window.spacing) / 2))\n"
          )
          if lv_old not in t:
              sys.exit("WallpaperPicker.qml: ListView highlight block not found")
          t = t.replace(lv_old, lv_new, 1)

          completed_needle = (
              "        Quickshell.execDetached([\"bash\", \"-c\", \"mkdir -p '\" + decodeURIComponent(window.searchDir.replace(\"file://\", \"\")) + \"'\"]);\n"
              "        \n"
              "        window.loadMonitors();\n"
              "\n"
              "        if (searchState.searched) {\n"
          )
          completed_insert = (
              "        Quickshell.execDetached([\"bash\", \"-c\", \"mkdir -p '\" + decodeURIComponent(window.searchDir.replace(\"file://\", \"\")) + \"'\"]);\n"
              "        Qt.callLater(function () {\n"
              "            window.syncLocalModel();\n"
              "            window.tryFocus();\n"
              "        });\n"
              "        \n"
              "        window.loadMonitors();\n"
              "\n"
              "        if (searchState.searched) {\n"
          )
          if completed_needle not in t:
              sys.exit("WallpaperPicker.qml: Component.onCompleted mkdir block not found")
          t = t.replace(completed_needle, completed_insert, 1)

          mg = os.environ.get("MATUGEN_EXE", "").strip()
          if mg:
              old = "matugen image "
              new = (
                  mg
                  + " image --source-color-index 0 -q -c \"$HOME/.config/matugen/config.toml\" "
              )
              if old not in t:
                  sys.exit("WallpaperPicker.qml: matugen image invocation not found")
              t = t.replace(old, new)

          p.write_text(t)
        '';

      patchGuideWeatherPy =
        pkgs.writeText "patch-guide-weather.py" ''
          import json
          import os
          import pathlib
          import sys
          import re

          out = pathlib.Path(sys.argv[1])
          qs = os.environ.get("QUICKSHELL_EXE", "quickshell")
          p = out / "quickshell/guide/GuidePopup.qml"
          if not p.is_file():
              print("Warning: GuidePopup.qml not found. Skipping weather patch.", file=sys.stderr)
              sys.exit(0)
              
          t = p.read_text()

          new_func = (
              "                function saveWeatherConfig() {\n"
              "                    var home = Quickshell.env(\"HOME\");\n"
              "                    var envPath = home + \"/.config/hypr/weather.env\";\n"
              "                    var cacheWeather = home + \"/.cache/quickshell/weather\";\n"
              "                    var wscript = home + \"/.config/hypr/scripts/quickshell/calendar/weather.sh\";\n"
              "                    var marker = \"QS_WEATHER_ENV_\" + Math.random().toString(36).slice(2) + \"_\" + Date.now();\n"
              "                    var body = \"# OpenWeather API Configuration\\n\" +\n"
              "                        \"OPENWEATHER_KEY=\" + apiKeyInput.text + \"\\n\" +\n"
              "                        \"OPENWEATHER_CITY_ID=\" + cityIdInput.text + \"\\n\" +\n"
              "                        \"OPENWEATHER_UNIT=\" + weatherTab.selectedUnit + \"\\n\";\n"
              "                    var cmd =\n"
              "                        \"( mkdir -p '\" + home + \"/.config/hypr' && cat > '\" + envPath + \"' <<'\" + marker + \"'\\n\" +\n"
              "                        body +\n"
              "                        marker + \"\\n\" +\n"
              "                        \") && rm -rf '\" + cacheWeather + \"' 2>/dev/null || true\" +\n"
              "                        \" && notify-send 'Weather' 'API configuration saved successfully!'\" +\n"
              "                        \" && bash '\" + wscript + \"' --json >/dev/null 2>&1 || true\";\n"
              "                    Quickshell.execDetached([\"bash\", \"-c\", cmd]);\n"
              "                    Quickshell.execDetached(["
              + json.dumps(qs)
              + ', "-p", home + "/.config/hypr/scripts/quickshell/TopBar.qml", "ipc", "call", "topbar", "refreshWeather"]);\n'
              "                }"
          )

          match = re.search(r'function\s+saveWeatherConfig\s*\(\)\s*\{', t)
          if match:
              start_idx = match.start()
              brace_idx = t.find('{', start_idx)
              depth = 0
              end_idx = -1
              
              for i in range(brace_idx, len(t)):
                  if t[i] == '{':
                      depth += 1
                  elif t[i] == '}':
                      depth -= 1
                      if depth == 0:
                          end_idx = i + 1
                          break
              
              if end_idx != -1:
                  t = t[:start_idx] + new_func + t[end_idx:]
              else:
                  print("Warning: GuidePopup.qml: saveWeatherConfig brace parse failed. Skipping patch.", file=sys.stderr)
          else:
              print("Warning: GuidePopup.qml: saveWeatherConfig function not found. Upstream likely changed. Skipping patch.", file=sys.stderr)

          p.write_text(t)
        '';

      patchWeatherShPy =
        pkgs.writeText "patch-weather-sh.py" ''
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/calendar/weather.sh"
          if not p.is_file():
              sys.exit("weather.sh not found")
          t = p.read_text()
          old = 'ENV_FILE="$(dirname "$0")/.env"\n'
          new = (
              'ENV_FILE="$HOME/.config/hypr/weather.env"\n'
              'if [ ! -f "$ENV_FILE" ]; then\n'
              '    ENV_FILE="$(dirname "$0")/.env"\n'
              "fi\n"
          )
          if old not in t:
              sys.exit("weather.sh: ENV_FILE line not found")
          t = t.replace(old, new, 1)

          oldEnv = (
              "if [ -f \"$ENV_FILE\" ]; then\n"
              "    export $(grep -v '^#' \"$ENV_FILE\" | xargs)\n"
              "fi\n"
          )
          newEnv = (
              "if [ -f \"$ENV_FILE\" ]; then\n"
              "    set -a\n"
              "    . \"$ENV_FILE\"\n"
              "    set +a\n"
              "fi\n"
          )
          if oldEnv in t:
              t = t.replace(oldEnv, newEnv, 1)

          oldJson = (
              "        if [ \"$env_changed\" -eq 1 ]; then\n"
              "            # The user just modified the .env file. Bypass cache entirely.\n"
              "            touch \"$json_file\" \n"
              "            get_data &\n"
          )
          newJson = (
              "        if [ \"$env_changed\" -eq 1 ]; then\n"
              "            # The user just modified the .env file. Bypass cache entirely.\n"
              "            get_data\n"
          )
          if oldJson in t:
              t = t.replace(oldJson, newJson, 1)
          p.write_text(t)
        '';

      patchWorkspacesShPy =
        pkgs.writeText "patch-workspaces-sh.py" ''
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/workspaces.sh"
          if not p.is_file():
              sys.exit("workspaces.sh not found")
          t = p.read_text()
          top = (
              "# Configuration: Parse from settings.json dynamically, fallback to 8\n"
              "SETTINGS_FILE=\"$HOME/.config/hypr/settings.json\"\n"
              "SEQ_END=$(jq -r '.workspaceCount // 8' \"$SETTINGS_FILE\" 2>/dev/null)\n"
              "# Double check it is a valid integer to prevent jq errors later\n"
              "if ! [[ \"$SEQ_END\" =~ ^[0-9]+$ ]]; then\n"
              "    SEQ_END=8\n"
              "fi\n"
              "\n"
          )
          t = t.replace(top, 'SETTINGS_FILE="$HOME/.config/hypr/settings.json"\n\n', 1)
          t = t.replace(
              "print_workspaces() {\n    # Get raw data with a timeout fallback\n",
              (
                  "print_workspaces() {\n"
                  "    SEQ_END=$(jq -r '.workspaceCount // 8' \"$SETTINGS_FILE\" 2>/dev/null)\n"
                  "    if ! [[ \"$SEQ_END\" =~ ^[0-9]+$ ]]; then\n"
                  "        SEQ_END=8\n"
                  "    fi\n"
                  "    if [ \"$SEQ_END\" -lt 1 ] 2>/dev/null; then\n"
                  "        SEQ_END=1\n"
                  "    fi\n"
                  "    # Get raw data with a timeout fallback\n"
              ),
              1,
          )
          before = (
              "# Print initial state\n"
              "print_workspaces\n"
              "\n"
              "# ============================================================================\n"
              "# 2. THE EVENT DEBOUNCER\n"
          )
          after = (
              "# If only workspace count changed, Hyprland may emit no event — still refresh the bar list.\n"
              "(\n"
              "    while inotifywait -q -e close_write \"$SETTINGS_FILE\" 2>/dev/null; do\n"
              "        print_workspaces\n"
              "    done\n"
              ") &\n"
              "\n"
              "# Print initial state\n"
              "print_workspaces\n"
              "\n"
              "# ============================================================================\n"
              "# 2. THE EVENT DEBOUNCER\n"
          )
          if before not in t:
              sys.exit("workspaces.sh: expected print initial / debouncer block not found")
          t = t.replace(before, after, 1)
          old_inner = (
              "    # Get raw data with a timeout fallback\n"
              "    spaces=$(timeout 2 hyprctl workspaces -j 2>/dev/null)\n"
              "    active=$(timeout 2 hyprctl activeworkspace -j 2>/dev/null | jq '.id')\n"
              "\n"
              "    # Failsafe if hyprctl crashes to prevent jq from outputting errors\n"
              "    if [ -z \"$spaces\" ] || [ -z \"$active\" ]; then return; fi\n"
          )
          new_inner = (
              "    # Get raw data with a timeout fallback\n"
              "    spaces=$(timeout 2 hyprctl workspaces -j 2>/dev/null) || true\n"
              "    aw=$(timeout 2 hyprctl activeworkspace -j 2>/dev/null) || true\n"
              "    active=$(printf '%s' \"$aw\" | jq -r 'try (.id|tonumber) catch 0' 2>/dev/null) || true\n"
              "    if ! [[ \"$active\" =~ ^[0-9]+$ ]]; then active=0; fi\n"
              "\n"
              "    if [ -z \"$spaces\" ]; then return; fi\n"
          )
          if old_inner not in t:
              sys.exit("workspaces.sh: print_workspaces hypr fetch block not found")
          t = t.replace(old_inner, new_inner, 1)
          p.write_text(t)
        '';

      patchTopBarWeatherIpcPy =
        pkgs.writeText "patch-topbar-weather-ipc.py" ''
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/TopBar.qml"
          if not p.is_file():
              sys.exit("TopBar.qml not found")
          t = p.read_text()
          if "function refreshWeather" in t:
              p.write_text(t)
          else:
              key = "function queueReload()"
              i = t.find(key)
              if i < 0:
                  sys.exit("TopBar.qml: function queueReload not found")
              brace = t.find("{", i)
              depth = 0
              k = brace
              while k < len(t):
                  if t[k] == "{":
                      depth += 1
                  elif t[k] == "}":
                      depth -= 1
                      if depth == 0:
                          k += 1
                          break
                  k += 1
              if depth != 0:
                  sys.exit("TopBar.qml: queueReload brace parse failed")
              add = "\n                function refreshWeather() {\n                    weatherPoller.running = false\n                    weatherPoller.running = true\n                }\n"
              p.write_text(t[:k] + add + t[k:])
        '';

      defaultHyprSettingsJson =
        pkgs.writeText "hypr-quickshell-settings-default.json" (
          builtins.toJSON {
            uiScale = 1.0;
            workspaceCount = 10;
            topbarHelpIcon = true;
            wallpaperDir = qs.wallpaperDirectory;
          }
        );

      patchSettingsPopupPy =
        pkgs.writeText "patch-settings-popup.py" ''
          import json
          import os
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/settings/SettingsPopup.qml"
          if not p.is_file():
              sys.exit("SettingsPopup.qml not found")
          t = p.read_text()
          qs = os.environ["QUICKSHELL_EXE"]

          old_save = (
              "    function saveAppSettings() {\n"
              "        let config = {\n"
              '            "uiScale": root.setUiScale,\n'
              '            "openGuideAtStartup": root.setOpenGuideAtStartup,\n'
              '            "topbarHelpIcon": root.setTopbarHelpIcon,\n'
              '            "wallpaperDir": root.setWallpaperDir,\n'
              '            "language": root.setLanguage,\n'
              '            "kbOptions": root.setKbOptions,\n'
              '            "workspaceCount": root.setWorkspaceCount\n'
              "        };\n"
              "        let jsonString = JSON.stringify(config, null, 2);\n"
              "        \n"
              "        let cmd = \"mkdir -p ~/.config/hypr/ && echo '\" + jsonString + \"' > ~/.config/hypr/settings.json && notify-send 'Quickshell' 'Settings Applied Successfully!'\";\n"
              "                  \n"
              '        Quickshell.execDetached(["bash", "-c", cmd]);\n'
              "        \n"
              "        // ONLY queue a TopBar reload if the workspace count actually changed\n"
              "        if (root.setWorkspaceCount !== root.initialWorkspaceCount) {\n"
              '            Quickshell.execDetached(["qs", "-p", Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/TopBar.qml", "ipc", "call", "topbar", "queueReload"]);\n'
              "            \n"
              "            // Update the baseline so subsequent saves don't trigger unnecessary reloads\n"
              "            root.initialWorkspaceCount = root.setWorkspaceCount; \n"
              "        }\n"
              "    }"
          )
          new_save = (
              "    function saveAppSettings() {\n"
              "        let config = {\n"
              '            "uiScale": root.setUiScale,\n'
              '            "openGuideAtStartup": root.setOpenGuideAtStartup,\n'
              '            "topbarHelpIcon": root.setTopbarHelpIcon,\n'
              '            "wallpaperDir": root.setWallpaperDir,\n'
              '            "language": root.setLanguage,\n'
              '            "kbOptions": root.setKbOptions,\n'
              '            "workspaceCount": Math.min(99, Math.max(1, root.setWorkspaceCount)),\n'
              "        };\n"
              "        let jsonString = JSON.stringify(config, null, 2);\n"
              "        let home = Quickshell.env('HOME');\n"
              "        let qsb = " + json.dumps(qs) + ";\n"
              "        let eofMarker = \"QS_HYPR_SETTINGS_JSON_\" + Math.random().toString(36).slice(2) + \"_\" + Date.now();\n"
              "        let cmd =\n"
              '            "( mkdir -p ~/.config/hypr/ && cat > ~/.config/hypr/settings.json <<\'" + eofMarker + "\'\\n" +\n'
              "            jsonString +\n"
              '            "\\n" + eofMarker +\n'
              '            "\\n) && notify-send \'Quickshell\' \'Settings Applied Successfully!\'" +\n'
              '            " && bash " + home + "/.config/hypr/scripts/quickshell/sync_qs_workspaces.sh" +\n'
              '            " && " + qsb + " -p " + home + "/.config/hypr/scripts/quickshell/TopBar.qml ipc call topbar queueReload";\n'
              "\n"
              '        Quickshell.execDetached(["bash", "-c", cmd]);\n'
              "\n"
              "        if (root.setWorkspaceCount !== root.initialWorkspaceCount) {\n"
              "            root.initialWorkspaceCount = root.setWorkspaceCount;\n"
              "        }\n"
              "    }"
          )
          if old_save not in t:
              print("Warning: SettingsPopup.qml: saveAppSettings block not found. Skipping patch.", file=sys.stderr)
          else:
              t = t.replace(old_save, new_save, 1)
              p.write_text(t)
        '';

      patchWindowRegistryJs =
        pkgs.writeText "patch-window-registry.py" ''
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/WindowRegistry.js"
          if not p.is_file():
              sys.exit("WindowRegistry.js not found")
          t = p.read_text()
          needle = (
              "function getLayout(name, mx, my, mw, mh, userScale) {\n"
              "    let scale = getScale(mw, userScale);"
          )
          insert = (
              "function getLayout(name, mx, my, mw, mh, userScale) {\n"
              "    mw = mw > 0 ? mw : 1920;\n"
              "    mh = mh > 0 ? mh : 1080;\n"
              "    let scale = getScale(mw, userScale);"
          )
          if needle not in t:
              sys.exit("WindowRegistry.js: getLayout header not found")
          p.write_text(t.replace(needle, insert, 1))
        '';

      patchQsManagerPy =
        pkgs.writeText "patch-qs-manager.py" ''
          import os
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "qs_manager.sh"
          if not p.is_file():
              sys.exit("qs_manager.sh not found")
          t = p.read_text()

          jq = pathlib.Path(os.environ["JQ_EXE"])
          qs = os.environ["QUICKSHELL_EXE"]

          header_needle = (
              'BT_PID_FILE="$QS_RUN_DIR/bt_scan_pid"\n'
              'BT_SCAN_LOG="$QS_LOG_DIR/bt_scan.log"\n'
              'SRC_DIR="''${WALLPAPER_DIR:-''${srcdir:-$HOME/Pictures/Wallpapers}}"\n'
          )
          header_insert = (
              'BT_PID_FILE="$QS_RUN_DIR/bt_scan_pid"\n'
              'BT_SCAN_LOG="$QS_LOG_DIR/bt_scan.log"\n'
              '\n'
              '# NixOS: Hyprland keybind env often lacks magick/ffmpeg (wallpaper thumbnails).\n'
              'export PATH="$PATH:'
              + os.environ["MAGICK_BINDIR"]
              + ":"
              + os.environ["FFMPEG_BINDIR"]
              + ":"
              + str(jq.parent)
              + "\"\n"
              + "_wpd=$( "
              + str(jq)
              + ' -r \'.wallpaperDir // empty\' "$HOME/.config/hypr/settings.json" 2>/dev/null || true )\n'
              + '[ -n "$_wpd" ] && export WALLPAPER_DIR="$_wpd"\n'
              + '\n'
              'SRC_DIR="''${WALLPAPER_DIR:-''${srcdir:-$HOME/Pictures/Wallpapers}}"\n'
          )
          if header_needle not in t:
              sys.exit("qs_manager.sh: header block before SRC_DIR not found")
          if "Hyprland keybind env often lacks magick" not in t:
              t = t.replace(header_needle, header_insert, 1)

          old_shell = (
              'if ! pgrep -f "quickshell.*Shell.qml" >/dev/null; then\n'
              '    quickshell -p "$SHELL_QML_PATH" >/dev/null 2>&1 &\n'
              "    disown\n"
              "fi\n"
          )
          new_shell = (
              'if ! pgrep -f "quickshell.*Shell.qml" >/dev/null; then\n'
              + '    env NIXOS_OZONE_WL=1 WALLPAPER_DIR="$WALLPAPER_DIR" '
              + qs
              + ' -p "$SHELL_QML_PATH" >/dev/null 2>&1 &\n'
              + "    disown\n"
              + "fi\n"
          )
          if old_shell not in t:
              sys.exit("qs_manager.sh: quickshell Shell.qml restart block not found")
          t = t.replace(old_shell, new_shell, 1)

          t = t.replace("command -v swww", "command -v awww")
          t = t.replace("swww query", "awww query")
          p.write_text(t)
        '';

      patchSettingsWatcherShPy =
        pkgs.writeText "patch-settings-watcher-sh.py" ''
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "settings_watcher.sh"
          if not p.is_file():
              sys.exit("settings_watcher.sh not found")
          t = p.read_text()
          if "sync_qs_workspaces.sh" in t:
              p.write_text(t)
          elif "hyprctl reload" in t:
              old = "    hyprctl reload 2>/dev/null || true\n"
              new = (
                  "    hyprctl reload 2>/dev/null || true\n"
                  "    bash \"$(dirname \"$0\")/quickshell/sync_qs_workspaces.sh\" 2>/dev/null || true\n"
              )
              if old not in t:
                  sys.exit("settings_watcher.sh: hyprctl reload line not found")
              t = t.replace(old, new, 1)
              p.write_text(t)
          else:
              needle = (
                  "        if [ -f \"$ZSH_RC\" ]; then\n"
                  "            sed -i \"s|^export WALLPAPER_DIR=.*|export WALLPAPER_DIR=\\\"$WP_DIR\\\"|\" \"$ZSH_RC\"\n"
                  "        fi\n"
                  "    fi\n"
                  "done\n"
              )
              insert = (
                  "        if [ -f \"$ZSH_RC\" ]; then\n"
                  "            sed -i \"s|^export WALLPAPER_DIR=.*|export WALLPAPER_DIR=\\\"$WP_DIR\\\"|\" \"$ZSH_RC\"\n"
                  "        fi\n"
                  "    fi\n"
                  "\n"
                  "    hyprctl reload 2>/dev/null || true\n"
                  "    bash \"$(dirname \"$0\")/quickshell/sync_qs_workspaces.sh\" 2>/dev/null || true\n"
                  "done\n"
              )
              if needle not in t:
                  sys.exit("settings_watcher.sh: wallpaper tail block not found")
              t = t.replace(needle, insert, 1)
              p.write_text(t)
        '';

      hyprScripts =
        pkgs.runCommand "hoachnt-hypr-scripts-from-ilyamiro"
          {
            inherit scriptsSrc;
            meta.description = "Upstream Hyprland helper scripts + Quickshell QML (read-only)";
          }
          ''
            mkdir -p "$out"
            cp -r "$scriptsSrc"/. "$out/"
            find "$out" -type f -name '*.sh' -exec chmod +x {} +
            echo 'pkill hyprpaper && hyprpaper &' > "$out/reload-hyprpaper.sh"
            chmod +x "$out/reload-hyprpaper.sh"
            
            if [ -f "$out/quickshell/Main.qml" ]; then
              chmod -R u+w "$out"
              ${pkgs.python3}/bin/python3 ${patchMainQmlPy} "$out" || echo "Warning: patchMainQmlPy failed, skipping."
            fi
            if [ -f "$out/quickshell/guide/GuidePopup.qml" ]; then
              chmod -R u+w "$out"
              ${pkgs.python3}/bin/python3 ${patchGuidePopupPy} "$out" || echo "Warning: patchGuidePopupPy failed, skipping."
              QUICKSHELL_EXE="${quickshellWrapped}/bin/quickshell" \
                ${pkgs.python3}/bin/python3 ${patchGuideWeatherPy} "$out" || echo "Warning: patchGuideWeatherPy failed, skipping."
            fi
            if [ -f "$out/quickshell/calendar/weather.sh" ]; then
              chmod u+w "$out/quickshell/calendar/weather.sh"
              ${pkgs.python3}/bin/python3 ${patchWeatherShPy} "$out" || echo "Warning: patchWeatherShPy failed, skipping."
            fi
            if [ -f "$out/quickshell/calendar/schedule/get_schedule.py" ]; then
              chmod -R u+w "$out/quickshell/calendar/schedule"
              ${pkgs.python3}/bin/python3 ${./patches/patch-schedule.py} "$out" || echo "Warning: patch-schedule.py failed, skipping."
            fi
            if [ -f "$out/quickshell/workspaces.sh" ]; then
              chmod u+w "$out/quickshell/workspaces.sh"
              ${pkgs.python3}/bin/python3 ${patchWorkspacesShPy} "$out" || echo "Warning: patchWorkspacesShPy failed, skipping."
              ${pkgs.python3}/bin/python3 ${./patches/patch-workspaces-jq.py} "$out" || echo "Warning: patch-workspaces-jq.py failed, skipping."
            fi
            
            cp ${./scripts/quickshell-sync-workspaces.sh} "$out/quickshell/sync_qs_workspaces.sh"
            ${pkgs.gnused}/bin/sed -i \
              -e 's#@HYPRCTL@#${pkgs.hyprland}/bin/hyprctl#' \
              -e 's#@JQ@#${pkgs.jq}/bin/jq#' \
              -e 's#@TIMEOUT@#${pkgs.coreutils}/bin/timeout#' \
              "$out/quickshell/sync_qs_workspaces.sh"
            chmod +x "$out/quickshell/sync_qs_workspaces.sh"
            
            cp ${./scripts/quickshell-workspace-next.sh} "$out/quickshell/workspace_next.sh"
            ${pkgs.gnused}/bin/sed -i \
              -e 's#@HYPRCTL@#${pkgs.hyprland}/bin/hyprctl#' \
              -e 's#@JQ@#${pkgs.jq}/bin/jq#' \
              "$out/quickshell/workspace_next.sh"
            chmod +x "$out/quickshell/workspace_next.sh"
            
            cp ${./scripts/quickshell-workspace-prev.sh} "$out/quickshell/workspace_prev.sh"
            ${pkgs.gnused}/bin/sed -i \
              -e 's#@HYPRCTL@#${pkgs.hyprland}/bin/hyprctl#' \
              -e 's#@JQ@#${pkgs.jq}/bin/jq#' \
              "$out/quickshell/workspace_prev.sh"
            chmod +x "$out/quickshell/workspace_prev.sh"
            
            if [ -f "$out/quickshell/TopBar.qml" ]; then
              chmod u+w "$out/quickshell/TopBar.qml"
              ${pkgs.python3}/bin/python3 ${patchTopBarWeatherIpcPy} "$out" || echo "Warning: patchTopBarWeatherIpcPy failed, skipping."
              ${pkgs.python3}/bin/python3 ${./patches/patch-topbar-bar-margins.py} "$out" || echo "Warning: patch-topbar-bar-margins.py failed, skipping."
              ${pkgs.python3}/bin/python3 ${./patches/patch-topbar-workspaces.py} "$out" || echo "Warning: patch-topbar-workspaces.py failed, skipping."
            fi
            
            if [ -f "$out/quickshell/battery/BatteryPopup.qml" ]; then
              chmod u+w "$out/quickshell/battery/BatteryPopup.qml"
              ${pkgs.gnused}/bin/sed -i \
                's#powerprofilesctl#${pkgs.power-profiles-daemon}/bin/powerprofilesctl#g' \
                "$out/quickshell/battery/BatteryPopup.qml"
            fi
            
            if [ -f "$out/quickshell/wallpaper/WallpaperPicker.qml" ]; then
              chmod -R u+w "$out"
              MATUGEN_EXE="${lib.getExe pkgs.matugen}" \
                ${pkgs.python3}/bin/python3 ${patchWallpaperPickerPy} "$out" || echo "Warning: patchWallpaperPickerPy failed, skipping."
            fi
            
            if [ -f "$out/quickshell/settings/SettingsPopup.qml" ]; then
              chmod -R u+w "$out"
              QUICKSHELL_EXE="${quickshellWrapped}/bin/quickshell" \
                ${pkgs.python3}/bin/python3 ${patchSettingsPopupPy} "$out" || echo "Warning: patchSettingsPopupPy failed, skipping."
            fi
            
            if [ -f "$out/quickshell/WindowRegistry.js" ]; then
              chmod -R u+w "$out"
              ${pkgs.python3}/bin/python3 ${patchWindowRegistryJs} "$out" || echo "Warning: patchWindowRegistryJs failed, skipping."
            fi
            
            if [ -f "$out/qs_manager.sh" ]; then
              chmod u+w "$out/qs_manager.sh"
              MAGICK_BINDIR="${pkgs.imagemagick}/bin" \
              FFMPEG_BINDIR="${pkgs.ffmpeg-headless}/bin" \
              JQ_EXE="${pkgs.jq}/bin/jq" \
              QUICKSHELL_EXE="${quickshellWrapped}/bin/quickshell" \
                ${pkgs.python3}/bin/python3 ${patchQsManagerPy} "$out" || echo "Warning: patchQsManagerPy failed, skipping."
              # Fix bluetoothctl scan off (non-interactive)
              ${pkgs.gnused}/bin/sed -i \
                's|(bluetoothctl scan off|(echo "scan off" \| bluetoothctl|g' \
                "$out/qs_manager.sh"
            fi

            if [ -f "$out/quickshell/network/bluetooth_panel_logic.sh" ]; then
              chmod u+w "$out/quickshell/network/bluetooth_panel_logic.sh"
              ${pkgs.python3}/bin/python3 ${./patches/patch-bluetooth-panel.py} "$out" || echo "Warning: patch-bluetooth-panel.py failed, skipping."
            fi
            if [ -f "$out/quickshell/watchers/bt_fetch.sh" ]; then
              chmod u+w "$out/quickshell/watchers/bt_fetch.sh"
              ${pkgs.python3}/bin/python3 ${./patches/patch-bt-fetch.py} "$out" || echo "Warning: patch-bt-fetch.py failed, skipping."
            fi

            chmod -R u+w "$out"
            find "$out" -type f \( -name '*.qml' -o -name '*.sh' \) -print0 | \
              xargs -0 ${pkgs.gnused}/bin/sed -i \
                's|inotifywait|${pkgs.inotify-tools}/bin/inotifywait|'
                
            if [ -f "$out/quickshell/wallpaper/WallpaperPicker.qml" ]; then
              chmod u+w "$out/quickshell/wallpaper/WallpaperPicker.qml"
              ${pkgs.gnused}/bin/sed -i \
                -e 's|@INOTIFYWAIT@|${pkgs.inotify-tools}/bin/inotifywait|g' \
                -e 's/swww img/awww img/g' \
                -e 's/swww_debug/awww_debug/g' \
                "$out/quickshell/wallpaper/WallpaperPicker.qml"
            fi
            
            if [ -f "$out/settings_watcher.sh" ]; then
              chmod u+w "$out/settings_watcher.sh"
              ${pkgs.python3}/bin/python3 ${patchSettingsWatcherShPy} "$out" || echo "Warning: patchSettingsWatcherShPy failed, skipping."
            fi
            
            if [ -f "$out/quickshell/wallpaper/matugen_reload.sh" ]; then
              chmod u+w "$out/quickshell/wallpaper/matugen_reload.sh"

              # Fix killall -> pkill (killall is not available on NixOS by default)
              ${pkgs.gnused}/bin/sed -i 's|killall -USR1 \.kitty-wrapped|pkill -USR1 -f kitty 2>/dev/null|g' \
                "$out/quickshell/wallpaper/matugen_reload.sh"
              ${pkgs.gnused}/bin/sed -i 's|killall -USR1 cava|pkill -USR1 -x cava 2>/dev/null|g' \
                "$out/quickshell/wallpaper/matugen_reload.sh"

              # Wrap swaync-client in timeout to prevent infinite hang when swaync is not running
              ${pkgs.gnused}/bin/sed -i 's|swaync-client -rs|timeout 2 swaync-client -rs 2>/dev/null|g' \
                "$out/quickshell/wallpaper/matugen_reload.sh"

              {
                echo ""
                echo "# --- quickshell-shell (Nix): Hyprland + Quickshell pick up matugen output ---"
                echo "hyprctl reload 2>/dev/null || true"
                echo "${quickshellWrapped}/bin/quickshell -p \"\$HOME/.config/hypr/scripts/quickshell/Shell.qml\" ipc call main forceReload 2>/dev/null || true"
                echo "${quickshellWrapped}/bin/quickshell -p \"\$HOME/.config/hypr/scripts/quickshell/Shell.qml\" ipc call topbar forceReload 2>/dev/null || true"
              } >> "$out/quickshell/wallpaper/matugen_reload.sh"
            fi
          '';

      matugenPack =
        pkgs.runCommand "hoachnt-matugen-pack"
          {
            inherit matugenProgramsSrc hyprlandMatugenTemplate;
            matugenToml =
              pkgs.writeText "matugen-config.toml" ''
                [config]
                reload_apps = false

                [templates.quickshell]
                input_path = "${hm}/.config/matugen/templates/qs_colors.json.template"
                output_path = "/tmp/qs_colors.json"

                [templates.hyprland]
                input_path = "${hm}/.config/matugen/templates/hyprland.conf.template"
                output_path = "${hm}/.config/hypr/colors.conf"

                [templates.gtk]
                input_path = "${hm}/.config/matugen/templates/gtk.css.template"
                output_path = "${hm}/.cache/matugen/colors-gtk.css"



                [templates.kitty]
                input_path = "${hm}/.config/matugen/templates/kitty-colors.conf.template"
                output_path = "/tmp/kitty-matugen-colors.conf"

                [templates.cava]
                input_path = "${hm}/.config/matugen/templates/cava-colors.ini.template"
                output_path = "${hm}/.config/cava/colors"
              '';
          }
          ''
            mkdir -p "$out"
            cp -r "$matugenProgramsSrc/templates" "$out/templates"
            chmod -R u+w "$out/templates"
            cp ${hyprlandMatugenTemplate} "$out/templates/hyprland.conf.template"
            cp "$matugenToml" "$out/config.toml"
          '';

      integrationConf =
        pkgs.writeText "quickshell-integration.conf" ''
          # Generated by Home Manager (modules/home/hyprland/quickshell.nix).
          # Uses CTRL+ALT ($qsMod) for Quickshell so your SUPER bindings in hyprland-base.conf stay free.
          #
          # Before first session: create ${qs.wallpaperDirectory} and run once:
          #   matugen image /path/to/wall.jpg
          #
          # Disable in hyprland-base.conf when using this shell:
          #   - exec-once waybar …   (TopBar replaces it)
          #   - exec-once hyprpaper … if you use awww here instead
          #
          # Matugen → ~/.config/hypr/colors.conf (relative path: same dir as hyprland.conf).
          source = colors.conf

          env = NIXOS_OZONE_WL,1
          env = WALLPAPER_DIR,${qs.wallpaperDirectory}

          exec-once = ${pkgs.awww}/bin/awww-daemon
          exec-once = ${pkgs.playerctl}/bin/playerctld
          exec-once = ${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store
          exec-once = ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store
          exec-once = bash ${hyprScripts}/settings_watcher.sh &
          exec-once = bash ${hyprScripts}/volume_listener.sh
          # Pass WALLPAPER_DIR explicitly — Quickshell sometimes does not inherit Hyprland `env =` entries on all setups.
          exec-once = ${pkgs.coreutils}/bin/env NIXOS_OZONE_WL=1 WALLPAPER_DIR=${qs.wallpaperDirectory} ${quickshellWrapped}/bin/quickshell -p ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/Shell.qml
          exec-once = ${pkgs.python3}/bin/python3 ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/focustime/focus_daemon.py &

          # Синтаксис Hyprland 0.53+: см. https://wiki.hyprland.org/Configuring/Window-Rules/#layer-rules
          layerrule = blur on, ignore_alpha 0.05, match:namespace qs-master

          layerrule = no_anim on, match:namespace ^(volume_osd)$
          layerrule = no_anim on, match:namespace ^(brightness_osd)$
          layerrule = no_anim on, match:namespace hyprpicker
          layerrule = no_anim on, match:namespace qsdock

          $qsMod = CTRL_ALT

          unbind = SUPER ALT, left
          unbind = SUPER ALT, right
          unbind = SUPER_ALT, left
          unbind = SUPER_ALT, right
          unbind = SUPER_ALT_SHIFT, period
          unbind = SUPER_ALT_SHIFT, comma
          bind = SUPER ALT, left, exec, ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/workspace_prev.sh
          bind = SUPER ALT, right, exec, ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/workspace_next.sh
          bind = SUPER_ALT_SHIFT, period, exec, ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/workspace_next.sh
          bind = SUPER_ALT_SHIFT, comma, exec, ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/workspace_prev.sh

          bind = SUPER, W, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle wallpaper
          unbind = SUPER, R
          bind = SUPER, R, exec, bash ~/.config/hypr/scripts/rofi_show.sh drun

          bind = $qsMod, D, exec, bash ~/.config/hypr/scripts/rofi_show.sh drun
          bind = $qsMod, TAB, exec, bash ~/.config/hypr/scripts/rofi_show.sh window
          bind = $qsMod, C, exec, bash ~/.config/hypr/scripts/rofi_clipboard.sh
          bind = $qsMod, M, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle monitors
          bind = $qsMod, A, exec, ${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw
          bind = $qsMod, R, exec, bash ~/.config/hypr/scripts/reload.sh
          bind = CTRL_ALT_SHIFT, S, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle settings
          bind = $qsMod, Q, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle music
          bind = $qsMod, B, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle battery
          bind = $qsMod, W, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle wallpaper
          bind = $qsMod, P, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle wallpaper
          bind = $qsMod, S, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle calendar
          bind = $qsMod, N, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle network
          bind = CTRL_ALT_SHIFT, T, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle focustime
          bind = $qsMod, V, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle volume
          bind = $qsMod, H, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle guide

          bind = $qsMod, 1, exec, ~/.config/hypr/scripts/qs_manager.sh 1
          bind = $qsMod, 2, exec, ~/.config/hypr/scripts/qs_manager.sh 2
          bind = $qsMod, 3, exec, ~/.config/hypr/scripts/qs_manager.sh 3
          bind = $qsMod, 4, exec, ~/.config/hypr/scripts/qs_manager.sh 4
          bind = $qsMod, 5, exec, ~/.config/hypr/scripts/qs_manager.sh 5
          bind = $qsMod, 6, exec, ~/.config/hypr/scripts/qs_manager.sh 6
          bind = $qsMod, 7, exec, ~/.config/hypr/scripts/qs_manager.sh 7
          bind = $qsMod, 8, exec, ~/.config/hypr/scripts/qs_manager.sh 8
          bind = $qsMod, 9, exec, ~/.config/hypr/scripts/qs_manager.sh 9
          bind = $qsMod, 0, exec, ~/.config/hypr/scripts/qs_manager.sh 10

          bind = CTRL_ALT_SHIFT, 1, exec, ~/.config/hypr/scripts/qs_manager.sh 1 move
          bind = CTRL_ALT_SHIFT, 2, exec, ~/.config/hypr/scripts/qs_manager.sh 2 move
          bind = CTRL_ALT_SHIFT, 3, exec, ~/.config/hypr/scripts/qs_manager.sh 3 move
          bind = CTRL_ALT_SHIFT, 4, exec, ~/.config/hypr/scripts/qs_manager.sh 4 move
          bind = CTRL_ALT_SHIFT, 5, exec, ~/.config/hypr/scripts/qs_manager.sh 5 move
          bind = CTRL_ALT_SHIFT, 6, exec, ~/.config/hypr/scripts/qs_manager.sh 6 move
          bind = CTRL_ALT_SHIFT, 7, exec, ~/.config/hypr/scripts/qs_manager.sh 7 move
          bind = CTRL_ALT_SHIFT, 8, exec, ~/.config/hypr/scripts/qs_manager.sh 8 move
          bind = CTRL_ALT_SHIFT, 9, exec, ~/.config/hypr/scripts/qs_manager.sh 9 move
          bind = CTRL_ALT_SHIFT, 0, exec, ~/.config/hypr/scripts/qs_manager.sh 10 move
        '';

    in {

      home.packages = with pkgs; [
        inotify-tools
        power-profiles-daemon
        quickshellWrapped
        matugen
        awww
        rofi
        imagemagick
        ffmpeg
        jq
        socat
        bc
        pamixer
        playerctl
        cliphist
        networkmanager_dmenu
        grim
        slurp
        satty
        lm_sensors
        acpi
        iw
        fd
        ripgrep
        bluez
        libnotify
        pkgs.nerd-fonts.iosevka
      ];

      home.file.".config/hypr/scripts".source = hyprScripts;

      home.file.".config/hypr/quickshell-integration.conf".source = integrationConf;

      home.sessionVariables.WALLPAPER_DIR = qs.wallpaperDirectory;

      home.activation.quickshellWallpaperDir =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p "${qs.wallpaperDirectory}"
          mkdir -p "${config.home.homeDirectory}/.cache/wallpaper_picker/thumbs"
        '';

      home.activation.quickshellMatugenHyprColors =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          _c="${config.home.homeDirectory}/.config/hypr/colors.conf"
          mkdir -p "${config.home.homeDirectory}/.config/hypr"
          if [ ! -s "$_c" ]; then
            ${pkgs.coreutils}/bin/printf '%s\n' \
              '$active_border = rgba(89b4faee)' \
              '$inactive_border = rgba(585b70aa)' > "$_c"
            {
              echo 'general {'
              echo '    col.active_border = $active_border'
              echo '    col.inactive_border = $inactive_border'
              echo '}'
            } >> "$_c"
            chmod 644 "$_c"
          elif ! grep -q 'col.active_border' "$_c" 2>/dev/null; then
            {
              echo
              echo 'general {'
              echo '    col.active_border = $active_border'
              echo '    col.inactive_border = $inactive_border'
              echo '}'
            } >> "$_c"
            chmod 644 "$_c"
          fi
        '';

      home.activation.quickshellHyprSettingsWritable =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          _d="${config.home.homeDirectory}/.config/hypr"
          _f="$_d/settings.json"
          mkdir -p "$_d"
          if [ -L "$_f" ] || [ ! -f "$_f" ]; then
            rm -f "$_f"
            install -m644 ${defaultHyprSettingsJson} "$_f"
          fi
          if [ -f "$_f" ] && [ ! -L "$_f" ] && ${lib.getExe pkgs.jq} -e '(.workspaceCount // 0) > 99' "$_f" 2>/dev/null; then
            _t="$_f.qsclamp"
            ${lib.getExe pkgs.jq} '.workspaceCount = 99' "$_f" > "$_t" && install -m644 "$_t" "$_f"
            rm -f "$_t"
          fi
        '';

      home.file.".config/hypr/QUICKSHELL_README.txt".text = ''
        Quickshell UI (ilyamiro-style) is enabled from Nix.

        1) Comment out `exec-once = waybar …` in ~/.config/hypr/hyprland-base.conf (TopBar replaces Waybar).
        2) Pick ONE wallpaper daemon: either comment `exec-once = hyprpaper` and use awww from integration,
           or set quickshellShell.enable = false and keep hyprpaper only.
        3) Wallpaper: put images in quickshellShell.wallpaperDirectory (also WALLPAPER_DIR). Default is ~/Pictures/Wallpapers —
           if your folder is ~/Pictures/wallpaper, set quickshellShell.wallpaperDirectory in home module.
           Quick set: awww img /path/to/file.jpg
           Theme from image: matugen image /path/to/file.jpg -q   (-q avoids extra noise; ensure ~/.cache/matugen exists)
           Widget: CTRL+ALT+W or SUPER+W; if nothing opens (e.g. Cursor steals Ctrl+Alt+W) use CTRL+ALT+P.
           Hyprland accents: matugen writes ~/.config/hypr/colors.conf; quickshell-integration.conf sources it.
           GTK: set quickshellShell.gtkMatugenTheme = true to import ~/.cache/matugen/colors-gtk.css.
        4) Widget shortcuts use CTRL+ALT (see ~/.config/hypr/quickshell-integration.conf), not SUPER.

        Your blur { } settings remain in hyprland-base.conf; layerrules for qs-master are appended via integration.
      '';

      xdg.configFile."matugen" = {
        source = matugenPack;
        recursive = true;
      };

      xdg.configFile."rofi/config.rasi".text = ''
        configuration {
          modi: "drun,filebrowser,window";
          show-icons: true;
          drun-display-format: "{name}";
          window-format: "{w} · {c} · {t}";
          hover-select: true;
          case-sensitive: false;
        }

        @theme "theme.rasi"
      '';

      programs.rofi = {
        enable = true;
        package = pkgs.rofi;
      };

      gtk.gtk3.extraCss = lib.mkAfter (
        lib.optionalString qs.gtkMatugenTheme ''
          @import url("file://${config.home.homeDirectory}/.cache/matugen/colors-gtk.css");
        ''
      );

      gtk.gtk4.extraCss = lib.mkAfter (
        lib.optionalString qs.gtkMatugenTheme ''
          @import url("file://${config.home.homeDirectory}/.cache/matugen/colors-gtk.css");
        ''
      );

      wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
        source = ~/.config/hypr/quickshell-integration.conf
      '';
    }
  );
}