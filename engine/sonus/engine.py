"""The long-running half of the plugin: owns the graph and the routes.

omarchy-shell runs this as a child process and talks JSON lines with it:
commands in on stdin, state out on stdout. The engine runs as long as the
plugin is enabled, panel open or not, because routes are enforced all the
time, exactly as the desktop app's poller did while hidden.

Out:
  {"type": "config", ...}   saved routes, EQ curves and switches
  {"type": "state", ...}    one graph snapshot (0.7 s open, 2 s hidden)
  {"type": "update", ...}   update check results
  {"type": "notice", ...}   one-line messages for the status area

In: see Engine.handle().
"""

from __future__ import annotations

import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import effects, legacy, pipewire, profiles, updater
from . import eq as eqmod
from .config import CHANNELS, SINK_CHANNELS, SINK_KEYS, load_settings, save_settings
from .graph import GraphProcess

ACTIVE_INTERVAL = 0.7
IDLE_INTERVAL = 2.0
EQ_PERSIST_DELAY = 0.8
GRAPH_RETRY = 6.0


class Writer(threading.Thread):
    """Applies volume, mute and EQ writes, latest value per target wins.

    A dragged fader sends a value every frame; queueing each one would leave
    the audio trailing the thumb by however long wpctl takes per call.
    """

    def __init__(self) -> None:
        super().__init__(daemon=True)
        self._cond = threading.Condition()
        self._pending: dict[str, object] = {}

    def submit(self, key: str, job) -> None:
        with self._cond:
            self._pending[key] = job
            self._cond.notify()

    def run(self) -> None:
        while True:
            with self._cond:
                while not self._pending:
                    self._cond.wait()
                key = next(iter(self._pending))
                job = self._pending.pop(key)
            try:
                job()
            except Exception:
                pass


