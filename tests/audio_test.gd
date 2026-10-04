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


const STAGE2_TRACKS := {
	"stage2_boulevard": [174.0, 32],
	"stage2_canyon": [176.0, 32],
	"stage2_hovercraft": [178.0, 24],
	"stage2_boss": [180.0, 32],
	"stage2_boss_phase2": [180.0, 32],
}
const STAGE2_SOUNDS := ["losat_lase", "losat_launch", "losat_hit", "mech_step", "mech_step_2", "mech_step_3", "hydraulic_slam", "gatling_spin", "cannon_lowpressure", "rocket_ripple", "atgm_launch", "heli_gatling", "hover_fan", "hover_laser", "mine_beep"]
var _levels := {}


## Decode without playing or relying on a sound device. Spectral bands separate sub and break energy.
func _music_levels(name: String) -> Dictionary:
	if _levels.has(name):
		return _levels[name]
	var path := "res://assets/music/%s.ogg" % name
	if not ResourceLoader.exists(path):
		check(false, "%s exists" % path)
		return {}
	var audio := load(path) as AudioStreamOggVorbis
	var playback := audio.instantiate_playback()
	playback.start()
	var rate := float(AudioServer.get_mix_rate())
	var count := roundi(audio.get_length() * rate)
	var energy := 0.0
	var sub := 0.0
	var treble := 0.0
	var peak := 0.0
	var first := Vector2.ZERO
	var last := Vector2.ZERO
	var low := Vector2.ZERO
	var mid := Vector2.ZERO
	var sections := [0.0, 0.0, 0.0, 0.0]
	var a := 1.0 - exp(-TAU * 140.0 / rate)
	var b := 1.0 - exp(-TAU * 2500.0 / rate)
	var at := 0
	while at < count:
		var frames := playback.mix_audio(1.0, mini(4096, count - at))
		if frames.is_empty():
			check(count - at < 1024, "%s decodes to its advertised duration" % name)
			break
		for frame: Vector2 in frames:
			if at == 0:
				first = frame
			last = frame
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			energy += frame.length_squared() * 0.5
			low += a * (frame - low)
			mid += b * (frame - mid)
			sub += low.length_squared() * 0.5
			var high := (frame - mid).length_squared() * 0.5
			treble += high
			sections[mini(3, at * 4 / count)] += high / (count / 4.0)
			at += 1
	playback.stop()
	var result := {"length": audio.get_length(), "db": linear_to_db(sqrt(energy / count)), "peak": peak, "seam": maxf(absf(first.x - last.x), absf(first.y - last.y)), "sub": sub / energy, "high": treble / energy, "sections": sections}
	_levels[name] = result
	print("AUDIO %s %s" % [name, result])
	return result


func test_stage2_music_levels_and_loop_boundaries() -> void:
	var reference := _music_levels("stage_a")
	for name: String in STAGE2_TRACKS:
		var stats := _music_levels(name)
		if stats.is_empty():
			continue
		var spec: Array = STAGE2_TRACKS[name]
		check_near(stats.length, spec[1] * 4.0 * 60.0 / spec[0], 0.001, "%s loops on a complete bar" % name)
		check_near(stats.db, reference.db, 1.0, "%s matches stage 1 loudness" % name)
		check(stats.peak < 0.98, "%s has codec headroom" % name)
		check(stats.seam < 0.035, "%s has no loop-boundary click" % name)
		check(stats.sub > 0.02 and stats.high > 0.005, "%s carries sub bass and bright breaks" % name)


func test_stage2_breaks_build_and_boss_phase_changes() -> void:
	var boulevard := _music_levels("stage2_boulevard")
	if not boulevard.is_empty():
		check(boulevard.sections[2] > boulevard.sections[0] * 1.5, "boulevard builds from sparse opening to full breaks")
	var hunter := _music_levels("stage2_boss")
	var phase := _music_levels("stage2_boss_phase2")
	if not hunter.is_empty() and not phase.is_empty():
		check(phase.high > hunter.high * 1.15, "boss phase two audibly intensifies the breaks")
		check_near(phase.length, hunter.length, 0.001, "boss variants share tempo and phrase length")


func test_stage2_effects_are_registered_and_click_free() -> void:
	for name: String in STAGE2_SOUNDS:
		check(Sfx.SOUNDS.has(name), "%s is available to enemy callers" % name)
		var path := "res://assets/audio/synth/%s.wav" % name
		if not FileAccess.file_exists(path):
			check(false, "%s exists" % path)
			continue
		var audio := load(path) as AudioStreamWAV
		check(audio != null and not audio.stereo and audio.mix_rate == 44100, "%s imports as mono 44.1 kHz" % name)
		var samples := _samples(path)
		var peak := 0.0
		var energy := 0.0
		for value in samples:
			peak = maxf(peak, absf(value))
			energy += value * value
		check(peak > 0.25 and peak < 0.96, "%s has unclipped level" % name)
		check(linear_to_db(sqrt(energy / samples.size())) > -35.0, "%s is not mostly silence" % name)
		check(absf(samples[0] - samples[-1]) < 0.02, "%s has a clean boundary" % name)
		check(audio.get_length() >= 0.1 and audio.get_length() <= 4.0, "%s has a bounded duration" % name)


func test_stage2_boss_variant_crossfades_and_hover_loop_stops() -> void:
	if not ResourceLoader.exists("res://assets/music/stage2_boss.ogg") or not Sfx.SOUNDS.has("hover_fan"):
		check(false, "stage 2 boss music and hover fan are available")
		return
	var world := stage()
	Game.silent = false
	Sfx.play_music("res://assets/music/stage2_boss.ogg")
	var first := Sfx.music
	Sfx.play_music("res://assets/music/stage2_boss_phase2.ogg")
	check(first.playing and Sfx.music != first and Sfx.music.playing, "boss phase transition overlaps both variants")
	check((Sfx.music.stream as AudioStreamOggVorbis).loop, "boss variant loops through the existing music API")
	var fan := Sfx.loop("hover_fan", world.player)
	check(fan != null and (fan.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "hover turbine uses the existing attached loop API")
	Game.silent = true
	Sfx.stop_all()
	check(not fan.playing and fan.stream == null, "stopping releases the hover turbine loop")


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


func test_music_crossfades_between_tracks() -> void:
	# Master stays muted from the silent setup, so nothing is heard while the players run.
	Game.silent = false
	Sfx.play_music("res://assets/music/stage_a.ogg")
	var first := Sfx.music
	check(first.playing and first.volume_db == 0.0, "the first track starts at full volume")
	Sfx.play_music("res://assets/music/stage_b.ogg")
	var second := Sfx.music
	check(second != first and second.playing, "the next track starts on the other player")
	check(first.playing, "the old track keeps playing while it fades")
	check(second.volume_db < -20.0, "the new track fades in rather than cutting in")
	await get_tree().create_timer(Sfx.MUSIC_FADE_OUT + 0.3).timeout
	check(not first.playing, "the old track stops once faded")
	check_near(second.volume_db, 0.0, 0.5, "the new track ends at full volume")
	Sfx.play_music("res://assets/music/stage_b.ogg")
	check(Sfx.music == second, "asking for the playing track again does not restart it")
	Sfx.stop_music()
	check(not first.playing and not second.playing, "stopping silences both players")
	Game.silent = true
