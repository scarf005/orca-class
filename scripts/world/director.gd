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
	"sporefly": "res://scripts/enemies/sporefly.gd",
	"husk": "res://scripts/enemies/husk.gd",
	"mortar": "res://scripts/enemies/mortar.gd",
	"skimmer": "res://scripts/enemies/skimmer.gd",
	"burrower": "res://scripts/enemies/burrower.gd",
	"glinter": "res://scripts/enemies/glinter.gd",
	"torpedo_boat": "res://scripts/enemies/torpedo_boat.gd",
	"ugv": "res://scripts/enemies/ugv.gd",
	"uav": "res://scripts/enemies/uav.gd",
	"crawler": "res://scripts/enemies/crawler.gd",
	"spitter": "res://scripts/enemies/spitter.gd",
	"walker": "res://scripts/enemies/walker.gd",
	"quad": "res://scripts/enemies/quad_mech.gd",
	"abel": "res://scripts/enemies/abel.gd",
	"kain": "res://scripts/enemies/kain.gd",
	"adam": "res://scripts/enemies/adam.gd",
	"colossus": "res://scripts/enemies/colossus.gd",
	"hovercraft": "res://scripts/enemies/hovercraft.gd",
	"helicopter": "res://scripts/enemies/helicopter.gd",
	"hind": "res://scripts/enemies/hind.gd",
	"rooftop_battery": "res://scripts/enemies/rooftop_battery.gd",
	"sea_mine": "res://scripts/enemies/sea_mine.gd",
	"drone_boat": "res://scripts/enemies/drone_boat.gd",
	"tiltrotor": "res://scripts/enemies/tiltrotor.gd",
	"gunship": "res://scripts/enemies/gunship.gd",
	"hi_mo": "res://scripts/enemies/hi_mo.gd",
	"borer": "res://scripts/enemies/borer.gd",
	"wing": "res://scripts/enemies/wing.gd",
}

const MIDBOSS_RESUME := 0.6 ## Seconds after the mid-boss dies before the rail runs again.

const BOSS_CLEAR_DELAY := 1.2 ## After the boss falls, so the breach lands before the call-out; the flood plays on behind it.

## The duel prototype (`-- --duel`): the rail stands still on the farm straight and the hunters come
## again each time they are all down, so one fight can be played over and over.
const DUEL_D := 100.0
const DUEL_RESPAWN := 2.5
## How many of each hunter a duel round sends, tuned live in the duel mode.
static var duel_round := Armament.Round.APHE ## The round every duel refit loads (picked in the duel panel).
static var duel_counts := {"helicopter": 0, "tiltrotor": 1, "walker": 2, "uav": 0, "quad": 0, "ugv": 0, "fpv": 0, "abel": 0, "kain": 0, "adam": 0, "hind": 0, "rooftop_battery": 0, "sea_mine": 0, "drone_boat": 0}
const DUEL := {
	"hind": {"height": 7.0, "ahead": 65.0, "u": -8.0, "spacing": 20.0},
	"rooftop_battery": {"ahead": 65.0, "u": 12.0, "spacing": 12.0},
	"sea_mine": {"ahead": 25.0, "spacing": 4.0},
	"drone_boat": {"ahead": 65.0, "spacing": 5.0},
	"helicopter": {"height": 13.0, "ahead": 90.0, "u": -8.0, "formation": "line", "spacing": 20.0},
	"tiltrotor": {"height": 10.0, "ahead": 150.0, "u": 16.0, "formation": "line", "spacing": 20.0},
	"walker": {"formation": "sides", "spacing": 9.0, "ahead": 60.0},
	"uav": {"formation": "line", "spacing": 10.0, "props": {"attack": "bomb"}},
	"quad": {"formation": "sides", "spacing": 8.0, "ahead": 90.0},
	"abel": {"formation": "sides", "spacing": 8.0, "ahead": 85.0},
	"kain": {"formation": "sides", "spacing": 9.0, "ahead": 80.0},
	"adam": {"formation": "line", "spacing": 8.0, "ahead": 35.0},
	"ugv": {"formation": "sides", "spacing": 8.0, "ahead": 80.0},
	"fpv": {"formation": "v", "height": 8.0, "spacing": 5.0},
}

