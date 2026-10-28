# AGENTS.md

How Sonus is put together, for anyone (or any agent) changing it. The user-facing story is in [README.md](README.md).

## Layout

- `Service.qml`: always loaded. Runs `bin/sonus-engine` and talks JSON lines with it; mirrors its state for the panel; owns the `sonus` IPC target.
- `Panel.qml`, `ui/`: the bar entry and panel, once per monitor, all reading the one service. `ui/Eq.js` is the panel's copy of the EQ model.
- `engine/sonus/`: the engine (Python, stdlib only). `graph.py` renders and runs the filter-chain graph as `sonus-graph.service`; `pipewire.py` reads and moves streams; `eq.py` is the EQ model; `profiles.py` is the per-output-device volume and EQ; `config.py` the settings in `~/.config/sonusdeck/settings.json`, shared with the Sonus desktop app.
- `bin/sonus-engine`: the entry point. It sets `sys.dont_write_bytecode` so `engine/` never gains a `__pycache__`.

## Test

```bash
node tests/eq.test.js
python3 -B -m unittest discover tests
omarchy-shell sonus status | jq
```

`ui/Eq.js` and `engine/sonus/eq.py` must agree on the bands; `tests/eq.test.js` checks it.

Sonus keeps its own settings file rather than `shell.json`, so the `WidgetSettings.qml` rule below does not apply to it; the rest does.

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
