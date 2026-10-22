"""Update checks for the plugin's own git checkout, and applying them.

Every push to the tracked branch counts as an update, as in the desktop
app. Nothing changes until the reader asks; a failed check is silent, since
the panel has to stay useful offline. Applying hands over to Omarchy's own
`omarchy plugin update`, which fast-forwards the checkout and lets the shell
reload the plugin.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

_TIMEOUT = 15.0


@dataclass(frozen=True)
class Status:
    """`state` is unknown | current | outdated | failed."""

    state: str
    local: str = ""

    def to_dict(self) -> dict:
        return {"state": self.state, "local": self.local}


def _git(root: Path, *args: str, timeout: float = 5.0) -> tuple[bool, str]:
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_SSH_COMMAND="ssh -oBatchMode=yes")
    try:
        done = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True, text=True, timeout=timeout, env=env,
        )
    except (OSError, subprocess.SubprocessError):
        return False, ""
    return done.returncode == 0, done.stdout.strip()


def local_commit(root: Path) -> str:
    if not (root / ".git").exists():
        return ""
    ok, out = _git(root, "rev-parse", "HEAD")
    return out if ok else ""


def check(root: Path) -> Status:
    local = local_commit(root)
    if not local:
        return Status("unknown")
    ok, _ = _git(root, "fetch", "--quiet", "origin", "HEAD", timeout=_TIMEOUT)
    if not ok:
        return Status("unknown", local)
    ok, remote = _git(root, "rev-parse", "FETCH_HEAD")
    if not ok or not remote or remote == local:
        return Status("current", local)
    # A checkout sitting ahead of the branch (development) is not outdated.
    ahead, _ = _git(root, "merge-base", "--is-ancestor", remote, "HEAD")
    return Status("current" if ahead else "outdated", local)


def apply(plugin_id: str) -> bool:
    command = shutil.which("omarchy-plugin-update")
    if command is None:
        return False
    try:
        done = subprocess.run(
            [command, plugin_id, "--yes"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120.0,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return done.returncode == 0
