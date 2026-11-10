extends TestCase
## City bipeds step with the foot they stand on planted while they walk, and brace to skate once they
## move faster than a stride can carry them.

const STEP := 1.0 / 60.0
const BUMP := 0.4 ## Metres the ground is raised under the right foot.


## A Kain whose right foot always finds ground BUMP higher than the street.
class BumpKain extends Kain:
	func ground_under(at: Vector3) -> float:
		return super(at) + (BUMP if model.to_local(at).x > 0.0 else 0.0)


func _setup() -> World:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 2)
	await frames(2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.velocity = Vector3.ZERO
	for prop: Prop in world.props.get_children():
		prop.dead = true
	world.rail.mode = Rail.Mode.HOLD
	return world


func _spawn(world: World, enemy: BipedMech, ahead := 60.0) -> BipedMech:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + ahead, 0.0)
	world.add_enemy(enemy)
	var toward := world.player.global_position - enemy.global_position
	enemy.model.rotation.y = atan2(-toward.x, -toward.z)
	return enemy


func _feet(mech: BipedMech) -> Array[Vector3]:
	var feet: Array[Vector3] = []
	for i in mech._legs.size():
		feet.append(mech.sole(i))
	return feet


## Walks `mech` toward `goal` at `speed` and returns how far the foot it stands on (the lower one) slid over the
## ground, as a share of the distance the body covered.
func _slip(mech: BipedMech, goal: Vector3, speed: float, seconds: float) -> float:
	var path := 0.0
	var slid := 0.0
	var last := _feet(mech)
	for _i in roundi(seconds / STEP):
		var body := mech.global_position
		mech.walk_to(goal, speed, STEP)
		mech.stride(STEP)
		path += Vector2(mech.global_position.x - body.x, mech.global_position.z - body.z).length()
		var feet := _feet(mech)
		var low := 0 if feet[0].y < feet[1].y - 0.01 else (1 if feet[1].y < feet[0].y - 0.01 else -1)
		var moves: Array[float] = []
		for k in 2:
			moves.append(Vector2(feet[k].x - last[k].x, feet[k].z - last[k].z).length())
		slid += moves[low] if low >= 0 else minf(moves[0], moves[1])
		last = feet
	check(path > 4.0, "the mech walked (%.1f m)" % path)
	return slid / maxf(path, 0.001)


func test_a_walking_biped_keeps_its_standing_foot_planted_forward_and_backward() -> void:
	for kind in [Kain, Abel, Adam]:
		var world := await _setup()
		var mech := _spawn(world, kind.new())
		var facing := -mech.model.global_basis.z
		facing.y = 0.0
		var forward := _slip(mech, mech.global_position + facing.normalized() * 40.0, 6.0, 2.0)
		check(forward < 0.12, "%s walking toward the tank slides its standing foot %.0f%% of the way" % [kind.get_global_name(), forward * 100.0])
		var backward := _slip(mech, mech.global_position - facing.normalized() * 40.0, 6.0, 2.0)
		check(backward < 0.12, "%s backing off slides its standing foot %.0f%% of the way" % [kind.get_global_name(), backward * 100.0])


## A Kain that counts the feet it hears land.
class CountingKain extends Kain:
	var landed: Array[int] = []
	func _footfall(i: int) -> void:
		landed.append(i)
		super(i)


func test_a_walking_biped_rolls_over_its_standing_leg_leans_in_and_thumps_each_step() -> void:
	var world := await _setup()
	var mech: CountingKain = _spawn(world, CountingKain.new())
	var facing := -mech.model.global_basis.z
	facing.y = 0.0
	var goal := mech.global_position + facing.normalized() * 40.0
	var over := 0
	var samples := 0
	for _i in roundi(2.0 / STEP):
		mech.walk_to(goal, 6.0, STEP)
		mech.stride(STEP)
		var feet := _feet(mech)
		var standing := 0 if feet[0].y < feet[1].y - 0.01 else (1 if feet[1].y < feet[0].y - 0.01 else -1)
		if standing >= 0 and absf(mech._body.rotation.z) > 0.01:
			samples += 1
			# The standing hip sits lower than the swinging one.
			if signf(mech._legs[standing].position.x) == -signf(mech._body.rotation.z):
				over += 1
	check(samples > 30 and over == samples, "the body rolls over the standing leg (%d of %d frames)" % [over, samples])
	check(mech._body.rotation.x < -0.05, "and leans into the walk (%.2f rad)" % mech._body.rotation.x)
	check(mech.landed.size() >= 3 and mech.landed.has(0) and mech.landed.has(1), "each landing foot thumps (%s)" % [mech.landed])


func test_a_biped_pacing_the_rail_braces_its_legs_instead_of_flickering_them() -> void:
	var world := await _setup()
	var mech := _spawn(world, Kain.new())
	var low: Array[float] = [INF, INF]
	var high: Array[float] = [-INF, -INF]
	var goal := mech.global_position + (mech.global_position - world.player.global_position).normalized() * 200.0
	for i in 90:
		mech.walk_to(goal, Rail.CRUISE, STEP)
		mech.stride(STEP)
		if i >= 30:
			for k in 2:
				low[k] = minf(low[k], mech._legs[k].rotation.x)
				high[k] = maxf(high[k], mech._legs[k].rotation.x)
	for k in 2:
		check(rad_to_deg(high[k] - low[k]) < 5.0, "leg %d holds its skating stance at rail speed (%.1f deg)" % [k, rad_to_deg(high[k] - low[k])])
	check(absf(mech._legs[0].rotation.x - mech._legs[1].rotation.x) > 0.3, "one leg braced ahead of the other")


func test_each_foot_stands_on_the_ground_under_it() -> void:
	var world := await _setup()
	var mech := _spawn(world, BumpKain.new())
	for _i in 30:
		mech.stride(STEP)
	for i in 2:
		var sole := mech.sole(i)
		check_near(sole.y, mech.ground_under(sole), 0.05, "foot %d rests on the ground under it (%.2f m)" % [i, sole.y - mech.ground_under(sole)])
	check(mech._knees[1].rotation.x - mech._knees[0].rotation.x > 0.15, "the knee on the raised ground folds further (%.2f rad)" % (mech._knees[1].rotation.x - mech._knees[0].rotation.x))
