# Run with: python3 -m unittest discover tests
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
from pathlib import Path

# Imports from engine/ would leave bytecode in the plugin folder, and the
# shell reloads every plugin when a file appears there.
sys.dont_write_bytecode = True
# config.py reads XDG_CONFIG_HOME on import; point it somewhere disposable.
_config_home = tempfile.mkdtemp(prefix="sonus-test-")
os.environ["XDG_CONFIG_HOME"] = _config_home
os.environ["XDG_STATE_HOME"] = tempfile.mkdtemp(prefix="sonus-state-")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "engine"))

from sonus import cava, config, eq, graph, notices, pipewire, profiles, updater  # noqa: E402


class ChannelEqTest(unittest.TestCase):
    def test_from_dict_clamps_and_pads(self):
        state = eq.ChannelEq.from_dict({"enabled": False, "preamp": 40, "gains": [30, -30]})
        self.assertFalse(state.enabled)
        self.assertEqual(state.preamp, eq.PREAMP_LIMIT)
        self.assertEqual(state.gains, [18.0, -18.0] + [0.0] * 8)

    def test_from_dict_survives_junk(self):
        self.assertEqual(eq.ChannelEq.from_dict("nope").to_dict(), eq.ChannelEq().to_dict())
        state = eq.ChannelEq.from_dict({"preamp": "loud", "gains": ["a", 1]})
        self.assertEqual(state.preamp, 0.0)
        self.assertEqual(state.gains, [0.0] * eq.BAND_COUNT)

    def test_round_trip_and_signature(self):
        state = eq.ChannelEq(True, -2.345, [1.234] + [0.0] * 9)
        again = eq.ChannelEq.from_dict(state.to_dict())
        self.assertEqual(again.signature(), (True, -2.35, (1.23,) + (0.0,) * 9))

    def test_store_and_load_all(self):
        settings = {}
        eq.store_all(settings, {"game": eq.ChannelEq(True, 1.0, [2.0] * 10)})
        loaded = eq.load_all(settings, ("game", "chat"))
        self.assertEqual(loaded["game"].gains, [2.0] * 10)
        self.assertEqual(loaded["chat"].gains, [0.0] * 10)


class GraphTest(unittest.TestCase):
    def test_every_sink_channel_is_a_filter_chain(self):
        text = graph.render_config({})
        for channel in config.SINK_CHANNELS:
            self.assertIn(f'node.name        = "{channel.node_name}"', text)
        self.assertEqual(text.count("libpipewire-module-filter-chain"), len(config.SINK_CHANNELS))
        self.assertEqual(text.count("label = bq_peaking"), len(config.SINK_CHANNELS) * eq.BAND_COUNT)

    def test_bypassed_eq_renders_flat(self):
        state = eq.ChannelEq(False, 6.0, [9.0] * 10)
        text = graph.render_config({"game": state})
        self.assertNotIn('"Gain" = 9.00', text)
        self.assertIn('"Mult" = 1.000000', text)

    def test_gain_and_preamp_reach_the_graph(self):
        state = eq.ChannelEq(True, -6.0, [0.0] * 5 + [4.5] + [0.0] * 4)
        text = graph.render_config({"chat": state})
        self.assertIn('"Freq" = 1000.0 "Q" = 1.80 "Gain" = 4.50', text)
        self.assertIn('"Mult" = 0.501187', text)


