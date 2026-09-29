extends Node
## CPU work only, not rendered FPS. Run with --headless -- --run=res://tools/benchmark.gd.


func run() -> int:
	var terrain := Terrain.new()
	terrain.threaded = false
	add_child(terrain)
	terrain.stream(0.0, true)
	var timings: Array[float] = []
	# Stream at 120 updates/s for 25 simulated seconds, including new chunks and attachments.
	for frame in 3000:
		var start := Time.get_ticks_usec()
		terrain.stream(frame * 22.2 / 120.0)
		timings.append((Time.get_ticks_usec() - start) / 1000.0)
	_report("terrain_stream", timings)
	terrain.free()
	var fx := Fx.new()
	add_child(fx)
	seed(42)
	for kind in [Fx.Kind.SOLID, Fx.Kind.GLOW, Fx.Kind.FLAME]:
		for i in 600:
			fx.spawn(kind, Vector3(i % 30, 8, i / 30), Vector3(1, 2, 3), 1000, 1, Color.WHITE,
				{"spin": 1.0, "drag": 0.6, "gravity": 2.0})
	timings.clear()
	for frame in 160:
		var start := Time.get_ticks_usec()
		fx._process(1.0 / 200.0)
		if frame >= 40:
			timings.append((Time.get_ticks_usec() - start) / 1000.0)
	_report("particles_%d" % fx.particle_count(), timings)
	fx.free()
	# Thirty flyers in flight, each with its trail (an FPV wave and then some).
	var movers: Array[Node3D] = []
	var trails: Array[FlyerTrail] = []
	for i in 30:
		var mover := Node3D.new()
		add_child(mover)
		var trail := FlyerTrail.new()
		trail.source = mover
		trail.setup(mover.position, 0.25)
		add_child(trail)
		movers.append(mover)
		trails.append(trail)
	timings.clear()
	for frame in 300:
		var start := Time.get_ticks_usec()
		for i in 30:
			movers[i].position = Vector3(frame * 0.5, 10.0 + i, sin(frame * 0.1 + i) * 8.0)
			trails[i]._process(1.0 / 60.0)
		if frame >= 60:
			timings.append((Time.get_ticks_usec() - start) / 1000.0)
	_report("flyer_trails_30", timings)
	# Twelve ground enemies driving at 16 m/s, each laying prints into the shared buffer.
	var marks := TrackMarks.new(TrackMarks.SHARED_COUNT)
	add_child(marks)
	var lasts: Array[Vector3] = []
	lasts.resize(12)
	lasts.fill(Vector3.INF)
	timings.clear()
	for frame in 600:
		var start := Time.get_ticks_usec()
		for i in 12:
			var hull := Transform3D(Basis(), Vector3(i * 8.0, 0.0, 200.0 - frame * 16.0 / 60.0))
			lasts[i] = marks.lay(lasts[i], hull, [-0.95, 0.95], 0.6, false, false)
		if frame >= 60:
			timings.append((Time.get_ticks_usec() - start) / 1000.0)
	_report("enemy_marks_12", timings)
	# Forty fire zones and ten burning enemies with the particle system running, as in a dragon's-breath fight.
	var world := World.new()
	add_child(world)
	world.start_stage()
	world.player.input_enabled = false
	world.rail.mode = Rail.Mode.ARENA
	seed(7)
	for i in 10:
		var enemy := Ugv.new()
		enemy.position = Course.ground_at(world.rail.d + 20.0 + i * 5.0, (i % 5 - 2) * 4.0)
		world.add_enemy(enemy)
		enemy.max_hp = 1e6
		enemy.hp = 1e6
	for i in FireZone.MAX_ZONES:
		FireZone.ignite(Course.ground_at(world.rail.d + 15.0 + (i % 8) * 8.0, (i / 8 - 2) * 8.0))
	timings.clear()
	var peak := 0
	for frame in 240:
		var start := Time.get_ticks_usec()
		for enemy in world.enemies:
			enemy.burning = 3.0
			enemy.hp = enemy.max_hp
			enemy._burn(1.0 / 60.0)
		for zone in FireZone._zones:
			zone._process(1.0 / 60.0)
		world.fx._process(1.0 / 60.0)
		if frame >= 60:
			timings.append((Time.get_ticks_usec() - start) / 1000.0)
		peak = maxi(peak, world.fx.particle_count())
	_report("fire_40_zones_10_burning_peak%d" % peak, timings)
	world.free()
	# Forty ground units checking for water each frame, plus 200 bouncing debris spawns, over the road and the reservoir.
	fx = Fx.new()
	add_child(fx)
	timings.clear()
	for frame in 300:
		var start := Time.get_ticks_usec()
		for i in 40:
			var at := Course.to_world(2000.0 + i * 12.0 + frame, -20.0 + i, 0.0)
			Water.surface_at(Vector3(at.x, Course.height_at(at), at.z))
		for i in 200:
			var at := Course.to_world(2000.0 + i * 4.0, -20.0 + frame % 10, 5.0)
			fx.spawn(Fx.Kind.SOLID, at, Vector3.ZERO, 0.01, 1, Color.WHITE, {"bounce": true})
		if frame >= 60:
			timings.append((Time.get_ticks_usec() - start) / 1000.0)
		fx._process(1.0 / 60.0)
	_report("water_40_units_200_bounces", timings)
	return 0


func _report(label: String, timings: Array[float]) -> void:
	timings.sort()
	print("BENCH %s median=%.3fms p95=%.3fms p99=%.3fms max=%.3fms samples=%d" % [label,
		timings[timings.size() / 2], timings[int(timings.size() * 0.95)],
		timings[int(timings.size() * 0.99)], timings[-1], timings.size()])
