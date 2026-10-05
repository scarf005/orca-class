set positional-arguments := true

godot := env("GODOT", "godot")
blender := env("BLENDER", "blender")
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

# Record the stage 1 tiltrotor promo clip to builds/promo/promo.mp4.
promo *args:
    mkdir -p builds/promo
    touch builds/.gdignore
    xvfb-run -a -s "-screen 0 1920x1080x24" {{ quote(godot) }} --path . --resolution 1920x1080 --fixed-fps 60 --audio-driver Dummy --write-movie builds/promo/promo.avi -- --run=res://tools/promo.gd --sound "$@"
    ffmpeg -y -loglevel error -i builds/promo/promo.avi -vf scale=1920:1080:flags=neighbor -c:v libx264 -crf 24 -preset slow -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart builds/promo/promo.mp4

# Open the debug room.
debug-room:
    {{ quote(godot) }} --path . -- --debug-room

# Refresh imported assets and the script class cache.
import:
    {{ quote(godot) }} --headless --path . --import

# Run all tests, or filter by filename (e.g. just test tail). Tests use a temporary
# XDG data root so settings, bests and live tuning cannot touch the developer profile.
test only="": import
    tmpdir="$(mktemp -d)"; trap 'rm -rf "${tmpdir}"' EXIT; mkdir -p "${tmpdir}/data" "${tmpdir}/config" "${tmpdir}/cache"; log="${tmpdir}/test.log"; status=0; ORCA_TEST_DATA_HOME="${tmpdir}/data" XDG_DATA_HOME="${tmpdir}/data" XDG_CONFIG_HOME="${tmpdir}/config" XDG_CACHE_HOME="${tmpdir}/cache" {{ quote(godot) }} --headless --fixed-fps 60 --path . -- --run=res://tests/run.gd --only="$1" >"${log}" 2>&1 || status=$?; cat "${log}"; if [ "${status}" -ne 0 ]; then exit "${status}"; fi; if ! grep -Fq "Test sandbox verified: true" "${log}" || ! grep -Fq "Test user data directory: ${tmpdir}/data/" "${log}"; then echo 'FAIL: test user data directory was not isolated' >&2; exit 1; fi; if grep -Eq '(^|: )(SCRIPT ERROR|ERROR):|Parse Error|Failed to (load|instantiate)' "${log}"; then echo 'FAIL: Godot reported a runtime or script error' >&2; exit 1; fi

# Export the web build (requires Godot export templates).
export-web: import
    mkdir -p builds/web
    touch builds/.gdignore
    {{ quote(godot) }} --headless --path . --export-release Web builds/web/index.html
    test -s builds/web/index.html
    test -s builds/web/index.pck
    test -s builds/web/index.wasm

# Export separate Linux, Windows, and macOS builds for itch.io.
export-desktop: import
    mkdir -p builds/desktop/linux builds/desktop/windows builds/desktop/mac
    touch builds/.gdignore
    {{ quote(godot) }} --headless --path . --export-release Linux builds/desktop/linux/OrcaClass.x86_64
    {{ quote(godot) }} --headless --path . --export-release "Windows Desktop" builds/desktop/windows/OrcaClass.exe
    {{ quote(godot) }} --headless --path . --export-release macOS builds/desktop/mac/OrcaClass.app
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
    {{ quote(butler) }} validate --platform linux builds/desktop/linux
    {{ quote(butler) }} validate --platform windows builds/desktop/windows
    {{ quote(butler) }} validate --platform osx builds/desktop/mac

# Rebuild, validate, and upload each itch.io channel; optionally label the version.
upload version="": export validate
    {{ quote(butler) }} push --if-changed {{ if version != "" { "--userversion=" + quote(version) } else { "" } }} builds/web {{ quote(itch_project + ":html") }}
    {{ quote(butler) }} push --if-changed {{ if version != "" { "--userversion=" + quote(version) } else { "" } }} builds/desktop/linux {{ quote(itch_project + ":linux") }}
    {{ quote(butler) }} push --if-changed {{ if version != "" { "--userversion=" + quote(version) } else { "" } }} builds/desktop/windows {{ quote(itch_project + ":windows") }}
    {{ quote(butler) }} push --if-changed {{ if version != "" { "--userversion=" + quote(version) } else { "" } }} builds/desktop/mac {{ quote(itch_project + ":osx") }}

# Regenerate the Korean and English string table.
strings:
    python3 tools/strings.py

# Export edited Blender actor sources; names optionally select individual actors.
export-actors *names:
    {{ quote(blender) }} --background --python-exit-code 1 --python tools/export_actors.py -- "$@"

# Check that Blender edits reach GLB without overwriting source files.
test-actor-export:
    mkdir -p builds
    touch builds/.gdignore
    {{ quote(blender) }} --background --python-exit-code 1 --python tools/test_actor_export.py

# Regenerate synthesized effects and music.
audio:
    uv run --with numpy tools/audio.py

# Measure terrain streaming CPU timings.
benchmark: import
    {{ quote(godot) }} --headless --path . -- --run=res://tools/benchmark.gd
