#!/usr/bin/env python3
"""TopBar.qml: top/bottom margins + exclusiveZone + strut height (see Main.qml topBarHole)."""
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
p = out / "quickshell/TopBar.qml"
if not p.is_file():
    sys.exit("TopBar.qml not found")
t = p.read_text()

# s(48)+s(4)+s(4) = 56 at uiScale 1.0
new = """            height: barHeight
            margins { top: s(4); bottom: s(4); left: s(4); right: s(4) }
            exclusiveZone: barHeight + s(4) + s(4) """

upstream = """            height: barHeight
            margins { top: s(8); bottom: 0; left: s(4); right: s(4) }
            exclusiveZone: barHeight """

if upstream in t:
    t = t.replace(upstream, new, 1)
else:
    sys.exit("TopBar.qml: expected margins block not found")

p.write_text(t)
