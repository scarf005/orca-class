set positional-arguments := true

godot := env("GODOT", "godot")
butler := env("BUTLER", "butler")
itch_project := env("ITCH_PROJECT", "scarf005/orca-class")

# List common actions.
default:
    @just --list

# Run the game; extra arguments are passed to the main scene.
run *args:
    {{ quote(godot) }} --path . -- "$@"

# Skip the title screen.
play *args:
    {{ quote(godot) }} --path . -- --play "$@"

# Fight one hunter group over and over (tiltrotor and walkers) on a held rail.
duel *args:
    {{ quote(godot) }} --path . -- --duel "$@"

# Open the debug room.
debug-room:
    {{ quote(godot) }} --path . -- --debug-room

# Refresh imported assets and the script class cache.
import:
    {{ quote(godot) }} --headless --path . --import

# Run all tests, or filter by filename (e.g. just test tail).
test only="": import
    {{ quote(godot) }} --headless --fixed-fps 60 --path . -- --run=res://tests/run.gd --only="$1"

# Export the web build (requires Godot export templates).
export-web: import
    mkdir -p builds/web
    touch builds/.gdignore
    {{ quote(godot) }} --headless --path . --export-release Web builds/web/index.html
    test -s builds/web/index.html
    test -s builds/web/index.pck
    test -s builds/web/index.wasm

# Export Linux, Windows, and macOS into the itch.io desktop bundle.
export-desktop: import
    mkdir -p builds/desktop/linux builds/desktop/windows builds/desktop/mac
    touch builds/.gdignore
    {{ quote(godot) }} --headless --path . --export-release Linux builds/desktop/linux/OrcaClass.x86_64
    {{ quote(godot) }} --headless --path . --export-release "Windows Desktop" builds/desktop/windows/OrcaClass.exe
    {{ quote(godot) }} --headless --path . --export-release macOS builds/desktop/mac/OrcaClass.app
    cp tools/desktop.itch.toml builds/desktop/.itch.toml
    chmod +x builds/desktop/linux/OrcaClass.x86_64
    test -s builds/desktop/linux/OrcaClass.x86_64
    test -s builds/desktop/windows/OrcaClass.exe
    test -s 'builds/desktop/mac/OrcaClass.app/Contents/MacOS/orca class'

# Export every release platform.
export: export-web export-desktop

# Rebuild and serve the web game at http://127.0.0.1:8000.
serve port="8000": export-web
    python3 tools/serve_web.py --port "$1"

# Authenticate butler for local uploads.
login:
    {{ quote(butler) }} login

# Validate existing builds without uploading them.
validate:
    {{ quote(butler) }} validate builds/web
    {{ quote(butler) }} validate builds/desktop
    {{ quote(butler) }} validate --platform windows builds/desktop
    {{ quote(butler) }} validate --platform osx builds/desktop

# Rebuild, validate, and upload both itch.io channels; optionally label the version.
upload version="": export validate
    {{ quote(butler) }} push --if-changed {{ if version != "" { "--userversion=" + quote(version) } else { "" } }} builds/web {{ quote(itch_project + ":html") }}
    {{ quote(butler) }} push --if-changed {{ if version != "" { "--userversion=" + quote(version) } else { "" } }} builds/desktop {{ quote(itch_project + ":desktop") }}

# Regenerate the Korean and English string table.
strings:
    python3 tools/strings.py

# Regenerate synthesized effects and music.
audio:
    uv run --with numpy tools/audio.py

# Measure terrain streaming CPU timings.
benchmark: import
    {{ quote(godot) }} --headless --path . -- --run=res://tools/benchmark.gd
