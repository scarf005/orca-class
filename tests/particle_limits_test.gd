extends TestCase


func _set_limits(life: float, distance: float) -> void:
	var tuning := GameTuning.new()
	for row: Array in tuning._rows:
		if row[0] == "Fragments/smoke duration (s)":
			row[2].call(life)
		if row[0] == "Fragments/smoke travel (m)":
			row[2].call(distance)


func test_debris_and_its_smoke_use_only_the_shared_duel_duration() -> void:
	_set_limits(0.75, 50.0)
	var labels: Array = GameTuning.new()._rows.map(func(row: Array) -> String: return row[0])
	check(not labels.has("Debris life (s)") and not labels.has("Debris smoke life (s)"), "duplicate debris settings are removed")
	var fx := Fx.new()
	add_child(fx)
	fx._shard(Vector3(0, 100, 0), Vector3(8, 6, 0), 0.4, Fx.Debris.FOLIAGE)
	var shard: Fx.Particle = fx._pools[Fx.Kind.SOLID][0]
	check_eq(shard.max_life, 0.75, "debris uses the shared duration instead of a separate cap")
	fx._process(0.125)
	var puffs: Array = fx._pools[Fx.Kind.GLOW]
	check(not puffs.is_empty(), "moving debris emits smoke through the production path")
	check(puffs.all(func(p: Fx.Particle) -> bool: return p.max_life == 0.75), "debris smoke also uses the shared duration")
	fx.free()


func test_fragments_and_smoke_expire_at_default_duration() -> void:
	_set_limits(1.0, 50.0)
	var fx := Fx.new()
	add_child(fx)
	for kind: Fx.Kind in [Fx.Kind.SOLID, Fx.Kind.GLOW, Fx.Kind.FLAME]:
		fx.spawn(kind, Vector3.ZERO, Vector3.ZERO, 4.0, 1.0, Color.WHITE)
	fx._process(0.75)
	check_eq(fx.particle_count(), 3, "particles survive before the duration limit")
	fx._process(0.25)
	for kind: Fx.Kind in [Fx.Kind.SOLID, Fx.Kind.GLOW]:
		check(fx._pools[kind].is_empty(), "fragments and smoke expire at exactly 1 s")
		check_eq(fx._multimeshes[kind].visible_instance_count, 0, "expired particles are no longer rendered")
	check_eq(fx._pools[Fx.Kind.FLAME].size(), 1, "flames retain their own lifetime")
	fx.free()


func test_fragments_and_smoke_expire_at_cumulative_travel_limit() -> void:
	_set_limits(8.0, 50.0)
	var fx := Fx.new()
	add_child(fx)
	for kind: Fx.Kind in [Fx.Kind.SOLID, Fx.Kind.GLOW, Fx.Kind.FLAME]:
		fx.spawn(kind, Vector3.ZERO, Vector3(100, 0, 0), 4.0, 1.0, Color.WHITE)
	fx._process(0.25)
	check_eq(fx.particle_count(), 3, "particles survive after travelling 25 m")
	for kind: Fx.Kind in [Fx.Kind.SOLID, Fx.Kind.GLOW, Fx.Kind.FLAME]:
		(fx._pools[kind][0] as Fx.Particle).velocity = Vector3(-100, 0, 0)
	fx._process(0.25)
	for kind: Fx.Kind in [Fx.Kind.SOLID, Fx.Kind.GLOW]:
		check(fx._pools[kind].is_empty(), "50 m out-and-back travel expires particles despite zero displacement")
		check_eq(fx._multimeshes[kind].visible_instance_count, 0, "distance-expired particles are not rendered")
	check_eq(fx._pools[Fx.Kind.FLAME].size(), 1, "flames are not distance limited")
	fx.free()


func test_duel_limits_change_live_particles_and_preserve_shorter_lifetimes() -> void:
	_set_limits(4.0, 100.0)
	var fx := Fx.new()
	add_child(fx)
	fx.spawn(Fx.Kind.GLOW, Vector3.ZERO, Vector3(60, 0, 0), 6.0, 1.0, Color.WHITE)
	fx.spawn(Fx.Kind.SOLID, Vector3.ZERO, Vector3.ZERO, 0.5, 1.0, Color.WHITE)
	fx._process(1.25)
	check(fx._pools[Fx.Kind.SOLID].is_empty(), "shorter caller lifetime still expires")
	check_eq(fx._pools[Fx.Kind.GLOW].size(), 1, "duel settings extend both default caps")
	_set_limits(4.0, 50.0)
	fx._process(0.0)
	check(fx._pools[Fx.Kind.GLOW].is_empty(), "lowering travel limit removes already-over-limit smoke")
	fx.spawn(Fx.Kind.SOLID, Vector3.ZERO, Vector3.ZERO, 6.0, 1.0, Color.WHITE)
	fx._process(1.25)
	check_eq(fx._pools[Fx.Kind.SOLID].size(), 1, "extended duration applies to fragments")
	_set_limits(1.0, 50.0)
	fx._process(0.0)
	check(fx._pools[Fx.Kind.SOLID].is_empty(), "lowering duration removes already-over-limit fragments")
	fx.free()
