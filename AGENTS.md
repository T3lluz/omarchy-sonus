# AGENTS.md

How Sonus is put together, for anyone (or any agent) changing it. The user-facing story is in [README.md](README.md).

## Layout

- `Service.qml`: always loaded. Runs `bin/sonus-engine` and talks JSON lines with it; mirrors its state for the panel; owns the `sonus` IPC target; keeps the Ctrl+Alt+V Hyprland bind in `~/.config/hypr/bindings.lua` via `ui/Shortcut.js`.
- `Panel.qml`, `ui/`: the bar entry and panel, once per monitor, all reading the one service. The mixer is a wide panel of tiles with no empty rows. The top row is `HeroBlock.qml` (title, changing caption, settings) in the first column, then `DeviceTile.qml` for the output and the input, one line each, with `DeviceList.qml` sliding open under them as small tiles on the channels' four columns. Below that, `ChannelTile.qml` for the four channels in one row, each with its fader on top and its bucket of `AppCard.qml`s along the bottom; `NoChannelTile.qml` is a strip under them for apps that skip the channels. Every tile and card is the same two parts: `TileHead.qml` (icon, name, a line of state) and `TileFader.qml` (mute, fader, percent). `Panel.qml` sets the shared sizes (`iconCol`, `percentW`, `tilePad`, `tileGap`), copied from Omarchy's own panels, and `mixerWidth`, the one number that isn't: the official 380 can't hold four channels in a row. Settings stays at 380. `Grip.qml` is the drag sign, `DragHandle.qml` picks an app up. `ui/Eq.js` is the panel's copy of the EQ model, `ui/Audio.js` the panel's words, `ui/Glyphs.js` its icons. `ui/` also holds the panel kit (below).
- **Icons** are Material Design glyphs from the theme's Nerd Font, as in the official panels: 16 px in a tile's 22 px column, 14 px on buttons and rows, 24 px only in the hero. App icons come from the icon theme at 16 px. A channel's icon must not look like a device's; `tests/audio.test.js` checks it.
- **Changing text.** Explanation lives in the hero's caption, not in paragraphs: `Panel.heroLine` says what is happening (a drag, a just-finished move or switch) and otherwise rotates the facts from `Audio.heroPhrases` every 2.8 s with the official panels' crossfade. The caption keeps room for two lines in the hero's column, so anything with a name in it goes through `Audio.fitted`. A tile's own line changes the same way. Tooltips carry the rest.
- `engine/sonus/`: the engine (Python, stdlib only). `graph.py` renders and runs the filter-chain graph as `sonus-graph.service`; `pipewire.py` reads and moves streams; `eq.py` is the EQ model; `profiles.py` is the per-output-device volume and EQ; `config.py` the settings in `~/.config/sonusdeck/settings.json`, shared with the Sonus desktop app.
- `bin/sonus-engine`: the entry point. It sets `sys.dont_write_bytecode` so `engine/` never gains a `__pycache__`.

## Test

```bash
node tests/eq.test.js
node tests/audio.test.js
node tests/shortcut.test.js
python3 -B -m unittest discover tests
omarchy-shell sonus status | jq
```

`ui/Eq.js` and `engine/sonus/eq.py` must agree on the bands; `tests/eq.test.js` checks it. `ui/Shortcut.js` owns the Ctrl+Alt+V block; `tests/shortcut.test.js` checks the unbind-before-bind shape.

Sonus keeps its own settings file rather than `shell.json`, so the `WidgetSettings.qml` rule below does not apply to it; the rest does.

## Panel kit

`SectionHeader`, `StatTile`, `ToggleTile`, `SwitchRow`, `Seg`, `Notice`, `LevelBar`, `OptionRow`, `Caption` and `UpdateSection` in `ui/` are the panel kit: the same files, byte for byte, in ROG Deck, Batteries, Sonus and Server Dashboard, so the four look like one family. Change a kit file in all four or not at all. `Glyph.qml` is the one part each plugin owns: Nerd Font glyphs here, drawn Tabler icons in Batteries.

Panels never cut text: a `Notice` shows all of its message, a `Caption` breaks long words and paths, and a `ToggleTile` label that does not fit shows in full in its tooltip.

## Rules that are easy to break

- **Settings** are read with `setting(key, fallback)` and saved with `persistSettings({...})`. Both go through `WidgetSettings.qml`, which reads `~/.config/omarchy/shell.json` itself. Never read `settings.foo` directly: the bar's copy turns a list into a Qt sequence that fails `Array.isArray`, and after a plugin reload it can be older than the file. Either one makes a pick look unset, which is how choices "reset after a reboot" or differ between monitors.
- **One widget per monitor.** The bar draws the widget on every screen. Long-running work (a poller, a client, a process) lives in one place, a leader instance or the service, and the others read from it. Never start it per instance.
- **IPC** is answered by whichever monitor's widget registered first, so `open`, `close` and `toggle` go through the shell's `summon`, `hide` and `toggle`, which pick the focused monitor.
- **Nothing may write inside the plugin folder at runtime.** The shell watches it and reloads every plugin when a file appears there. Python sets `sys.dont_write_bytecode`; state goes to `~/.local/state` or `~/.config`.
- **Updates run detached.** `omarchy plugin update` writes into the plugin folder, which reloads the plugin and ends the engine. `updater.start` launches the runner as `sonus-update.service` so it outlives that, and the next engine reports its result from `~/.local/state/sonus/update.json`. Never run the update as a child of the engine.
- **Apps are what apps play.** A filter-chain or loopback plays into the hardware through a stream of its own; `pipewire.is_app_stream` keeps those (anything with `node.link-group` and no binary) out of the app list.
- **QML changes need `omarchy restart shell`.** Hot reload can keep the old component cached.
- **Pure logic goes in `Model.js`** (a `.pragma library` with no QML) so `node tests/*.test.js` can run it. Change it with a test.
- Comments say why, in plain sentences. Match the surrounding code.

## Release

Bump `version` in `manifest.json` and the version badge in `README.md` together, run the tests, and describe the change for the person using it in the commit message.
