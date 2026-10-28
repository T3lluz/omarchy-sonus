"""Update checks for the plugin's own git checkout, and applying them.

Every push to the tracked branch counts as an update, as in the desktop
app. Nothing changes until the reader asks; a failed check only says so,
since the panel has to stay useful offline.

Applying hands over to Omarchy's own `omarchy plugin update`, run detached
from the engine. The update rewrites files in the plugin folder, and the
shell reloads every plugin the moment a file there changes, which ends this
engine. A child of the engine would die with it halfway through, after the
merge and before validation, and the update script would roll itself back.
So the runner lives in its own transient unit and leaves its result in
~/.local/state/sonus, where the next engine picks it up.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

_TIMEOUT = 15.0
UNIT = "sonus-update"
# A result older than this is history, not news.
RESULT_FRESH = 600.0
# A runner that has not finished by now is gone.
RUN_LIMIT = 240.0


def _state_dir() -> Path:
    value = os.environ.get("XDG_STATE_HOME")
    return (Path(value) if value else Path.home() / ".local/state") / "sonus"


def result_path() -> Path:
    return _state_dir() / "update.json"


def log_path() -> Path:
    return _state_dir() / "update.log"


@dataclass(frozen=True)
class Status:
    """`state` is unmanaged | current | outdated | offline | failed.

    `modified` means the checkout has local edits; the update sets them
    aside with `git stash` rather than refusing.
    """

    state: str
    local: str = ""
    remote: str = ""
    version: str = ""
    summary: str = ""
    behind: int = 0
    modified: bool = False
    message: str = ""
    checked: float = 0.0

    def to_dict(self) -> dict:
        return asdict(self)


def _git(root: Path, *args: str, timeout: float = 5.0) -> tuple[bool, str]:
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_SSH_COMMAND="ssh -oBatchMode=yes")
    try:
        done = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True, text=True, timeout=timeout, env=env,
            stdin=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError):
        return False, ""
    return done.returncode == 0, done.stdout.strip()


def is_checkout(root: Path) -> bool:
    return (root / ".git").exists()


def local_commit(root: Path) -> str:
    if not is_checkout(root):
        return ""
    ok, out = _git(root, "rev-parse", "HEAD")
    return out if ok else ""


def modified(root: Path) -> bool:
    """Tracked edits or untracked files, ignoring what .gitignore covers."""
    ok, out = _git(root, "status", "--porcelain")
    return ok and bool(out)


def manifest_version(text: str) -> str:
    try:
        data = json.loads(text)
    except (TypeError, ValueError):
        return ""
    version = data.get("version") if isinstance(data, dict) else None
    return str(version) if isinstance(version, str) else ""


def installed_version(root: Path) -> str:
    try:
        return manifest_version((root / "manifest.json").read_text(encoding="utf-8"))
    except OSError:
        return ""


def check(root: Path) -> Status:
    now = time.time()
    local = local_commit(root)
    if not local:
        return Status("unmanaged", checked=now)
    dirty = modified(root)
    ok, _ = _git(root, "fetch", "--quiet", "origin", "HEAD", timeout=_TIMEOUT)
    if not ok:
        return Status("offline", local, modified=dirty, checked=now)
    ok, remote = _git(root, "rev-parse", "FETCH_HEAD")
    if not ok or not remote or remote == local:
        return Status("current", local, remote, modified=dirty, checked=now)
    # A checkout sitting ahead of the branch (development) is not outdated.
    ahead, _ = _git(root, "merge-base", "--is-ancestor", remote, "HEAD")
    if ahead:
        return Status("current", local, remote, modified=dirty, checked=now)
    _, text = _git(root, "show", "FETCH_HEAD:manifest.json")
    _, summary = _git(root, "log", "-1", "--format=%s", "FETCH_HEAD")
    _, count = _git(root, "rev-list", "--count", "HEAD..FETCH_HEAD")
    return Status(
        "outdated", local, remote,
        version=manifest_version(text),
        summary=summary,
        behind=int(count) if count.isdigit() else 0,
        modified=dirty,
        checked=now,
    )


# ----- applying ------------------------------------------------------------


def _write_result(data: dict) -> None:
    path = result_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    tmp.replace(path)


def read_result() -> dict | None:
    try:
        data = json.loads(result_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def clear_result() -> None:
    try:
        result_path().unlink()
    except OSError:
        pass


def running(result: dict | None) -> bool:
    """A runner that said it started and has not reported back yet."""
    if not result or not result.get("running"):
        return False
    return time.time() - float(result.get("at") or 0) < RUN_LIMIT


def start(root: Path, plugin_id: str) -> str:
    """Launch the detached runner. Returns "" or why it could not start."""
    if shutil.which("omarchy-plugin-update") is None:
        return "omarchy plugin update is missing"
    if not is_checkout(root):
        return "Not installed from git"
    if running(read_result()):
        return ""
    _write_result({"running": True, "at": time.time()})
    runner = [sys.executable or "python3", "-I", str(root / "bin" / "sonus-engine"),
              "--plugin-dir", str(root), "--plugin-id", plugin_id, "--apply-update"]
    if shutil.which("systemd-run"):
        subprocess.run(["systemctl", "--user", "reset-failed", UNIT],
                       capture_output=True, timeout=5.0)
        try:
            done = subprocess.run(
                ["systemd-run", "--user", "--quiet", "--collect", f"--unit={UNIT}",
                 "--description=Sonus plugin update",
                 f"--setenv=PATH={os.environ.get('PATH', '/usr/bin')}", *runner],
                capture_output=True, text=True, timeout=10.0,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            done = None
            error = str(exc)
        if done is not None and done.returncode == 0:
            return ""
        error = (done.stderr.strip() if done is not None else error) or "systemd-run failed"
        if "already" in error.lower():
            return ""
    try:
        subprocess.Popen(runner, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as exc:
        clear_result()
        return str(exc)
    return ""


def notify(title: str, body: str) -> None:
    if shutil.which("notify-send") is None:
        return
    try:
        subprocess.run(["notify-send", "--app-name=Sonus", "--icon=audio-card", title, body],
                       capture_output=True, timeout=5.0)
    except (OSError, subprocess.SubprocessError):
        pass


def _last_line(text: str) -> str:
    lines = [line.strip() for line in (text or "").splitlines() if line.strip()]
    line = lines[-1] if lines else ""
    return line.removeprefix("omarchy-plugin-update: ")


def run(root: Path, plugin_id: str) -> dict:
    """The detached half: set local edits aside, update, record the outcome."""
    started = time.time()
    _write_result({"running": True, "at": started})
    before = local_commit(root)
    previous = installed_version(root)
    stashed = False
    message = ""
    ok = False
    output = ""
    if modified(root):
        stashed, _ = _git(root, "stash", "push", "--include-untracked",
                          "--message", "Sonus: local changes set aside by the panel's update",
                          timeout=30.0)
        if not stashed:
            message = "Local changes in the plugin folder could not be set aside"
    if not message:
        try:
            done = subprocess.run(
                ["omarchy-plugin-update", plugin_id, "--yes"],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=180.0,
            )
            ok = done.returncode == 0
            output = (done.stdout or "") + (done.stderr or "")
            if not ok:
                message = _last_line(done.stderr) or _last_line(done.stdout) or "The update failed"
        except (OSError, subprocess.SubprocessError) as exc:
            message = str(exc)
    after = local_commit(root)
    if not ok and stashed:
        # Nothing moved, so the edits go back where they were.
        _git(root, "stash", "pop", timeout=30.0)
        stashed = False
    result = {
        "running": False,
        "ok": ok and after != before,
        "current": ok and after == before,
        "from": before,
        "to": after,
        "previous": previous,
        "version": installed_version(root),
        "stashed": stashed,
        "message": message,
        "at": time.time(),
    }
    try:
        log_path().write_text(output, encoding="utf-8")
    except OSError:
        pass
    _write_result(result)
    return result
