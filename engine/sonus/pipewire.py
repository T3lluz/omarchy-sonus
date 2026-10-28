"""Reading and driving the PipeWire graph through the standard CLI tools.

Ported unchanged in behaviour from the Sonus desktop app: the same snapshot,
the same grouping of an app's streams, the same routing rules.
"""

from __future__ import annotations

import json
import subprocess
import time
from dataclasses import asdict, dataclass, field

from . import eq as eqmod
from . import profiles
from .config import NODE_PREFIX, SINK_CHANNELS

STREAM_CLASSES = ("Stream/Output/Audio",)
_TIMEOUT = 2.5
_SKIP_APPS = frozenset({
    "easyeffects",
    "pipewire",
    "pipewire-pulse",
    "wireplumber",
    "sonusdeck",
    "quickshell",
})

# PipeWire stores volumes on a cubic curve; wpctl and the percentage in the
# panel both speak the linear one.
_CUBE = 1.0 / 3.0

EFFECTS_SINK = "easyeffects_sink"


def _linear(cubic: float) -> float:
    return max(0.0, min(1.0, cubic ** _CUBE)) if cubic > 0 else 0.0


def _run(args: list[str], timeout: float = _TIMEOUT) -> str:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout if result.returncode == 0 else ""


@dataclass
class NodeState:
    node_id: int
    serial: int
    name: str
    description: str
    volume: float = 1.0
    muted: bool = False


@dataclass
class AppStream:
    key: str
    name: str
    node_id: int
    serial: int
    volume: float = 1.0
    muted: bool = False
    icon_name: str = ""
    binary: str = ""
    channel: str = ""
    members: list[int] = field(default_factory=list)
    # Object serial of every member stream (== pactl sink-input index);
    # moving an app means moving each of these.
    serials: list[int] = field(default_factory=list)


@dataclass
class Endpoint:
    """One hardware output or input the panel can select."""

    node_id: int
    name: str
    label: str
    volume: float
    muted: bool
    form: str
    key: str
    active: bool = False

    def to_dict(self) -> dict:
        return {
            "id": self.node_id,
            "name": self.name,
            "label": self.label,
            "volume": round(self.volume, 4),
            "muted": self.muted,
            "form": self.form,
            "key": self.key,
            "active": self.active,
        }


@dataclass
class Snapshot:
    channels: dict[str, NodeState] = field(default_factory=dict)
    apps: list[AppStream] = field(default_factory=list)
    output_serials: dict[str, int] = field(default_factory=dict)
    outputs: list[Endpoint] = field(default_factory=list)
    inputs: list[Endpoint] = field(default_factory=list)
    default_sink: str = ""
    volume_sink: str = ""
    output_label: str = ""
    output_form: str = "speaker"
    mix_target: str = ""
    ready: bool = False

    def to_dict(self) -> dict:
        return {
            "channels": {key: asdict(state) for key, state in self.channels.items()},
            "apps": [asdict(app) for app in self.apps],
            "outputs": [item.to_dict() for item in self.outputs],
            "inputs": [item.to_dict() for item in self.inputs],
            "defaultSink": self.default_sink,
            "volumeSink": self.volume_sink,
            "outputLabel": self.output_label,
            "outputForm": self.output_form,
            "mixTarget": self.mix_target,
            "ready": self.ready,
        }


def _props_volume(info: dict) -> tuple[float, bool]:
    params = (info.get("params") or {}).get("Props") or []
    volume, muted = 1.0, False
    for entry in params:
        if "channelVolumes" in entry:
            vols = entry.get("channelVolumes") or []
            if vols:
                volume = _linear(max(float(v) for v in vols))
        elif "volume" in entry and "channelVolumes" not in entry:
            volume = _linear(float(entry.get("volume", 1.0)))
        if "mute" in entry:
            muted = bool(entry.get("mute"))
    return volume, muted


def _app_identity(props: dict) -> tuple[str, str, str, str]:
    binary = str(props.get("application.process.binary") or "")
    app_name = str(props.get("application.name") or "")
    media = str(props.get("media.name") or "")
    icon = str(props.get("application.icon-name") or props.get("application.icon") or "")
    label = app_name or binary or media or "App"
    key = (binary or app_name or label).lower()
    if not icon:
        icon = (binary or app_name).lower()
    return key, label, icon, binary


