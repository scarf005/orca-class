class_name Director
extends Node
## Runs the stage script: fires events as the rail reaches them, spawns waves in formation,
## manages checkpoints, the mid-boss hold and the boss arena, and tracks sections.

signal section_changed(section: int)
signal checkpoint_reached(name: String)
signal storm(duration: float)
signal incoming(from: Vector3) ## A wave is arriving from outside the view; the HUD points to it.

const ENEMY_SCRIPTS := {
	"fpv": "res://scripts/enemies/fpv_drone.gd",
	"airboat": "res://scripts/enemies/airboat.gd",
	"spray_drone": "res://scripts/enemies/spray_drone.gd",
	"heron": "res://scripts/enemies/heron_walker.gd",
	"leech": "res://scripts/enemies/canal_leech.gd",
	"egg_cluster": "res://scripts/enemies/snail_egg_cluster.gd",
	"lotus_mine": "res://scripts/enemies/lotus_mine.gd",
	"gnat": "res://scripts/enemies/gnat_swarm.gd",
	"ugv": "res://scripts/enemies/ugv.gd",
	"uav": "res://scripts/enemies/uav.gd",
	"crawler": "res://scripts/enemies/crawler.gd",
	"spitter": "res://scripts/enemies/spitter.gd",
	"walker": "res://scripts/enemies/walker.gd",
	"quad": "res://scripts/enemies/quad_mech.gd",
	"colossus": "res://scripts/enemies/colossus.gd",
	"combine": "res://scripts/enemies/combine.gd",
	"helicopter": "res://scripts/enemies/helicopter.gd",
	"gunship": "res://scripts/enemies/gunship.gd",
	"floodgate": "res://scripts/enemies/floodgate.gd",
}

const MIDBOSS_RESUME := 0.6 ## Seconds after the mid-boss dies before the rail runs again.

## Swarm enemies come in bigger numbers than the stage script lists: mayhem needs fodder.
const FODDER := {"fpv": 1.5, "crawler": 1.6}

const BOSS_CLEAR_DELAY := 6.5 ## After the boss falls, so the dam's breach and flood play out.

var events: Array[Dictionary] = []
var scenery := Scenery.new()
var section := 0
var _next_event := 0
var _hard := false


func begin(checkpoint: String) -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	var world := World.current
	world.rail.d = Course.stage.checkpoints.get(checkpoint, 0.0)
	if not checkpoint.is_empty():
		world.stats.ranked = false
	events = Course.stage.events(_hard)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	# A checkpoint start skips everything before it.
	while _next_event < events.size() and events[_next_event].d < world.rail.d:
		_next_event += 1
	# Load every enemy script and music track now so first appearances do not hitch.
	for path: String in ENEMY_SCRIPTS.values():
		load(path)
	for section in Course.stage.section_starts.size():
		var track := Course.stage.music(section)
		if not track.is_empty():
			load(track)
	load(Course.stage.boss_music)
	world.add_child(scenery)
	scenery.build()
	scenery.stream(world.rail.d, 100000)
	section = Course.section_at(world.rail.d)
	var tier: int = Course.stage.coax_tiers.get(checkpoint, 0)
	if tier > 0:
		world.player.set_coax_tier(tier)
	if Course.stage.start_rws:
		world.player.mount_rws()
	_play_section_music()


func _process(_delta: float) -> void:
	var world := World.current
	var d := world.rail.d
	scenery.stream(d)
	var current := Course.section_at(d)
	if current != section:
		_finish_section()
		section = current
		section_changed.emit(section)
		_play_section_music()
	while _next_event < events.size() and events[_next_event].d <= d:
		_fire(events[_next_event])
		_next_event += 1


func _finish_section() -> void:
	var world := World.current
	if world.stats.section_damage <= 0.0:
		world.award(5000, world.player.global_position, false)
	world.stats.section_damage = 0.0


func _play_section_music() -> void:
	var track := Course.stage.music(section)
	if not track.is_empty(): # The boss event starts the boss theme.
		Sfx.play_music(track)


func _fire(event: Dictionary) -> void:
	var world := World.current
	match event.type:
		"wave":
			spawn_wave(event)
		"pickup":
			var p := Course.ground_at(event.d + event.get("ahead", 40.0), event.get("u", 0.0))
			world.spawn_pickup(event.id, p + Vector3.UP * 1.6)
		"checkpoint":
			checkpoint_reached.emit(event.name)
		"hold":
			world.rail.mode = Rail.Mode.HOLD
			world.rail.hold_at = event.at
		"release":
			world.rail.mode = Rail.Mode.RAIL
		"boss":
			_start_boss(event)
		"midboss":
			_start_midboss(event)
		"storm":
			storm.emit(event.duration)
		"music":
			Sfx.play_music(event.path)


