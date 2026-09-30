extends Node
## Sound playback: pooled positional one-shots in the running world, loops attached to nodes, UI
## sounds and music.

const SOUNDS := {
	"cannon": ["res://assets/audio/synth/cannon.wav", 0.0],
	"blast": ["res://assets/audio/blast.ogg", 0.0],
	"blast_small": ["res://assets/audio/blast.ogg", -5.0, 1.45],
	"impact": ["res://assets/audio/rubble.ogg", -2.0, 0.7],
	"hit_confirm": ["res://assets/audio/synth/hit_metal.wav", -5.0, 1.0],
	"kill_confirm": ["res://assets/audio/synth/kill_crunch.wav", 0.0, 1.0],
	"coax8": ["res://assets/audio/synth/coax8.wav", -9.0],
	"coax15": ["res://assets/audio/synth/coax15.wav", -8.0],
	"coax20": ["res://assets/audio/synth/coax20.wav", -7.0],
	"enemy_gun": ["res://assets/audio/ciws.ogg", -6.0, 0.9],
	"zap": ["res://assets/audio/laser.ogg", -4.0, 1.3],
	"rubble": ["res://assets/audio/rubble.ogg", 0.0],
	"wood": ["res://assets/audio/wood.ogg", 0.0],
	"skid": ["res://assets/audio/skid.ogg", -3.0],
	"engine": ["res://assets/audio/engine.ogg", 0.0],
	"track": ["res://assets/audio/track.ogg", 0.0],
	"launch": ["res://assets/audio/smoke.ogg", 0.0],
	"whip": ["res://assets/audio/synth/whip.wav", 0.0],
	"grab": ["res://assets/audio/synth/grab.wav", 0.0],
	"stab": ["res://assets/audio/synth/stab.wav", 0.0],
	"pickup": ["res://assets/audio/synth/pickup.wav", -2.0],
	"hurt": ["res://assets/audio/synth/hurt.wav", 0.0],
	"pop": ["res://assets/audio/synth/pop.wav", -2.0],
	"airburst": ["res://assets/audio/synth/airburst.wav", 0.0],
	"overheat": ["res://assets/audio/synth/overheat.wav", 0.0],
	"buzz": ["res://assets/audio/synth/buzz.wav", -6.0],
	"dive": ["res://assets/audio/synth/dive.wav", -2.0],
	"rotor": ["res://assets/audio/synth/rotor.wav", 0.0],
	"jet": ["res://assets/audio/synth/jet.wav", -2.0],
	"squelch": ["res://assets/audio/synth/squelch.wav", 0.0],
	"spore": ["res://assets/audio/synth/spore.wav", -2.0],
	"warn": ["res://assets/audio/synth/warn.wav", -4.0],
	"lock": ["res://assets/audio/synth/lock.wav", -4.0],
	"ui_move": ["res://assets/audio/synth/ui_move.wav", -8.0],
	"ui_select": ["res://assets/audio/synth/ui_select.wav", -4.0],
	"shout": ["res://assets/audio/synth/shout.wav", -2.0],
	"combo": ["res://assets/audio/synth/combo.wav", -8.0],
	"roar": ["res://assets/audio/synth/roar.wav", 0.0],
	"rush": ["res://assets/audio/synth/rush.wav", 0.0],
	"whoomp": ["res://assets/audio/synth/whoomp.wav", 0.0],
	"steam": ["res://assets/audio/synth/steam.wav", -2.0],
	"slosh": ["res://assets/audio/synth/slosh.wav", -6.0],
	"airboat_roar": ["res://assets/audio/synth/airboat_roar.wav", -7.0],
	"airboat_warn": ["res://assets/audio/synth/airboat_warn.wav", -2.0],
	"airboat_gun": ["res://assets/audio/synth/airboat_gun.wav", -4.0],
	"airboat_fan": ["res://assets/audio/synth/airboat_fan.wav", 0.0],
	"airboat_death": ["res://assets/audio/synth/airboat_death.wav", 0.0],
	"spray_drone": ["res://assets/audio/synth/spray_drone.wav", -10.0],
	"spray_warn": ["res://assets/audio/synth/spray_warn.wav", -3.0],
	"spray_full": ["res://assets/audio/synth/spray_full.wav", -1.0],
	"spray_death": ["res://assets/audio/synth/spray_death.wav", 0.0],
	"heron_warn": ["res://assets/audio/synth/heron_warn.wav", -2.0],
	"heron_stab": ["res://assets/audio/synth/heron_stab.wav", 0.0],
	"heron_topple": ["res://assets/audio/synth/heron_topple.wav", 0.0],
	"leech_ripple": ["res://assets/audio/synth/leech_ripple.wav", -2.0],
	"leech_latch": ["res://assets/audio/synth/leech_latch.wav", 0.0],
	"leech_pop": ["res://assets/audio/synth/leech_pop.wav", -1.0],
	"eggs_warn": ["res://assets/audio/synth/eggs_warn.wav", -2.0],
	"eggs_hatch": ["res://assets/audio/synth/eggs_hatch.wav", 0.0],
	"eggs_pop": ["res://assets/audio/synth/eggs_pop.wav", -1.0],
	"lotus_tick": ["res://assets/audio/synth/lotus_tick.wav", -2.0],
	"lotus_blast": ["res://assets/audio/synth/lotus_blast.wav", 0.0],
	"lotus_pop": ["res://assets/audio/synth/lotus_pop.wav", -1.0],
	"gnat_whine": ["res://assets/audio/synth/gnat_whine.wav", -8.0],
	"gnat_warn": ["res://assets/audio/synth/gnat_warn.wav", -2.0],
	"gnat_attack": ["res://assets/audio/synth/gnat_attack.wav", -1.0],
	"gnat_pop": ["res://assets/audio/synth/gnat_pop.wav", -1.0],
	"combine_engine": ["res://assets/audio/synth/combine_engine.wav", -5.0],
	"combine_reel": ["res://assets/audio/synth/combine_reel.wav", -1.0],
	"combine_auger": ["res://assets/audio/synth/combine_auger.wav", -1.0],
	"combine_chaff": ["res://assets/audio/synth/combine_chaff.wav", -1.0],
	"combine_death": ["res://assets/audio/synth/combine_death.wav", 0.0],
}

