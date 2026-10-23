<div align="center">
  <img src="assets/icon.svg" width="72" height="72" alt="Sonus" />
  <h1>Sonus</h1>
  <p>A Sonar-style mixer for <b>PipeWire</b> that drops down from the Omarchy bar:<br/>
  <b>Master</b> plus <b>Game, Chat, Media and Aux</b> channels, drag-and-drop app routing, and a 10-band EQ per channel.</p>
  <p>
    <img alt="Version" src="https://img.shields.io/badge/v1.1.0-111111?label=version" />
    <img alt="Omarchy 4" src="https://img.shields.io/badge/Omarchy-4-a58bff" />
    <img alt="PipeWire" src="https://img.shields.io/badge/PipeWire-filter--chain-a58bff" />
    <a href="https://github.com/T3lluz/omarchy-sonus/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/T3lluz/omarchy-sonus/actions/workflows/ci.yml/badge.svg" /></a>
    <img alt="License" src="https://img.shields.io/badge/license-MIT-34413e" />
  </p>
  <p><a href="#install"><b>Install</b></a> · <a href="#features">Features</a> · <a href="#use">Use</a> · <a href="#how-it-works">How it works</a></p>
  <img src="assets/preview.png" width="360" alt="The Sonus panel: master, four channels and the apps routed to them" />
</div>

## Features

- **Channels:** Game, Chat, Media and Aux are real PipeWire sinks, each with its own volume and mute, all mixed into your output. Master is the output itself.
- **Routing:** drag an app onto a channel, or pick one from its button. Routes are remembered and enforced whenever the app starts playing again, panel open or not. Drop an app on Master to unassign it.
- **EQ per channel:** ten octave bands from 32 Hz to 16 kHz with a preamp, presets (Flat, Bass, Voice, Treble, Steps), the live response curve, and a bypass switch. Changes apply to the running graph with no gap.
- **Keyboard first:** every row, fader and band is reachable without the mouse.
- **No gap on reload:** the channels run as the user unit `sonus-graph.service`, so a shell restart or plugin reload adopts the running graph instead of rebuilding it.
- **Plays well with EasyEffects:** channel outputs land in EasyEffects when it runs, and Sonus keeps it from EQ-ing twice or stealing streams.
- It is the [Sonus](https://github.com/T3lluz/Sonus) desktop app rebuilt as a native Omarchy panel, and shares its settings, so routes and EQ curves carry over. While the desktop app runs, routing pauses here and the panel offers **Switch**.

## Install

```bash
omarchy plugin add https://github.com/T3lluz/omarchy-sonus.git --enable
```

Needs PipeWire with `pipewire-pulse` (Omarchy's default): `pw-dump`, `pw-cli`, `wpctl` and `pactl`. The engine is Python 3, standard library only.

Bind a hotkey in `~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + ALT + V", "Sonus", "omarchy-shell sonus toggle")
```

## Use

| Input | Action |
|---|---|
| Click the bar icon | Open the panel |
| Scroll / middle-click the icon | Master volume / mute |
| Right-click the icon | Settings |
| Drag an app onto a channel | Assign it (drop on Master to unassign) |
| App's channel button | Pick a channel |
| Sliders icon on a channel | That channel's EQ |
| `j`/`k`, `h`/`l` | Move, volume |
| `m`, `e`, `1`–`4` / `0`, `s`, `esc` | Mute, EQ, assign / unassign, settings, back |
| In the EQ: `h`/`l`, `j`/`k`, `0`, `p` | Pick a band, move it, zero it, next preset |

## Commands

```bash
omarchy-shell sonus toggle          # open | close | show | hide
omarchy-shell sonus eq chat         # open one channel's EQ: game | chat | media | aux
omarchy-shell sonus settings
omarchy-shell sonus takeover        # retire the Sonus desktop app: stop it, remove its autostart
omarchy-shell sonus status          # JSON: engine, master volume, apps, output
```

## How it works

- `bin/sonus-engine` (Python, stdlib only) owns the PipeWire side: the filter-chain sinks with the EQ, route enforcement, and keeping EasyEffects from double-EQ-ing or stealing streams. `Service.qml` runs it and talks JSON lines with it over stdin and stdout.
- The channel graph runs as the transient user unit `sonus-graph.service`, so it outlives the shell.
- `Panel.qml` and `ui/` draw the bar icon and panel, one per monitor, all reading the one service.
- Settings live in `~/.config/sonusdeck/settings.json`, shared with the desktop app.

Stop the channels with `python3 -I bin/sonus-engine --stop-graph`.

## Development

```bash
node tests/eq.test.js
python3 -B -m unittest discover tests
omarchy restart shell    # pick up QML changes
```

The tests check that the panel's EQ model (`ui/Eq.js`) and the engine's (`engine/sonus/eq.py`) agree on the band layout. See [AGENTS.md](AGENTS.md) for how the pieces fit.

## License

MIT. Not affiliated with SteelSeries.

One of a set of Omarchy plugins: [Batteries](https://github.com/T3lluz/omarchy-batteries) · [ROG Deck](https://github.com/T3lluz/omarchy-rog-deck) · **Sonus** · [Server Dashboard](https://github.com/T3lluz/omarchy-server-dashboard)
