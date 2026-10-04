extends TestCase
## Where a stage says water slows the tank, shallow water cuts the strafe, deep water cuts it more and halves the overdrive refill.

const DRY_U := 0.0
const SHALLOW_U := 20.0
const DEEP_U := -20.0
const D := 300.0


## Stage 2's road with a shallow sheet to the right and a deep one to the left; the road itself is dry.
class Flooded extends Stage2:
	func water_surface(c: Vector2) -> float:
		if c.y > 10.0:
			return 0.4
		return 1.4 if c.y < -10.0 else -INF


## The same water on a stage that does not slow the tank.
class Dry extends Flooded:
	func _init() -> void:
		super()
		water_slows = false


func _flooded(definition: StageDef) -> World:
	var world := stage("", true, 2)
	Course.stage = definition # Same road as stage 2, so the world's terrain stays valid.
	world.player.invulnerable = true
	return world


## The tank on a spot, pinned there so only its strafe speed and the meter change.
func _drive(world: World, u: float, frame_count: int, action := "") -> Dictionary:
	var tank := world.player
	tank.input_enabled = not action.is_empty()
	world.rail.d = D
	world.rail.meter = 0.2
	tank.course_u = u
	tank.course_offset = 0.0
	tank.local_velocity = Vector2.ZERO
	var fastest := 0.0
	if not action.is_empty():
		Input.action_press(action)
	for i in frame_count:
		await frames(1)
		fastest = maxf(fastest, absf(tank.local_velocity.x))
		tank.course_u = u
		world.rail.d = D
	if not action.is_empty():
		Input.action_release(action)
	tank.input_enabled = false
	return {"speed": fastest, "meter": world.rail.meter, "depth": tank.water_depth}


func test_wading_slows_the_strafe_and_deep_water_slows_the_refill() -> void:
	var world := _flooded(Flooded.new())
	var dry := await _drive(world, DRY_U, 20, "move_right")
	var shallow := await _drive(world, SHALLOW_U, 20, "move_right")
	var deep := await _drive(world, DEEP_U, 20, "move_left")
	check_eq(dry.depth, 0.0, "the road is dry")
	check(shallow.depth > 0.0 and shallow.depth <= Water.DEEP, "the right bank is shallow (%.2f m)" % shallow.depth)
	check(deep.depth > Water.DEEP, "the left bank is deep (%.2f m)" % deep.depth)
	check_near(dry.speed, Tank.MOVE_SPEED.x, 0.01, "dry ground: full strafe speed")
	check_near(shallow.speed, Tank.MOVE_SPEED.x * Tank.WADE_SPEED, 0.01, "shallow: 85%")
	check_near(deep.speed, Tank.MOVE_SPEED.x * Tank.DEEP_SPEED, 0.01, "deep: 65%")
	var gains := {}
	for name: String in ["dry", "shallow", "deep"]:
		var u: float = {"dry": DRY_U, "shallow": SHALLOW_U, "deep": DEEP_U}[name]
		gains[name] = (await _drive(world, u, 60)).meter - 0.2
	check(gains.dry > 0.05, "the meter refills on dry ground (%.3f)" % gains.dry)
	check_near(gains.shallow, gains.dry, 0.01, "shallow water leaves the refill alone")
	check_near(gains.deep, gains.dry * Tank.DEEP_REFILL, gains.dry * 0.06, "deep water halves it (%.3f vs %.3f)" % [gains.deep, gains.dry])


func test_a_stage_without_the_rule_does_not_slow_the_tank() -> void:
	var world := _flooded(Dry.new())
	var shallow := await _drive(world, SHALLOW_U, 20, "move_right")
	check(Water.surface_at(world.player.global_position) > -INF, "the tank stands in water")
	check_eq(shallow.depth, 0.0, "but the stage does not count it")
	check_near(shallow.speed, Tank.MOVE_SPEED.x, 0.01, "so the strafe keeps full speed")
	check_eq(world.player.water_factor(), 1.0, "with no factor")


func test_stage_1_reservoir_does_not_change_the_driving() -> void:
	var world := stage("", true, 1)
	var tank := world.player
	world.rail.d = 2200.0
	tank.course_u = -30.0
	await frames(3)
	check(Water.surface_at(tank.global_position) > -INF, "the tank is in the reservoir")
	check_eq(tank.water_depth, 0.0, "stage 1 does not slow it")
	check_eq(tank.water_factor(), 1.0, "with the full strafe")


func test_hud_shows_what_the_tank_is_driving_through() -> void:
	var world := _flooded(Flooded.new())
	var hud := Hud.new()
	hud.world = world
	add_child(hud)
	var tank := world.player
	var seen := {}
	for spot in [[DRY_U, "dry"], [SHALLOW_U, "shallow"], [DEEP_U, "deep"]]:
		world.rail.d = D
		tank.course_u = spot[0]
		await frames(2)
		seen[spot[1]] = hud.terrain_glyph()
	check_eq(seen, {"dry": 0, "shallow": 1, "deep": 2}, "the glyph names the water")
	hud.free()
