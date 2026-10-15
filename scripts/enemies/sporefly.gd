class_name Sporefly
extends FpvDrone
## Stage 1 fungal swarm flyer: the FPV drone's weave, flashing hover and committed dive, and its pursuit
## from behind, but a pod body that bursts into a lingering spore cloud instead of a warhead. Coax or
## the tail clears the swarm; a swell the tank drives out of costs only the cloud.

const CLOUD_RADIUS := 2.6


func _init() -> void:
	super()
	debris = [Fx.Debris.FLESH, Fx.Debris.SPORE]
	weakness = {Hit.Kind.BLAST: 1.5, Hit.Kind.FIRE: 3.0, Hit.Kind.FRAGMENT: 2.0}


func build() -> void:
	var body := MeshInstance3D.new()
	body.mesh = ActorMeshes.mesh("sporefly", "body")
	model.add_child(body)
	for slot: Vector2 in [Vector2(0.69, -0.375), Vector2(-0.69, -0.375), Vector2(0.63, 0.31), Vector2(-0.63, 0.31)]:
		var rotor := MeshInstance3D.new()
		rotor.mesh = ActorMeshes.mesh("sporefly", "wing")
		rotor.position = Vector3(slot.x, 0.375, slot.y)
		rotor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(rotor)
		_rotors.append(rotor)
	_light = MeshInstance3D.new()
	_light.mesh = ActorMeshes.mesh("sporefly", "light")
	_light.position = Vector3(0, 0.0625, -0.9)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Palette.FUNGUS
	_light.material_override = material
	model.add_child(_light)
	_buzz = Sfx.loop("buzz", self, -8.0)
	if _buzz:
		_buzz.pitch_scale = randf_range(0.6, 0.8)


func _hard_shot(tank: Tank) -> void:
	var glob := fire_at("pellet", hit_center(), tank.hit_center() + tank.velocity * 0.4, 26.0, 6.0, Palette.FUNGUS)
	glob.hit.kind = Hit.Kind.SPORE
	glob.interceptable = true


func _strike(tank: Tank) -> void:
	var hit := Hit.make(Hit.Kind.SPORE, 9.0, global_position, _dive_dir)
	hit.source = self
	tank.take_hit(hit)
	Hazard.spawn(global_position, CLOUD_RADIUS, 1.8, 6.0)
	_explode()


func _explode() -> void:
	World.current.fx.spores(global_position, 14, CLOUD_RADIUS)
	Sfx.play("spore", global_position)
	despawn()


func on_death(hit: Hit) -> void:
	soft_death(hit)
