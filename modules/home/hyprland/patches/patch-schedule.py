"""Patch ilyamiro schedule widget: portable Firefox profile, no fake Error rows, purge bad cache."""
import pathlib
import sys


def main() -> None:
    out = pathlib.Path(sys.argv[1])
    patch_get_schedule(out)
    patch_schedule_manager(out)


def patch_schedule_manager(out: pathlib.Path) -> None:
    p = out / "quickshell/calendar/schedule/schedule_manager.sh"
    if not p.is_file():
        return
    t = p.read_text()
    needle = 'mkdir -p "$CACHE_DIR"\n\ntrigger_update() {'
    insert = (
        'mkdir -p "$CACHE_DIR"\n\n'
        "# Drop stale schedule.json from failed Selenium runs (e.g. missing Firefox profile).\n"
        'if [ -f "$CACHE_FILE" ] && grep -qF \'"header": "Error"\' "$CACHE_FILE" 2>/dev/null; then\n'
        '  rm -f "$CACHE_FILE"\n'
        "fi\n\n"
        "trigger_update() {"
    )
    if needle not in t:
        sys.exit("schedule_manager.sh: insert point after mkdir not found")
    t = t.replace(needle, insert, 1)
    p.write_text(t)


def patch_get_schedule(out: pathlib.Path) -> None:
    p = out / "quickshell/calendar/schedule/get_schedule.py"
    if not p.is_file():
        return
    t = p.read_text()

    old_profile = 'PROFILE_PATH = "/home/ilyamiro/.mozilla/firefox/schedule.special"'
    new_profile = (
        "PROFILE_PATH = os.environ.get(\n"
        '    "QUICKSHELL_SCHEDULE_FF_PROFILE",\n'
        '    os.path.expanduser("~/.mozilla/firefox/schedule.special"),\n'
        ")"
    )
    if old_profile not in t:
        sys.exit("get_schedule.py: ilyamiro PROFILE_PATH line not found")
    t = t.replace(old_profile, new_profile, 1)

    old_start = """def update_schedule():
    options = Options()"""
    new_start = """def update_schedule():
    if not os.path.isdir(PROFILE_PATH):
        output = {"header": "No Classes Found", "lessons": [], "link": GENERIC_URL}
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        with open(CACHE_FILE, "w") as f:
            json.dump(output, f)
        return

    options = Options()"""
    if old_start not in t:
        sys.exit("get_schedule.py: update_schedule() start block not found")
    t = t.replace(old_start, new_start, 1)

    old_ex = (
        '        output = {"header": "Error", "lessons": [{"type": "class", "time": "Error", '
        '"subject": "Check Script", "room": "!", "teacher": str(e), "start": 0, "end": 0, '
        '"width": 100, "char_limit": 10}], "link": ""}'
    )
    new_ex = '        output = {"header": "No Classes Found", "lessons": [], "link": GENERIC_URL}'
    if old_ex not in t:
        sys.exit("get_schedule.py: exception output line not found")
    t = t.replace(old_ex, new_ex, 1)

    p.write_text(t)


if __name__ == "__main__":
    main()

