class_name Prop
extends Entity
## A destructible piece of scenery with a vertical-cylinder footprint.
## Anything the tank drives into breaks at once; crushable ones also give way to a tail swat. Tall
## thin ones (`falls`: poles, trees) snap at the base and topple the way they were shot instead of
## vanishing.

signal felled(prop: Prop) ## It started to topple.

var kind := ""
var footprint := 1.0
var height := 2.0
var crushable := false
var debris: Array = [Fx.Debris.WOOD, Fx.Debris.CONCRETE] ## Fx.Debris materials it breaks into.
var burnable := false
var explosive := false
var blast_size := 4.5 ## Radius of the explosion when an explosive prop goes up.
var fungal := false ## Bursts into spores and splatter when destroyed.
var vent := false ## A methane vent: any fire or blast sets it off in a flame burst that lights its neighbours.
var sluice := false ## A paddy gate (물꼬): broken, it lets a surge of water run down-slope.
var flattens := false ## Destroyed, it squelches and leaves a dark flattened stain of itself (ground veins).
var supports: Array[Prop] = [] ## Pieces resting on this one; they topple when it breaks.
var falls := false
var vehicle := false ## Run over, it is squashed, knocked flying or burst apart, but never blows up.
var _topple := -1.0
var _topple_axis := Vector3.RIGHT
var _topple_by_player := false
var rubble_mesh: Mesh
var score := 0


const DRAW_DISTANCE := 150.0 ## Fog hides small props well before this.
const VENT_CHAIN_RANGE := 16.0
const VENT_CHAIN_DELAY := 0.3 ## Seconds each vent burns before it lights the next.


func _init() -> void:
	team = Team.NEUTRAL
	always_tick = false


func setup(kind_value: String, mesh: Mesh, footprint_value: float, height_value: float, hp_value: float) -> Prop:
	kind = kind_value
	footprint = footprint_value
	height = height_value
	max_hp = hp_value
	hp = hp_value
	radius = footprint_value
	center_height = height_value * 0.5
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.name = "Mesh"
	# Tall landmarks stay visible down the valley; small clutter is culled and casts no shadow.
	instance.visibility_range_end = DRAW_DISTANCE + height_value * 12.0
	if height_value < 2.5 or footprint_value < 1.0:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	track_meshes(self)
	return self


static var _see_through := _make_see_through()
static var _stain_material := _make_stain()


## The vertex-colored material darkened to a wine-mauve, for what has been trodden flat.
static func _make_stain() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Palette.MAUVE.darkened(0.55)
	material.roughness = 1.0
	return material


## A screen-door version of the vertex-colored material, shared by every faded prop. It reuses the
## particle shader, so fading in the middle of a fight compiles nothing new.
static func _make_see_through() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/dither_fade.gdshader")
	material.set_shader_parameter("alpha_scale", 0.35)
	return material


## Tips over away from `from` and breaks apart when it hits the ground.
func topple(by_player: bool, from: Vector3) -> void:
	if _topple >= 0.0:
		return
	_topple = 0.0
	_topple_by_player = by_player
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	_topple_axis = Vector3.UP.cross(away.normalized())
	always_tick = true
	set_process(true)
	felled.emit(self)


func is_falling() -> bool:
	return _topple >= 0.0


## Driven into by the tank itself, as opposed to crashing down or being shot.
static func _rammed(hit: Hit) -> bool:
	return hit != null and hit.kind == Hit.Kind.RAM and hit.source is Tank


func die(hit: Hit) -> void:
	if falls and not is_falling() and not dead and not overkilled:
		# Snaps at the base in a burst of splinters and goes over, away from the blow.
		hp = 1.0
		var push := Enemy.kill_push(hit)
		if push == Vector3.ZERO:
			push = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		var world := World.current
		world.fx.debris(global_position + Vector3.UP * 0.6, 10, debris, 8.0, 0.25, push)
		world.fx.dust(global_position, 4, 1.0, Palette.MIST)
		Sfx.play("wood", global_position, 0.0, randf_range(0.8, 1.1))
		if hit != null and hit.by_player():
			world.style_event("DEMOLITION", 8.0)
		topple(hit != null and hit.by_player(), global_position - push)
		return
	super(hit)


