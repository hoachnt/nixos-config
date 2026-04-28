# TopBar.qml: GNOME-like workspace row — always show all slots, tooltips, readable empty state.
# argv[1] = $out (hypr scripts store root)
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
p = out / "quickshell/TopBar.qml"
t = p.read_text()

old_lim = "                                property bool isLimited: workspacesBox.limitActive && index >= 6"
new_lim = "                                property bool isLimited: false // always show all (GNOME-like)"
if old_lim not in t:
    sys.exit("TopBar.qml: isLimited line not found")
t = t.replace(old_lim, new_lim, 1)

old_append = '                                    workspacesModel.append({ "wsId": "", "wsState": "" });'
new_append = '                                    workspacesModel.append({ "wsId": "", "wsState": "", "wsTooltip": "" });'
if old_append not in t:
    sys.exit("TopBar.qml: workspacesModel.append not found")
t = t.replace(old_append, new_append, 1)

old_idclose = (
    "                                    if (workspacesModel.get(i).wsId !== newData[i].id.toString()) {\n"
    "                                        workspacesModel.setProperty(i, \"wsId\", newData[i].id.toString());\n"
    "                                    }\n"
    "                    }\n"
)
new_idclose = (
    "                                    if (workspacesModel.get(i).wsId !== newData[i].id.toString()) {\n"
    "                                        workspacesModel.setProperty(i, \"wsId\", newData[i].id.toString());\n"
    "                                    }\n"
    "                                    if (workspacesModel.get(i).wsTooltip !== (newData[i].tooltip || \"\")) {\n"
    "                                        workspacesModel.setProperty(i, \"wsTooltip\", (newData[i].tooltip || \"\"));\n"
    "                                    }\n"
    "                    }\n"
)
if old_idclose not in t:
    sys.exit("TopBar.qml: for-loop / wsId block not found")
t = t.replace(old_idclose, new_idclose, 1)

old_color = (
    "                                color: stateLabel === \"active\" \n"
    "                                        ? mocha.mauve \n"
    "                                        : (isHovered \n"
    "                                            ? Qt.rgba(mocha.overlay0.r, mocha.overlay0.g, mocha.overlay0.b, 0.9) \n"
    "                                            : (stateLabel === \"occupied\" \n"
    "                                                ? Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.9) \n"
    "                                                : \"transparent\"))\n"
)
new_color = (
    "                                color: stateLabel === \"active\" \n"
    "                                        ? mocha.mauve \n"
    "                                        : (isHovered \n"
    "                                            ? Qt.rgba(mocha.overlay0.r, mocha.overlay0.g, mocha.overlay0.b, 0.9) \n"
    "                                            : (stateLabel === \"occupied\" \n"
    "                                                ? Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.9) \n"
    "                                                : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.5)))\n"
)
if old_color not in t:
    sys.exit("TopBar.qml: workspace color expression not found")
t = t.replace(old_color, new_color, 1)

old_tw = (
    "                                property real targetWidth: barWindow.s(32)\n"
    "                                width: targetWidth\n"
    "                                Behavior on targetWidth { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }"
)
new_tw = (
    "                                property real targetWidth: (model.wsId.length > 1) ? barWindow.s(40) : barWindow.s(32)\n"
    "                                width: targetWidth\n"
    "                                Behavior on targetWidth { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }"
)
if old_tw not in t:
    sys.exit("TopBar.qml: workspace targetWidth block not found (duplicate elsewhere?)")
t = t.replace(old_tw, new_tw, 1)

old_ma = (
    "                                MouseArea {\n"
    "                                    id: wsPillMouse\n"
    "                                    hoverEnabled: true\n"
    "                                    anchors.fill: parent\n"
    "                                    onClicked: Quickshell.execDetached([\"bash\", \"-c\", \"~/.config/hypr/scripts/qs_manager.sh \" + wsName])\n"
    "                                }\n"
    "                            }\n"
)
new_ma = (
    "                                MouseArea {\n"
    "                                    id: wsPillMouse\n"
    "                                    hoverEnabled: true\n"
    "                                    anchors.fill: parent\n"
    "                                    onClicked: Quickshell.execDetached([\"bash\", \"-c\", \"~/.config/hypr/scripts/qs_manager.sh \" + wsName])\n"
    "                                }\n"
    "                                ToolTip {\n"
    "                                    parent: wsPill\n"
    "                                    x: (parent.width - width) / 2\n"
    "                                    y: parent.height + barWindow.s(4)\n"
    "                                    delay: 350\n"
    "                                    text: (model.wsTooltip && model.wsTooltip.length && model.wsTooltip !== \"Empty\") ? model.wsTooltip : (\"Workspace \" + model.wsId)\n"
    "                                    visible: wsPillMouse.containsMouse\n"
    "                                }\n"
    "                            }\n"
)
if old_ma not in t:
    sys.exit("TopBar.qml: workspace MouseArea + delegate end not found")
t = t.replace(old_ma, new_ma, 1)

p.write_text(t)
