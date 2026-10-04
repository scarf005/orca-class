extends TestCase
## The debug room builds every model without errors and restores the course when it closes.


func test_debug_room_shows_everything() -> void:
	var room := DebugRoom.new()
	add_child(room)
	await frames(5)
	check(Course.flat, "the floor is flat while the room is open")
	var expected := [
		"fpv", "ugv:gun", "ugv:atgm", "ugv:supply", "uav", "helicopter", "tiltrotor",
		"crawler", "spitter", "walker:gun", "walker:missile", "quad:flak", "quad:mortar",
		"colossus", "gunship",
	]
	var actual: Array[String] = []
	for enemy: Entity in room.world.enemies:
		if enemy is FpvDrone:
			actual.append("fpv")
		elif enemy is Ugv:
			actual.append("ugv:%s" % enemy.weapon)
		elif enemy is Uav:
			actual.append("uav")
		elif enemy is Helicopter:
			actual.append("helicopter")
		elif enemy is Tiltrotor:
			actual.append("tiltrotor")
		elif enemy is Crawler:
			actual.append("crawler")
		elif enemy is Spitter:
			actual.append("spitter")
		elif enemy is Walker:
			actual.append("walker:%s" % enemy.weapon)
		elif enemy is QuadMech:
			actual.append("quad:%s" % enemy.weapon)
		elif enemy is Colossus:
			actual.append("colossus")
		elif enemy is Gunship:
			actual.append("gunship")
	actual.sort()
	expected.sort()
	check_eq(actual, expected, "debug room poses the complete enemy and boss catalogue")
	check(room.world.pickups.size() == Pickup.IDS.size(), "every pickup is shown")
	check(not room.world.pickups.any(func(p: Pickup) -> bool: return p.id in ["canister", "airburst"]), "disabled rounds do not spawn in the debug room")
	var enemy_count := room.world.enemies.size()
	await frames(30)
	check_eq(room.world.enemies.size(), enemy_count, "posed enemies do not act, leave or attack")
	room.queue_free()
	await frames(2)
	check(not Course.flat, "closing the room restores the valley")
