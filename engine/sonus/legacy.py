"""The Sonus desktop app (PyQt), which this plugin replaces.

Both programs drive the same sinks from the same settings file. Running
together they would fight: the desktop app re-asserts the routes it holds in
memory every second, so an app moved here would be moved straight back. While
it runs, the engine leaves routing and the graph alone, and the panel offers
to take over.

Taking over stops the desktop app and switches off how it starts with the
session (its XDG autostart entry and systemd user unit), the same things its
own "Start with system" switch turns off. Nothing is uninstalled:
`sonusdeck` still runs by hand.
"""

from __future__ import annotations

import os
import signal
import subprocess
import time
from pathlib import Path

from .config import CONFIG_HOME

UNIT = "sonusdeck.service"
AUTOSTART_PATH = CONFIG_HOME / "autostart" / "sonusdeck.desktop"
UNIT_PATH = CONFIG_HOME / "systemd" / "user" / UNIT
_MARKERS = (b"sonus_deck.py", b"-msonusdeck", b"-m\x00sonusdeck")


def pids() -> list[int]:
    found: list[int] = []
    me = os.getpid()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        if pid == me:
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes()
        except OSError:
            continue
        if b"python" in cmdline and any(marker in cmdline for marker in _MARKERS):
            found.append(pid)
    return found


def running() -> bool:
    return bool(pids())


def _systemctl(*args: str) -> None:
    try:
        subprocess.run(["systemctl", "--user", *args], capture_output=True, timeout=10.0)
    except (OSError, subprocess.SubprocessError):
        pass


def take_over(settings: dict) -> None:
    """Stop the desktop app for good. The caller starts the plugin's graph
    right after, since the app's graph goes down with its unit."""
    _systemctl("disable", "--now", UNIT)
    try:
        UNIT_PATH.unlink(missing_ok=True)
    except OSError:
        pass
    _systemctl("daemon-reload")
    try:
        AUTOSTART_PATH.unlink(missing_ok=True)
    except OSError:
        pass
    for pid in pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            continue
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline and pids():
        time.sleep(0.1)
    # Should the desktop app ever be launched by hand again, it reads this
    # and leaves autostart off rather than re-registering itself.
    settings["autostart"] = False