const POOL_SIZE := 40

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_owner: Node3D
var _next := 0
var _ui := AudioStreamPlayer.new()
var _combat := AudioStreamPlayer.new()
var _last_hit_sound := -100
var _guns := {} ## Sound name -> its own non-positional player, so different guns overlap.
var music := AudioStreamPlayer.new()
var _music_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.bus = &"SFX"
	add_child(_ui)
	_combat.bus = &"SFX"
	_combat.max_polyphony = 4
	add_child(_combat)
	music.bus = &"Music"
	add_child(music)


func stream(name: String) -> AudioStream:
	if Game.silent:
		return null
	if not _streams.has(name):
		var spec: Array = SOUNDS.get(name, [])
		_streams[name] = load(spec[0]) if not spec.is_empty() and ResourceLoader.exists(spec[0]) else null
	return _streams[name]


func _ensure_pool() -> bool:
	var world := World.current
	if world == null:
		return false
	if _pool_owner != world:
		_pool.clear()
		_pool_owner = world
		for i in POOL_SIZE:
			var player := AudioStreamPlayer3D.new()
			player.bus = &"SFX"
			player.unit_size = 18.0
			player.max_distance = 260.0
			player.attenuation_filter_cutoff_hz = 9000.0
			world.add_child(player)
			_pool.append(player)
	return true


## Plays a positional one-shot in the running world. Falls back to a flat UI sound outside it.
func play(name: String, position := Vector3.INF, volume_db := 0.0, pitch := 1.0) -> void:
	var audio := stream(name)
	if audio == null:
		return
	var spec: Array = SOUNDS[name]
	var base_pitch: float = spec[2] if spec.size() > 2 else 1.0
	if position == Vector3.INF or not _ensure_pool():
		ui(name, volume_db, pitch)
		return
	# Steal the oldest voice when all are busy.
	var player := _pool[_next]
	for i in POOL_SIZE:
		var candidate := _pool[(_next + i) % POOL_SIZE]
		if not candidate.playing:
			player = candidate
			break
	_next = (_pool.find(player) + 1) % POOL_SIZE
	player.stream = audio
	player.volume_db = spec[1] + volume_db
	player.pitch_scale = base_pitch * pitch
	player.global_position = position
	player.play()


## The tank's own guns: full volume whatever the camera distance, each shot overlapping the last.
func gun(name: String, pitch := 1.0) -> void:
	var audio := stream(name)
	if audio == null:
		return
	if not _guns.has(name):
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		player.max_polyphony = 8
		player.stream = audio
		player.volume_db = SOUNDS[name][1]
		add_child(player)
		_guns[name] = player
	var player: AudioStreamPlayer = _guns[name]
	player.pitch_scale = pitch
	player.play()


## Feedback stays audible at long range and never cuts off menu sounds.
func confirm_hit(killed: bool) -> void:
	if Game.silent:
		return
	var now := Time.get_ticks_msec()
	if not killed and now - _last_hit_sound < 35:
		return
	_last_hit_sound = now
	var name := "kill_confirm" if killed else "hit_confirm"
	_combat.stream = stream(name)
	_combat.volume_db = SOUNDS[name][1]
	_combat.pitch_scale = SOUNDS[name][2] * randf_range(0.9, 1.15)
	_combat.play()


func ui(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var audio := stream(name)
	if audio == null:
		return
	var spec: Array = SOUNDS[name]
	_ui.stream = audio
	_ui.volume_db = spec[1] + volume_db
	_ui.pitch_scale = (spec[2] if spec.size() > 2 else 1.0) * pitch
	_ui.play()


## A looping sound attached to a node; returns the player so callers can modulate it.
func loop(name: String, parent: Node3D, volume_db := 0.0) -> AudioStreamPlayer3D:
	if Game.silent:
		return null
	var audio := stream(name)
	if audio == null:
		return null
	audio = audio.duplicate()
	if audio is AudioStreamOggVorbis:
		(audio as AudioStreamOggVorbis).loop = true
	elif audio is AudioStreamWAV:
		var wav := audio as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	var player := AudioStreamPlayer3D.new()
	player.stream = audio
	player.bus = &"SFX"
	player.volume_db = SOUNDS[name][1] + volume_db
	player.unit_size = 14.0
	player.autoplay = true
	parent.add_child(player)
	return player


func play_music(path: String, loop := true, volume_db := 0.0) -> void:
	if Game.silent:
		stop_music()
		return
	if path == _music_path and music.playing:
		return
	_music_path = path
	if path.is_empty() or not ResourceLoader.exists(path):
		music.stop()
		return
	var stream_value: AudioStream = load(path).duplicate()
	if stream_value is AudioStreamOggVorbis:
		(stream_value as AudioStreamOggVorbis).loop = loop
	music.stream = stream_value
	music.volume_db = volume_db
	music.play()


func stop_music() -> void:
	_music_path = ""
	music.stop()
	music.stream = null
