"""Per-output-device mixer profiles.

AirPods and the laptop speakers are different devices, so each keeps its own
output volume, channel volumes and channel equalizers. The profile key follows
the hardware, not the PipeWire node id: a Bluetooth device reconnects under a
new node but the same address, and the A2DP and headset profiles of one pair
of buds share a curve.

The live `eq` object in settings.json stays the curve of whichever device is
current, which is what the Sonus desktop app reads. The other devices live
under `profiles`.
"""

from __future__ import annotations

import re

from . import eq as eqmod
from .config import NODE_PREFIX, SINK_KEYS

_MAC = re.compile(
    r"([0-9a-f]{2})[:_]([0-9a-f]{2})[:_]([0-9a-f]{2})"
    r"[:_]([0-9a-f]{2})[:_]([0-9a-f]{2})[:_]([0-9a-f]{2})",
    re.IGNORECASE,
)


class Mix:
    """Volume and mute for one channel or the hardware output."""

    def __init__(self, volume: float = 1.0, muted: bool = False) -> None:
        self.volume = max(0.0, min(1.0, float(volume)))
        self.muted = bool(muted)

    def to_dict(self) -> dict:
        return {"volume": round(self.volume, 4), "muted": self.muted}

    @classmethod
    def from_dict(cls, data: object) -> "Mix":
        if not isinstance(data, dict):
            return cls()
        try:
            volume = float(data.get("volume", 1.0))
        except (TypeError, ValueError):
            volume = 1.0
        return cls(volume, bool(data.get("muted", False)))


class Profile:
    def __init__(
        self,
        label: str = "",
        volume: float = 1.0,
        muted: bool = False,
        channels: dict[str, Mix] | None = None,
        eqs: dict[str, eqmod.ChannelEq] | None = None,
    ) -> None:
        self.label = label
        self.volume = max(0.0, min(1.0, float(volume)))
        self.muted = bool(muted)
        self.channels = channels if channels is not None else {}
        self.eqs = eqs if eqs is not None else {}

    def normalized(self) -> "Profile":
        channels = {key: (self.channels.get(key) or Mix()) for key in SINK_KEYS}
        eqs = {key: (self.eqs.get(key) or eqmod.ChannelEq()).normalized() for key in SINK_KEYS}
        return Profile(self.label, self.volume, self.muted, channels, eqs)

    def to_dict(self) -> dict:
        state = self.normalized()
        return {
            "label": state.label,
            "volume": round(state.volume, 4),
            "muted": state.muted,
            "channels": {key: mix.to_dict() for key, mix in state.channels.items()},
            "eq": {key: eq.to_dict() for key, eq in state.eqs.items()},
        }

    @classmethod
    def from_dict(cls, data: object) -> "Profile":
        if not isinstance(data, dict):
            return cls().normalized()
        try:
            volume = float(data.get("volume", 1.0))
        except (TypeError, ValueError):
            volume = 1.0
        channels_raw = data.get("channels")
        if not isinstance(channels_raw, dict):
            channels_raw = {}
        eqs_raw = data.get("eq")
        if not isinstance(eqs_raw, dict):
            eqs_raw = {}
        channels = {key: Mix.from_dict(channels_raw.get(key)) for key in SINK_KEYS}
        eqs = {key: eqmod.ChannelEq.from_dict(eqs_raw.get(key)) for key in SINK_KEYS}
        return cls(str(data.get("label") or ""), volume, bool(data.get("muted", False)), channels, eqs).normalized()


def clone_eqs(eqs: dict | None) -> dict[str, eqmod.ChannelEq]:
    """Independent copies, so editing one device cannot move another's faders."""
    out = {}
    for key in SINK_KEYS:
        state = eqs.get(key) if eqs else None
        if isinstance(state, eqmod.ChannelEq):
            out[key] = eqmod.ChannelEq.from_dict(state.to_dict())
        else:
            out[key] = eqmod.ChannelEq.from_dict(state)
    return out


def from_live(label: str, volume: float, muted: bool, channel_nodes: dict, eqs: dict) -> Profile:
    """A profile seeded from what is playing, used the first time a device is seen."""
    channels = {}
    for key in SINK_KEYS:
        node = channel_nodes.get(key) if channel_nodes else None
        if node is None:
            channels[key] = Mix()
        else:
            channels[key] = Mix(getattr(node, "volume", 1.0), getattr(node, "muted", False))
    return Profile(label, volume, muted, channels, clone_eqs(eqs)).normalized()


