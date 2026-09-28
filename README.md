# Hypha (균사)

A Star Fox-style tank shooter in pastel ditherpunk. Drive the Orca-class, with Ha Yoon at the controls,
through a fungus-infested, abandoned Korean farming village. Stage 1 runs from the farm road, through the village,
branch school, reservoir and overpass, to a gunship fight below the dam. See [`GOAL.md`](GOAL.md) for the design.

## Play

Requires Godot 4.7.2 (stable).

```sh
godot --path .
```

`godot --path . -- --play` skips the title screen.

FPS is displayed below the score in the upper-left corner, including in menus and while paused.

### Web

Install the Godot 4.7.2 export templates through **Editor → Manage Export Templates**, then export the
[`Web` preset](export_presets.cfg) and serve it locally:

```sh
mkdir -p builds/web
touch builds/.gdignore
godot --headless --path . --export-release Web builds/web/index.html
python3 -m http.server 8000 --bind 127.0.0.1 --directory builds/web
```

Open [the local game](http://127.0.0.1:8000) in a desktop browser with WebGL 2 and WebAssembly. Click the game
to focus it and enable audio; keyboard, mouse and gamepad controls are the same as on desktop.

To publish, serve the entire `builds/web/` directory from an HTTPS static host, keeping the generated filenames.
The Web build uses the Compatibility renderer and preserves worker threads for terrain generation. Its generated
PWA service worker supplies the cross-origin isolation headers required for threads, so the page may reload once
on its first visit. A host can also supply `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp` directly. See [Godot's Web export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#serving-the-files).

### Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move within the corridor | WASD | Left stick |
| Aim turret | Mouse | Right stick (with light aim assist) |
| Coaxial gun (hold; leads the soft-locked target) | Left mouse | RT |
| 100 mm main gun | Right mouse | LT |
| Boost / brake (shared meter) | Hold W / S | Left stick |
| Dash (the tail kicks the hull that way) | Double-tap a direction | LB / RB (sideways) |
| Pause | Esc | Start |

The tail acts on its own: it snatches pickups, grabs and throws small enemies, stabs large ones and swats diving
drones. Keyboard and mouse bindings can be changed in Settings → Controls.

## Develop

Tests (headless, deterministic frame time):

```sh
godot --headless --path . --import   # refresh the class cache after adding class_name scripts
godot --headless --fixed-fps 60 --path . -- --run=res://tests/run.gd [--only=tail]
```

The exit code is the number of failed checks.

Debug room (also on the title menu), a gallery of every model and effect on a flat checkered floor (10 m squares): WASD to fly, Q/E
down/up, Shift for speed, right-drag to look, 1–9 to jump between rows.

```sh
godot --path . -- --debug-room
```

Tools run through the main scene with `--run`:

```sh
# Bot playthrough with screenshots and frame timing. A small window keeps xvfb's software presentation cheap.
xvfb-run -a godot --path . --resolution 960x540 -- --run=res://tools/autoplay.gd \
  --seconds=420 --scale=3 --god --shots=30,60 --out=builds/auto [--checkpoint=boss] [--profile]
# Screenshots of every debug room row.
xvfb-run -a godot --path . --resolution 960x540 -- --run=res://tools/debug_room_shots.gd --out=builds/debug_room
# Course fly-through screenshots.
xvfb-run -a godot --path . -- --run=res://tools/capture_course.gd --d=100,700,1620 --out=builds/shots
```

Generated content:

- `python3 tools/strings.py` writes `i18n/strings.csv` (Korean and English).
- `uv run --with numpy tools/audio.py` synthesizes the effects in `assets/audio/synth/` and the music in
  `assets/music/`.

### Layout

- `scripts/core`: palette, flat-shaded mesh builder, dither view, settings and audio autoloads.
- `scripts/world`: course geography, terrain streaming, scenery, stage script and director, rail and camera.
- `scripts/player`: the tank, its model, weapons data and tail.
- `scripts/enemies`: FPV drones, UGVs, UAVs, attack helicopters, crawlers, spitters, the colossus mid-boss and the
  twin-rotor gunship boss.
- `scripts/combat`: hits, entities, projectiles, pickups, hazards and effects.
- `scripts/ui`: HUD, menus, title, results.

## Credits

- Tank concept and specifications: [`scarf005/orca-class`](https://github.com/scarf005/orca-class).
- Recorded sound effects: CC0; see [`assets/audio/ATTRIBUTION.md`](assets/audio/ATTRIBUTION.md).
- Font: x10y12pxDenkiChipHangul, SIL OFL 1.1; see [`assets/fonts/ATTRIBUTION.md`](assets/fonts/ATTRIBUTION.md).
- Synthesized effects, music, models and code were made for this project.