class PipewireHelpersTest(unittest.TestCase):
    def test_mix_target_prefers_easyeffects_then_the_real_default(self):
        self.assertEqual(pipewire.mix_target_name(["alsa_out", "easyeffects_sink"], "alsa_out"), "easyeffects_sink")
        self.assertEqual(pipewire.mix_target_name(["alsa_out"], "alsa_out"), "alsa_out")
        # Never one of our own channels, even when it is the default.
        self.assertEqual(pipewire.mix_target_name(["sonusdeck_game", "alsa_out"], "sonusdeck_game"), "alsa_out")

    def test_volume_is_linearised_from_cubic(self):
        volume, muted = pipewire._props_volume({"params": {"Props": [{"channelVolumes": [0.125, 0.125], "mute": True}]}})
        self.assertAlmostEqual(volume, 0.5)
        self.assertTrue(muted)
        self.assertEqual(pipewire._props_volume({}), (1.0, False))

    def test_app_identity(self):
        key, label, icon, binary = pipewire._app_identity({"application.process.binary": "Discord", "application.name": "WEBRTC VoiceEngine"})
        self.assertEqual((key, label, icon, binary), ("discord", "WEBRTC VoiceEngine", "discord", "Discord"))
        self.assertEqual(pipewire._app_identity({})[1], "App")

    def test_filter_chain_playback_is_not_an_app(self):
        tuning = {
            "media.class": "Stream/Output/Audio",
            "node.name": "laptop_speakers_playback",
            "node.link-group": "filter-chain-1168-29",
            "media.name": "Laptop speakers",
        }
        self.assertFalse(pipewire.is_app_stream(tuning))
        self.assertFalse(pipewire.is_app_stream({"media.class": "Stream/Output/Audio", "node.name": "output.sonusdeck_game"}))
        self.assertTrue(pipewire.is_app_stream({"media.class": "Stream/Output/Audio", "application.process.binary": "spotify"}))
        self.assertFalse(pipewire.is_app_stream({"media.class": "Stream/Input/Audio", "application.process.binary": "discord"}))


    def test_a_paused_stream_is_not_playing(self):
        self.assertTrue(pipewire.stream_playing({"state": "running"}, {"pulse.corked": False}))
        self.assertFalse(pipewire.stream_playing({"state": "idle"}, {"pulse.corked": True}))
        self.assertFalse(pipewire.stream_playing({"state": "running"}, {"pulse.corked": "true"}))
        self.assertFalse(pipewire.stream_playing({"state": "suspended"}, {}))


