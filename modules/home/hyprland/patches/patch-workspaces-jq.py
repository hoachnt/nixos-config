#!/usr/bin/env python3
"""workspaces.sh jq: bar uses workspaceCount only; last pill id is always end (never > end on bar)."""
import pathlib
import sys

out = pathlib.Path(sys.argv[1])
p = out / "quickshell/workspaces.sh"
if not p.is_file():
    sys.exit("workspaces.sh not found")
t = p.read_text()

marker = "# last pill id = end (no workspace id > end on bar)"
if marker in t:
    p.write_text(t)
    sys.exit(0)

upstream_old = """        # Create a map of workspace ID -> workspace data for easy lookup
        (map( { (.id|tostring): . } ) | add) as $s
        |
        # Iterate from 1 to SEQ_END
        [range(1; ($end|tonumber) + 1)] | map(
            . as $i |
            # Determine state: active -> occupied -> empty
            (if $i == $a then "active"
             elif ($s[$i|tostring] != null and $s[$i|tostring].windows > 0) then "occupied"
             else "empty" end) as $state |

            # Get window title for tooltip (if exists)
            (if $s[$i|tostring] != null then $s[$i|tostring].lastwindowtitle else "Empty" end) as $win |

            {
                id: $i,
                state: $state,
                tooltip: $win
            }
        )"""

prev_patch = """        # Create a map of workspace ID -> workspace data for easy lookup
        (map( { (.id|tostring): . } ) | add) as $s
        |
        ($end|tonumber) as $end
        | ($a|tonumber) as $a
        |
        # Static bar width: fixed 1..end-1; last slot shows max(end, active) for id when active > end
        [range(1; $end + 1)] | map(
            . as $slot |
            (if $slot < $end then $slot
             elif $a > $end then $a
             else $end end) as $wid |
            # Determine state: active -> occupied -> empty
            (if $wid == $a then "active"
             elif ($s[$wid|tostring] != null and $s[$wid|tostring].windows > 0) then "occupied"
             else "empty" end) as $state |

            # Get window title for tooltip (if exists)
            (if $s[$wid|tostring] != null then $s[$wid|tostring].lastwindowtitle else "Empty" end) as $win |

            {
                id: $wid,
                state: $state,
                tooltip: $win
            }
        )"""

new_jq = """        # Create a map of workspace ID -> workspace data for easy lookup
        (map( { (.id|tostring): . } ) | add) as $s
        |
        ($end|tonumber) as $end
        | ($a|tonumber) as $a
        |
        # last pill id = end (no workspace id > end on bar); last pill active if a==end or a>end
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

            {
                id: $wid,
                state: $state,
                tooltip: $win
            }
        )"""

if prev_patch in t:
    t = t.replace(prev_patch, new_jq, 1)
elif upstream_old in t:
    t = t.replace(upstream_old, new_jq, 1)
else:
    sys.exit("workspaces.sh: jq workspace block not found (upstream or prior patch)")
p.write_text(t)
