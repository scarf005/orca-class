class_name Prop
extends Entity
## A destructible piece of scenery with a vertical-cylinder footprint.
## Solid props block the tank; crushable ones break when the tank drives into them.

var kind := ""
var footprint := 1.0
var height := 2.0
var solid := true
var crushable := false
var debris_colors: Array = [Palette.WOOD, Palette.CONCRETE]
var drop := "" ## Pickup id dropped when destroyed.
var burnable := false
var explosive := false
var blast_size := 4.5 ## Radius of the explosion when an explosive prop goes up.
var fungal := false ## Bursts into spores and splatter when destroyed.
var supports: Array[Prop] = [] ## Pieces resting on this one; they topple when it breaks.
var _topple := -1.0
var _topple_axis := Vector3.RIGHT
var _topple_by_player := false
var rubble_mesh: Mesh
var score := 0


const DRAW_DISTANCE := 150.0 ## Fog hides small props well before this.


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


func tick(delta: float) -> void:
	if _topple < 0.0:
		return
	_topple += delta
	var k := minf(_topple / 1.1, 1.0)
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


func damage_multiplier(hit: Hit) -> float:
	if hit.kind == Hit.Kind.BULLET and hit.caliber < 15:
		return 0.25
	if hit.kind == Hit.Kind.FIRE:
		return 3.0 if burnable else 0.3
	return 1.0


func on_death(hit: Hit) -> void:
	var world := World.current
	var center := global_position + Vector3.UP * height * 0.4
	world.fx.debris(center, int(clampf(footprint * height * 1.5, 4, 24)), debris_colors, 5.0 + footprint, 0.3 + footprint * 0.12)
	world.fx.dust(global_position, int(clampf(footprint * 3.0, 3, 14)), footprint, Palette.MIST)
	Sfx.play("rubble" if footprint > 1.5 else "wood", global_position)
	if footprint > 2.5:
		world.shake(0.25, global_position)
	if not drop.is_empty():
		world.spawn_pickup(drop, global_position + Vector3.UP)
	for piece in supports:
		if is_instance_valid(piece) and not piece.dead:
			piece.topple(hit != null and hit.by_player(), global_position)
	if explosive:
		# Wrecks the player sets off only hurt enemies; stray enemy fire makes them dangerous to everyone.
		var by_player := hit != null and hit.by_player()
		# Chain blasts carry this prop as their source so kills count as collateral.
		var chain := Hit.new()
		chain.source = self if by_player else null
		world.blast(center, blast_size, 45.0 + blast_size * 4.0, Team.PLAYER if by_player else Team.NEUTRAL, chain, self, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.INK])
		world.fx.smoke_column(center, blast_size * 0.6, [Palette.DUSK, Palette.INK, Palette.SLATE])
		world.fx.burn(global_position, 4.0 + blast_size, 0.8)
	if score > 0:
		world.award(score, global_position, false)
	if hit != null and hit.by_player():
		world.style_event("DEMOLITION", 8.0 + footprint * 6.0)
		if hit.kind == Hit.Kind.RAM and footprint > 2.5:
			# Bulldozed buildings go up in a cloud of plaster and roof tiles.
			world.fx.dust(global_position + Vector3.UP, 16, footprint * 1.2, Palette.MIST)
			world.fx.debris(center + Vector3.UP * height * 0.3, 18, debris_colors, 12.0, 0.5)
			world.hitstop(0.03)
	if fungal:
		world.fx.spores(center, int(5 + footprint * 3), footprint)
		world.fx.debris(center, int(3 + footprint * 2), [Palette.FUNGUS, Palette.MAUVE, Palette.BLUSH], 7.0, 0.3)
		Sfx.play("squelch", global_position, 0.0, randf_range(0.7, 1.0))
	elif burnable and hit and hit.incendiary:
		world.fx.spores(center, 10, footprint)
	if rubble_mesh:
		# Leave a rubble pile behind instead of vanishing.
		var rubble := MeshInstance3D.new()
		rubble.mesh = rubble_mesh
		rubble.transform = global_transform
		world.props.add_child(rubble)
