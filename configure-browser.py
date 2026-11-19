#!/usr/bin/env python3
"""Persist the camera backend for the next Chrome or Firefox launch."""

import argparse
import json
import os
from pathlib import Path
import re
import stat
import tempfile

CHROME_FLAG = "enable-webrtc-pipewire-camera"
FIREFOX_PREF = "media.webrtc.camera.allow-pipewire"
FIREFOX_BEGIN = "// BEGIN LAPBC710 camera"
FIREFOX_END = "// END LAPBC710 camera"


def write_atomic(path, content):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(content)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def chrome(args):
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    profile = args.profile or config / "google-chrome"
    if os.path.lexists(profile / "SingletonLock"):
        raise SystemExit("Quit Chrome completely before editing Local State.")
    path = profile / "Local State"
    data = json.loads(path.read_text())
    browser = data.setdefault("browser", {})
    original = browser.get("enabled_labs_experiments", [])
    flags = [flag for flag in original if flag.partition("@")[0] != CHROME_FLAG]
    if not args.default:
        flags.append(f"{CHROME_FLAG}@1")
    if flags != original:
        browser["enabled_labs_experiments"] = flags
        write_atomic(path, json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")


def firefox(args):
    profile = args.profile
    if profile is None or not (profile / "prefs.js").is_file():
        raise SystemExit("Pass the Firefox profile directory from about:profiles with --profile.")
    # Firefox reads user.js at startup and does not write to it.
    path = profile / "user.js"
    original = path.read_text() if path.exists() else ""
    block = rf"(?m)^{re.escape(FIREFOX_BEGIN)}\n[^\n]*\n{re.escape(FIREFOX_END)}\n?"
    text = re.sub(block, "", original)
    if not args.default:
        if FIREFOX_PREF in text:
            raise SystemExit("This Firefox user.js already defines the camera preference. Review that entry first.")
        if text and not text.endswith("\n"):
            text += "\n"
        text += f'{FIREFOX_BEGIN}\nuser_pref("{FIREFOX_PREF}", true);\n{FIREFOX_END}\n'
    if text != original:
        write_atomic(path, text)
    if args.default:
        print(f"Reset {FIREFOX_PREF} in about:config to clear Firefox’s stored preference too.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("browser", choices=("chrome", "firefox"))
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--default", action="store_true", help="remove the managed override")
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error("Run as your desktop user.")
    (chrome if args.browser == "chrome" else firefox)(args)
    print(f"{args.browser} camera setting saved for the next launch.")


if __name__ == "__main__":
    main()