## Pursuit: a tank that runs slow on the rail draws FPV pursuers from behind. Tuned live in the duel mode.
static var PURSUIT_SLOW := 0.7 ## Share of cruise below which the tank counts as slow.
static var PURSUIT_FILL := 1.5 ## Seconds of slowness before the first group launches.
static var PURSUIT_GROUP := 2 ## Drones in the first group; each later group of the same spell has one more, up to 4.
static var PURSUIT_INTERVAL := 2.5 ## Seconds between groups while the tank stays slow.
const PURSUIT_MAX := 10 ## Pursuers alive at once, so a long crawl cannot bury the tank.
const PURSUIT_STAGES := [1] ## City cover fights need time to aim without drawing drone swarms.

var events: Array[Dictionary] = []
var slow_meter := 0.0 ## 0..1: fills while the tank is slow on the rail, drains while it is fast.
var scenery := Scenery.new()
var section := 0
var _next_event := 0
var _hard := false
var _hold_group: Array[Enemy] = [] ## A hold keeps the rail stopped until these are gone.
var _hold_left := 0.0 ## Seconds before a hold gives up and lets the rail run anyway.
var _hold_reward := "" ## Pickup dropped ahead of the tank when the hold group is cleared, never on a timeout.
var _duel := false
var _duel_wait := 0.0
var _pursuit_wait := 0.0
var _pursuit_groups := 0 ## Groups sent in the current spell of slowness.


func begin(checkpoint: String) -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	var world := World.current
	world.rail.d = Course.stage.checkpoints.get(checkpoint, 0.0)
	if not StageEvents.playtest.is_empty():
		world.rail.d = StageEvents.playtest.d
	if not checkpoint.is_empty() or not StageEvents.playtest.is_empty():
		world.stats.ranked = false
	_duel = checkpoint == "duel"
	events = Course.stage.run_events(_hard)
	if _duel:
		events.clear()
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	# A checkpoint start skips everything before it.
	while _next_event < events.size() and events[_next_event].d < world.rail.d:
		_next_event += 1
	# Load every enemy script and music track now so first appearances do not hitch.
	for path: String in ENEMY_SCRIPTS.values():
		load(path)
	var tracks := {}
	for phase in 3:
		tracks[Course.stage.boss_music(phase)] = true
	for i in Course.stage.section_starts.size():
		tracks[Course.stage.music(i)] = true
	for event in events:
		if event.type == "boss":
			tracks[event.get("music", Course.stage.boss_music())] = true
		if event.type == "music" or event.has("music"):
			tracks[event.get("music", event.get("path", ""))] = true
	for track: String in tracks:
		if not track.is_empty():
			load(track)
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
	if _duel:
		world.rail.mode = Rail.Mode.HOLD
		world.rail.hold_at = DUEL_D
		_duel_wait = 1.5 # A beat to look around before the first hunters arrive.


func _process(delta: float) -> void:
	var world := World.current
	var d := world.rail.d
	scenery.stream(d)
	var current := Course.section_at(d)
	if current != section:
		_finish_section()
		section = current
		section_changed.emit(section)
		_play_section_music()
	if _duel:
		_duel_wait = _duel_wait - delta if world.enemies.is_empty() else DUEL_RESPAWN
		if _duel_wait <= 0.0:
			_duel_wait = DUEL_RESPAWN
			world.player.refit() # Every round starts with a whole tank and a full magazine.
			world.player.load_round(duel_round)
			for kind: String in DUEL:
				if duel_counts[kind] > 0:
					var event: Dictionary = DUEL[kind].duplicate()
					event.merge({"d": d, "kind": kind, "count": duel_counts[kind]})
					spawn_wave(event)
	_update_pursuit(delta)
	if _hold_left > 0.0:
		_hold_left -= delta
		var alive := false
		for enemy in _hold_group:
			alive = alive or (is_instance_valid(enemy) and not enemy.dead)
		if not alive and not _hold_reward.is_empty():
			world.spawn_pickup(_hold_reward, Course.ground_at(d + 30.0, 0.0) + Vector3.UP * 1.6)
		if not alive or _hold_left <= 0.0:
			_hold_left = 0.0
			_hold_reward = ""
			_hold_group.clear()
			world.rail.mode = Rail.Mode.RAIL
	while _next_event < events.size() and events[_next_event].d <= d:
		_fire(events[_next_event])
		_next_event += 1


