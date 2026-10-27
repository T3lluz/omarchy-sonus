"""Channel definitions and the on-disk settings.

The plugin keeps the Sonus desktop app's on-disk identity on purpose: the
same `sonusdeck_*` sink names, the same ~/.config/sonusdeck directory and the
same settings.json. Apps that remember "Sonus Chat" as their output keep
finding it, saved routes and EQ curves carry over, and a graph the desktop
app started is adopted instead of restarted, so switching causes no gap.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

APP_NAME = "Sonus"
APP_ID = "sonusdeck"
NODE_PREFIX = "sonusdeck"


@dataclass(frozen=True)
class Channel:
    key: str
    label: str
    kind: str  # "master" | "sink"

    @property
    def node_name(self) -> str:
        return f"{NODE_PREFIX}_{self.key}"

    @property
    def description(self) -> str:
        return f"{APP_NAME} {self.label.title()}"


CHANNELS: tuple[Channel, ...] = (
    Channel("master", "MASTER", "master"),
    Channel("game", "GAME", "sink"),
    Channel("chat", "CHAT", "sink"),
    Channel("media", "MEDIA", "sink"),
    Channel("aux", "AUX", "sink"),
)

SINK_CHANNELS = tuple(c for c in CHANNELS if c.kind == "sink")
SINK_KEYS = tuple(c.key for c in SINK_CHANNELS)
CHANNEL_BY_KEY = {c.key: c for c in CHANNELS}


def _xdg(var: str, fallback: str) -> Path:
    value = os.environ.get(var)
    return Path(value) if value else Path.home() / fallback


CONFIG_HOME = _xdg("XDG_CONFIG_HOME", ".config")
CONFIG_DIR = CONFIG_HOME / APP_ID
SETTINGS_PATH = CONFIG_DIR / "settings.json"
GRAPH_CONF = "graph.conf"
GRAPH_CONF_PATH = CONFIG_DIR / GRAPH_CONF

DEFAULTS: dict = {
    "manage_graph": True,
    "routes": {},
    "eq": {},
    "profiles": {},
    "active_profile": "",
}


def load_settings() -> dict:
    data = json.loads(json.dumps(DEFAULTS))
    try:
        with open(SETTINGS_PATH, encoding="utf-8") as fh:
            stored = json.load(fh)
        if isinstance(stored, dict):
            data.update(stored)
    except (OSError, json.JSONDecodeError):
        pass
    if not isinstance(data.get("routes"), dict):
        data["routes"] = {}
    if not isinstance(data.get("profiles"), dict):
        data["profiles"] = {}
    if not isinstance(data.get("active_profile"), str):
        data["active_profile"] = ""
    return data


def save_settings(data: dict) -> None:
    """Atomic write. Keys this plugin does not use (the desktop app's window
    position, its autostart flag) are carried through untouched."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS_PATH.with_suffix(".json.tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    tmp.replace(SETTINGS_PATH)
