# AGENTS.md

How Sonus is put together, for anyone (or any agent) changing it. The user-facing story is in [README.md](README.md).

## Layout

- `Service.qml`: always loaded. Runs `bin/sonus-engine` and talks JSON lines with it; mirrors its state for the panel; owns the `sonus` IPC target; keeps the Ctrl+Alt+V Hyprland bind in `~/.config/hypr/bindings.lua` via `ui/Shortcut.js`.
- `Panel.qml`, `ui/`: the bar entry and panel, once per monitor, all reading the one service. The mixer is a wide panel of rooms (see Panel look) with no empty rows. The top row is a room holding `HeroBlock.qml` (the mark, title, the prompt line, settings) over Game, then `DeviceTile.qml` for the output and the input sharing the rest equally: device names run long, and a channel's column leaves a three-digit figure no room for one. `DeviceList.qml` slides open under them as small rooms on the channels' four columns. Below that, `ChannelTile.qml` for the four channels in one row, each with its fader on top, its equalizer drawer under it, and its bucket of `AppCard.qml`s along the bottom; `NoChannelTile.qml` is a room under them for apps that skip the channels. Every room is `Room.qml` (tint, rise, ripple, click) around `RoomHeader.qml` (pixel icon, name and chevron, a decoding state line, `BigFigure.qml`) and `Fader.qml` (the mute button in the icon column, then `Meter.qml`, the cells that are also the fader). `Drawer.qml` is what a click opens. `Panel.qml` sets the shared sizes (`roomPad`, `roomGap`, `iconColumn`, `textInset`) and `mixerWidth`, wider than the official 380 so four channels fit in a row. Settings stays at 380. `Grip.qml` is the drag sign, `DragHandle.qml` picks an app up. `HoverCard.qml` is what the bar item opens on hover, a `HoverRow.qml` per room. `SonusLogo.qml` draws the mark. `ui/Model.js` is the Rooms logic (tones, block face, pixel type, cells, stories, decode, icon maps, the hover card's rows), `ui/Eq.js` the panel's copy of the EQ model, `ui/Audio.js` the panel's words, `ui/Glyphs.js` the Nerd Font glyphs handed to the kit and the shell's volume toast. `ui/` also holds the panel kit (below).
- **Icons** are pixel art from one set, Pixelarticons (MIT), drawn by `PixelIcon.qml` on whole device pixels from `ui/Pixels.js`: never scaled, smoothed or turned off the quarter turns. `scripts/fetch-pixel-icons.py` builds `Pixels.js` (and keeps the source SVGs in `pixels/`), plus the AirPods drawn by hand in the same weight. Add an icon to its `ICONS` list and run it; `--show` prints the grids. Apps keep their own icons from the icon theme, in their own colours; only a missing one falls back to the pixel `app-windows`.
- **The mark** is the app icon's three faders in pixels (`Model.sonusLogo`, drawn by `SonusLogo.qml`): one-cell tracks, knobs three by two, the track lit under each knob and dim over it. In the bar that is the bar's foreground and its dim colour, at the shell's icon size. Muted, the faders are down and all of it dim. In the panel's title room the knobs rise into place on opening and slide down and back on mute (`Model.logoKnobs`), a whole row at a time. A channel's icon must not look like a device's; `tests/model.test.js` checks it, and that every name the QML uses exists.
- **Changing text.** Explanation lives in the hero's prompt line, not in paragraphs: `Panel.heroLine` says what is happening (a drag, an open room, a just-finished move or switch) and otherwise rotates the facts from `Audio.heroPhrases` every 2.8 s, each typed out behind a cursor. A line that follows the pointer (a drag, a fader) shows at once. The prompt keeps room for two lines in the hero's column, so anything with a name in it goes through `Audio.fitted`. State lines under a room's name decode on opening only. Tooltips carry the rest.
- `engine/sonus/`: the engine (Python, stdlib only). `graph.py` renders and runs the filter-chain graph as `sonus-graph.service`; `pipewire.py` reads and moves streams; `eq.py` is the EQ model; `profiles.py` is the per-output-device volume and EQ; `config.py` the settings in `~/.config/sonusdeck/settings.json`, shared with the Sonus desktop app.
- `engine/sonus/notices.py`: the desktop notifications ("Sonus updated", "Sonus could not update"), in the Rooms look the guide's Notifications section sets out. They stay real notifications sent with `notify-send`, never a window of our own, which would cover the shell's stack. The picture is a pixel badge drawn in Python for the shell's picture slot in device pixels: `Service.qml` sends `Style.space(40)` (`look`), the engine multiplies it by the focused screen's scale from `hyprctl` and writes the PNG to `~/.local/state/sonus/notices/`. The mark or `warning-diamond` comes from `ui/Pixels.js`; the mark's shape is copied from `Model.sonusLogo`, and a test holds the two together. Updated is the text colour (the title room has no tone) with its meter full; failed is the urgent colour where it reads on the background, with the meter empty. A click opens the panel, or the settings page for a failure. A second failure replaces the first, and a success replaces a failure still up (ids in `~/.local/state/sonus/notices.json`). `omarchy-shell sonus previewNotices` runs that life on made-up values. On a 1.25 screen the slot is a fraction of a device pixel and the shell smooths the picture, so the badge shows a little soft there however it is drawn.
- `bin/sonus-engine`: the entry point. It sets `sys.dont_write_bytecode` so `engine/` never gains a `__pycache__`.

## Test

```bash
node tests/eq.test.js
node tests/audio.test.js
node tests/model.test.js
node tests/shortcut.test.js
python3 -B -m unittest discover tests
omarchy-shell sonus status | jq
```

`ui/Eq.js` and `engine/sonus/eq.py` must agree on the bands; `tests/eq.test.js` checks it. `ui/Shortcut.js` owns the Ctrl+Alt+V block; `tests/shortcut.test.js` checks the unbind-before-bind shape.

Sonus keeps its own settings file rather than `shell.json`, so the `WidgetSettings.qml` rule below does not apply to it; the rest does.

## Panel look

The mixer is in the Rooms look Batteries 2.8 set (the brief is `files get key:roomstheme`): each thing a room tinted in its own tone, numbers in a block face, pixel icons, and motion that answers what happens. The settings page keeps the panel kit, so it matches the other plugins. Scaled through `Style`.

- Rooms: padding 10, joined by 3, `Style.cornerRadius`, the tone at 0.065 alpha, 0.11 under the pointer or while open, 0.17 with an outline as a drop target. The keyboard's cursor adds a 1 px outline in the tone, so it reads apart from the pointer.
- Tones (`Model.toneName`, `Model.roomToneHex`): the output and input are the machine (blue), Game is play (green), Chat a connection (cyan), Media media (magenta), Aux yellow; the title room and the apps that skip the channels have none and take the text colour. The theme's colour of that name from its `colors.toml` (read on each open) when it is a colour, else DailyDash's hue, softened 30% toward the text colour. An app card takes its channel's tone. Only the panel and the hover card use tones; the bar keeps the bar's colours.
- A room's header: pixel icon at `font.heading` × 1.25 (20) in the tone, `font.body` bold name with a `font.caption` chevron that flips when the room is open, `font.caption` state dimmed, the volume as `BigFigure` on the `font.bodySmall` grid on the right. Its mark column (`Model.markFor`) holds `volume-x` or `mic-off` when muted, else `sliders-horizontal` when the channel's EQ shapes the sound; muted also greys the figure. An app's volume is in the pixel type, small, so the channels' figures stay the big ones.
- Meters: ten cells, a tenth each (an app's are thin), track at 0.12, outline at 0.6, no nub. The meter is the fader: press or drag across it in 5% steps, a 1 px tick shows where the pointer would set it, right-click mutes. The input's meter lights the cells it hears (`peak`).
- Clicks open things: a device room its devices, a channel room its equalizer (on or off, and the way into the curve), an app card its channels as buttons in their tones. One open at a time.

Motion, all on one clock (`entry` goes up on each open; `clock` ticks only while a ripple runs) and all off with reduced motion:

- Opening: rooms rise 12 and fade in, 70 ms apart; each meter fills from empty over 680 ms while its figure counts up; state lines decode out of scrambled glyphs; each icon plays its story (`Model.storyOf`: a controller shakes, a chat buzzes, media pulses, earbuds tilt); the prompt types itself out.
- Pointer: cells under it give; a click ripples out through the room's meter (Weave's 760 ms), plays the icon again and opens the room, its drawer sliding over 280 ms.
- Changes while open: a level slides to its new value in 420 ms. Pages slide 18 px in from their side, and the gear turns in 45° steps.



`SectionHeader`, `StatTile`, `ToggleTile`, `SwitchRow`, `Seg`, `Notice`, `LevelBar`, `OptionRow`, `Caption` and `UpdateSection` in `ui/` are the panel kit: the same files, byte for byte, in ROG Deck, Batteries, Sonus and Server Dashboard, so the four look like one family. Change a kit file in all four or not at all. `Glyph.qml` is the one part each plugin owns: here it looks the glyph up in `Model.PIXEL_GLYPHS` and draws its pixel icon, so the kit's icons match the rooms'. Map every glyph Sonus hands the kit there; `tests/model.test.js` checks `Glyphs.js` against it. The one icon it cannot reach is the "Check now" button inside `UpdateSection`.

Panels never cut text: a `Notice` shows all of its message, a `Caption` breaks long words and paths, and a `ToggleTile` label that does not fit shows in full in its tooltip. Every text that can hold a name wraps with `Text.Wrap` (at words, and inside a word only when the word alone is wider than its column, like `alsa_output.usb-…`), never `WordWrap`, which lets such a word run out of its column. A room's name keeps its chevron after its last line. Check layout changes against long names and three-digit volumes at the panel's real width: `Style.space` scales, so the 860 mixer is about 790 on this machine.

## Rules that are easy to break

- **Settings** are read with `setting(key, fallback)` and saved with `persistSettings({...})`. Both go through `WidgetSettings.qml`, which reads `~/.config/omarchy/shell.json` itself. Never read `settings.foo` directly: the bar's copy turns a list into a Qt sequence that fails `Array.isArray`, and after a plugin reload it can be older than the file. Either one makes a pick look unset, which is how choices "reset after a reboot" or differ between monitors.
- **One widget per monitor.** The bar draws the widget on every screen. Long-running work (a poller, a client, a process) lives in one place, a leader instance or the service, and the others read from it. Never start it per instance.
- **IPC** is answered by whichever monitor's widget registered first, so `open`, `close` and `toggle` go through the shell's `summon`, `hide` and `toggle`, which pick the focused monitor.
- **Nothing may write inside the plugin folder at runtime.** The shell watches it and reloads every plugin when a file appears there. Python sets `sys.dont_write_bytecode`; state goes to `~/.local/state` or `~/.config`.
- **Updates run detached.** `omarchy plugin update` writes into the plugin folder, which reloads the plugin and ends the engine. `updater.start` launches the runner as `sonus-update.service` so it outlives that, and the next engine reports its result from `~/.local/state/sonus/update.json`. That next engine runs the new code and restarts the shell, because the shell's plugin reload keeps QML it has already compiled: without the restart, the old panel stays on screen reading the new version. The runner is the old version's code, so anything an update must do afterwards belongs in the next engine. Never run the update as a child of the engine.
- **Apps are what apps play.** A filter-chain or loopback plays into the hardware through a stream of its own; `pipewire.is_app_stream` keeps those (anything with `node.link-group` and no binary) out of the app list.
- **QML changes need `omarchy restart shell`.** Hot reload can keep the old component cached.
- **Pure logic goes in `ui/Model.js`, `ui/Audio.js` or `ui/Eq.js`** (`.pragma library` files with no QML) so `node tests/*.test.js` can run it. Change it with a test.
- **Pixel art stays sharp.** `Rectangle`s with `antialiasing: false`, positions in whole cells of the icon's own grid (`PixelIcon.cell`), never `scale` or a turn other than a quarter (the gear's eighths are the one exception, and only while it turns).
- Comments say why, in plain sentences. Match the surrounding code.

## Release

Bump `version` in `manifest.json` and the version badge in `README.md` together, run the tests, and describe the change for the person using it in the commit message.
