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
  {"type": "output", ...}   the output device just changed: its label and form
  {"type": "cava", ...}     whether cava is there for the visualizer, or being installed

In: see Engine.handle().
"""

from __future__ import annotations

import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import cava, effects, legacy, notices, pipewire, profiles, updater
from . import eq as eqmod
from .config import CHANNELS, SINK_CHANNELS, SINK_KEYS, load_settings, save_settings
from .graph import GraphProcess

ACTIVE_INTERVAL = 0.7
IDLE_INTERVAL = 2.0
EQ_PERSIST_DELAY = 0.8
GRAPH_RETRY = 6.0
UPDATE_FIRST_CHECK = 60.0
UPDATE_INTERVAL = 6 * 3600.0


# What the status line says when a command fails; the exception goes to stderr.
FAILED_COMMANDS = {
    "selectOutput": "Couldn't switch output",
    "selectInput": "Couldn't switch input",
    "volume": "Couldn't change the volume",
    "mute": "Couldn't change the mute",
    "route": "Couldn't move the app",
    "eq": "Couldn't change the equalizer",
    "installCava": "Couldn't install cava",
    "updateApply": "Couldn't start the update",
    "setting": "Couldn't save that setting",
    "takeover": "Couldn't take over from the desktop app",
}


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
        # A finished update is restarting the shell; this engine is about to end.
        self._restarting = False
        self._cava_busy = False
        self._cava_message = ""
        # The message says all there is to do (pacman failed), so the settings
        # page adds no "Install cava to see the visualizer."
        self._cava_final = False
        self._cava_retries = 0
        self._poll_failing = False
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

    def notice(self, text: str, error: bool = False, form: str = "") -> None:
        self.emit({"type": "notice", "text": text, "error": error, "form": form})

    def emit_config(self) -> None:
        with self._state_lock:
            self.emit({
                "type": "config",
                "routes": dict(self.routes()),
                "eq": {key: state.to_dict() for key, state in self.eqs.items()},
                "manageGraph": bool(self.settings.get("manage_graph", True)),
                "visualizer": bool(self.settings.get("visualizer", True)),
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
        # EasyEffects is optional, so whether it runs is not news.
        return ""

    def ensure_eq_applied(self, snap: pipewire.Snapshot) -> None:
        """Re-push saved EQs whenever a channel node (re)appears."""
        for channel in SINK_CHANNELS:
            node = snap.channels.get(channel.key)
            state = self.eqs.get(channel.key)
            if node is None or state is None:
                continue
            wanted = (node.node_id, state.signature())
            if self.eq_applied.get(channel.key) != wanted:
                self._writer.submit(f"eq:{channel.key}", lambda k=channel.key, w=wanted, n=node.node_id, s=state: self._push_eq(k, w, n, s))

    def _push_eq(self, key: str, wanted: tuple, node_id: int, state) -> None:
        """Counts as applied only when pw-cli took it; a failed push (the node
        not ready yet) is tried again on the next poll."""
        if pipewire.set_channel_eq(node_id, state):
            with self._state_lock:
                self.eq_applied[key] = wanted

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
                self._poll_failing = False
            except Exception as exc:  # keep routing alive whatever happens
                print(f"sonus: poll failed: {exc!r}", file=sys.stderr, flush=True)
                if not self._poll_failing:
                    self._poll_failing = True
                    self.notice("Lost track of PipeWire, retrying", error=True)
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
            # A cava installed by hand shows up the next time the panel opens.
            if self.active:
                self.emit_cava()
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
            # Waits on the runner for minutes; keep it off the shared pool.
            threading.Thread(target=self.update_apply, daemon=True).start()
        elif cmd == "look":
            # Style.space(40), the shell's picture slot, for the badges.
            notices.set_slot(msg.get("slot"))
        elif cmd == "installCava":
            threading.Thread(target=self.install_cava, kwargs={"asked": True}, daemon=True).start()
        elif cmd == "previewNotices":
            version = updater.installed_version(self.plugin_dir)
            threading.Thread(target=notices.preview, args=(version,), daemon=True).start()

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
            wanted = (node.node_id, state.signature())
            self._writer.submit(
                f"eq:{key}",
                lambda k=key, w=wanted, n=node.node_id, s=state: self._push_eq(k, w, n, s),
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

    def _switch_profile(self, snap: pipewire.Snapshot, key: str, label: str) -> bool:
        """Make `key` the current device; True when its saved mix came back."""
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
            # Says why the faders just moved.
            self.notice(f"{label}: saved volume and EQ restored", form=snap.output_form)
            return True
        chosen.eqs = profiles.clone_eqs(self.eqs)
        self.profiles[key] = chosen
        self.persist_later()
        return False

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
            # A change the user made or plugged in, not the device found at
            # startup, gets the on-screen toast.
            announce = self._profiles_started
            self._profiles_started = True
            restored = False
            if self._skip_apply_once:
                self._skip_apply_once = False
                self._remember_without_apply(snap, key, label)
            else:
                restored = self._switch_profile(snap, key, label)
            if announce:
                self.emit({"type": "output", "label": label, "form": snap.output_form, "restored": restored})
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
        try:
            pipewire.set_default_output(node_id, name)
        except Exception as exc:
            print(f"sonus: switching output: {exc!r}", file=sys.stderr, flush=True)
            self.notice("Couldn't switch output", error=True)
            return
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
        try:
            pipewire.set_default_input(node_id, name)
        except Exception as exc:
            print(f"sonus: switching input: {exc!r}", file=sys.stderr, flush=True)
            self.notice("Couldn't switch input", error=True)
            return
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
                wanted = (node.node_id, state.signature())
                node_id = node.node_id
                self._writer.submit(f"eq:{key}", lambda: self._push_eq(key, wanted, node_id, state))
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
        elif key == "visualizer":
            with self._state_lock:
                self.settings["visualizer"] = bool(value)
            self.persist()
            self.emit_cava()
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
            status = updater.Status("offline", updater.local_commit(self.plugin_dir))
        self._update_busy = False
        self.emit({"type": "update", "busy": False, "applying": False, **status.to_dict()})

    def update_loop(self) -> None:
        """Look for updates a minute after start, then every few hours, so the
        badge shows up without opening the panel first."""
        time.sleep(UPDATE_FIRST_CHECK)
        while True:
            self.update_check()
            time.sleep(UPDATE_INTERVAL)

    def update_apply(self) -> None:
        if self._update_busy:
            return
        self._update_busy = True
        self.emit({"type": "update", "busy": True, "applying": True, "message": ""})
        error = updater.start(self.plugin_dir, self.plugin_id)
        if error:
            self._update_busy = False
            self.emit({"type": "update", "busy": False, "applying": False,
                       "state": "failed", "message": error})
            return
        self._await_update()

    def _await_update(self) -> None:
        """Wait for the detached runner. A successful update reloads the
        plugin and ends this engine first; this only reports what did not."""
        deadline = time.monotonic() + updater.RUN_LIMIT
        while time.monotonic() < deadline:
            time.sleep(0.5)
            result = updater.read_result()
            if result is None or result.get("running"):
                continue
            self._update_busy = False
            self._report_update(result)
            return
        self._update_busy = False
        self.emit({"type": "update", "busy": False, "applying": False, "state": "failed",
                   "message": "The update did not finish; see ~/.local/state/sonus/update.log"})

    def _report_update(self, result: dict) -> None:
        updater.clear_result()
        if result.get("ok"):
            version = result.get("version") or ""
            text = f"Updated to {version}" if version else "Updated"
            if result.get("stashed"):
                text += ". Local edits were set aside with git stash"
            # The result is already cleared, so this happens once. The shell's
            # reload keeps the QML it compiled, and the old panel would stay on
            # screen reading the new version number. The restart closes the
            # panel, so this is said on the desktop.
            cava_next = cava.will_ask(self.visualizer_on())
            if cava_next:
                cava.mark_pending(version)
            notices.updated(version, bool(result.get("stashed")), cava_next=cava_next)
            self._restarting = True
            if updater.restart_shell():
                return
            self._restarting = False
            self.notice(text + ". Run: omarchy restart shell")
            self.update_check()
        elif result.get("current"):
            self.emit({"type": "update", "busy": False, "applying": False, "state": "current",
                       "local": updater.local_commit(self.plugin_dir), "checked": time.time()})
        else:
            message = result.get("message") or "The update failed"
            self.emit({"type": "update", "busy": False, "applying": False, "state": "failed",
                       "local": updater.local_commit(self.plugin_dir), "message": message})
            if not self.active:
                notices.failed(message)
            self.notice(f"Update failed: {message}", error=True)

    def resume_update(self) -> None:
        """Pick up an update this engine's predecessor started: report how it
        ended, or keep the panel showing it while the runner works."""
        result = updater.read_result()
        if result is None:
            return
        if updater.running(result):
            self._update_busy = True
            self.emit({"type": "update", "busy": True, "applying": True})
            self._await_update()
            return
        if time.time() - float(result.get("at") or 0) < updater.RESULT_FRESH and not result.get("running"):
            self._report_update(result)
        else:
            updater.clear_result()

    # ----- cava -----------------------------------------------------------

    def visualizer_on(self) -> bool:
        with self._state_lock:
            return bool(self.settings.get("visualizer", True))

    def emit_cava(self) -> None:
        self.emit({"type": "cava", "installed": cava.installed(), "installing": self._cava_busy,
                   "message": self._cava_message, "final": self._cava_final})

    def install_cava(self, asked: bool = False) -> None:
        """Install cava. `asked` is the settings page's Install button, which
        always may ask, even after a no; otherwise this is the ask right after
        an update."""
        if self._cava_busy:
            return
        if asked:
            cava.forget_decline()
        self._cava_busy = True
        self._cava_message = ""
        self._cava_final = False
        self.emit_cava()
        try:
            result = cava.install()
        finally:
            self._cava_busy = False
        cava.record(result, updater.installed_version(self.plugin_dir))
        self._cava_message = result.message
        self._cava_final = not result.ok and result.prompted and not result.declined
        if result.no_agent and not asked and self._cava_retries < 3:
            # The shell's polkit agent is not up yet: no prompt showed, so try
            # again in a minute rather than give up.
            self._cava_retries += 1
            threading.Timer(60.0, self.cava_startup).start()
        self.emit_cava()

    def cava_startup(self) -> None:
        """Ask for cava only right after an update said it would (cava.py).
        Not from an engine that is restarting the shell after that update:
        the shell is the polkit agent, so its prompt would go with it. The
        next engine asks."""
        if self._restarting:
            return
        if cava.running():
            self._cava_busy = True
            self.emit_cava()
            cava.wait_running()
            self._cava_busy = False
            self.emit_cava()
            return
        if not cava.should_ask(self.visualizer_on()):
            return
        # The shell has just started, and its polkit agent with it.
        time.sleep(4.0)
        if self._restarting or not cava.should_ask(self.visualizer_on()):
            return
        self.install_cava()

    def startup(self) -> None:
        # First, so the panel knows about cava even while an update is
        # still being waited on below.
        self.emit_cava()
        self.resume_update()
        self.cava_startup()

    # ----- main -----------------------------------------------------------

    def run(self) -> int:
        self._writer.start()
        self.legacy = legacy.running()
        self.emit_config()
        self.emit({"type": "update", "busy": False, "state": "unknown",
                   "local": updater.local_commit(self.plugin_dir)})
        self._pool.submit(self.setup)
        threading.Thread(target=self.poll_loop, daemon=True).start()
        threading.Thread(target=self.startup, daemon=True).start()
        threading.Thread(target=self.update_loop, daemon=True).start()
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
                    print(f"sonus: {msg.get('cmd')}: {exc!r}", file=sys.stderr, flush=True)
                    self.notice(FAILED_COMMANDS.get(str(msg.get("cmd")), "Something went wrong, try again"), error=True)
        # stdin closed: the shell is reloading or quitting. Save, leave the
        # graph running for the next engine to adopt.
        self.persist()
        return 0


# The block Service.qml keeps in ~/.config/hypr/bindings.lua (ui/Shortcut.js).
SHORTCUT_BEGIN = "-- >>> sonus shortcut"
SHORTCUT_END = "-- <<< sonus shortcut"


def bindings_path() -> Path:
    return Path.home() / ".config" / "hypr" / "bindings.lua"


def strip_shortcut(path: Path | None = None) -> bool:
    """Take Sonus's Ctrl+Alt+V block out of Hyprland's bindings, for removing
    the plugin. True if there was one."""
    path = path or bindings_path()
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return False
    start = text.find(SHORTCUT_BEGIN)
    if start < 0:
        return False
    end = text.find(SHORTCUT_END, start)
    end = len(text) if end < 0 else end + len(SHORTCUT_END)
    before = text[:start].rstrip("\n")
    after = text[end:].lstrip("\n")
    rest = before + ("\n\n" + after if after else "\n") if before else after
    try:
        path.write_text(rest, encoding="utf-8")
    except OSError:
        return False
    return True


def main(argv: list[str]) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="sonus-engine")
    parser.add_argument("--plugin-dir", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--plugin-id", default="io.github.t3lluz.sonus")
    parser.add_argument("--stop-graph", action="store_true",
                        help="stop the virtual channels, take out the Ctrl+Alt+V bind and exit "
                             "(run before removing the plugin)")
    parser.add_argument("--snapshot", action="store_true",
                        help="print one graph snapshot as JSON and exit")
    parser.add_argument("--apply-update", action="store_true",
                        help="update the plugin checkout (run detached by the panel)")
    args = parser.parse_args(argv)
    if args.apply_update:
        return 0 if updater.run(Path(args.plugin_dir), args.plugin_id).get("ok") else 1
    if args.stop_graph:
        GraphProcess().stop()
        strip_shortcut()
        return 0
    if args.snapshot:
        print(json.dumps(pipewire.snapshot().to_dict(), indent=2))
        return 0
    return Engine(Path(args.plugin_dir), args.plugin_id).run()