class Engine:
    def __init__(self, plugin_dir: Path, plugin_id: str) -> None:
        self.plugin_dir = plugin_dir
        self.plugin_id = plugin_id
        self.settings = load_settings()
        self.eqs = eqmod.load_all(self.settings, SINK_KEYS)
        self.profiles = profiles.load(self.settings)
        active = self.settings.get("active_profile") or ""
        self.active_key = active if isinstance(active, str) else ""
        self._profiles_started = False
        self._apply_pending = False
        self._hold_until = 0.0
        self._skip_apply_once = False
        self.profile_epoch = 0
        self.eq_applied: dict[str, tuple] = {}
        self.graph = GraphProcess()
        self.snap = pipewire.Snapshot()
        self.active = False
        self.legacy = False
        self.setup_done = False
        self.last_graph_try = 0.0
        self._wake = threading.Event()
        self._out = threading.Lock()
        self._state_lock = threading.RLock()
        self._persist_timer: threading.Timer | None = None
        self._pool = ThreadPoolExecutor(max_workers=3)
        self._writer = Writer()
        self._update_busy = False

    # ----- output ---------------------------------------------------------

    def emit(self, payload: dict) -> None:
        line = json.dumps(payload, separators=(",", ":"))
        with self._out:
            try:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            except (BrokenPipeError, ValueError):
                # The shell went away; the graph is not ours to stop.
                import os
                os._exit(0)

    def notice(self, text: str, error: bool = False) -> None:
        self.emit({"type": "notice", "text": text, "error": error})

    def emit_config(self) -> None:
        with self._state_lock:
            self.emit({
                "type": "config",
                "routes": dict(self.routes()),
                "eq": {key: state.to_dict() for key, state in self.eqs.items()},
                "manageGraph": bool(self.settings.get("manage_graph", True)),
                "pos": self.settings.get("panel_pos"),
            })

    # ----- settings ---------------------------------------------------------

    def routes(self) -> dict[str, str]:
        routes = self.settings.get("routes")
        return routes if isinstance(routes, dict) else {}

    def persist(self) -> None:
        with self._state_lock:
            if self._persist_timer is not None:
                self._persist_timer.cancel()
                self._persist_timer = None
            eqmod.store_all(self.settings, self.eqs)
            if self.active_key:
                self.settings["active_profile"] = self.active_key
            profiles.store(self.settings, self.profiles)
            try:
                save_settings(self.settings)
            except OSError as exc:
                self.notice(f"Could not save settings: {exc}", error=True)

    def persist_later(self) -> None:
        with self._state_lock:
            if self._persist_timer is not None:
                self._persist_timer.cancel()
            self._persist_timer = threading.Timer(EQ_PERSIST_DELAY, self.persist)
            self._persist_timer.daemon = True
            self._persist_timer.start()

    # ----- graph ----------------------------------------------------------

    def manage(self) -> bool:
        return bool(self.settings.get("manage_graph", True)) and not self.legacy

    def setup(self) -> None:
        """Bring up the channels and tame EasyEffects, as the desktop app did
        on launch. Safe to repeat."""
        if self.legacy:
            # Retried by poll_once once the desktop app is gone.
            return
        if self.manage():
            self.last_graph_try = time.monotonic()
            if not self.graph.start(self.eqs) and self.graph.error:
                self.notice(f"Virtual channels: {self.graph.error}", error=True)
            effects.ensure_passthrough()
            effects.ensure_manual_routing()
        self.setup_done = True
        self._wake.set()

    def watch_graph(self, snap: pipewire.Snapshot) -> None:
        """Bring the channels back if something took them down (a PipeWire
        restart, the desktop app's unit being stopped)."""
        if not self.setup_done or not self.manage() or snap.ready:
            return
        now = time.monotonic()
        if now - self.last_graph_try < GRAPH_RETRY:
            return
        self.last_graph_try = now
        self._pool.submit(self.graph.start, self.eqs)

    # ----- polling --------------------------------------------------------

    def status_text(self, snap: pipewire.Snapshot) -> str:
        if self.legacy:
            return "Routing paused"
        if not snap.channels or not snap.ready:
            if not self.settings.get("manage_graph", True):
                return "Virtual channels are off"
            return "Starting channels…"
        missing = [c.label.title() for c in CHANNELS if c.kind != "master" and c.key not in snap.channels]
        if missing:
            return "Missing: " + ", ".join(missing)
        return effects.status_text()

    def ensure_eq_applied(self, snap: pipewire.Snapshot) -> None:
        """Re-push saved EQs whenever a channel node (re)appears."""
        for channel in SINK_CHANNELS:
            node = snap.channels.get(channel.key)
            state = self.eqs.get(channel.key)
            if node is None or state is None:
                continue
            wanted = (node.node_id, state.signature())
            if self.eq_applied.get(channel.key) != wanted:
                self.eq_applied[channel.key] = wanted
                node_id = node.node_id
                self._writer.submit(f"eq:{channel.key}", lambda n=node_id, s=state: pipewire.set_channel_eq(n, s))

    def poll_once(self) -> None:
        was_legacy = self.legacy
        self.legacy = legacy.running()
        if was_legacy and not self.legacy and not self.setup_done:
            self._pool.submit(self.setup)
        elif self.legacy and not was_legacy:
            self.setup_done = False
        snap = pipewire.snapshot()
        if not self.legacy:
            pipewire.retarget_channel_outputs(snap)
            with self._state_lock:
                routes = dict(self.routes())
            pipewire.enforce_app_routes(snap, routes)
            self.watch_graph(snap)
        with self._state_lock:
            self.snap = snap
            if was_legacy and not self.legacy:
                self._adopt_disk_settings(snap)
            if not self.legacy:
                self.sync_profile(snap)
            self.ensure_eq_applied(snap)
        payload = snap.to_dict()
        payload.update({
            "type": "state",
            "status": self.status_text(snap),
            "legacy": self.legacy,
            "effectsRunning": snap.mix_target == pipewire.EFFECTS_SINK,
            "activeProfile": self.active_key,
            "profileEpoch": self.profile_epoch,
        })
        self.emit(payload)

    def poll_loop(self) -> None:
        while True:
            try:
                self.poll_once()
            except Exception as exc:  # keep routing alive whatever happens
                self.notice(f"Poll failed: {exc}", error=True)
            self._wake.wait(ACTIVE_INTERVAL if self.active else IDLE_INTERVAL)
            self._wake.clear()

    # ----- commands -------------------------------------------------------

    def find_app(self, key: str):
        return next((a for a in self.snap.apps if a.key == key), None)

    def handle(self, msg: dict) -> None:
        cmd = msg.get("cmd")
        if cmd == "active":
            self.active = bool(msg.get("value"))
            self._wake.set()
        elif cmd == "refresh":
            self._wake.set()
        elif cmd == "volume":
            ids = [int(i) for i in msg.get("ids") or []]
            value = float(msg.get("value", 0.0))
            with self._state_lock:
                self._note_levels(ids, volume=value)
            self._writer.submit(
                "vol:" + ",".join(map(str, ids)),
                lambda: [pipewire.set_volume(i, value) for i in ids],
            )
        elif cmd == "mute":
            ids = [int(i) for i in msg.get("ids") or []]
            value = bool(msg.get("value"))
            with self._state_lock:
                self._note_levels(ids, muted=value)
            self._writer.submit(
                "mute:" + ",".join(map(str, ids)),
                lambda: [pipewire.set_mute(i, value) for i in ids],
            )
            self._wake.set()
        elif cmd == "selectOutput":
            self._select(self._select_output, msg)
        elif cmd == "selectInput":
            self._select(self._select_input, msg)
        elif cmd == "route":
            self.route(str(msg.get("key", "")), str(msg.get("channel", "")))
        elif cmd == "eq":
            self.set_eq(str(msg.get("key", "")), msg.get("state"))
        elif cmd == "persist":
            self.persist()
        elif cmd == "setting":
            self.set_setting(str(msg.get("key", "")), msg.get("value"))
        elif cmd == "takeover":
            self._pool.submit(self.take_over)
        elif cmd == "updateCheck":
            self._pool.submit(self.update_check)
        elif cmd == "updateApply":
            self._pool.submit(self.update_apply)

    def _note_levels(self, ids: list[int], volume: float | None = None, muted: bool | None = None) -> None:
        """Remember a fader move on the device that is playing. Caller holds the lock."""
        profile = self.profiles.get(self.active_key)
        if profile is None:
            return
        wanted = set(ids)
        changed = False
        master = self.snap.channels.get("master")
        if master is not None and master.node_id in wanted:
            if volume is not None:
                profile.volume = max(0.0, min(1.0, volume))
            if muted is not None:
                profile.muted = muted
            changed = True
        for key in SINK_KEYS:
            node = self.snap.channels.get(key)
            if node is None or node.node_id not in wanted:
                continue
            mix = profile.channels.setdefault(key, profiles.Mix())
            if volume is not None:
                mix.volume = max(0.0, min(1.0, volume))
            if muted is not None:
                mix.muted = muted
            changed = True
        if changed:
            self.persist_later()

    def _push_volume(self, node_id: int, volume: float) -> None:
        self._writer.submit(f"vol:{node_id}", lambda n=node_id, v=volume: pipewire.set_volume(n, v))

    def _push_mute(self, node_id: int, muted: bool) -> None:
        self._writer.submit(f"mute:{node_id}", lambda n=node_id, m=muted: pipewire.set_mute(n, m))

    def _push_profile(self, profile: profiles.Profile, snap: pipewire.Snapshot) -> bool:
        """Write a profile onto the live nodes. False while a channel is still missing."""
        missing = False
        for key in SINK_KEYS:
            state = self.eqs.get(key) or eqmod.ChannelEq()
            node = snap.channels.get(key)
            if node is None:
                if self.manage():
                    missing = True
                continue
            self.eq_applied[key] = (node.node_id, state.signature())
            self._writer.submit(
                f"eq:{key}",
                lambda n=node.node_id, s=state: pipewire.set_channel_eq(n, s),
            )
            mix = profile.channels.get(key) or profiles.Mix()
            self._push_volume(node.node_id, mix.volume)
            self._push_mute(node.node_id, mix.muted)
        master = snap.channels.get("master")
        if master is not None:
            self._push_volume(master.node_id, profile.volume)
            self._push_mute(master.node_id, profile.muted)
        else:
            missing = True
        return not missing

    def _apply_profile(self, profile: profiles.Profile, snap: pipewire.Snapshot) -> None:
        profile = profile.normalized()
        self.eqs = profiles.clone_eqs(profile.eqs)
        profile.eqs = self.eqs
        self.profiles[self.active_key] = profile
        self._hold_until = time.monotonic() + 2.0
        self.profile_epoch += 1
        self._apply_pending = not self._push_profile(profile, snap)
        self.settings["active_profile"] = self.active_key
        self.emit({
            "type": "profile",
            "epoch": self.profile_epoch,
            "key": self.active_key,
            "masterVolume": profile.volume,
            "masterMuted": profile.muted,
            "channels": {key: profile.channels[key].to_dict() for key in SINK_KEYS},
        })
        self.emit_config()
        self.persist_later()

    def _switch_profile(self, snap: pipewire.Snapshot, key: str, label: str) -> None:
        master = snap.channels.get("master")
        fallback = profiles.from_live(
            label,
            master.volume if master is not None else 1.0,
            master.muted if master is not None else False,
            snap.channels,
            self.eqs,
        )
        chosen, apply = profiles.adopt(self.profiles, key, fallback)
        self.active_key = key
        self.settings["active_profile"] = key
        if apply:
            self._apply_profile(chosen, snap)
            return
        chosen.eqs = profiles.clone_eqs(self.eqs)
        self.profiles[key] = chosen
        self.persist_later()

    def _capture_profile(self, snap: pipewire.Snapshot) -> None:
        profile = self.profiles.get(self.active_key)
        master = snap.channels.get("master")
        if profile is None or master is None:
            return
        changed = False
        if abs(profile.volume - master.volume) > 0.005 or profile.muted != master.muted:
            profile.volume = master.volume
            profile.muted = master.muted
            changed = True
        if snap.output_label and profile.label != snap.output_label:
            profile.label = snap.output_label
            changed = True
        for key in SINK_KEYS:
            node = snap.channels.get(key)
            if node is None:
                continue
            mix = profile.channels.setdefault(key, profiles.Mix())
            if abs(mix.volume - node.volume) > 0.005 or mix.muted != node.muted:
                mix.volume = node.volume
                mix.muted = node.muted
                changed = True
        if changed:
            self.persist_later()

    def sync_profile(self, snap: pipewire.Snapshot) -> None:
        """Load a device's saved mix when the output changes, including at startup."""
        if self.legacy or not snap.volume_sink or "master" not in snap.channels:
            return
        key = profiles.profile_key(snap.volume_sink)
        label = snap.output_label or snap.volume_sink
        if self._apply_pending and key == self.active_key and key in self.profiles:
            self._hold_until = time.monotonic() + 2.0
            if self._push_profile(self.profiles[key], snap):
                self._apply_pending = False
            return
        if key != self.active_key:
            self._profiles_started = True
            if self._skip_apply_once:
                self._skip_apply_once = False
                self._remember_without_apply(snap, key, label)
            else:
                self._switch_profile(snap, key, label)
            return
        if not self._profiles_started:
            self._profiles_started = True
            if self._skip_apply_once or key not in self.profiles:
                self._skip_apply_once = False
                self._remember_without_apply(snap, key, label)
            else:
                self._apply_profile(self.profiles[key], snap)
            return
        if time.monotonic() < self._hold_until:
            return
        self._capture_profile(snap)

    def _adopt_disk_settings(self, _snap: pipewire.Snapshot) -> None:
        """The desktop app just quit. Take the curves it wrote, and don't stomp them."""
        self.settings = load_settings()
        self.eqs = eqmod.load_all(self.settings, SINK_KEYS)
        self.profiles = profiles.load(self.settings)
        self.eq_applied.clear()
        # sync_profile folds these curves into the current device without
        # pushing the previous profile back over them. The snapshot is what
        # that next step reads.
        self._skip_apply_once = True
        self._profiles_started = False
        self._apply_pending = False
        self._hold_until = 0.0
        saved = self.settings.get("active_profile") or ""
        self.active_key = saved if isinstance(saved, str) else ""

    def _remember_without_apply(self, snap: pipewire.Snapshot, key: str, label: str) -> None:
        """Keep the curves already loaded and attach them to this device."""
        if key not in self.profiles:
            self._switch_profile(snap, key, label)
            return
        profile = self.profiles[key]
        profile.eqs = profiles.clone_eqs(self.eqs)
        master = snap.channels.get("master")
        if master is not None:
            profile.volume = master.volume
            profile.muted = master.muted
        if label:
            profile.label = label
        self.active_key = key
        self.settings["active_profile"] = key
        self.persist_later()

    def _select(self, fn, msg: dict) -> None:
        name = str(msg.get("name") or "")
        if not name:
            return
        try:
            node_id = int(msg.get("id"))
        except (TypeError, ValueError):
            return
        self._pool.submit(fn, node_id, name)

    def _select_output(self, node_id: int, name: str) -> None:
        pipewire.set_default_output(node_id, name)
        try:
            snap = pipewire.snapshot()
            if not self.legacy:
                with self._state_lock:
                    routes = dict(self.routes())
                pipewire.retarget_channel_outputs(snap)
                pipewire.enforce_app_routes(snap, routes)
        except Exception:
            pass
        self._wake.set()

    def _select_input(self, node_id: int, name: str) -> None:
        pipewire.set_default_input(node_id, name)
        self._wake.set()

    def route(self, key: str, channel_key: str) -> None:
        """Assign an app to a category ("" = back to the mix) and move it.

        A plain, gapless PipeWire retarget; the poller re-asserts the route
        should anything try to steal the stream back.
        """
        with self._state_lock:
            app = self.find_app(key)
            if app is None:
                return
            routes = dict(self.routes())
            if channel_key:
                channel = next((c for c in SINK_CHANNELS if c.key == channel_key), None)
                if channel is None:
                    return
                routes[app.binary or app.key] = channel_key
                target = channel.node_name
            else:
                routes.pop(app.binary or app.key, None)
                target = self.snap.mix_target or self.snap.default_sink
            self.settings["routes"] = routes
            serials = list(app.serials or [app.serial])
        self.persist()
        if target and not self.legacy:
            def move() -> None:
                for serial in serials:
                    if serial:
                        pipewire.move_stream(serial, target)
                self._wake.set()
            self._pool.submit(move)

    def set_eq(self, key: str, data) -> None:
        if key not in SINK_KEYS:
            return
        state = eqmod.ChannelEq.from_dict(data)
        with self._state_lock:
            self.eqs[key] = state
            profile = self.profiles.get(self.active_key)
            if profile is not None:
                profile.eqs[key] = state
            node = self.snap.channels.get(key)
            if node is not None:
                self.eq_applied[key] = (node.node_id, state.signature())
                node_id = node.node_id
                self._writer.submit(f"eq:{key}", lambda: pipewire.set_channel_eq(node_id, state))
        self.persist_later()

    def set_setting(self, key: str, value) -> None:
        if key == "manage_graph":
            with self._state_lock:
                self.settings["manage_graph"] = bool(value)
            self.persist()
            if self.legacy:
                return
            if value:
                self._pool.submit(self.setup)
            else:
                self._pool.submit(self.graph.stop)
            self._wake.set()
        elif key == "panel_pos":
            with self._state_lock:
                self.settings["panel_pos"] = value if isinstance(value, dict) else None
            self.persist()

    def take_over(self) -> None:
        self.notice("Switching from the Sonus desktop app…")
        with self._state_lock:
            legacy.take_over(self.settings)
        self.persist()
        self.legacy = False
        # The desktop app's graph went down with its unit; start ours now
        # rather than waiting for the watchdog.
        self.setup_done = False
        self.setup()
        self.notice("Sonus now runs in the shell")
        self._wake.set()

    def update_check(self) -> None:
        if self._update_busy:
            return
        self._update_busy = True
        self.emit({"type": "update", "busy": True, "applying": False})
        try:
            status = updater.check(self.plugin_dir)
        except Exception:
            status = updater.Status("unknown")
        self._update_busy = False
        self.emit({"type": "update", "busy": False, **status.to_dict()})

    def update_apply(self) -> None:
        if self._update_busy:
            return
        self._update_busy = True
        self.emit({"type": "update", "busy": True, "applying": True})
        ok = updater.apply(self.plugin_id)
        self._update_busy = False
        # On success the shell reloads the plugin and this engine with it.
        if not ok:
            self.emit({"type": "update", "busy": False, "state": "failed",
                       "local": updater.local_commit(self.plugin_dir)})

    # ----- main -----------------------------------------------------------

    def run(self) -> int:
        self._writer.start()
        self.legacy = legacy.running()
        self.emit_config()
        self.emit({"type": "update", "busy": False, "state": "unknown",
                   "local": updater.local_commit(self.plugin_dir)})
        self._pool.submit(self.setup)
        threading.Thread(target=self.poll_loop, daemon=True).start()
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(msg, dict):
                try:
                    self.handle(msg)
                except Exception as exc:
                    self.notice(f"{msg.get('cmd')}: {exc}", error=True)
        # stdin closed: the shell is reloading or quitting. Save, leave the
        # graph running for the next engine to adopt.
        self.persist()
        return 0


def main(argv: list[str]) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="sonus-engine")
    parser.add_argument("--plugin-dir", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--plugin-id", default="io.github.t3lluz.sonus")
    parser.add_argument("--stop-graph", action="store_true",
                        help="stop the virtual channels and exit")
    parser.add_argument("--snapshot", action="store_true",
                        help="print one graph snapshot as JSON and exit")
    args = parser.parse_args(argv)
    if args.stop_graph:
        GraphProcess().stop()
        return 0
    if args.snapshot:
        print(json.dumps(pipewire.snapshot().to_dict(), indent=2))
        return 0
    return Engine(Path(args.plugin_dir), args.plugin_id).run()