## Spawns a formation. Positions are relative to the rail: `ahead` meters past the tank,
## `u` lateral offset, `height` above the ground.
func spawn_wave(event: Dictionary) -> Array[Enemy]:
	var world := World.current
	var spawned: Array[Enemy] = []
	var count: int = ceili(event.get("count", 1) * FODDER.get(event.kind, 1.0))
	if _hard:
		count = int(ceil(count * event.get("hard_scale", 1.4)))
	var kind: String = event.kind
	for i in count:
		var enemy: Enemy = load(ENEMY_SCRIPTS[kind]).new()
		var slot := _formation(event.get("formation", "line"), i, count, event)
		enemy.set_meta("slot", slot)
		for key in event.get("props", {}):
			enemy.set(key, event.props[key])
		if enemy is FpvDrone:
			var drone := enemy as FpvDrone
			var hover: float = -10.0 - i * 2.0 if event.get("formation", "") == "behind" else event.get("hover", 20.0) + i * 1.5
			drone.slot = Vector3(slot.x * 0.6, slot.y, hover)
			drone.approach_time = event.get("approach", 2.2) + i * event.get("stagger", 0.35)
		var d := world.rail.d + world.player.course_offset + slot.z
		var p := Course.to_world(d, slot.x)
		p.y = Course.height(d, slot.x) + slot.y
		enemy.position = p
		if slot.z < 0.0:
			enemy.despawn_behind = maxf(enemy.despawn_behind, -slot.z + 60.0)
		world.add_enemy(enemy)
		if event.has("drop") and i == count - 1:
			enemy.drop = event.drop
		spawned.append(enemy)
	var formation: String = event.get("formation", "line")
	if formation in ["behind", "flank"] or event.get("props", {}).get("from_behind", false):
		var center := Vector3.ZERO
		for enemy in spawned:
			center += enemy.position
		incoming.emit(center / maxf(spawned.size(), 1.0))
	return spawned


## Returns (u, height, ahead) for member `i` of a formation.
func _formation(kind: String, i: int, count: int, event: Dictionary) -> Vector3:
	var ahead: float = event.get("ahead", 90.0)
	var height: float = event.get("height", 0.0)
	var u: float = event.get("u", 0.0)
	var spacing: float = event.get("spacing", 5.0)
	var centered := i - (count - 1) * 0.5
	match kind:
		"line":
			return Vector3(u + centered * spacing, height, ahead)
		"column":
			return Vector3(u, height, ahead + i * spacing)
		"v":
			return Vector3(u + centered * spacing, height + absf(centered) * 0.8, ahead + absf(centered) * spacing * 0.8)
		"ring":
			var angle := TAU * i / count
			return Vector3(u + cos(angle) * spacing, height + sin(angle * 2.0), ahead + sin(angle) * spacing)
		"behind":
			return Vector3(u + centered * spacing, height, -30.0 - i * 3.0)
		"flank":
			# In from the side of the valley, level with the tank.
			var side := signf(u) if u != 0.0 else 1.0
			return Vector3(side * (Tank.lateral_limit(World.current.rail.d) + 18.0 + absf(centered) * spacing * 0.5), height, ahead + centered * spacing)
		"sides":
			var side := -1.0 if i % 2 == 0 else 1.0
			return Vector3(u + side * spacing, height, ahead + (i / 2) * 12.0)
		"scatter":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(event.d) + i
			return Vector3(u + rng.randf_range(-spacing, spacing), height, ahead + rng.randf_range(-spacing, spacing))
	return Vector3(u, height, ahead)


func _start_midboss(event: Dictionary) -> void:
	var world := World.current
	world.rail.mode = Rail.Mode.HOLD
	world.rail.hold_at = event.hold
	var boss: Enemy = load(ENEMY_SCRIPTS[event.kind]).new()
	boss.position = Course.ground_at(Course.stage.midboss_d, 0.0)
	world.add_enemy(boss)
	world.boss = boss
	world.boss_changed.emit(boss)
	boss.died.connect(func(_e: Entity) -> void:
		world.boss = null
		world.boss_changed.emit(null)
		get_tree().create_timer(MIDBOSS_RESUME).timeout.connect(func() -> void: world.rail.mode = Rail.Mode.RAIL))


func _start_boss(event: Dictionary) -> void:
	var world := World.current
	world.rail.mode = Rail.Mode.ARENA
	var boss: Enemy = load(ENEMY_SCRIPTS[event.kind]).new()
	boss.position = Course.stage.boss_position()
	world.add_enemy(boss)
	world.boss = boss
	world.boss_changed.emit(boss)
	boss.died.connect(func(_e: Entity) -> void:
		world.boss_changed.emit(null)
		get_tree().create_timer(BOSS_CLEAR_DELAY).timeout.connect(world.stage_cleared.emit))
	Sfx.play_music(Course.stage.boss_music)