def is_app_stream(props: dict) -> bool:
    """A playback stream an app opened, as opposed to plumbing.

    A filter-chain, loopback or combine sink plays into the hardware through
    a stream of its own (a speaker tuning's "Laptop speakers playback"). It
    carries `node.link-group` and no app; listing it would offer to route
    the speakers into a channel that plays into the speakers.
    """
    if str(props.get("media.class") or "") not in STREAM_CLASSES:
        return False
    name = str(props.get("node.name") or "")
    if name.startswith(f"output.{NODE_PREFIX}_") or name.startswith(NODE_PREFIX):
        return False
    if props.get("node.link-group") and not props.get("application.process.binary"):
        return False
    return True


def _sink_input_map() -> dict[int, int]:
    """Stream pulse index -> sink pulse index (both are PipeWire object serials)."""
    mapping: dict[int, int] = {}
    for line in _run(["pactl", "list", "short", "sink-inputs"]).splitlines():
        parts = line.split()
        if len(parts) >= 2:
            try:
                mapping[int(parts[0])] = int(parts[1])
            except ValueError:
                continue
    return mapping


def _sink_names_by_index() -> dict[int, str]:
    """Sink pulse index (== object serial) -> node name."""
    sinks: dict[int, str] = {}
    for line in _run(["pactl", "list", "short", "sinks"]).splitlines():
        parts = line.split()
        if len(parts) >= 2:
            try:
                sinks[int(parts[0])] = parts[1]
            except ValueError:
                continue
    return sinks


def default_sink_name() -> str:
    return _run(["pactl", "get-default-sink"]).strip()


def default_source_name() -> str:
    return _run(["pactl", "get-default-source"]).strip()


_volume_sink_cache: dict = {"at": 0.0, "default": "", "name": ""}
_availability_cache: dict = {"at": 0.0, "data": {}}


def resolve_volume_sink(default: str) -> str:
    """The sink whose volume is the loudness of the current output.

    A tuning or EasyEffects can be the default without being where the level
    lives. `omarchy-audio-output-sink` walks that chain to the hardware.
    """
    now = time.monotonic()
    cached = _volume_sink_cache
    if cached["default"] == default and cached["name"] and now - cached["at"] < 0.4:
        return str(cached["name"])
    resolved = _run(["omarchy-audio-output-sink"], timeout=3.0).strip() or default
    cached["at"] = now
    cached["default"] = default
    cached["name"] = resolved
    return resolved


def sink_availability() -> dict[str, bool]:
    now = time.monotonic()
    cached = _availability_cache
    if now - float(cached["at"]) < 5.0:
        return cached["data"]
    found = profiles.parse_availability(_run(["omarchy-audio-sink-availability"], timeout=3.0))
    cached["at"] = now
    cached["data"] = found
    return found


def _plain_records(nodes: list[tuple[dict, dict, dict]]) -> list[dict]:
    records = []
    for obj, _info, props in nodes:
        records.append({
            "id": int(obj.get("id") or 0),
            "name": str(props.get("node.name") or ""),
            "description": str(props.get("node.description") or ""),
            "nick": str(props.get("node.nick") or ""),
            "profile": str(props.get("device.profile.description") or ""),
            "media_class": str(props.get("media.class") or ""),
            "icon": str(props.get("device.icon-name") or ""),
        })
    return records


def build_endpoints(
    records: list[dict],
    availability: dict[str, bool],
    default_sink: str,
    volume_sink: str,
    default_source: str,
) -> tuple[list[Endpoint], list[Endpoint], str, str]:
    """Outputs and inputs for the panel, plus the label and glyph of the current output.

    Sonus' own channels and EasyEffects are left out: picking one would bypass
    the mixer. A sink marked unavailable (the speakers behind a tuning) is
    left out too. When the default itself is hidden, the resolved hardware
    sink is the one shown as current.
    """
    availability = availability or {}
    outputs: list[Endpoint] = []
    inputs: list[Endpoint] = []
    default_hidden = profiles.is_hidden_output(default_sink)
    for record in records:
        media = record.get("media_class") or ""
        name = record.get("name") or ""
        if not name:
            continue
        if media == "Audio/Sink":
            if profiles.is_hidden_output(name) or availability.get(name) is False:
                continue
            kind = "sink"
        elif media == "Audio/Source":
            if profiles.is_hidden_input(name):
                continue
            kind = "source"
        else:
            continue
        volume = float(record.get("volume", 1.0) or 0.0)
        muted = bool(record.get("muted", False))
        endpoint = Endpoint(
            node_id=int(record.get("id") or 0),
            name=name,
            label=profiles.endpoint_label(record),
            volume=volume,
            muted=muted,
            form=profiles.device_form(name, str(record.get("description") or ""), str(record.get("icon") or ""), kind),
            key=profiles.profile_key(name),
            active=(name == default_sink or (default_hidden and bool(volume_sink) and name == volume_sink))
            if kind == "sink" else name == default_source,
        )
        if kind == "sink":
            outputs.append(endpoint)
        else:
            inputs.append(endpoint)
    label, form = profiles.describe(volume_sink, records, "sink")
    for endpoint in outputs:
        if endpoint.active:
            label, form = endpoint.label, endpoint.form
            break
    return outputs, inputs, label, form


