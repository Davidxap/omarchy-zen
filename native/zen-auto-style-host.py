#!/usr/bin/env python3

import json
import struct
import sys
import time
from pathlib import Path


HOME = Path.home()
STYLESHEET = HOME / ".config/omarchy/current/theme/custom-zen.css"
LIGHT_MODE_MARKER = HOME / ".config/omarchy/current/theme/light.mode"
TRIGGER = HOME / ".cache/zen-auto-style/reload"
POLL_INTERVAL_SECONDS = 0.25


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


def send_stylesheet():
    try:
        css = STYLESHEET.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        write_message({"type": "error", "message": str(error)})
        return

    color_scheme = "light" if LIGHT_MODE_MARKER.is_file() else "dark"
    css += (
        "\n\n:root {\n"
        f"  color-scheme: {color_scheme} !important;\n"
        f"  --custom-zen-color-scheme: {color_scheme};\n"
        "}\n"
    )

    write_message(
        {
            "type": "stylesheet",
            "path": str(STYLESHEET),
            "colorScheme": color_scheme,
            "css": css,
        }
    )


def main():
    TRIGGER.parent.mkdir(parents=True, exist_ok=True)
    TRIGGER.touch(exist_ok=True)

    stylesheet_signature = None
    light_mode_signature = None
    trigger_signature = None

    while True:
        next_stylesheet_signature = file_signature(STYLESHEET)
        next_light_mode_signature = file_signature(LIGHT_MODE_MARKER)
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
                send_stylesheet()

        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