func tick(delta: float) -> void:
	if _topple < 0.0:
		return
	_topple += delta
	var k := minf(_topple / (0.7 if falls else 1.1), 1.0)
	rotate(_topple_axis, delta * (0.5 + k * 2.4))
	global_position.y -= delta * k * 6.0
	if k >= 1.0:
		var crash := Hit.make(Hit.Kind.RAM, 99999.0, global_position)
		if _topple_by_player:
			crash.source = World.current.player
		World.current.shake(0.5, global_position)
		take_hit(crash)


func set_see_through(enabled: bool) -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_override = _see_through if enabled else null


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	# Vertical cylinder: test in the ground plane, then check the height at the contact point.
	var base := global_position
	var r := footprint + extra_radius
	var a := Vector2(from.x - base.x, from.z - base.z)
	var b := Vector2(to.x - base.x, to.z - base.z)
	var d := b - a
	var length_2d := d.length()
	var t := -1.0
	if a.length() <= r:
		t = 0.0
	elif length_2d > 0.0001:
		var dir := d / length_2d
		var proj := -a.dot(dir)
		var perp := a.length_squared() - proj * proj
		if proj >= 0.0 and perp <= r * r:
			var along := proj - sqrt(r * r - perp)
			if along <= length_2d:
				t = along / length_2d
	if t < 0.0:
		return -1.0
	var y := lerpf(from.y, to.y, t)
	if y < base.y - 0.5 or y > base.y + height:
		return -1.0
	return t * from.distance_to(to)


## Driven over: one of a squashed hulk left behind, the whole car knocked flying in one wrecked
## piece, or a burst of parts; a crunch of glass and sparks either way, and no explosion.
func _run_over(world: World, push: Vector3) -> void:
	world.fx.sparks(global_position + Vector3.UP * 0.8, push + Vector3.UP, 18, Palette.BUTTER, 12.0)
	world.fx.debris(global_position + Vector3.UP, 6, [Fx.Debris.GLASS, Fx.Debris.PAINT], 9.0, 0.2, push)
	world.fx.dust(global_position, 6, footprint, Palette.OCHRE)
	world.shake(0.2, global_position)
	Sfx.play("rubble", global_position, 2.0, 1.3)
	Sfx.play("impact", global_position, 0.0, 0.7)
	var mesh := get_node("Mesh") as MeshInstance3D
	match randi() % 3:
		0:
			var hulk := MeshInstance3D.new()
			hulk.mesh = mesh.mesh
			hulk.transform = global_transform.scaled_local(Vector3(1.12, 0.28, 1.06))
			world.props.add_child(hulk)
		1:
			Wreck.launch(mesh, global_position + Vector3.UP, footprint, true, push * 16.0 + Vector3.UP * 4.0, false)
		2:
			world.fx.shatter(visual_bounds(), debris, push * 2.0)
	if score > 0:
		world.award(score, global_position, false)
	world.style_event("CRUSH", 12.0)


## A squelch, a puff of spores and flesh bits, and the same shape pressed flat and darkened where
## it grew, as scenery that can no longer be hit.
func _flatten(world: World) -> void:
	var center := global_position + Vector3.UP * height * 0.4
	Sfx.play("squelch", global_position, 0.0, randf_range(0.6, 1.25))
	world.fx.spores(center, 5, footprint)
	world.fx.debris(center, 4, [Fx.Debris.FLESH, Fx.Debris.SPORE], 5.0, 0.25)
	if score > 0:
		world.award(score, global_position, false)
	var stain := MeshInstance3D.new()
	stain.mesh = (get_node("Mesh") as MeshInstance3D).mesh
	stain.material_override = _stain_material
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stain.visibility_range_end = DRAW_DISTANCE
	stain.transform = global_transform.scaled_local(Vector3(1.1, 0.22, 1.1))
	world.props.add_child(stain)


## Down-slope of a paddy gate is toward the road, where the terraces step down.
func _release_surge(hit: Hit) -> void:
	var c := Course.to_course(global_position)
	Surge.release(global_position, Course.right(c.x) * -signf(c.y if c.y != 0.0 else 1.0), hit != null and hit.by_player())