## Only the rail running (never a hold, the duel or the arena) counts the tank's speed.
func _update_pursuit(delta: float) -> void:
	var world := World.current
	if Course.stage.number not in PURSUIT_STAGES or Game.difficulty == Game.Difficulty.EASY or world.rail.mode != Rail.Mode.RAIL or world.player.dead:
		slow_meter = 0.0
		_pursuit_groups = 0
		return
	var forward := world.rail.speed + world.player.local_velocity.y
	var slow := forward < PURSUIT_SLOW * Rail.CRUISE
	slow_meter = clampf(slow_meter + (1.0 if slow else -1.0) * delta / PURSUIT_FILL, 0.0, 1.0)
	if slow_meter <= 0.0:
		_pursuit_groups = 0
	if slow_meter < 1.0 or not slow:
		return
	_pursuit_wait -= delta
	if _pursuit_wait <= 0.0:
		_pursuit_wait = PURSUIT_INTERVAL
		send_pursuers(clampi(PURSUIT_GROUP + _pursuit_groups, 2, 4), randi() % FpvDrone.Pattern.size())
		_pursuit_groups += 1


## Launches a group of FPV pursuers from behind, all flying `pattern`. None while PURSUIT_MAX are
## already after the tank.
func send_pursuers(count: int, pattern: FpvDrone.Pattern) -> Array[Enemy]:
	var world := World.current
	var sent: Array[Enemy] = []
	if Game.difficulty == Game.Difficulty.EASY:
		return sent
	var alive := world.enemies.filter(func(e: Entity) -> bool: return e is FpvDrone and (e as FpvDrone).state == FpvDrone.State.PURSUE).size()
	if alive + count > PURSUIT_MAX:
		return sent
	var center := Vector3.ZERO
	for i in count:
		var drone := Sporefly.new()
		drone.state = FpvDrone.State.PURSUE
		drone.pattern = pattern
		drone.side = -1.0 if i % 2 == 0 else 1.0
		drone.lag = FpvDrone.PURSUIT_START + i * 2.5
		drone.phase = TAU * i / count
		drone.despawn_behind = 0.0
		drone.position = drone.pursuit_spot(world.player)
		center += drone.position
		world.add_enemy(drone)
		sent.append(drone)
	incoming.emit(center / count)
	Sfx.play("dive", center / count, 0.0, 0.7)
	return sent


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
		"ambush":
			spawn_ambush(event)
		"pickup":
			var p := Course.ground_at(event.d + event.get("ahead", 40.0), event.get("u", 0.0))
			world.spawn_pickup(event.id, p + Vector3.UP * 1.6)
		"checkpoint":
			checkpoint_reached.emit(event.name)
		"hold":
			# Everything already in play ahead of the tank has to go before the rail runs on.
			_hold_group.assign(world.enemies.filter(func(enemy: Enemy) -> bool: return Course.to_course(enemy.global_position).x > world.rail.d - 10.0))
			if not _hold_group.is_empty():
				world.rail.mode = Rail.Mode.HOLD
				world.rail.hold_at = event.at
				_hold_left = event.get("timeout", 30.0)
				_hold_reward = event.get("reward", "")
		"release":
			world.rail.mode = Rail.Mode.RAIL
		"boss":
			_start_boss(event)
		"midboss":
			_start_midboss(event)
		"storm":
			storm.emit(event.duration)
		"sprint":
			world.rail.sprint = float(event.kmh) / 3.6
		"music":
			Sfx.play_music(event.path)
		"topple":
			world.add_child(ToppleTower.new())
		"surge":
			var surge := TidalSurge.new()
			surge.d = event.d_center
			world.add_child(surge)


func spawn_ambush(event: Dictionary) -> Enemy:
	if not _hard:
		return null
	for spec in scenery.specs:
		if spec.kind not in ["house", "infested_house", "hall"] or absf(spec.d - float(event.building_d)) > 0.01:
			continue
		if not is_instance_valid(spec.node) and not spec.has_meta("destroyed"):
			scenery._instantiate(spec)
		var enemy: Enemy = load(ENEMY_SCRIPTS[event.kind]).new()
		enemy.position = Course.ground_at(spec.d, spec.u)
		if enemy is FpvDrone:
			(enemy as FpvDrone).approach_time = 0.2
		World.current.add_enemy(enemy)
		if enemy is Walker:
			(enemy as Walker)._attack_timer = 0.0
		var host := spec.node as Prop if is_instance_valid(spec.node) else null
		var cfg: Array = Scenery.PROPS[spec.kind]
		enemy.hide_in(host, enemy.position, cfg[1], cfg[0])
		return enemy
	push_error("Ambush building missing at %.0f m" % event.building_d)
	return null


