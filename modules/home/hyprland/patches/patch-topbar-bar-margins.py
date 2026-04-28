#!/usr/bin/env python3
"""TopBar.qml: top/bottom margins + exclusiveZone + strut height (see Main.qml topBarHole)."""
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
p = out / "quickshell/TopBar.qml"
if not p.is_file():
    sys.exit("TopBar.qml not found")
t = p.read_text()

# s(48)+s(4)+s(2) = 54 at uiScale 1.0 — slightly less bottom than top (fixes perceived larger bottom gap)
new = """            // Top margin s(4), bottom s(2): visual balance; exclusiveZone = bar + margins
            height: barHeight
            margins { top: s(4); bottom: s(2); left: s(4); right: s(4) }
            
            exclusiveZone: barHeight + s(4) + s(2)"""

upstream = """            // THICKER BAR, MINIMAL MARGINS (Scaled)
            height: barHeight
            margins { top: s(8); bottom: 0; left: s(4); right: s(4) }
            
            // exclusiveZone = height + top margin
            exclusiveZone: barHeight + s(4)"""

eq4 = """            // Equal top/bottom margins (scaled); exclusiveZone matches full vertical strut
            height: barHeight
            margins { top: s(4); bottom: s(4); left: s(4); right: s(4) }
            
            exclusiveZone: barHeight + s(4) + s(4)"""

if "Top margin s(4), bottom s(2)" in t:
    p.write_text(t)
    sys.exit(0)
if upstream in t:
    t = t.replace(upstream, new, 1)
elif eq4 in t:
    t = t.replace(eq4, new, 1)
else:
    sys.exit("TopBar.qml: expected margins block (upstream or prior patch) not found")
p.write_text(t)
