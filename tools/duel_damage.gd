extends Node
## Stands the tank still against each listed hunter for a while and prints how much damage it took.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/duel_damage.gd --kind=abel,kain [--seconds=30] [--stage=2]

func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	for kind: String in String(args.get("kind", "abel")).split(",", false):
		for other: String in Director.duel_counts:
			Director.duel_counts[other] = 0
		Director.duel_counts[kind] = int(args.get("count", "1"))
		var screen := GameScreen.new()
		screen.stage = int(args.get("stage", "2"))
		screen.checkpoint = "duel"
		add_child(screen)
		var tank := screen.world.player
		var elapsed := 0.0
		var hits := []
		var last := tank.hp
		var warned := {}
		var warnings := 0
		while elapsed < float(args.get("seconds", "30")):
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			tank.input_enabled = false
			if tank.hp < last - 0.01:
				hits.append("%.1fs:-%.0f" % [elapsed, last - tank.hp])
			last = tank.hp
			for enemy in screen.world.enemies.filter(func(e: Entity) -> bool: return e is Enemy):
				var now: bool = enemy.telegraphing()
				if now and not warned.get(enemy, false):
					warnings += 1
				warned[enemy] = now
		print("DUELDAMAGE %s hp=%.0f/%.0f attacks=%d hits=%s" % [kind, tank.hp, tank.max_hp, warnings, hits])
		screen.queue_free()
		await get_tree().process_frame
	return 0