## Spawns a formation. Positions are relative to the rail: `ahead` meters past the tank,
## `u` lateral offset, `height` above the ground.
func spawn_wave(event: Dictionary) -> Array[Enemy]:
	var world := World.current
	var spawned: Array[Enemy] = []
	var count: int = event.get("count", 1)
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
		if Course.stage.city and slot.z > 0.0 and (enemy is Hind or (enemy is BipedMech and not enemy is Adam)):
			enemy.walk_in()
		if enemy is BipedMech or enemy is Hind:
			var toward := world.player.hit_center() - enemy.hit_center()
			enemy.model.rotation.y = atan2(-toward.x, -toward.z)
		if event.has("drop") and i == count - 1:
			enemy.drop = event.drop
		spawned.append(enemy)
	var formation: String = event.get("formation", "line")
	if formation in ["behind", "flank"] or event.get("props", {}).get("from_behind", false):
		var center := Vector3.ZERO
		for enemy in spawned:
			center += enemy.position
		incoming.emit(center / maxf(spawned.size(), 1.0))
	# A squad is one event: its escorts arrive in the same frame as their elite, including on checkpoint sorties.
	for member: Dictionary in event.get("squad", []):
		var escort := member.duplicate(true)
		escort.merge({"d": event.get("d", world.rail.d), "hard_scale": event.get("hard_scale", 1.0)}, false)
		spawned.append_array(spawn_wave(escort))
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
	if event.kind == "hovercraft":
		var arena := Course.stage.arena_at(world.rail.d)
		Course.stage.arena_center_d = arena.d
		Course.stage.arena_radius = arena.radius
	world.rail.mode = Rail.Mode.ARENA if event.kind == "hovercraft" else Rail.Mode.HOLD
	world.rail.hold_at = event.hold
	var boss: Enemy = load(ENEMY_SCRIPTS[event.kind]).new()
	boss.position = Course.ground_at(Course.stage.midboss_d + float(event.get("ahead", 0.0)), 0.0)
	world.add_enemy(boss)
	world.boss = boss
	world.boss_changed.emit(boss)
	if event.has("music"):
		Sfx.play_music(event.music)
	boss.died.connect(func(_e: Entity) -> void:
		world.boss = null
		world.boss_changed.emit(null)
		if event.has("music") and section + 1 < Course.stage.section_starts.size():
			Sfx.play_music(Course.stage.music(section + 1)) # Its theme sinks with it; the road ahead takes over.
		get_tree().create_timer(MIDBOSS_RESUME).timeout.connect(func() -> void:
			if event.kind == "hovercraft":
				world.rail.d = maxf(world.rail.d, Course.to_course(world.player.global_position).x - world.player.course_offset)
				world.player.local_velocity = Vector2.ZERO
			world.rail.mode = Rail.Mode.RAIL))


func _start_boss(event: Dictionary) -> void:
	var world := World.current
	var arena := Course.stage.arena_at(world.rail.d)
	Course.stage.arena_center_d = arena.d
	Course.stage.arena_radius = arena.radius
	var on_rail: bool = event.get("rail", false) # The boss fight runs along the road instead of in an arena.
	world.rail.mode = Rail.Mode.RAIL if on_rail else Rail.Mode.ARENA
	var boss: Enemy = load(ENEMY_SCRIPTS[event.kind]).new()
	boss.position = Course.ground_at(Course.stage.arena_center_d + event.get("ahead", 70.0), event.get("u", 0.0)) + Vector3.UP * float(event.height) if event.has("height") else Course.stage.boss_position()
	world.add_enemy(boss)
	world.boss = boss
	world.boss_changed.emit(boss)
	boss.died.connect(func(_e: Entity) -> void:
		world.boss_changed.emit(null)
		world.rail.sprint = 0.0
		get_tree().create_timer(BOSS_CLEAR_DELAY).timeout.connect(world.stage_cleared.emit))
	Sfx.play_music(event.get("music", Course.stage.boss_music()))
