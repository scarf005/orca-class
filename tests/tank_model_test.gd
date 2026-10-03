extends TestCase
## Coax barrels emerge inside the mantlet outline without changing the main gun.


func test_every_coax_tier_fits_the_mantlet_and_uses_its_actual_muzzle() -> void:
	var model := stage().player.model
	for calibers: Array in Armament.COAX_TIERS:
		model.set_coax_guns(calibers)
		check_eq(model.coax_muzzles.size(), calibers.size(), "each mounted gun has a muzzle")
		for i in calibers.size():
			var tip := model.coax_muzzles[i]
			var gun := tip.get_parent() as Node3D
			var mesh := gun.get_child(0) as MeshInstance3D
			var bounds := mesh.mesh.get_aabb()
			var at := gun.position + tip.position
			var radius: float = {8: 0.035, 15: 0.055, 20: 0.12}[calibers[i]]
			check(absf(at.x) + radius < 0.45, "barrel fits inside the mantlet width")
			check(absf(at.y) + radius < 0.31, "barrel fits inside the mantlet height")
			check(at.z < -0.65 and at.z >= -1.2, "only a short barrel projects past the mantlet front")
			check_near(tip.position.z, bounds.position.z, 0.001, "shots originate at the mesh's muzzle")
			check(gun.get_parent().get_parent() == model.gun_pivot, "coax follows main gun elevation")
	check_eq(model.muzzle.position, Vector3(0, 0, -5.9), "main gun length is unchanged")