class ProfileTest(unittest.TestCase):
    def test_airpods_share_a_key_across_bluetooth_profiles(self):
        a2dp = profiles.profile_key("bluez_output.AA_BB_CC_DD_EE_FF.1")
        headset = profiles.profile_key("bluez_output.AA_BB_CC_DD_EE_FF.2")
        self.assertEqual(a2dp, "bluez:aa:bb:cc:dd:ee:ff")
        self.assertEqual(a2dp, headset)

    def test_laptop_speakers_and_hdmi_are_different_devices(self):
        speakers = profiles.profile_key("alsa_output.pci-0000_00_1f.3.analog-stereo")
        hdmi = profiles.profile_key("alsa_output.pci-0000_00_1f.3.hdmi-stereo")
        self.assertNotEqual(speakers, hdmi)
        self.assertTrue(speakers.startswith("alsa:"))

    def test_friendly_label_strips_the_card_prefix(self):
        self.assertEqual(profiles.friendly_label("Built-in Audio Analog Stereo"), "Analog Stereo")
        self.assertEqual(profiles.friendly_label("sof-soundwire Speaker"), "Speaker")

    def test_first_visit_keeps_what_is_playing_and_the_next_visit_restores(self):
        stored = {}
        live = profiles.from_live("Laptop", 0.4, False, {}, {"game": eq.ChannelEq(True, 0, [1.0] * 10)})
        chosen, apply = profiles.adopt(stored, "alsa:analog", live)
        self.assertFalse(apply)
        self.assertEqual(chosen.volume, 0.4)
        self.assertEqual(chosen.eqs["game"].gains[0], 1.0)
        chosen.volume = 0.2
        stored["alsa:analog"] = chosen
        again, apply = profiles.adopt(stored, "alsa:analog", live)
        self.assertTrue(apply)
        self.assertEqual(again.volume, 0.2)
        # The restored curve is a copy, so editing it leaves the saved one alone.
        again.eqs["game"].gains[0] = 9
        self.assertEqual(stored["alsa:analog"].eqs["game"].gains[0], 1.0)

    def test_round_trip(self):
        original = profiles.from_live("AirPods", 0.35, True, {}, {"chat": eq.ChannelEq(True, -1, [2.0] * 10)})
        settings = {}
        profiles.store(settings, {"bluez:aa": original})
        loaded = profiles.load(settings)["bluez:aa"]
        self.assertEqual(loaded.label, "AirPods")
        self.assertTrue(loaded.muted)
        self.assertEqual(loaded.eqs["chat"].gains, [2.0] * 10)
        self.assertEqual(loaded.channels["game"].volume, 1.0)

    def test_output_list_hides_sonus_and_easyeffects_and_marks_the_hardware(self):
        records = [
            {"id": 1, "name": "easyeffects_sink", "description": "EasyEffects", "nick": "", "profile": "", "media_class": "Audio/Sink", "icon": ""},
            {"id": 2, "name": "alsa_output.pci-0000_00_1f.3.analog-stereo", "description": "Built-in Audio Analog Stereo", "nick": "Speakers", "profile": "", "media_class": "Audio/Sink", "icon": "audio-card", "volume": 0.5, "muted": False},
            {"id": 3, "name": "bluez_output.AA_BB_CC_DD_EE_FF.1", "description": "AirPods Pro", "nick": "", "profile": "", "media_class": "Audio/Sink", "icon": "audio-headphones", "volume": 0.3, "muted": False},
            {"id": 4, "name": "sonusdeck_game", "description": "Sonus Game", "nick": "", "profile": "", "media_class": "Audio/Sink", "icon": ""},
            {"id": 5, "name": "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor", "description": "Monitor", "nick": "", "profile": "", "media_class": "Audio/Source", "icon": ""},
            {"id": 6, "name": "alsa_input.pci-0000_00_1f.3.analog-stereo", "description": "Built-in Audio Analog Stereo", "nick": "Microphone", "profile": "", "media_class": "Audio/Source", "icon": "audio-input-microphone", "volume": 0.8, "muted": False},
        ]
        outputs, inputs, label, form = pipewire.build_endpoints(
            records, {}, "easyeffects_sink", "alsa_output.pci-0000_00_1f.3.analog-stereo",
            "alsa_input.pci-0000_00_1f.3.analog-stereo", laptop=False,
        )
        names = [item.name for item in outputs]
        self.assertEqual(names, [
            "alsa_output.pci-0000_00_1f.3.analog-stereo",
            "bluez_output.AA_BB_CC_DD_EE_FF.1",
        ])
        self.assertTrue(outputs[0].active)
        self.assertFalse(outputs[1].active)
        self.assertEqual(outputs[0].label, "Speakers")
        self.assertEqual(outputs[1].form, "earbuds")
        self.assertEqual(outputs[1].key, "bluez:aa:bb:cc:dd:ee:ff")
        self.assertEqual(label, "Speakers")
        self.assertEqual(form, "speaker")
        self.assertEqual([item.name for item in inputs], ["alsa_input.pci-0000_00_1f.3.analog-stereo"])
        self.assertTrue(inputs[0].active)
        self.assertEqual(inputs[0].label, "Microphone")

    def test_device_forms(self):
        form = profiles.device_form
        # One sound card: the port in use decides speakers or headphones.
        card = ("alsa_output.pci-0000_75_00.6.analog-stereo", "Ryzen HD Audio Controller Analog Stereo", "audio-card-analog")
        self.assertEqual(form(*card, "sink", bus="pci", port="analog-output-speaker Speakers", laptop=True), "laptop")
        self.assertEqual(form(*card, "sink", bus="pci", port="analog-output-speaker Speakers", laptop=False), "speaker")
        self.assertEqual(form(*card, "sink", bus="pci", port="analog-output-headphones Headphones", laptop=True), "headphones")
        # Omarchy's speaker tuning has no device behind it, only its name.
        self.assertEqual(form("laptop_speakers", "Laptop speakers", "", "sink", laptop=True), "laptop")
        self.assertEqual(form("bluez_output.AA_BB_CC_DD_EE_FF.1", "AirPods Pro", "audio-headphones", "sink",
                              form_factor="headphone", bus="bluetooth"), "earbuds")
        self.assertEqual(form("bluez_output.11_22_33_44_55_66.1", "WH-1000XM5", "audio-headphones", "sink",
                              form_factor="headphone", bus="bluetooth"), "headphones")
        self.assertEqual(form("bluez_output.11_22_33_44_55_66.1", "Jabra", "", "sink",
                              form_factor="headset", bus="bluetooth"), "headset")
        self.assertEqual(form("bluez_output.11_22_33_44_55_66.1", "JBL Flip 6", "", "sink", bus="bluetooth"), "bluetooth")
        self.assertEqual(form("alsa_output.pci-0000_75_00.1.hdmi-stereo", "HDMI / DisplayPort", "", "sink", bus="pci"), "hdmi")
        self.assertEqual(form("alsa_output.pci-0000_75_00.1.hdmi-stereo", "LG TV", "", "sink", bus="pci"), "tv")
        self.assertEqual(form("alsa_output.usb-dac", "USB Audio", "", "sink", bus="usb", laptop=True), "speaker")
        self.assertEqual(form("alsa_input.pci-mic", "Internal Microphone", "", "source", bus="pci"), "mic")
        self.assertEqual(form("bluez_input.AA_BB_CC_DD_EE_FF.0", "Jabra", "", "source", bus="bluetooth"), "headset")

    def test_active_port_is_read_from_the_card(self):
        objects = [{"id": 53, "type": "PipeWire:Interface:Device", "info": {"params": {"Route": [
            {"name": "analog-input-internal-mic", "description": "Internal Microphone", "direction": "Input", "device": 0},
            {"name": "analog-output-headphones", "description": "Headphones", "direction": "Output", "device": 4},
        ]}}}]
        props = {"node.name": "alsa_output.pci.analog-stereo", "media.class": "Audio/Sink",
                 "device.id": 53, "card.profile.device": 4, "device.bus": "pci"}
        records = pipewire._plain_records([({"id": 7}, {}, props)], pipewire._active_ports(objects))
        self.assertEqual(records[0]["port"], "analog-output-headphones Headphones")
        self.assertEqual(profiles.record_form(records[0], "sink", laptop=True), "headphones")

    def test_unavailable_sink_is_hidden(self):
        records = [
            {"id": 2, "name": "alsa_output.pci-analog", "description": "Speakers", "nick": "", "profile": "", "media_class": "Audio/Sink", "icon": ""},
            {"id": 7, "name": "omarchy_speaker_tuning", "description": "Laptop", "nick": "", "profile": "", "media_class": "Audio/Sink", "icon": ""},
        ]
        outputs, _, label, _ = pipewire.build_endpoints(
            records, {"alsa_output.pci-analog": False}, "omarchy_speaker_tuning", "alsa_output.pci-analog", "",
        )
        self.assertEqual([item.name for item in outputs], ["omarchy_speaker_tuning"])
        self.assertTrue(outputs[0].active)
        self.assertEqual(label, "Laptop")