## Marsh gas goes up in a fireball; vents nearby catch a beat later, one link after another.
func _burst_vent(world: World, hit: Hit) -> void:
	var center := global_position + Vector3.UP * 0.6
	var by_player := hit != null and hit.by_player()
	var chain := Hit.new()
	chain.source = self if by_player else null
	world.fx.fireball(center, 1.5, 6.0, 0.7)
	world.fx.smoke_column(center, 2.0, [Palette.ASH, Palette.STONE])
	Sfx.play("whoomp", global_position, 0.0, randf_range(0.9, 1.1))
	world.blast(center, 4.5, 40.0, Team.PLAYER if by_player else Team.NEUTRAL, chain, self, [Palette.WHITE, Palette.BUTTER, Palette.AMBER, Palette.CORAL])
	if score > 0:
		world.award(score, global_position, false)
	for other: Prop in world.props.in_radius(global_position, VENT_CHAIN_RANGE):
		if other.vent and other != self and not other.dead:
			world.get_tree().create_timer(VENT_CHAIN_DELAY).timeout.connect(func() -> void:
				if is_instance_valid(other) and not other.dead:
					other.take_hit(Hit.make(Hit.Kind.FIRE, 999.0, other.global_position)))


func damage_multiplier(hit: Hit) -> float:
	if hit.kind == Hit.Kind.FIRE:
		return 3.0 if burnable else 0.3
	return 1.0


func on_death(hit: Hit) -> void:
	var world := World.current
	var center := global_position + Vector3.UP * height * 0.4
	var push := Enemy.kill_push(hit)
	# Rammed at speed, the pieces fly on ahead of the tank like it hit them at 80 km/h. What leaves
	# rubble sheds only some of itself; everything else goes entirely to pieces.
	var rammed := hit != null and hit.kind == Hit.Kind.RAM
	if vehicle and _rammed(hit):
		_run_over(world, push)
		return
	if vent:
		_burst_vent(world, hit)
		return
	if flattens:
		_flatten(world)
		return
	var remains := rubble_mesh != null and not overkilled
	world.fx.shatter(visual_bounds(), debris, push * (2.0 if rammed else 1.0), 0.35 if remains else 1.0)
	world.fx.dust(global_position, int(clampf(footprint * 3.0, 3, 14)), footprint, Palette.MIST)
	# Whatever breaks catches fire and smokes, a big building for longer and thicker.
	world.fx.smoke_column(center, footprint * 0.8, [Palette.ASH, Palette.STONE, Palette.DUSK])
	world.fx.burn(global_position, 2.0 + footprint * 1.5, clampf(footprint * 0.45, 0.4, 2.0))
	Sfx.play("rubble" if footprint > 1.5 else "wood", global_position)
	if footprint > 2.5:
		world.shake(0.25, global_position)
	for piece in supports:
		if not is_instance_valid(piece) or piece.dead:
			continue
		if _rammed(hit):
			# Rammed, the whole stack goes up at once instead of waiting to fall.
			piece.take_hit(hit)
		else:
			# Knocked out from one side, what it held falls away from the blow.
			piece.topple(hit != null and hit.by_player(), piece.global_position - push * 5.0 if push != Vector3.ZERO else global_position)
	if sluice:
		_release_surge(hit)
	if explosive:
		# Wrecks the player sets off only hurt enemies; stray enemy fire makes them dangerous to everyone.
		var by_player := hit != null and hit.by_player()
		# Chain blasts carry this prop as their source so kills count as collateral.
		var chain := Hit.new()
		chain.source = self if by_player else null
		world.blast(center, blast_size, 45.0 + blast_size * 4.0, Team.PLAYER if by_player else Team.NEUTRAL, chain, self, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.INK], push * 0.5)
		world.fx.smoke_column(center, blast_size * 0.6, [Palette.DUSK, Palette.INK, Palette.SLATE])
		world.fx.burn(global_position, 4.0 + blast_size, 0.8)
	if score > 0:
		world.award(score, global_position, false)
	if hit != null and hit.by_player():
		world.style_event("DEMOLITION", 8.0 + footprint * 6.0)
		if rammed and footprint > 2.5:
			# Bulldozed buildings go up in a cloud of plaster.
			world.fx.dust(global_position + Vector3.UP, 16, footprint * 1.2, Palette.MIST)
	if fungal:
		world.fx.spores(center, int(5 + footprint * 3), footprint)
		world.fx.debris(center, int(3 + footprint * 2), [Fx.Debris.FLESH, Fx.Debris.SPORE], 7.0, 0.3)
		Sfx.play("squelch", global_position, 0.0, randf_range(0.7, 1.0))
	elif burnable and hit and hit.incendiary:
		world.fx.spores(center, 10, footprint)
	if remains:
		# Leave a rubble pile behind instead of vanishing.
		var rubble := MeshInstance3D.new()
		rubble.mesh = rubble_mesh
		rubble.transform = global_transform
		world.props.add_child(rubble)
