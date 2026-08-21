#!/usr/bin/env python3

"""Native messaging host for zen-auto-style.

Watches Omarchy's generated browser stylesheet and pushes live updates to the
extension via Firefox's native messaging protocol. Uses inotify (stdlib ctypes)
on Linux for instant, near-zero-idle-CPU file watching with an automatic
fallback to polling when inotify is unavailable.

Protocol version 1: messages are {"type": "stylesheet", "path": str,
"colorScheme": "light"|"dark", "css": str} on stdout. Errors are reported as
{"type": "error", "message": str}.
"""

import ctypes
import ctypes.util
import json
import os
import signal
import struct
import sys
import time
from pathlib import Path


PROTOCOL_VERSION = 1
MAX_STYLESHEET_BYTES = 4 * 1024 * 1024  # 4 MB safety cap
POLL_INTERVAL_SECONDS = 0.25
LOG_MAX_BYTES = 512 * 1024  # rotate debug log past 512 KB

HOME = Path.home()
TRIGGER = HOME / ".cache/zen-auto-style/reload"
LOG_PATH = HOME / ".cache/zen-auto-style/host.log"

OMARCHY_THEME_DIRS = (
    HOME / ".local/state/omarchy/current/theme",
    HOME / ".config/omarchy/current/theme",
)

# inotify constants (see inotify(7))
IN_MODIFY = 0x00000002
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
IN_WATCH_MASK = (
    IN_MODIFY | IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO |
    IN_DELETE_SELF | IN_MOVE_SELF
)

_debug_enabled = os.environ.get("ZEN_AUTO_STYLE_DEBUG") == "1"
_running = True


def debug(message, *args):
    if not _debug_enabled:
        return
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        if LOG_PATH.exists() and LOG_PATH.stat().st_size > LOG_MAX_BYTES:
            LOG_PATH.unlink()
        with LOG_PATH.open("a", encoding="utf-8") as handle:
            stamp = time.strftime("%Y-%m-%d %H:%M:%S")
            handle.write(f"[{stamp}] {message % args}\n")
    except OSError:
        pass


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
    except (FileNotFoundError, OSError):
        return None


def send_stylesheet(theme_dir):
    stylesheet = theme_dir / "custom-zen.css"
    light_mode_marker = theme_dir / "light.mode"
    try:
        raw = stylesheet.read_bytes()
    except (OSError, UnicodeError) as error:
        write_message({"type": "error", "message": str(error)})
        debug("stylesheet read failed: %s", error)
        return

    if len(raw) > MAX_STYLESHEET_BYTES:
        msg = (
            f"stylesheet exceeds {MAX_STYLESHEET_BYTES} bytes "
            f"(got {len(raw)}); refusing to send"
        )
        write_message({"type": "error", "message": msg})
        debug(msg)
        return

    try:
        css = raw.decode("utf-8")
    except UnicodeDecodeError as error:
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
            "protocolVersion": PROTOCOL_VERSION,
            "path": str(stylesheet),
            "colorScheme": color_scheme,
            "css": css,
        }
    )
    debug("sent stylesheet (%d bytes, %s)", len(css), color_scheme)


# --- inotify backend -------------------------------------------------------

class InotifyBackend:
    """inotify-based watcher with near-zero idle CPU. ctypes + stdlib only."""

    def __init__(self):
        self._libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
        self._fd = -1
        self._watches = {}  # wd -> path(str)

    @property
    def name(self):
        return "inotify"

    def start(self):
        self._libc.inotify_init1.restype = ctypes.c_int
        self._fd = self._libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self._fd < 0:
            err = ctypes.get_errno()
            raise OSError(err, os.strerror(err))
        return self

    def add(self, path):
        """Watch a path. Safe to call repeatedly; no-op if already watched."""
        path_str = str(path)
        if any(existing == path_str for existing in self._watches.values()):
            return
        self._libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        self._libc.inotify_add_watch.restype = ctypes.c_int
        wd = self._libc.inotify_add_watch(
            self._fd,
            path_str.encode("utf-8", errors="surrogateescape"),
            IN_WATCH_MASK,
        )
        if wd < 0:
            err = ctypes.get_errno()
            debug("inotify_add_watch failed for %s: %s", path_str, os.strerror(err))
            return
        self._watches[wd] = path_str
        debug("watching %s (wd=%d)", path_str, wd)

    def remove_theme_watches(self):
        for wd in list(self._watches):
            self._libc.inotify_rm_watch(self._fd, wd)
            self._watches.pop(wd, None)

    def poll(self, timeout_ms):
        """Return True if any watched event arrived within timeout_ms."""
        import select
        rlist, _, _ = select.select([self._fd], [], [], timeout_ms / 1000.0)
        if not rlist:
            return False
        try:
            chunk = os.read(self._fd, 65536)
        except BlockingIOError:
            return False
        except OSError:
            return False
        if not chunk:
            return False
        debug("inotify event chunk: %d bytes", len(chunk))
        return True

    def close(self):
        if self._fd >= 0:
            try:
                os.close(self._fd)
            except OSError:
                pass
            self._fd = -1


