"""cava, which draws the spectrum in the mixer's title room.

The panel runs cava itself, and only while it is open (Service.qml). This side
makes sure it is installed. cava is in Arch's extra repository and needs root
to install, so it goes through pkexec and the shell's polkit prompt, and a
password prompt must never come out of nowhere. Sonus asks on its own only
right after an update, whose "Sonus updated" notification says the prompt is
next (`mark_pending`), and only if the Visualizer switch is on. A closed
prompt is a no for good: only the settings page's Install button asks again.

pacman runs in a transient unit of its own, so a shell restart in the middle
does not end it, and the next engine finds cava there.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

PACKAGE = "cava"
UNIT = "sonus-cava-install"
# pacman downloads cava and its few libraries; past this, something hangs.
INSTALL_LIMIT = 900.0
# pkexec's own exit codes for a closed or refused prompt. 127 is also what it
# gives when no polkit agent is running to show a prompt at all.
PROMPT_CLOSED = (126, 127)
NO_AGENT = "No authentication agent"
# What install() returns when pkexec never ran, so no prompt showed.
NOT_RUN = -2
# An update's ask waits for the engine after the shell restart; past this the
# update is old news and nothing on screen explains a prompt any more.
PENDING_FRESH = 1800.0


@dataclass
class Result:
    ok: bool
    code: int = 0
    # pkexec found no polkit agent: no prompt showed, so it can try again soon.
    no_agent: bool = False
    message: str = ""

    @property
    def declined(self) -> bool:
        return not self.ok and not self.no_agent and self.code in PROMPT_CLOSED

    @property
    def prompted(self) -> bool:
        """A password prompt really showed: anything that got past pkexec."""
        return self.ok or self.declined or (self.code not in PROMPT_CLOSED and self.code > 0)


def installed() -> bool:
    return shutil.which("cava") is not None


def _state_path() -> Path:
    value = os.environ.get("XDG_STATE_HOME")
    return (Path(value) if value else Path.home() / ".local/state") / "sonus" / "cava.json"


def read_state() -> dict:
    try:
        data = json.loads(_state_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def write_state(data: dict) -> None:
    path = _state_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data), encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass


def declined() -> bool:
    return bool(read_state().get("declined"))


def will_ask(enabled: bool) -> bool:
    """Whether an update should tell the user a prompt comes next."""
    return enabled and not installed() and not declined()


def mark_pending(version: str) -> None:
    """An update just said on the desktop that cava's prompt comes next."""
    state = read_state()
    state.update({"pending": version, "at": time.time()})
    write_state(state)


def should_ask(enabled: bool) -> bool:
    """Ask on our own: only right after an update said so, with the Visualizer
    on, never once declined, and once per version."""
    if not enabled or installed():
        return False
    state = read_state()
    pending = state.get("pending")
    if state.get("declined") or not pending or state.get("asked") == pending:
        return False
    return time.time() - float(state.get("at") or 0) < PENDING_FRESH


def record(result: Result, version: str) -> None:
    """Remember how an ask went. Only a prompt that really showed counts."""
    if result.ok:
        write_state({})
        return
    if result.declined:
        write_state({"declined": True})
        return
    if result.prompted:
        state = read_state()
        state["asked"] = state.get("pending") or version
        write_state(state)


def forget_decline() -> None:
    """The Install button: the user asks, so the old no is gone."""
    state = read_state()
    if state.pop("declined", None) is not None:
        write_state(state)


def _systemctl(*args: str) -> str:
    try:
        done = subprocess.run(["systemctl", "--user", *args], capture_output=True,
                              text=True, timeout=5.0, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.strip()


def running() -> bool:
    """An install another engine started is still going."""
    return shutil.which("systemctl") is not None and _systemctl("is-active", UNIT) in ("active", "activating")


def wait_running(limit: float = INSTALL_LIMIT) -> None:
    deadline = time.monotonic() + limit
    while running() and time.monotonic() < deadline:
        time.sleep(1.0)


# The reason alone; the settings page says what to do about it.
def failure(code: int, no_agent: bool = False) -> str:
    if no_agent:
        return "No password prompt could open"
    if code in PROMPT_CLOSED:
        return "The password prompt was closed"
    return "pacman could not install cava. Update the system (omarchy update) and try again"


def install() -> Result:
    """Install cava and wait for it."""
    if installed():
        return Result(True)
    if shutil.which("pacman") is None:
        return Result(False, NOT_RUN, message="Install cava with your package manager")
    if shutil.which("pkexec") is None:
        return Result(False, NOT_RUN, message="pkexec is missing, so install cava with pacman")
    if running():
        wait_running()
        return Result(True) if installed() else Result(False, NOT_RUN, message=failure(1))
    command = ["pkexec", "pacman", "-S", "--needed", "--noconfirm", PACKAGE]
    code, err = -1, ""
    if shutil.which("systemd-run"):
        _systemctl("reset-failed", UNIT)
        try:
            # --pipe hands pkexec's stderr back, to tell a missing polkit agent
            # from a closed prompt; both exit 127.
            done = subprocess.run(
                ["systemd-run", "--user", "--quiet", "--collect", "--wait", "--pipe", f"--unit={UNIT}",
                 "--description=Install cava for the Sonus visualizer",
                 f"--setenv=PATH={os.environ.get('PATH', '/usr/bin')}", *command],
                capture_output=True, text=True, timeout=INSTALL_LIMIT, stdin=subprocess.DEVNULL,
            )
            code, err = done.returncode, done.stderr or ""
        except subprocess.TimeoutExpired:
            return Result(False, 1, message="pacman took too long to install cava")
        except (OSError, subprocess.SubprocessError):
            code = -1
    if code == -1:
        try:
            done = subprocess.run(command, capture_output=True, text=True, timeout=INSTALL_LIMIT,
                                  stdin=subprocess.DEVNULL)
            code, err = done.returncode, done.stderr or ""
        except (OSError, subprocess.SubprocessError):
            code = 1
    if installed():
        return Result(True)
    no_agent = code in PROMPT_CLOSED and NO_AGENT in err
    return Result(False, code, no_agent, failure(code, no_agent))
