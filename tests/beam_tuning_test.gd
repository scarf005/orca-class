extends TestCase


func _panel() -> DuelPanel:
	var panel := DuelPanel.new()
	add_child(panel)
	return panel


func _slider(panel: DuelPanel, label: String) -> HSlider:
	for i in panel._tuning._rows.size():
		if panel._tuning._rows[i][0] == label:
			return panel._grid.get_child(i * 3 + 1)
	check(false, "duel slider exists: " + label)
	return null


func test_duel_smoke_sliders_control_rendered_size_and_fade_and_save() -> void:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	var panel := _panel()
	var shrink := _slider(panel, "Rail smoke shrink (0-1)")
	var fade := _slider(panel, "Rail smoke fade speed (x)")
	if shrink == null or fade == null:
		return
	var samples: Array[Vector2] = []
	for values: Vector2 in [Vector2(0, 1), Vector2(1, 1), Vector2(1, 2)]:
		shrink.value = values.x
		fade.value = values.y
		world.fx._pools[Fx.Kind.GLOW].clear()
		world.fx.rail_beam(Vector3(40, 30, 0), Vector3(40, 30, -30), Palette.CYAN)
		var trails: Array[Fx.Particle] = []
		var splashes: Array[Fx.Particle] = []
		world.fx._advance_pool(Fx.Kind.GLOW, 0.4, trails, splashes)
		var buffer: PackedFloat32Array = world.fx._buffers[Fx.Kind.GLOW]
		check(buffer.size() >= Fx.STRIDE, "smoke remains visible during the sampled fade")
		if buffer.size() >= Fx.STRIDE:
			samples.append(Vector2(buffer[16], buffer[15]))
	if samples.size() == 3:
		check(samples[1].x < samples[0].x, "more shrink produces smaller rendered smoke")
		check_eq(samples[1].y, samples[0].y, "shrink amount does not alter opacity")
		check(samples[2].y < samples[1].y, "faster fade produces lower rendered opacity at the same age")
	var config := ConfigFile.new()
	check_eq(config.load(GameTuning.PATH), OK, "slider changes save personal tuning")
	check_eq(config.get_value("constants", "Rail smoke shrink (0-1)"), 1.0, "shrink slider persists")
	check_eq(config.get_value("constants", "Rail smoke fade speed (x)"), 2.0, "fade slider persists")
	panel.queue_free()


func test_duel_beam_speed_changes_narrowing_without_shortening_the_ray() -> void:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	var panel := _panel()
	var slider := _slider(panel, "Hitscan beam shrink speed (x)")
	if slider == null:
		return
	var widths: Array[float] = []
	for speed in [0.5, 2.0]:
		slider.value = speed
		var before := world.fx._transients.size()
		world.player._fire_shell(Armament.Round.APFSDS, Vector3(40, 30, 0), Vector3.FORWARD, 1.0)
		var beam: MeshInstance3D = world.fx._transients[before + 1].node
		var length := beam.basis.z.length()
		world.fx._update_transients(0.02)
		widths.append(beam.basis.x.length())
		# Basis columns use float32; allow 1e-4 m over a 588 m beam.
		check_near(beam.basis.z.length(), length, 0.0001, "narrowing never shortens a hitscan ray")
	check(widths[1] < widths[0], "faster slider setting narrows the same beam more quickly")
	var config := ConfigFile.new()
	check_eq(config.load(GameTuning.PATH), OK, "beam speed slider saves")
	check_eq(config.get_value("constants", "Hitscan beam shrink speed (x)"), 2.0, "beam speed persists")
	panel.queue_free()


func test_every_hitscan_cannon_canister_and_ciws_beam_narrows() -> void:
	for round in [Armament.Round.APHE, Armament.Round.HEAT, Armament.Round.APFSDS, Armament.Round.AIRBURST, Armament.Round.CANISTER, -1]:
		var world := stage()
		world.set_process(false)
		world.director.set_process(false)
		Course.flat = true
		var muzzle := Vector3(40, 30, 0)
		if round == -1:
			var shot := world.spawn_projectile(Entity.Team.ENEMY, world.player.model.rws_lens.global_position + Vector3.FORWARD * 5, Vector3.BACK * 10, "orb")
			shot.interceptable = true
			shot.intercept_hp = 100
			world.player._update_ciws(0.01)
			check(shot.intercept_hp < 100, "CIWS follows its real damaging laser path")
		elif round == Armament.Round.CANISTER:
			world.player._fire_canister(muzzle, Vector3.FORWARD)
		else:
			world.player._fire_shell(round, muzzle, Vector3.FORWARD, 1.0)
		var meshes: Array = Fx._mesh_cache.keys().filter(func(key: String) -> bool: return key.begins_with("beam_")).map(func(key: String) -> Mesh: return Fx._mesh_cache[key])
		var beams := world.fx._transients.filter(func(t: Dictionary) -> bool: return t.node.mesh in meshes)
		check(not beams.is_empty(), "the production weapon creates beams for round %s" % round)
		var widths: Array[float] = []
		var lengths: Array[float] = []
		for beam in beams:
			widths.append(beam.node.basis.x.length())
			lengths.append(beam.node.basis.z.length())
		world.fx._update_transients(0.02)
		for i in beams.size():
			check(beams[i].node.basis.x.length() < widths[i], "each hitscan beam narrows for round %s" % round)
			check_near(beams[i].node.basis.z.length(), lengths[i], 0.0001, "the beam's endpoints stay fixed")