def _node_state(found: tuple[dict, dict, dict] | None, description: str) -> NodeState | None:
    if found is None:
        return None
    obj, info, props = found
    volume, muted = _props_volume(info)
    return NodeState(
        node_id=int(obj["id"]),
        serial=int(props.get("object.serial") or 0),
        name=str(props.get("node.name") or ""),
        description=description or str(props.get("node.description") or "Output"),
        volume=volume,
        muted=muted,
    )


def mix_target_name(sinks: list[str], default: str) -> str:
    """Where channel outputs should land so EasyEffects can EQ the device."""
    if EFFECTS_SINK in sinks:
        return EFFECTS_SINK
    if default and not default.startswith(NODE_PREFIX):
        return default
    for name in sinks:
        if not name.startswith(NODE_PREFIX):
            return name
    return default


def snapshot() -> Snapshot:
    raw = _run(["pw-dump"], timeout=4.0)
    default = default_sink_name()
    source = default_source_name()
    sinks = list(_sink_names_by_index().values())
    snap = Snapshot(
        default_sink=default,
        volume_sink=resolve_volume_sink(default),
        mix_target=mix_target_name(sinks, default),
    )
    if not raw:
        return snap
    try:
        objects = json.loads(raw)
    except json.JSONDecodeError:
        return snap

    nodes: list[tuple[dict, dict, dict]] = []
    by_name: dict[str, tuple[dict, dict, dict]] = {}
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        info = obj.get("info") or {}
        props = info.get("props") or {}
        nodes.append((obj, info, props))
        name = str(props.get("node.name") or "")
        if name:
            by_name[name] = (obj, info, props)

    serial_to_channel: dict[int, str] = {}
    output_by_name = {f"output.{channel.node_name}": channel.key for channel in SINK_CHANNELS}

    for obj, info, props in nodes:
        key = output_by_name.get(str(props.get("node.name") or ""))
        if key:
            serial = int(props.get("object.serial") or 0)
            if serial:
                snap.output_serials[key] = serial

    for channel in SINK_CHANNELS:
        found = by_name.get(channel.node_name)
        if found is None:
            continue
        obj, info, props = found
        volume, muted = _props_volume(info)
        serial = int(props.get("object.serial") or 0)
        snap.channels[channel.key] = NodeState(
            node_id=int(obj["id"]),
            serial=serial,
            name=channel.node_name,
            description=str(props.get("node.description") or channel.description),
            volume=volume,
            muted=muted,
        )
        serial_to_channel[serial] = channel.key

    records = _plain_records(nodes)
    # Volumes live on the node info, which the plain record does not carry.
    # Stamp them before the list is built so a row can show its own level.
    for record in records:
        found = by_name.get(record["name"])
        if found is None:
            continue
        volume, muted = _props_volume(found[1])
        record["volume"] = volume
        record["muted"] = muted
    snap.outputs, snap.inputs, snap.output_label, snap.output_form = build_endpoints(
        records, sink_availability(), snap.default_sink, snap.volume_sink, source,
    )

    master = _node_state(
        by_name.get(snap.volume_sink) or by_name.get(snap.default_sink) or by_name.get(snap.mix_target),
        snap.output_label or "Output",
    )
    if master is not None:
        snap.channels["master"] = master
    if source and not profiles.is_hidden_input(source):
        mic_label, _form = profiles.describe(source, records, "source")
        state = _node_state(by_name.get(source), mic_label)
        if state is not None:
            snap.channels["input"] = state

    routes = _sink_input_map()
    grouped: dict[str, AppStream] = {}
    for obj, info, props in nodes:
        if not is_app_stream(props):
            continue
        key, label, icon, binary = _app_identity(props)
        if key in _SKIP_APPS or binary.lower() in _SKIP_APPS:
            continue
        serial = int(props.get("object.serial") or 0)
        volume, muted = _props_volume(info)
        existing = grouped.get(key)
        if existing is not None:
            existing.members.append(int(obj["id"]))
            if serial:
                existing.serials.append(serial)
            continue
        grouped[key] = AppStream(
            key=key,
            name=label,
            node_id=int(obj["id"]),
            serial=serial,
            volume=volume,
            muted=muted,
            icon_name=icon,
            binary=binary,
            channel=serial_to_channel.get(routes.get(serial, -1), ""),
            members=[int(obj["id"])],
            serials=[serial] if serial else [],
        )

    snap.apps = sorted(grouped.values(), key=lambda a: a.name.lower())
    snap.ready = any(key in snap.channels for key in ("game", "chat", "media", "aux"))
    return snap


