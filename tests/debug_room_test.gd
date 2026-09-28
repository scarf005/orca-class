extends TestCase
## The debug room builds every model without errors and restores the course when it closes.


func test_debug_room_shows_everything() -> void:
	var room := DebugRoom.new()
	add_child(room)
	await frames(5)
	check(Course.flat, "the floor is flat while the room is open")
	check(room.world.enemies.size() >= 9, "all enemy types and bosses are posed")
	check(room.world.enemies.any(func(e: Entity) -> bool: return e is Helicopter), "ordinary helicopter is displayed")
	check(room.world.enemies.any(func(e: Entity) -> bool: return e is Gunship), "twin-rotor boss is displayed separately")
	check(room.world.pickups.size() == Pickup.IDS.size(), "every pickup is shown")
	var enemy_count := room.world.enemies.size()
	await frames(30)
	check_eq(room.world.enemies.size(), enemy_count, "posed enemies do not act, leave or attack")
	room.queue_free()
	await frames(2)
	check(not Course.flat, "closing the room restores the valley")
