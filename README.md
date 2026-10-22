# Sonus for Omarchy

Sonar-style mixer for PipeWire as an Omarchy shell plugin: Master plus Game, Chat, Media and Aux channels, drag-and-drop app routing, and a 10-band EQ per category. It's the [Sonus](https://github.com/T3lluz/Sonus) desktop app rebuilt as a native Omarchy panel that drops down from the bar.

## Install

```sh
omarchy plugin add https://github.com/T3lluz/omarchy-sonus.git --enable
```

Bind the hotkey in `~/.config/hypr/bindings.lua`:

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
| `j`/`k`, `h`/`l`, `m`, `e`, `1`-`4`/`0`, `s`, `esc` | Move, volume, mute, EQ, assign, settings, back |

`omarchy-shell sonus eq chat` and `omarchy-shell sonus settings` open a view directly. `omarchy-shell sonus takeover` retires the Sonus desktop app (stops it, removes its autostart), the same as the panel's **Switch**.

## How it works

`bin/sonus-engine` (Python, stdlib only) is the desktop app's PipeWire logic: filter-chain sinks with the EQ, route enforcement, and keeping EasyEffects from double-EQing or stealing streams. The service runs it and talks JSON lines with it. The channel graph runs as the transient user unit `sonus-graph.service`, so it survives shell restarts. Settings live in `~/.config/sonusdeck/settings.json`, shared with the desktop app, so routes and EQ carry over. While the desktop app runs, the plugin pauses routing and offers **Switch**.

Stop the channels: `python3 -I bin/sonus-engine --stop-graph`.

## License

MIT