def load(settings: dict) -> dict[str, Profile]:
    raw = settings.get("profiles")
    if not isinstance(raw, dict):
        return {}
    out = {}
    for key, value in raw.items():
        if isinstance(key, str) and key:
            out[key] = Profile.from_dict(value)
    return out


def store(settings: dict, profiles: dict[str, Profile]) -> None:
    settings["profiles"] = {key: profile.to_dict() for key, profile in profiles.items()}


def adopt(profiles: dict[str, Profile], key: str, fallback: Profile) -> tuple[Profile, bool]:
    """Return the profile for `key` and whether a saved one should be applied.

    The first time a device shows up, keep whatever is already playing and
    remember it. Later visits restore the saved volume and equalizer.
    """
    if not key:
        return fallback.normalized(), False
    found = profiles.get(key)
    if found is None:
        stored = fallback.normalized()
        profiles[key] = stored
        return stored, False
    return found.normalized(), True


def profile_key(node_name: str) -> str:
    """Stable id for a sink. Bluetooth uses the adapter address; ALSA uses the node."""
    name = node_name or ""
    if "bluez" in name.lower():
        match = _MAC.search(name)
        if match:
            return "bluez:" + ":".join(part.lower() for part in match.groups())
    if name.startswith("alsa_output."):
        return "alsa:" + name[len("alsa_output."):]
    if name.startswith("alsa_input."):
        return "alsa-in:" + name[len("alsa_input."):]
    return "node:" + name


def friendly_label(text: str) -> str:
    label = (text or "").strip()
    label = re.sub(r"^sof-soundwire\s+", "", label, flags=re.IGNORECASE)
    label = re.sub(r"^built-?in audio\s+", "", label, flags=re.IGNORECASE)
    label = re.sub(r"\s+Output$", "", label, flags=re.IGNORECASE)
    label = re.sub(r"\s+Input$", "", label, flags=re.IGNORECASE)
    label = re.sub(r"\bMicrophones\b", "Microphone", label)
    return label.strip()


def endpoint_label(record: dict) -> str:
    for candidate in (record.get("nick"), record.get("profile"), record.get("description"), record.get("name")):
        label = friendly_label(str(candidate or ""))
        if label:
            return label
    return "Unknown"


def device_form(name: str, description: str, icon: str, kind: str) -> str:
    """Coarse shape the panel uses to pick a glyph."""
    blob = f"{name} {description} {icon}".lower()
    if kind == "source":
        if any(word in blob for word in ("headset", "headphone", "airpod", "earbud")):
            return "headphones"
        if "bluetooth" in blob or "bluez" in blob:
            return "bluetooth"
        if "webcam" in blob or "camera" in blob:
            return "camera"
        return "mic"
    if any(word in blob for word in ("headphone", "headset", "earbud", "airpod", "earphone")):
        return "headphones"
    if "bluez" in blob or "bluetooth" in blob:
        return "bluetooth"
    if "hdmi" in blob or "displayport" in blob or "display" in blob:
        return "hdmi"
    return "speaker"


def describe(name: str, records: list[dict], kind: str = "sink") -> tuple[str, str]:
    for record in records:
        if record.get("name") == name:
            return endpoint_label(record), device_form(
                name, str(record.get("description") or ""), str(record.get("icon") or ""), kind
            )
    fallback = "Output" if kind == "sink" else "Input"
    form = "speaker" if kind == "sink" else "mic"
    return friendly_label(name) or fallback, form


def is_hidden_output(name: str) -> bool:
    """Virtual sinks the output list should not offer as devices.

    A speaker tuning stays visible: it is the output the system actually
    selects, and the physical sink behind it is reported unavailable instead.
    """
    node = name or ""
    if node.startswith(f"{NODE_PREFIX}_") or node.startswith(f"output.{NODE_PREFIX}_"):
        return True
    if node == "easyeffects_sink" or node.startswith("easyeffects_"):
        return True
    return False


def is_hidden_input(name: str) -> bool:
    node = name or ""
    if not node or node == "quickshell" or node.endswith(".monitor"):
        return True
    if node.startswith(f"{NODE_PREFIX}_") or node.startswith("easyeffects"):
        return True
    if node.startswith("omarchy_speaker_tuning"):
        return True
    return False


def parse_availability(raw: str) -> dict[str, bool]:
    """`omarchy-audio-sink-availability` lines: `node.name<TAB>0|1`."""
    found: dict[str, bool] = {}
    for line in (raw or "").splitlines():
        text = line.strip()
        if not text:
            continue
        parts = text.split("\t")
        if len(parts) >= 2:
            found[parts[0]] = parts[1] != "0"
    return found
