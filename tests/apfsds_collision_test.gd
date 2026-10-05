extends TestCase


func test_beam_damages_scenery_when_entering_through_roof() -> void:
	var world := stage()
	world.director.set_process(false)
	Course.flat = true
	var prop := Prop.new().setup("test_roof", BoxMesh.new(), 1.0, 2.0, 100000.0)
	prop.position = Vector3(40, 0, 0)
	world.props.add_child(prop)
	world.player.current_round = Armament.Round.APFSDS
	world.player.round_count = 6
	world.player.fire_cannon(Vector3(40, 2.5, 0), Vector3.DOWN, 1.0)
	check_eq(prop.max_hp - prop.hp, 9000.0, "a vertical roof entry deals exactly one dart hit before reaching earth")


func test_nonlethal_dart_boss_impacts_do_not_create_fireballs() -> void:
	for kind in ["gunship", "colossus"]:
		var world := stage()
		world.director.set_process(false)
		var boss: Enemy = Gunship.new() if kind == "gunship" else Colossus.new()
		boss.position = Vector3(40, 30, -60)
		world.add_enemy(boss)
		boss.set_process(false)
		# Keep real damage acceptance, without breaking a module or cap: their destruction can explode.
		if boss is Gunship:
			for part: Gunship.Part in boss.parts.values():
				part.hp = 100000.0
		else:
			for part: Colossus.Part in boss.parts:
				part.cap = 100000.0
		var before := boss.hp
		world.player.current_round = Armament.Round.APFSDS
		world.player.round_count = 6
		world.player.charge_lock = boss
		world.player._fire_shell(Armament.Round.APFSDS, boss.hit_center() + Vector3.BACK * 40.0, Vector3.FORWARD, 1.0)
		check(boss.hp < before if boss is Gunship else boss.parts.any(func(p: Colossus.Part) -> bool: return p.cap < 100000.0), "the real boss accepts the dart hit")
		check_eq(world.fx._transients.filter(func(t: Dictionary) -> bool: return t.has("fireball")).size(), 0, "a non-explosive dart impact has no fireball on %s" % kind)