# --- polling fallback -------------------------------------------------------

class PollingBackend:
    """Fallback watcher: stat()s files on a timer."""

    def __init__(self):
        self._paths = []

    @property
    def name(self):
        return "polling"

    def start(self):
        return self

    def add(self, path):
        path_str = str(path)
        if path_str not in self._paths:
            self._paths.append(path_str)

    def remove_theme_watches(self):
        # Polling backend rebuilds paths each loop; nothing to remove.
        pass

    def poll(self, _timeout_ms):
        time.sleep(POLL_INTERVAL_SECONDS)
        return True  # always re-check signatures

    def close(self):
        pass


def make_backend():
    try:
        backend = InotifyBackend().start()
        debug("inotify backend ready (fd=%d)", backend._fd)
        return backend
    except (OSError, AttributeError) as error:
        debug("inotify unavailable, falling back to polling: %s", error)
        return PollingBackend().start()


# --- signal handling --------------------------------------------------------

def _handle_signal(signum, _frame):
    global _running
    _running = False
    debug("received signal %d, shutting down", signum)


def main():
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    TRIGGER.parent.mkdir(parents=True, exist_ok=True)
    TRIGGER.touch(exist_ok=True)

    backend = make_backend()
    debug("zen-auto-style host starting (backend=%s)", backend.name)

    theme_dir = resolve_theme_dir()
    stylesheet = theme_dir / "custom-zen.css"
    light_mode_marker = theme_dir / "light.mode"

    stylesheet_signature = None
    light_mode_signature = None
    trigger_signature = None
    last_theme_dir = theme_dir

    def refresh_watches():
        backend.remove_theme_watches()
        for path in (TRIGGER, stylesheet, light_mode_marker):
            if path.exists():
                backend.add(path)
        backend.add(theme_dir)

    refresh_watches()

    while _running:
        # Re-resolve theme dir at runtime: if the active layout changed
        # (migration config -> state) or the dir (re)appeared, follow it.
        resolved = resolve_theme_dir()
        if resolved != last_theme_dir:
            debug("theme dir changed: %s -> %s", last_theme_dir, resolved)
            last_theme_dir = resolved
            theme_dir = resolved
            stylesheet = theme_dir / "custom-zen.css"
            light_mode_marker = theme_dir / "light.mode"
            refresh_watches()

        if backend.poll(250):
            next_stylesheet_sig = file_signature(stylesheet)
            next_light_mode_sig = file_signature(light_mode_marker)
            next_trigger_sig = file_signature(TRIGGER)

            if (
                next_stylesheet_sig != stylesheet_signature
                or next_light_mode_sig != light_mode_signature
                or next_trigger_sig != trigger_signature
            ):
                stylesheet_signature = next_stylesheet_sig
                light_mode_signature = next_light_mode_sig
                trigger_signature = next_trigger_sig
                if stylesheet_signature is not None:
                    send_stylesheet(theme_dir)
                # inotify: re-add watches on files that may have been replaced
                # (common pattern: renderers write a temp file then rename).
                if backend.name == "inotify":
                    refresh_watches()

    backend.close()
    debug("host exiting cleanly")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
    except Exception as error:
        debug("fatal: %s", error)
        try:
            write_message({"type": "error", "message": f"host crashed: {error}"})
        except Exception:
            pass
        raise
