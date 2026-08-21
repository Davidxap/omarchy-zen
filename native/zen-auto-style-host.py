#!/usr/bin/env python3

import json
import struct
import sys
import time
from pathlib import Path


HOME = Path.home()
TRIGGER = HOME / ".cache/zen-auto-style/reload"
POLL_INTERVAL_SECONDS = 0.25

OMARCHY_THEME_DIRS = (
    HOME / ".local/state/omarchy/current/theme",
    HOME / ".config/omarchy/current/theme",
)


def resolve_theme_dir():
    """Resolve the Omarchy theme directory for both 4.x and legacy layouts."""
    for theme_dir in OMARCHY_THEME_DIRS:
        try:
            if theme_dir.is_dir():
                return theme_dir
        except OSError:
            pass
    return OMARCHY_THEME_DIRS[0]


def write_message(message):
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(payload)))
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()


def file_signature(path):
    try:
        stat = path.stat()
        return stat.st_mtime_ns, stat.st_size, stat.st_ino
    except FileNotFoundError:
        return None


def send_stylesheet(theme_dir):
    stylesheet = theme_dir / "custom-zen.css"
    light_mode_marker = theme_dir / "light.mode"
    try:
        css = stylesheet.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        write_message({"type": "error", "message": str(error)})
        return

    color_scheme = "light" if light_mode_marker.is_file() else "dark"
    css += (
        "\n\n:root {\n"
        f"  color-scheme: {color_scheme} !important;\n"
        f"  --custom-zen-color-scheme: {color_scheme};\n"
        "}\n"
    )

    write_message(
        {
            "type": "stylesheet",
            "path": str(stylesheet),
            "colorScheme": color_scheme,
            "css": css,
        }
    )


def main():
    TRIGGER.parent.mkdir(parents=True, exist_ok=True)
    TRIGGER.touch(exist_ok=True)

    theme_dir = resolve_theme_dir()
    stylesheet = theme_dir / "custom-zen.css"
    light_mode_marker = theme_dir / "light.mode"

    stylesheet_signature = None
    light_mode_signature = None
    trigger_signature = None

    while True:
        next_stylesheet_signature = file_signature(stylesheet)
        next_light_mode_signature = file_signature(light_mode_marker)
        next_trigger_signature = file_signature(TRIGGER)

        if (
            next_stylesheet_signature != stylesheet_signature
            or next_light_mode_signature != light_mode_signature
            or next_trigger_signature != trigger_signature
        ):
            stylesheet_signature = next_stylesheet_signature
            light_mode_signature = next_light_mode_signature
            trigger_signature = next_trigger_signature
            if stylesheet_signature is not None:
                send_stylesheet(theme_dir)

        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
