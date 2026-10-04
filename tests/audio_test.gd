extends TestCase
## Tests and tools never play sound.


func test_script_runs_are_silent() -> void:
	var previous_silent := Game.silent
	check(Game.silent, "script runs flag themselves silent")
	Game.apply_settings()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "master bus stays muted after settings apply")
	var world := stage()
	check(world != null and AudioServer.is_bus_mute(0), "starting a stage (and its music) stays muted")
	check(Sfx.music.stream == null and not Sfx.music.playing, "a silent run does not start music")
	check(world.player._engine_sound == null, "a silent run does not create the engine loop")
	Game.silent = previous_silent


func test_leaving_the_tree_releases_every_audio_channel() -> void:
	var previous_silent := Game.silent
	var world := stage()
	var audio: Node = load("res://scripts/core/sfx.gd").new()
	add_child(audio)
	Game.silent = false
	audio.ui("ui_select")
	audio.gun("cannon")
	audio.confirm_hit(true)
	audio.play_music("res://assets/music/title.ogg")
	audio.play("blast", world.player.global_position)
	var engine: AudioStreamPlayer3D = audio.loop("engine", world.player)
	Game.silent = true
	var players: Array = audio.get_children()
	players.append_array(audio._pool)
	players.append(engine)
	check(engine != null and engine.stream != null, "the engine loop starts with a stream")
	check(audio.music.playing, "music plays before leaving the tree")
	remove_child(world)
	remove_child(audio)
	for player: Node in players:
		check(not player.playing and player.stream == null, "leaving the tree stops and clears %s" % player.get_class())
	audio.free()
	Game.silent = previous_silent


const CANNON := "res://assets/audio/synth/cannon.wav"


## Reads the source WAV (the imported stream is QOA-compressed): a canonical 44-byte header, mono 16-bit.
func _samples(path: String) -> PackedFloat32Array:
	var bytes := FileAccess.get_file_as_bytes(path)
	var out := PackedFloat32Array()
	out.resize((bytes.size() - 44) / 2)
	for i in out.size():
		out[i] = bytes.decode_s16(44 + i * 2) / 32768.0
	return out


func test_cannon_report_starts_at_once() -> void:
	var audio := load(CANNON) as AudioStreamWAV
	check(audio != null and not audio.stereo and audio.mix_rate == 44100, "the cannon imports as a mono 44.1 kHz stream")
	var samples := _samples(CANNON)
	var peak := 0.0
	var peak_at := 0
	for i in samples.size():
		if absf(samples[i]) > peak:
			peak = absf(samples[i])
			peak_at = i
	var onset := 0
	while onset < samples.size() and absf(samples[onset]) < peak * 0.05:
		onset += 1
	var ms := 1000.0 / 44100.0
	check(onset * ms <= 5.0, "the report is above 5%% of its peak within 5 ms (got %.2f ms)" % (onset * ms))
	check(peak_at * ms <= 15.0, "the report peaks within 15 ms (got %.2f ms)" % (peak_at * ms))
	check(peak < 1.0 and peak > 0.5, "the report is loud without clipping (peak %.2f)" % peak)
	check(samples.size() * ms <= 2000.0, "the report is at most 2 s long")


func test_player_cannon_plays_on_the_flat_gun_channel() -> void:
	var previous_silent := Game.silent
	var world := stage()
	Game.silent = false # Silent runs load no streams; the master bus stays muted.
	Sfx._guns.clear()
	world.player.fire_cannon()
	Game.silent = true
	check(Sfx._guns.has("cannon"), "the tank's own cannon shot goes through the non-positional gun player")
	Game.silent = previous_silent
