# Run with: python3 -m unittest discover tests
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# Imports from engine/ would leave bytecode in the plugin folder, and the
# shell reloads every plugin when a file appears there.
sys.dont_write_bytecode = True
# config.py reads XDG_CONFIG_HOME on import; point it somewhere disposable.
_config_home = tempfile.mkdtemp(prefix="sonus-test-")
os.environ["XDG_CONFIG_HOME"] = _config_home
os.environ["XDG_STATE_HOME"] = tempfile.mkdtemp(prefix="sonus-state-")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "engine"))

from sonus import config, eq, graph, pipewire, profiles, updater  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