def set_default_output(node_id: int, name: str) -> None:
    """Make `name` the system default without pulling apps off the channels.

    `omarchy-audio-output-set-default` moves every application stream onto the
    new sink. That would lift Spotify out of Media for a moment. The default
    is enough: the poller points the channel outputs at the mix target and
    puts each app back where it was routed.
    """
    if not name:
        return
    _run(["wpctl", "set-default", str(node_id)], timeout=3.0)
    _run(["pactl", "set-default-sink", name], timeout=3.0)
    _volume_sink_cache["at"] = 0.0


def set_default_input(node_id: int, name: str) -> None:
    if not name:
        return
    _run(["omarchy-audio-input-set-default", str(node_id), name], timeout=4.0)


def set_volume(node_id: int, volume: float) -> None:
    value = max(0.0, min(1.0, float(volume)))
    _run(["wpctl", "set-volume", str(node_id), f"{value:.4f}"])


def set_mute(node_id: int, muted: bool) -> None:
    _run(["wpctl", "set-mute", str(node_id), "1" if muted else "0"])


def move_stream(serial: int, sink_name: str) -> None:
    _run(["pactl", "move-sink-input", str(serial), sink_name])


def _eq_payload(state: eqmod.ChannelEq) -> str:
    """Props "params" list; a disabled EQ is written as an effective bypass."""
    state = state.normalized()
    active = state.enabled
    mult = eqmod.db_to_linear(state.preamp) if active else 1.0
    parts = [f'"{eqmod.PREAMP_NAME}:Mult" {mult:.6f}']
    for index in range(eqmod.BAND_COUNT):
        gain = state.gains[index] if active else 0.0
        freq = eqmod.BAND_FREQS[index]
        parts.append(
            f'"{eqmod.band_name(index)}:Freq" {freq:.1f} '
            f'"{eqmod.band_name(index)}:Q" {eqmod.BAND_Q:.2f} '
            f'"{eqmod.band_name(index)}:Gain" {gain:.2f}'
        )
    return "{ params = [ " + " ".join(parts) + " ] }"


def set_channel_eq(node_id: int, state: eqmod.ChannelEq) -> bool:
    """Push preamp and band gains into a channel's filter-chain sink node.

    The Props "params" values reach the DSP even though pw-cli's readback of
    that param can show stale values (verified with a signal-level test).
    """
    out = _run(["pw-cli", "set-param", str(node_id), "Props", _eq_payload(state)])
    return bool(out)


def retarget_channel_outputs(snap: Snapshot) -> None:
    """Keep Game/Chat/Media/Aux feeding EasyEffects (or the hardware sink)."""
    target = snap.mix_target
    if not target or not snap.output_serials:
        return
    routes = _sink_input_map()
    sink_names = _sink_names_by_index()
    for serial in snap.output_serials.values():
        current = sink_names.get(routes.get(serial, -1), "")
        if current != target:
            move_stream(serial, target)


def enforce_app_routes(snap: Snapshot, routes: dict[str, str]) -> None:
    """Keep every app stream where Sonus routed it.

    Assigned apps play into their category sink; everything else is parked on
    the mix target (easyeffects_sink while EasyEffects runs) so post-mix
    effects still apply. Runs on every poll, so nothing (an EasyEffects
    started later, session restores) can silently steal a stream.
    """
    if not snap.apps:
        return
    channel_sinks = {
        channel.key: channel.node_name
        for channel in SINK_CHANNELS
        if channel.key in snap.channels
    }
    stream_sinks = _sink_input_map()
    sink_names = _sink_names_by_index()
    grabbing = snap.mix_target == EFFECTS_SINK
    for app in snap.apps:
        wanted = channel_sinks.get(routes.get(app.binary or app.key, ""))
        for serial in app.serials or [app.serial]:
            if not serial:
                continue
            current = sink_names.get(stream_sinks.get(serial, -1), "")
            if wanted:
                target = wanted
            elif current.startswith(NODE_PREFIX) or (grabbing and current != EFFECTS_SINK):
                # Unassigned: never leave a stream on a category sink, and
                # feed it to EasyEffects when that is the mix target.
                target = snap.mix_target
            else:
                continue
            if current and current != target:
                move_stream(serial, target)
