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

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/Main.qml"
          t = p.read_text()

          # Legacy Main.qml: mask + compact topBarHole + MouseArea (ilyamiro ~0291dea).
          old_top_hole = (
              "    Item {\n"
              "        id: topBarHole\n"
              "        anchors.top: parent.top\n"
              "        anchors.left: parent.left\n"
              "        anchors.right: parent.right\n"
              "        height: 65 \n"
              "    }\n\n"
              "    MouseArea {\n"
              "        anchors.fill: parent\n"
              "        enabled: masterWindow.isVisible\n"
              "        onClicked: switchWidget(\"hidden\", \"\")\n"
              "    }\n"
          )
          new_top_hole = (
              "    Item {\n"
              "        id: topBarHole\n"
              "        anchors.top: parent.top\n"
              "        anchors.left: parent.left\n"
              "        anchors.right: parent.right\n"
              "        // Same vertical extent as TopBar: barHeight s(48) + top s(4) + bottom s(2) (= s(54)), scaled (see TopBar.qml)\n"
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
              "    }\n\n"
              "    MouseArea {\n"
              "        anchors.fill: parent\n"
              "        enabled: masterWindow.isVisible\n"
              "        onClicked: switchWidget(\"hidden\", \"\")\n"
              "    }\n"
          )
          if old_top_hole not in t:
              sys.exit(
                  "Main.qml: topBarHole block not recognized — flake input ilyamiro-config rev does not match patchMainQmlPy."
              )
          t = t.replace(old_top_hole, new_top_hole, 1)

          a = (
              "    property bool isVisible: false\n"
              "    property string activeArg: \"\""
          )
          b = (
              "    property bool isVisible: false\n"
              "    property bool overlayDismissReady: false\n"
              "    property string activeArg: \"\""
          )
          if a not in t:
              sys.exit("Main.qml: expected isVisible/activeArg block not found")
          t = t.replace(a, b, 1)

          marker = "    property real globalUiScale: 1.0\n\n    // =========================================================\n"
          timer = (
              "    property real globalUiScale: 1.0\n\n"
              "    Timer {\n"
              "        id: overlayDismissCooldown\n"
              "        interval: 380\n"
              "        repeat: false\n"
              "        onTriggered: masterWindow.overlayDismissReady = true\n"
              "    }\n\n"
              "    // =========================================================\n"
          )
          if marker not in t:
              sys.exit("Main.qml: globalUiScale marker not found")
          t = t.replace(marker, timer, 1)

          old_vis = (
              "    onIsVisibleChanged: {\n"
              "        if (isVisible) masterWindow.requestActivate();\n"
              "    }\n"
          )
          new_vis = (
              "    onIsVisibleChanged: {\n"
              "        overlayDismissCooldown.stop()\n"
              "        if (isVisible) {\n"
              "            masterWindow.overlayDismissReady = false\n"
              "            overlayDismissCooldown.start()\n"
              "            masterWindow.requestActivate()\n"
              "        } else {\n"
              "            masterWindow.overlayDismissReady = false\n"
              "        }\n"
              "    }\n"
          )
          old_vis_stack = (
              "    onIsVisibleChanged: {\n"
              "        if (isVisible) widgetStack.forceActiveFocus();\n"
              "    }\n"
          )
          new_vis_stack = (
              "    onIsVisibleChanged: {\n"
              "        overlayDismissCooldown.stop()\n"
              "        if (isVisible) {\n"
              "            masterWindow.overlayDismissReady = false\n"
              "            overlayDismissCooldown.start()\n"
              "            masterWindow.requestActivate()\n"
              "            widgetStack.forceActiveFocus();\n"
              "        } else {\n"
              "            masterWindow.overlayDismissReady = false\n"
              "        }\n"
              "    }\n"
          )
          if old_vis in t:
              t = t.replace(old_vis, new_vis, 1)
          elif old_vis_stack in t:
              t = t.replace(old_vis_stack, new_vis_stack, 1)
          else:
              sys.exit("Main.qml: onIsVisibleChanged block not found")

          old_mouse = (
              "    MouseArea {\n"
              "        anchors.fill: parent\n"
              "        enabled: masterWindow.isVisible\n"
              "        onClicked: switchWidget(\"hidden\", \"\")\n"
              "    }\n\n"
              "    Component.onCompleted:"
          )
          new_mouse = (
              "    MouseArea {\n"
              "        anchors.fill: parent\n"
              "        enabled: masterWindow.isVisible && masterWindow.overlayDismissReady\n"
              "        onClicked: switchWidget(\"hidden\", \"\")\n"
              "    }\n\n"
              "    Component.onCompleted:"
          )
          old_mouse_brace = (
              "    MouseArea {\n"
              "        anchors.fill: parent\n"
              "        enabled: masterWindow.isVisible\n"
              "        onClicked: switchWidget(\"hidden\", \"\")\n"
              "    }\n\n"
              "    Component.onCompleted: {"
          )
          new_mouse_brace = (
              "    MouseArea {\n"
              "        anchors.fill: parent\n"
              "        enabled: masterWindow.isVisible && masterWindow.overlayDismissReady\n"
              "        onClicked: switchWidget(\"hidden\", \"\")\n"
              "    }\n\n"
              "    Component.onCompleted: {"
          )
          if old_mouse in t:
              t = t.replace(old_mouse, new_mouse, 1)
          elif old_mouse_brace in t:
              t = t.replace(old_mouse_brace, new_mouse_brace, 1)
          else:
              sys.exit("Main.qml: root dismiss MouseArea before Component.onCompleted not found")

          # Quickshell/Qt: WlrLayershell deprecates plain width/height on PanelWindow; implicit size can stay 0
          # while the layer still participates in Hyprland blur → wallpaper (and other) widgets look "empty".
          shell_wh_old = (
              "    width: Screen.width\n"
              "    height: Screen.height\n\n"
              "    visible: isVisible\n"
          )
          shell_wh_new = (
              "    implicitWidth: Math.max(1, Screen.width)\n"
              "    implicitHeight: Math.max(1, Screen.height)\n"
              "    width: implicitWidth\n"
              "    height: implicitHeight\n\n"
              "    visible: isVisible\n"
          )
          if "implicitWidth: Math.max(1, Screen.width)" in t:
              pass
          elif shell_wh_old in t:
              t = t.replace(shell_wh_old, shell_wh_new, 1)
          elif "implicitWidth: masterWindow.screen.width" in t:
              pass
          else:
              sys.exit("Main.qml: PanelWindow sizing not recognized (Screen.width or masterWindow.screen)")

          p.write_text(t)
        '';

      # GuidePopup.qml lists upstream SUPER hotkeys; Hyprland binds use CTRL+ALT — fix displayed keys.
      patchGuidePopupPy =
        pkgs.writeText "patch-guide-popup.py" ''
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          p = out / "quickshell/guide/GuidePopup.qml"
          if not p.is_file():
              sys.exit("GuidePopup.qml not found")
          t = p.read_text()

          # Upstream buildKeybinds() uses objects with `cmd:` (ilyamiro ~0291dea).
          subs = [
              (
                  '{ k1: "SUPER", k2: "D", action: "App Launcher (Drun)", cmd: "bash ~/.config/hypr/scripts/rofi_show.sh drun" },',
                  '{ k1: "CTRL+ALT", k2: "D", action: "App Launcher (Drun)", cmd: "bash ~/.config/hypr/scripts/rofi_show.sh drun" },',
              ),
              (
                  '{ k1: "ALT", k2: "TAB", action: "Window Switcher", cmd: "bash ~/.config/hypr/scripts/rofi_show.sh window" },',
                  '{ k1: "CTRL+ALT", k2: "TAB", action: "Window Switcher (Rofi)", cmd: "bash ~/.config/hypr/scripts/rofi_show.sh window" },',
              ),
              (
                  '{ k1: "SUPER", k2: "C", action: "Clipboard History", cmd: "bash ~/.config/hypr/scripts/rofi_clipboard.sh" },',
                  '{ k1: "CTRL+ALT", k2: "C", action: "Clipboard History", cmd: "bash ~/.config/hypr/scripts/rofi_clipboard.sh" },',
              ),
              (
                  '{ k1: "SUPER", k2: "W", action: "Toggle Wallpaper", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle wallpaper" },',
                  '{ k1: "CTRL+ALT", k2: "W", action: "Toggle Wallpaper", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle wallpaper" },',
              ),
              (
                  '{ k1: "SUPER", k2: "Q", action: "Toggle Music", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle music" },',
                  '{ k1: "CTRL+ALT", k2: "Q", action: "Toggle Music", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle music" },',
              ),
              (
                  '{ k1: "SUPER", k2: "B", action: "Toggle Battery", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle battery" },',
                  '{ k1: "CTRL+ALT", k2: "B", action: "Toggle Battery", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle battery" },',
              ),
              (
                  '{ k1: "SUPER", k2: "S", action: "Toggle Calendar", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle calendar" },',
                  '{ k1: "CTRL+ALT", k2: "S", action: "Toggle Calendar", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle calendar" },',
              ),
              (
                  '{ k1: "SUPER", k2: "N", action: "Toggle Network", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle network" },',
                  '{ k1: "CTRL+ALT", k2: "N", action: "Toggle Network", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle network" },',
              ),
              (
                  '{ k1: "SUPER", k2: "V", action: "Toggle Volume", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle volume" },',
                  '{ k1: "CTRL+ALT", k2: "V", action: "Toggle Volume", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle volume" },',
              ),
              (
                  '{ k1: "SUPER", k2: "M", action: "Toggle Monitors", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle monitors" },',
                  '{ k1: "CTRL+ALT", k2: "M", action: "Toggle Monitors", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle monitors" },',
              ),
              (
                  '{ k1: "SUPER", k2: "H", action: "Toggle Guide", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle guide" },',
                  '{ k1: "CTRL+ALT", k2: "H", action: "Toggle Guide", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle guide" },',
              ),
              (
                  '{ k1: "SUPER+SHIFT", k2: "S", action: "Toggle Settings", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle settings" },',
                  '{ k1: "CTRL+ALT+SHIFT", k2: "S", action: "Toggle Settings", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle settings" },',
              ),
              (
                  '{ k1: "SUPER", k2: "R", action: "Reload System", cmd: "bash ~/.config/hypr/scripts/reload.sh" },',
                  '{ k1: "SUPER", k2: "R", action: "App Launcher (Rofi)", cmd: "bash ~/.config/hypr/scripts/rofi_show.sh drun" },',
              ),
              (
                  '{ k1: "SUPER+SHIFT", k2: "T", action: "Toggle FocusTime", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle focustime" },',
                  '{ k1: "CTRL+ALT+SHIFT", k2: "T", action: "Toggle FocusTime", cmd: "bash ~/.config/hypr/scripts/qs_manager.sh toggle focustime" },',
              ),
              (
                  '{ k1: "SUPER", k2: "A", action: "Toggle SwayNC Panel", cmd: "swaync-client -t -sw" },',
                  '{ k1: "CTRL+ALT", k2: "A", action: "Toggle SwayNC Panel", cmd: "swaync-client -t -sw" },',
              ),
          ]
          for old, new in subs:
              if old not in t:
                  sys.exit("GuidePopup.qml: substring not found:\\n" + old)
              t = t.replace(old, new, 1)

          p.write_text(t)
        '';

      # Upstream ties ListView/filter chrome opacity to FolderListModel.Ready only. On NixOS paths can sit in
      # Loading forever or Error — never Ready — so isReady stays false and the whole picker stays invisible.
      # You then only see Hyprland blur on qs-master ("milky mask"). Force UI visible regardless of model status.
      #
      # Root Item used `width: Screen.width`: when Quickshell reports Screen.width === 0 (common early in session),
      # the picker stays zero-width inside Main.qml's clip — same blur-only symptom. Fill StackView parent + scaler fallback.
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
              "    // --- Responsive Scaling Logic ---\n"
              "    Scaler {\n"
              "        id: scaler\n"
              "        currentWidth: Screen.width"
          )
          root_block_new = (
              "Item {\n"
              "    id: window\n"
              "    anchors.fill: parent\n"
              "\n"
              "    // --- Responsive Scaling Logic ---\n"
              "    Scaler {\n"
              "        id: scaler\n"
              "        currentWidth: Math.max(window.width, Screen.width) || 1920"
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
          t = t.replace(home_needle, home_insert, 1)

          src_old = (
              "    readonly property string srcDir: {\n"
              "    \tconst dir = Quickshell.env(\"WALLPAPER_DIR\")\n"
              "    \treturn (dir && dir !== \"\") \n"
              "        ? dir \n"
              "        : Quickshell.env(\"HOME\") + \"/Pictures/Wallpapers\"\n"
              "    }\n"
          )
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
          if src_old not in t:
              sys.exit("WallpaperPicker.qml: srcDir block not found")
          t = t.replace(src_old, src_new, 1)

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
              "        if (searchState.searched) {\n"
          )
          completed_insert = (
              "        Quickshell.execDetached([\"bash\", \"-c\", \"mkdir -p '\" + decodeURIComponent(window.searchDir.replace(\"file://\", \"\")) + \"'\"]);\n"
              "        Qt.callLater(function () {\n"
              "            window.syncLocalModel();\n"
              "            window.tryFocus();\n"
              "        });\n"
              "        \n"
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

      # Settings Apply used `echo '" + pretty-printed JSON + "'` — multiline JSON breaks the shell string, so nothing was written.
      # Guide writes API keys to scripts/quickshell/calendar/.env — that path is inside the HM symlink to the
      # Nix store and is read-only. Use ~/.config/hypr/weather.env + heredoc (safe for quotes in keys).
      patchGuideWeatherPy =
        pkgs.writeText "patch-guide-weather.py" ''
          import json
          import os
          import pathlib
          import sys

          out = pathlib.Path(sys.argv[1])
          qs = os.environ.get("QUICKSHELL_EXE", "quickshell")
          p = out / "quickshell/guide/GuidePopup.qml"
          if not p.is_file():
              sys.exit("GuidePopup.qml not found")
          t = p.read_text()

          old_upstream = (
              "                function saveWeatherConfig() {\n"
              "                    var cache_weather = Quickshell.env(\"HOME\") + \"/.cache/quickshell/weather\";\n"
              "                    var file = Quickshell.env(\"HOME\") + \"/.config/hypr/scripts/quickshell/calendar/.env\";\n"
              "                    var cmds = [\n"
              "                        \"mkdir -p $(dirname \" + file + \")\",\n"
              "                        \"echo '# OpenWeather API Configuration (OVERWRITE, not add)' > \" + file,\n"
              "                        \"echo 'OPENWEATHER_KEY=\" + apiKeyInput.text + \"' >> \" + file,\n"
              "                        \"echo 'OPENWEATHER_CITY_ID=\" + cityIdInput.text + \"' >> \" + file,\n"
              "                        \"echo 'OPENWEATHER_UNIT=\" + weatherTab.selectedUnit + \"' >> \" + file,\n"
              "                        \"rm -r \" + cache_weather,\n"
              "                        \"notify-send 'Weather' 'API configuration saved successfully!'\"\n"
              "                    ];\n"
              "                    var finalCmd = cmds.join(\" && \");\n"
              "                    Quickshell.execDetached([\"bash\", \"-c\", finalCmd]);\n"
              "                }"
          )
          # bash rejects `<<EOF` … newline … `&&` after heredoc end inside `bash -c` without wrapping `( … )`
          old_broken_heredoc = (
              "                function saveWeatherConfig() {\n"
              "                    var home = Quickshell.env(\"HOME\");\n"
              "                    var envPath = home + \"/.config/hypr/weather.env\";\n"
              "                    var cacheWeather = home + \"/.cache/quickshell/weather\";\n"
              "                    var marker = \"QS_WEATHER_ENV_\" + Math.random().toString(36).slice(2) + \"_\" + Date.now();\n"
              "                    var body = \"# OpenWeather API Configuration\\n\" +\n"
              "                        \"OPENWEATHER_KEY=\" + apiKeyInput.text + \"\\n\" +\n"
              "                        \"OPENWEATHER_CITY_ID=\" + cityIdInput.text + \"\\n\" +\n"
              "                        \"OPENWEATHER_UNIT=\" + weatherTab.selectedUnit + \"\\n\";\n"
              "                    var cmd =\n"
              "                        \"mkdir -p '\" + home + \"/.config/hypr' && cat > '\" + envPath + \"' <<'\" + marker + \"'\\n\" +\n"
              "                        body +\n"
              "                        marker + \"\\n\" +\n"
              "                        \"&& rm -rf '\" + cacheWeather + \"' 2>/dev/null || true\" +\n"
              "                        \" && notify-send 'Weather' 'API configuration saved successfully!'\";\n"
              "                    Quickshell.execDetached([\"bash\", \"-c\", cmd]);\n"
              "                }"
          )
          new = (
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
          if old_upstream in t:
              t = t.replace(old_upstream, new, 1)
          elif old_broken_heredoc in t:
              t = t.replace(old_broken_heredoc, new, 1)
          else:
              sys.exit("GuidePopup.qml: saveWeatherConfig block not found")
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

          # env_changed: was touch + get_data& then cat — raced with stale json
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

      # Writable default seeded on activate — not a home.file store symlink (Apply must overwrite).
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
          # Single bash -c chain: write settings → sync /tmp/qs_workspaces.json → topbar queueReload (avoids race between detached bashes)
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
              sys.exit("SettingsPopup.qml: saveAppSettings block not found")
          t = t.replace(old_save, new_save, 1)
          p.write_text(t)
        '';

      # If Screen.width/height are briefly 0 in Quickshell, wallpaper layout becomes w: 0 — clip rect empty (milky blur only).
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

      # Wallpaper widget is the only one that shells out to magick/ffmpeg for thumbnails and reads WALLPAPER_DIR.
      # Hyprland `exec` / keybind env often omits HM packages from PATH → thumbnails never generate (empty carousel).
      # qs_manager also restarts quickshell without Hyprland `env =` → WALLPAPER_DIR unset for that process.
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
              'QS_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"\n'
              'BT_PID_FILE="$HOME/.cache/bt_scan_pid"\n'
              'BT_SCAN_LOG="$HOME/.cache/bt_scan.log"\n'
              'SRC_DIR="''${WALLPAPER_DIR:-''${srcdir:-$HOME/Pictures/Wallpapers}}"\n'
          )
          header_insert = (
              'QS_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"\n'
              'BT_PID_FILE="$HOME/.cache/bt_scan_pid"\n'
              'BT_SCAN_LOG="$HOME/.cache/bt_scan.log"\n'
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

          old_main = (
              'if ! pgrep -f "quickshell.*Main\\.qml" >/dev/null; then\n'
              '    quickshell -p "$MAIN_QML_PATH" >/dev/null 2>&1 &\n'
              "    disown\n"
              "fi\n"
          )
          new_main = (
              'if ! pgrep -f "quickshell.*Main\\.qml" >/dev/null; then\n'
              + '    env NIXOS_OZONE_WL=1 WALLPAPER_DIR="$WALLPAPER_DIR" '
              + qs
              + ' -p "$MAIN_QML_PATH" >/dev/null 2>&1 &\n'
              + "    disown\n"
              + "fi\n"
          )
          old_bar = (
              'if ! pgrep -f "quickshell.*TopBar\\.qml" >/dev/null; then\n'
              '    quickshell -p "$BAR_QML_PATH" >/dev/null 2>&1 &\n'
              "    disown\n"
              "fi\n"
          )
          new_bar = (
              'if ! pgrep -f "quickshell.*TopBar\\.qml" >/dev/null; then\n'
              + '    env NIXOS_OZONE_WL=1 WALLPAPER_DIR="$WALLPAPER_DIR" '
              + qs
              + ' -p "$BAR_QML_PATH" >/dev/null 2>&1 &\n'
              + "    disown\n"
              + "fi\n"
          )
          if old_main not in t:
              sys.exit("qs_manager.sh: quickshell Main.qml restart block not found")
          if old_bar not in t:
              sys.exit("qs_manager.sh: quickshell TopBar.qml restart block not found")
          t = t.replace(old_main, new_main, 1)
          t = t.replace(old_bar, new_bar, 1)

          p.write_text(t)
        '';

      # After editing hyprland.conf (layout, wallpaper env), reload Hyprland so changes apply without re-login.
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
            # Main.qml patches (upstream: ilyamiro/nixos-configuration):
            # - topBarHole height matches TopBar (s(48)+top s(4)+bottom s(2)) * globalUiScale; do NOT stretch it (e.g. 160) or
            #   the hole lets clicks through to apps (e.g. Cursor) above the real bar.
            # - dim Rectangle under TopBar: Hyprland blur (qs-master) + slight opacity read as frosted.
            # - dismiss cooldown: opening a widget enables overlay before mouse-up; without delay the same click closes it.
            # (Upstream dirs may be mode 555 — chmod then rewrite.)
            if [ -f "$out/quickshell/Main.qml" ]; then
              chmod -R u+w "$out"
              ${pkgs.python3}/bin/python3 ${patchMainQmlPy} "$out"
            fi
            if [ -f "$out/quickshell/guide/GuidePopup.qml" ]; then
              chmod -R u+w "$out"
              ${pkgs.python3}/bin/python3 ${patchGuidePopupPy} "$out"
              QUICKSHELL_EXE="${quickshellWrapped}/bin/quickshell" \
                ${pkgs.python3}/bin/python3 ${patchGuideWeatherPy} "$out"
            fi
            if [ -f "$out/quickshell/calendar/weather.sh" ]; then
              chmod u+w "$out/quickshell/calendar/weather.sh"
              ${pkgs.python3}/bin/python3 ${patchWeatherShPy} "$out"
            fi
            if [ -f "$out/quickshell/calendar/schedule/get_schedule.py" ]; then
              chmod -R u+w "$out/quickshell/calendar/schedule"
              ${pkgs.python3}/bin/python3 ${./patches/patch-schedule.py} "$out"
            fi
            if [ -f "$out/quickshell/workspaces.sh" ]; then
              chmod u+w "$out/quickshell/workspaces.sh"
              ${pkgs.python3}/bin/python3 ${patchWorkspacesShPy} "$out"
              ${pkgs.python3}/bin/python3 ${./patches/patch-workspaces-jq.py} "$out"
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
              ${pkgs.python3}/bin/python3 ${patchTopBarWeatherIpcPy} "$out"
              ${pkgs.python3}/bin/python3 ${./patches/patch-topbar-bar-margins.py} "$out"
              ${pkgs.python3}/bin/python3 ${./patches/patch-topbar-workspaces.py} "$out"
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
                ${pkgs.python3}/bin/python3 ${patchWallpaperPickerPy} "$out"
            fi
            if [ -f "$out/quickshell/settings/SettingsPopup.qml" ]; then
              chmod -R u+w "$out"
              QUICKSHELL_EXE="${quickshellWrapped}/bin/quickshell" \
                ${pkgs.python3}/bin/python3 ${patchSettingsPopupPy} "$out"
            fi
            if [ -f "$out/quickshell/WindowRegistry.js" ]; then
              chmod -R u+w "$out"
              ${pkgs.python3}/bin/python3 ${patchWindowRegistryJs} "$out"
            fi
            if [ -f "$out/qs_manager.sh" ]; then
              chmod u+w "$out/qs_manager.sh"
              MAGICK_BINDIR="${pkgs.imagemagick}/bin" \
              FFMPEG_BINDIR="${pkgs.ffmpeg-headless}/bin" \
              JQ_EXE="${pkgs.jq}/bin/jq" \
              QUICKSHELL_EXE="${quickshellWrapped}/bin/quickshell" \
                ${pkgs.python3}/bin/python3 ${patchQsManagerPy} "$out"
            fi
            # Main/TopBar/Scaler QML + settings_watcher.sh use `inotifywait` for IPC.
            # Hyprland exec-once often has a minimal PATH → command not found, widgets never open.
            chmod -R u+w "$out"
            # One substitution per line: with `g`, `/nix/.../bin/inotifywait` would match again and double the path.
            find "$out" -type f \( -name '*.qml' -o -name '*.sh' \) -print0 | \
              xargs -0 ${pkgs.gnused}/bin/sed -i \
                's|inotifywait|${pkgs.inotify-tools}/bin/inotifywait|'
            # After global inotifywait substitution (avoid double-prefix on WallpaperPicker).
            if [ -f "$out/quickshell/wallpaper/WallpaperPicker.qml" ]; then
              chmod u+w "$out/quickshell/wallpaper/WallpaperPicker.qml"
              ${pkgs.gnused}/bin/sed -i \
                's|@INOTIFYWAIT@|${pkgs.inotify-tools}/bin/inotifywait|g' \
                "$out/quickshell/wallpaper/WallpaperPicker.qml"
            fi
            if [ -f "$out/settings_watcher.sh" ]; then
              chmod u+w "$out/settings_watcher.sh"
              ${pkgs.python3}/bin/python3 ${patchSettingsWatcherShPy} "$out"
            fi
            if [ -f "$out/quickshell/wallpaper/matugen_reload.sh" ]; then
              chmod u+w "$out/quickshell/wallpaper/matugen_reload.sh"
              {
                echo ""
                echo "# --- quickshell-shell (Nix): Hyprland + Quickshell pick up matugen output ---"
                echo "hyprctl reload 2>/dev/null || true"
                echo "${quickshellWrapped}/bin/quickshell -p \"\$HOME/.config/hypr/scripts/quickshell/Main.qml\" ipc call main forceReload 2>/dev/null || true"
                echo "${quickshellWrapped}/bin/quickshell -p \"\$HOME/.config/hypr/scripts/quickshell/TopBar.qml\" ipc call topbar forceReload 2>/dev/null || true"
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
                input_path = "${hm}/.config/hypr/scripts/quickshell/colors.json.template"
                output_path = "/tmp/qs_colors.json"

                [templates.hyprland]
                input_path = "${hm}/.config/matugen/templates/hyprland.conf.template"
                output_path = "${hm}/.config/hypr/colors.conf"

                [templates.gtk]
                input_path = "${hm}/.config/matugen/templates/gtk.css.template"
                output_path = "${hm}/.cache/matugen/colors-gtk.css"

                [templates.rofi]
                input_path = "${hm}/.config/matugen/templates/rofi.rasi.template"
                output_path = "${hm}/.config/rofi/theme.rasi"

                [templates.swayosd]
                input_path = "${hm}/.config/matugen/templates/swayosd.css.template"
                output_path = "${hm}/.config/swayosd/style.css"

                [templates.swaync]
                input_path = "${hm}/.config/matugen/templates/swaync.css.template"
                output_path = "${hm}/.config/swaync/style.css"

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
          #   - exec-once hyprpaper … if you use swww here instead
          #
          # Matugen → ~/.config/hypr/colors.conf (relative path: same dir as hyprland.conf).
          source = colors.conf

          env = NIXOS_OZONE_WL,1
          env = WALLPAPER_DIR,${qs.wallpaperDirectory}

          exec-once = ${pkgs.swww}/bin/swww-daemon
          exec-once = ${pkgs.playerctl}/bin/playerctld
          exec-once = ${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store
          exec-once = ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store
          exec-once = bash ${hyprScripts}/settings_watcher.sh &
          exec-once = bash ${hyprScripts}/volume_listener.sh
          # Pass WALLPAPER_DIR explicitly — Quickshell sometimes does not inherit Hyprland `env =` entries on all setups.
          exec-once = ${pkgs.coreutils}/bin/env NIXOS_OZONE_WL=1 WALLPAPER_DIR=${qs.wallpaperDirectory} ${quickshellWrapped}/bin/quickshell -p ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/Main.qml
          exec-once = ${pkgs.coreutils}/bin/env NIXOS_OZONE_WL=1 WALLPAPER_DIR=${qs.wallpaperDirectory} ${quickshellWrapped}/bin/quickshell -p ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/TopBar.qml
          exec-once = ${pkgs.python3}/bin/python3 ${config.home.homeDirectory}/.config/hypr/scripts/quickshell/focustime/focus_daemon.py &

          # Синтаксис Hyprland 0.53+: см. https://wiki.hyprland.org/Configuring/Window-Rules/#layer-rules
          layerrule = blur on, ignore_alpha 0.05, match:namespace qs-master
          # Верхняя панель Quickshell часто без отдельного namespace в QML — при необходимости добавьте правило
          # после `hyprctl layers` (только match:namespace, не match:class).

          layerrule = no_anim on, match:namespace ^(volume_osd)$
          layerrule = no_anim on, match:namespace ^(brightness_osd)$
          layerrule = no_anim on, match:namespace hyprpicker
          layerrule = no_anim on, match:namespace qsdock

          $qsMod = CTRL_ALT

          # Carousel 1..workspaceCount (wrap). Base: `bind = $mainMod ALT, left` → SUPER+ALT+arrow (mods space-separated: SUPER ALT, key).
          # `SUPER, ALT, left` is wrong: Hyprland treats `left` as dispatcher → "invalid dispatcher left".
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

          # Same action as Guide "Toggle Wallpaper" (upstream used SUPER+W); optional duplicate if nothing else uses SUPER+W in hyprland-base.conf.
          bind = SUPER, W, exec, bash ~/.config/hypr/scripts/qs_manager.sh toggle wallpaper
          # hyprland-base.conf often binds $mainMod,R to hyprlauncher — unbind so only rofi remains.
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
          # Cursor/VS Code often grabs Ctrl+Alt+W — use this if wallpaper never opens from W.
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
        swww
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
        # TopBar.qml uses font.family "Iosevka Nerd Font" for NF glyphs (help/search/settings icons).
        pkgs.nerd-fonts.iosevka
      ];

      home.file.".config/hypr/scripts".source = hyprScripts;

      home.file.".config/hypr/quickshell-integration.conf".source = integrationConf;

      # Do not manage settings.json as a home.file (store symlink) — Quickshell Apply must overwrite a real file.
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
        2) Pick ONE wallpaper daemon: either comment `exec-once = hyprpaper` and use swww from integration,
           or set quickshellShell.enable = false and keep hyprpaper only.
        3) Wallpaper: put images in quickshellShell.wallpaperDirectory (also WALLPAPER_DIR). Default is ~/Pictures/Wallpapers —
           if your folder is ~/Pictures/wallpaper, set quickshellShell.wallpaperDirectory in home module.
           Quick set: swww img /path/to/file.jpg
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

      # Must load after hyprland-base.conf so carousel `unbind = SUPER ALT, left/right`
      # runs against the base `workspace -1/+1` binds (HM merges plain extraConfig before mkAfter).
      wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
        source = ~/.config/hypr/quickshell-integration.conf
      '';
    }
  );
}
