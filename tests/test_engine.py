# Run with: python3 -m unittest discover tests
import os
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
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "engine"))

from sonus import config, eq, graph, pipewire  # noqa: E402


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


class SettingsTest(unittest.TestCase):
    def test_save_keeps_unknown_keys_and_load_fills_defaults(self):
        config.save_settings({"routes": "broken", "window": {"x": 1}})
        loaded = config.load_settings()
        self.assertEqual(loaded["routes"], {})
        self.assertEqual(loaded["window"], {"x": 1})
        self.assertTrue(loaded["manage_graph"])
        self.assertTrue(str(config.SETTINGS_PATH).startswith(_config_home))


if __name__ == "__main__":
    unittest.main()