class SettingsTest(unittest.TestCase):
    def test_save_keeps_unknown_keys_and_load_fills_defaults(self):
        config.save_settings({"routes": "broken", "window": {"x": 1}})
        loaded = config.load_settings()
        self.assertEqual(loaded["routes"], {})
        self.assertEqual(loaded["window"], {"x": 1})
        self.assertTrue(loaded["manage_graph"])
        self.assertTrue(str(config.SETTINGS_PATH).startswith(_config_home))


def _git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True,
                   env=dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
                            GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t"))


@unittest.skipUnless(shutil.which("git"), "needs git")
class UpdaterTest(unittest.TestCase):
    """A plugin checkout cloned from a local origin that then moves ahead."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="sonus-update-"))
        self.origin = self.tmp / "origin"
        self.origin.mkdir()
        _git(self.origin, "init", "-q", "-b", "main")
        (self.origin / "manifest.json").write_text(json.dumps({"version": "1.0.0"}))
        _git(self.origin, "add", ".")
        _git(self.origin, "commit", "-qm", "first")
        self.plugin = self.tmp / "plugin"
        _git(self.tmp, "clone", "-q", str(self.origin), str(self.plugin))
        (self.origin / "manifest.json").write_text(json.dumps({"version": "1.1.0"}))
        _git(self.origin, "commit", "-qam", "Sonus 1.1: better")
        # Stands in for `omarchy plugin update`: fast-forward or fail.
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        script = self.bin / "omarchy-plugin-update"
        script.write_text(
            "#!/bin/bash\n"
            f'cd "{self.plugin}" && git fetch -q origin HEAD && git merge -q --ff-only FETCH_HEAD '
            '|| { echo "omarchy-plugin-update: cannot fast-forward" >&2; exit 1; }\n'
        )
        script.chmod(0o755)
        self.path = os.environ["PATH"]
        os.environ["PATH"] = f"{self.bin}:{self.path}"

    def tearDown(self):
        os.environ["PATH"] = self.path
        shutil.rmtree(self.tmp, ignore_errors=True)
        updater.clear_result()

    def test_check_reports_the_new_version_and_local_edits(self):
        status = updater.check(self.plugin)
        self.assertEqual(status.state, "outdated")
        self.assertEqual(status.version, "1.1.0")
        self.assertEqual(status.summary, "Sonus 1.1: better")
        self.assertEqual(status.behind, 1)
        self.assertFalse(status.modified)
        (self.plugin / "Panel.qml").write_text("// a local edit")
        self.assertTrue(updater.check(self.plugin).modified)

    def test_a_folder_without_git_is_unmanaged(self):
        self.assertEqual(updater.check(self.tmp / "bin").state, "unmanaged")

    def test_a_finished_update_restarts_the_shell_once(self):
        # The shell's reload keeps compiled QML, so only a restart shows the new panel.
        from sonus.engine import Engine
        engine = mock.MagicMock()
        with mock.patch.object(updater, "restart_shell", return_value=True) as restart, \
                mock.patch.object(cava, "installed", return_value=True), \
                mock.patch.object(notices, "updated") as notify, mock.patch.object(notices, "failed"):
            Engine._report_update(engine, {"ok": True, "version": "1.1.0"})
            restart.assert_called_once()
            notify.assert_called_once_with("1.1.0", False, cava_next=False)
            # This engine is on its way out with the shell, so cava waits for the next.
            self.assertTrue(engine._restarting)
            engine.update_check.assert_not_called()
            self.assertIsNone(updater.read_result())

            restart.reset_mock()
            Engine._report_update(engine, {"current": True})
            Engine._report_update(engine, {"message": "no"})
            restart.assert_not_called()

    def test_a_restart_that_cannot_start_says_how(self):
        from sonus.engine import Engine
        engine = mock.MagicMock()
        with mock.patch.object(updater, "restart_shell", return_value=False), mock.patch.object(notices, "updated"):
            Engine._report_update(engine, {"ok": True, "version": "1.1.0"})
        self.assertIn("omarchy restart shell", engine.notice.call_args[0][0])
        engine.update_check.assert_called_once()

    def test_restart_shell_runs_apart_from_the_engine(self):
        marker = self.tmp / "restarted"
        script = self.bin / "omarchy-restart-shell"
        script.write_text(f"#!/bin/sh\ntouch {marker}\n")
        script.chmod(0o755)
        real_which = shutil.which
        with mock.patch.object(updater.shutil, "which",
                               side_effect=lambda name: None if name == "systemd-run" else real_which(name)):
            self.assertTrue(updater.restart_shell())
        deadline = time.time() + 5
        while not marker.exists() and time.time() < deadline:
            time.sleep(0.05)
        self.assertTrue(marker.exists())

    def test_run_sets_local_edits_aside_and_updates(self):
        (self.plugin / "manifest.json").write_text(json.dumps({"version": "1.0.0-local"}))
        (self.plugin / "extra.qml").write_text("// untracked")
        result = updater.run(self.plugin, "io.example.sonus")
        self.assertTrue(result["ok"], result)
        self.assertTrue(result["stashed"])
        self.assertEqual(result["version"], "1.1.0")
        self.assertEqual(updater.read_result()["version"], "1.1.0")
        self.assertFalse(updater.modified(self.plugin))

    def test_edits_that_are_the_update_leave_no_stash(self):
        # The update's files copied in by hand, as a development copy has them.
        (self.plugin / "manifest.json").write_text(json.dumps({"version": "1.1.0"}))
        result = updater.run(self.plugin, "io.example.sonus")
        self.assertTrue(result["ok"], result)
        self.assertFalse(result["stashed"])
        stashes = subprocess.run(["git", "-C", str(self.plugin), "stash", "list"],
                                 capture_output=True, text=True).stdout
        self.assertEqual(stashes.strip(), "")

    def test_a_failed_run_puts_local_edits_back(self):
        (self.origin / "manifest.json").write_text(json.dumps({"version": "2.0.0"}))
        _git(self.plugin, "commit", "-qam", "diverged", "--allow-empty")
        _git(self.origin, "commit", "-qam", "upstream")
        (self.plugin / "notes.txt").write_text("keep me")
        result = updater.run(self.plugin, "io.example.sonus")
        self.assertFalse(result["ok"])
        self.assertEqual(result["message"], "cannot fast-forward")
        self.assertEqual((self.plugin / "notes.txt").read_text(), "keep me")


class NoticesTest(unittest.TestCase):
    """The notifications' words and their pixel badge."""

    def setUp(self):
        notices._ids_path().unlink(missing_ok=True)

    GREY_THEME = {"foreground": "#cacccc", "background": "#101315", "urgent": "#565d60"}
    RED_THEME = {"foreground": "#cacccc", "background": "#101315", "urgent": "#e06c75"}

    def test_the_words(self):
        self.assertEqual(notices.updated_text("1.9"), ("Sonus updated to 1.9", "Click to open the mixer."))
        self.assertEqual(notices.updated_text("", True),
                         ("Sonus updated", "Your local edits are in git stash."))
        self.assertEqual(notices.updated_text("1.12.0", cava_next=True),
                         ("Sonus updated to 1.12.0", "Next it asks for your password "
                          "to install cava, which draws the visualizer."))
        self.assertEqual(notices.failed_text("could not reach github.com"),
                         ("Sonus couldn't update", "Could not reach github.com."))
        self.assertEqual(notices.failed_text("Nope!"), ("Sonus couldn't update", "Nope!"))
        self.assertEqual(notices.failed_text(""), ("Sonus couldn't update", "The update failed."))

    def test_the_slot_in_device_pixels(self):
        # Style.space(40) is 37 on this machine's UI scale.
        self.assertEqual(notices.badge_size(37, 1.25), 46)
        self.assertEqual(notices.badge_size(37, 2.0), 74)
        self.assertEqual(notices.badge_size(40, 1.0), 40)

    def test_the_theme_colours_as_the_shell_reads_them(self):
        colors = notices.theme_colors('foreground = "#aabbcc"\nbackground = "#000000"\ncolor1 = "#ff0000"\n')
        self.assertEqual(colors, {"foreground": "#aabbcc", "background": "#000000", "urgent": "#ff0000"})
        self.assertEqual(notices.theme_colors("")["foreground"], "#cacccc")

    def test_a_failure_takes_the_urgent_colour_only_where_it_reads(self):
        fg = notices.hex_rgb("#cacccc")
        self.assertEqual(notices.tone("updated", self.RED_THEME), fg)
        self.assertEqual(notices.tone("failed", self.RED_THEME), notices.hex_rgb("#e06c75"))
        # Some themes' red is a grey; the warning icon carries it then.
        self.assertEqual(notices.tone("failed", self.GREY_THEME), fg)

    def test_the_logo_is_the_panels(self):
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is missing")
        model = Path(__file__).resolve().parent.parent / "ui" / "Model.js"
        script = ("const fs=require('fs');const vm=require('vm');const c={};vm.createContext(c);"
                  "vm.runInContext(fs.readFileSync(process.argv[1],'utf8').replace('.pragma library',''),c);"
                  "console.log(JSON.stringify({lit:c.sonusLogo(null,'lit'),track:c.sonusLogo(null,'track')}))")
        out = json.loads(subprocess.run([node, "-e", script, str(model)], capture_output=True,
                                        text=True, check=True).stdout)

        def cells(rects):
            return {(x + dx, y + dy) for x, y, w, h in rects for dx in range(w) for dy in range(h)}

        for part in ("lit", "track"):
            for grid in ("g12", "g24"):
                self.assertEqual(cells(notices.logo(part)[grid]), cells(out[part][grid]), (part, grid))

    def alphas(self, rows):
        return {rows[y][x * 4 + 3] for y in range(len(rows)) for x in range(len(rows[0]) // 4)}

    def test_the_badge_is_whole_pixels_of_the_tone(self):
        for size in (46, 74, 40):
            for kind in ("updated", "failed"):
                rows = notices.badge(kind, size, self.RED_THEME)
                self.assertEqual(len(rows), size)
                self.assertEqual(len(rows[0]), size * 4)
                # The tile, the meter's track, its outline, the mark's dim
                # track and solid: nothing in between, so nothing was smoothed.
                tile = round(0.14 * 255)
                allowed = {tile, 255}
                for a in (0.12, 0.6, 0.4):
                    sa = round(a * 255) / 255
                    allowed.add(round((sa + tile / 255 * (1 - sa)) * 255))
                self.assertLessEqual(self.alphas(rows), allowed, (kind, size))
                rgb = notices.tone(kind, self.RED_THEME)
                self.assertEqual(tuple(rows[0][0:3]), rgb)

    def test_the_meter_says_whether_it_went_through(self):
        size = 46
        u = size // 20
        top = (size - 20 * u) // 2
        bx, by = (size - 18 * u) // 2, top + 14 * u

        def lit(rows):
            return [rows[by + 2 * u][(bx + 2 * u + n * 3 * u) * 4 + 3] == 255 for n in range(5)]

        self.assertEqual(lit(notices.badge("updated", size, self.RED_THEME)), [True] * 5)
        self.assertEqual(lit(notices.badge("failed", size, self.RED_THEME)), [False] * 5)

    def test_the_icon_fills_twelve_units(self):
        for size in (46, 74):
            u = size // 20
            rows = notices.badge_pixels(size, [({"g24": [[0, 0, 24, 24]], "g12": [[0, 0, 12, 12]]}, 1.0)], 0, (1, 2, 3))
            solid = [(x, y) for y in range(size) for x in range(size) if rows[y][x * 4 + 3] == 255]
            xs = [x for x, y in solid if y < (size - 20 * u) // 2 + 12 * u]
            self.assertEqual(max(xs) - min(xs) + 1, 12 * u, size)

    def test_the_badge_goes_to_the_state_dir(self):
        path = Path(notices.write_badge("updated", 46, self.RED_THEME))
        plugin = Path(__file__).resolve().parent.parent
        self.assertFalse(str(path).startswith(str(plugin)))
        self.assertEqual(path.name, "updated-46.png")
        data = path.read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(data[16:24], bytes([0, 0, 0, 46, 0, 0, 0, 46]))
        self.assertFalse(path.name.endswith("-symbolic.png"))

    def test_the_command(self):
        cmd = notices.command("T", "B", "/x.png", ["omarchy-shell", "sonus", "open"], 7)
        self.assertIn("string:omarchy-exec-argv:" + json.dumps(["omarchy-shell", "sonus", "open"]), cmd)
        self.assertEqual(cmd[cmd.index("-r") + 1], "7")
        self.assertEqual(cmd[cmd.index("-i") + 1], "/x.png")
        self.assertEqual(cmd[-3:], ["--", "T", "B"])
        self.assertNotIn("-r", notices.command("T", "B", "", ["x"]))
        self.assertEqual(notices.command("T", "B", "", ["x"])[notices.command("T", "B", "", ["x"]).index("-i") + 1],
                         "audio-card")

    def test_a_success_takes_the_place_of_a_failure(self):
        with mock.patch.object(notices, "send", side_effect=[11, 12, 13, 14]) as send:
            notices.failed("no network")
            notices.failed("still no network")
            notices.updated("1.9")
            notices.updated("2.0")
        calls = send.call_args_list
        self.assertEqual(calls[0].args[0], "failed")
        self.assertEqual(calls[0].args[3], ["omarchy-shell", "sonus", "settings"])
        self.assertEqual(calls[0].args[4], 0)
        # A second failure replaces the first, and the success the second.
        self.assertEqual(calls[1].args[4], 11)
        self.assertEqual(calls[2].args[0], "updated")
        self.assertEqual(calls[2].args[3], ["omarchy-shell", "sonus", "open"])
        self.assertEqual(calls[2].args[4], 12)
        # With the failure answered, the next success is a card of its own.
        self.assertEqual(calls[3].args[4], 0)

    def test_the_preview_leaves_real_failures_alone(self):
        with mock.patch.object(notices, "send", side_effect=[21, 22, 23, 24]) as send:
            notices.failed("no network")
            notices.preview("1.9", delay=0)
            notices.updated("1.9")
        calls = send.call_args_list
        self.assertEqual(calls[1].args[4], 0)
        self.assertEqual(calls[2].args[4], 22)
        self.assertEqual(calls[3].args[4], 21)


class RemoveTest(unittest.TestCase):
    def test_stop_graph_takes_the_shortcut_out(self):
        from sonus.engine import strip_shortcut
        tmp = Path(tempfile.mkdtemp(prefix="sonus-binds-")) / "bindings.lua"
        tmp.write_text('o.bind("SUPER + A", "A", "a")\n\n'
                       '-- >>> sonus shortcut (written by Sonus; keeps Ctrl+Alt+V on the panel)\n'
                       'hl.unbind("CTRL + ALT + V")\n'
                       'o.bind("CTRL + ALT + V", "Sonus", "omarchy-shell sonus toggle")\n'
                       '-- <<< sonus shortcut\n', encoding="utf-8")
        self.assertTrue(strip_shortcut(tmp))
        self.assertEqual(tmp.read_text(encoding="utf-8"), 'o.bind("SUPER + A", "A", "a")\n')
        self.assertFalse(strip_shortcut(tmp))


class CavaTest(unittest.TestCase):
    """A password prompt for cava never comes out of nowhere: Sonus asks on
    its own only right after an update said so, with the Visualizer on, and a
    closed prompt is a no until the Install button."""

    def setUp(self):
        cava._state_path().unlink(missing_ok=True)

    def test_it_asks_only_after_an_update_said_so(self):
        with mock.patch.object(cava, "installed", return_value=False):
            # A fresh install or a login: nothing on screen explains a prompt.
            self.assertFalse(cava.should_ask(True))
            cava.mark_pending("1.12.0")
            self.assertTrue(cava.should_ask(True))
            # The Visualizer switch is off: never.
            self.assertFalse(cava.should_ask(False))
            # Once a prompt showed, not again for that version.
            cava.record(cava.Result(False, 1, message="pacman failed"), "1.12.0")
            self.assertFalse(cava.should_ask(True))
            cava.mark_pending("1.13.0")
            self.assertTrue(cava.should_ask(True))
        with mock.patch.object(cava, "installed", return_value=True):
            self.assertFalse(cava.should_ask(True))

    def test_an_old_update_does_not_ask(self):
        with mock.patch.object(cava, "installed", return_value=False):
            cava.write_state({"pending": "1.12.0", "at": time.time() - cava.PENDING_FRESH - 1})
            self.assertFalse(cava.should_ask(True))

    def test_a_no_is_for_good_until_the_button(self):
        with mock.patch.object(cava, "installed", return_value=False):
            cava.mark_pending("1.12.0")
            cava.record(cava.Result(False, 126, message=cava.failure(126)), "1.12.0")
            self.assertEqual(cava.read_state(), {"declined": True})
            cava.mark_pending("1.13.0")
            self.assertFalse(cava.should_ask(True))
            self.assertFalse(cava.will_ask(True))
            cava.forget_decline()
            self.assertTrue(cava.will_ask(True))

    def test_no_agent_is_not_a_no(self):
        result = cava.Result(False, 127, no_agent=True, message=cava.failure(127, True))
        self.assertFalse(result.declined)
        self.assertFalse(result.prompted)
        with mock.patch.object(cava, "installed", return_value=False):
            cava.mark_pending("1.12.0")
            cava.record(result, "1.12.0")
            self.assertTrue(cava.should_ask(True))

    def _install(self, code, stderr=""):
        tools = {"pacman": "/usr/bin/pacman", "pkexec": "/usr/bin/pkexec", "systemd-run": "/usr/bin/systemd-run"}
        runs = []

        def run(argv, **kwargs):
            runs.append(argv)
            if argv[0] == "systemd-run":
                return subprocess.CompletedProcess(argv, code, "", stderr)
            return subprocess.CompletedProcess(argv, 0, "", "")

        with mock.patch.object(cava, "installed", return_value=False), \
                mock.patch.object(cava, "running", return_value=False), \
                mock.patch.object(cava.shutil, "which", side_effect=tools.get), \
                mock.patch.object(cava.subprocess, "run", side_effect=run):
            return cava.install(), next(argv for argv in runs if argv[0] == "systemd-run")

    def test_a_closed_prompt_says_so(self):
        result, unit = self._install(126)
        self.assertTrue(result.declined)
        self.assertEqual(result.message, "The password prompt was closed")
        self.assertEqual(unit[-6:], ["pkexec", "pacman", "-S", "--needed", "--noconfirm", "cava"])
        self.assertIn("--wait", unit)
        self.assertIn("--pipe", unit)

    def test_no_agent_is_told_apart(self):
        result, _ = self._install(127, "Error executing command as another user: No authentication agent found.")
        self.assertTrue(result.no_agent)
        self.assertFalse(result.declined)

    def test_a_pacman_failure_says_what_to_do(self):
        result, _ = self._install(1)
        self.assertTrue(result.prompted)
        self.assertEqual(result.message,
                         "pacman could not install cava. Update the system (omarchy update) and try again")

    def test_without_pacman_it_asks_for_a_hand(self):
        with mock.patch.object(cava, "installed", return_value=False), \
                mock.patch.object(cava.shutil, "which", return_value=None):
            result = cava.install()
        self.assertEqual(result.message, "Install cava with your package manager")
        self.assertFalse(result.prompted)

    def test_an_engine_restarting_the_shell_leaves_it_to_the_next(self):
        from sonus.engine import Engine
        engine = mock.MagicMock()
        engine._restarting = True
        with mock.patch.object(cava, "install") as install, mock.patch.object(cava, "should_ask", return_value=True):
            Engine.cava_startup(engine)
        install.assert_not_called()
        engine.install_cava.assert_not_called()

    def test_after_an_update_it_asks(self):
        from sonus.engine import Engine
        engine = mock.MagicMock()
        engine._restarting = False
        with mock.patch.object(cava, "running", return_value=False), \
                mock.patch.object(cava, "should_ask", return_value=True), \
                mock.patch.object(time, "sleep"):
            Engine.cava_startup(engine)
        engine.install_cava.assert_called_once_with()

    def test_startup_reports_cava_before_waiting_on_an_update(self):
        from sonus.engine import Engine
        engine = mock.MagicMock()
        order = []
        engine.emit_cava.side_effect = lambda: order.append("cava")
        engine.resume_update.side_effect = lambda: order.append("update")
        Engine.startup(engine)
        self.assertEqual(order[:2], ["cava", "update"])

    def test_an_update_marks_the_ask_only_with_the_visualizer_on(self):
        from sonus.engine import Engine
        for on in (True, False):
            cava._state_path().unlink(missing_ok=True)
            engine = mock.MagicMock()
            engine.visualizer_on.return_value = on
            with mock.patch.object(updater, "restart_shell", return_value=True), \
                    mock.patch.object(cava, "installed", return_value=False), \
                    mock.patch.object(notices, "updated") as notify:
                Engine._report_update(engine, {"ok": True, "version": "1.12.0"})
            notify.assert_called_once_with("1.12.0", False, cava_next=on)
            self.assertEqual(cava.read_state().get("pending"), "1.12.0" if on else None)


if __name__ == "__main__":
    unittest.main()
