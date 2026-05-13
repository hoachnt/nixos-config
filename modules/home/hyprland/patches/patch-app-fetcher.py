#!/usr/bin/env python3
"""
Patch app_fetcher.py to include the Home Manager per-user profile
applications directory, which is where most HM-managed .desktop
files live on NixOS.
"""
import pathlib, sys, os

out = pathlib.Path(sys.argv[1])
p = out / "quickshell/applauncher/app_fetcher.py"
if not p.is_file():
    sys.exit("app_fetcher.py not found")

t = p.read_text()

# The current script only looks in ~/.nix-profile/share/applications
# but Home Manager installs .desktop files to /etc/profiles/per-user/<user>/share/applications
# Also add the home-manager generation path as a fallback.
old_dirs = "f'{home}/.nix-profile/share/applications',"
new_dirs = (
    "f'{home}/.nix-profile/share/applications',\n"
    "        # NixOS Home Manager per-user profile (most HM apps live here)\n"
    "        f'/etc/profiles/per-user/{os.environ.get(\"USER\", \"nobody\")}/share/applications',\n"
    "        f'{home}/.local/state/nix/profiles/home-manager/home-files/.local/share/applications',"
)

if old_dirs in t:
    t = t.replace(old_dirs, new_dirs, 1)
else:
    print("Warning: nix-profile applications line not found (already patched?)", file=sys.stderr)

p.write_text(t)
print("app_fetcher.py patched successfully")
