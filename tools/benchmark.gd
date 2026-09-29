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
	return 0


func _report(label: String, timings: Array[float]) -> void:
	timings.sort()
	print("BENCH %s median=%.3fms p95=%.3fms p99=%.3fms max=%.3fms samples=%d" % [label,
		timings[timings.size() / 2], timings[int(timings.size() * 0.95)],
		timings[int(timings.size() * 0.99)], timings[-1], timings.size()])
