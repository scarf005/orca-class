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
var hard := false ## A solid building: the tank breaks it but loses most of its speed doing so.
var debris: Array = [Fx.Debris.WOOD, Fx.Debris.CONCRETE] ## Fx.Debris materials it breaks into.
var burnable := false
var explosive := false
var blast_size := 4.5 ## Radius of the explosion when an explosive prop goes up.
var fungal := false ## Bursts into spores and splatter when destroyed.
var flattens := false ## Destroyed, it squelches and leaves a dark flattened stain of itself (ground veins).
var supports: Array[Prop] = [] ## Pieces resting on this one; they topple when it breaks.
var falls := false
var vehicle := false ## Run over, it is squashed, knocked flying or burst apart, but never blows up.
var _topple := -1.0
var _topple_axis := Vector3.RIGHT
var _topple_by_player := false
var _topple_start := Transform3D.IDENTITY
var rubble_mesh: Mesh
var score := 0


const DRAW_DISTANCE := 150.0 ## Fog hides small props well before this.

enum CollapseStyle { NONE, TORN, SINK, RAM, TOPPLE, BURN }
const BUILDINGS := ["house", "infested_house", "hall", "greenhouse", "church", "church_nave", "church_tower", "church_spire", "school", "school_wing", "school_center", "gas_station", "bus_stop", "pavilion", "overpass_pier", "overpass_deck", "pier", "gate"]
## Tuned live in the duel mode, hence static vars: at 105 km/h a slow fall lands behind the tank.
static var TOPPLE_TIME := 0.45 ## Seconds a tall thing takes to fall flat.
static var COLLAPSE_TIME := 0.45 ## Seconds a building takes to sink or fold.
static var KNOCK_SPEED := 10.0 ## m/s a tall thing is knocked flying at by a plain blow; harder ones throw it faster.
const TALL := ["church_tower", "church_spire", "overpass_pier", "fungal_spire", "spore_tower", "flagpole"]


## The killing blow chooses the motion, not a random roll. Fire wins over its shell delivery;
## tall structures stay rigid except when a main-gun round tears them apart.
func collapse_style(hit: Hit) -> CollapseStyle:
	if vehicle or flattens or not (kind in BUILDINGS or kind in TALL or falls):
		return CollapseStyle.NONE
	if hit != null:
		if hit.kind == Hit.Kind.FIRE or hit.incendiary:
			return CollapseStyle.BURN
		if hit.caliber >= 100 and hit.kind in [Hit.Kind.SHELL, Hit.Kind.BLAST]:
			return CollapseStyle.TORN
	if falls or kind in TALL:
		return CollapseStyle.TOPPLE
	# Everything else bursts into its roof and walls too: rammed, they fly on along the tank's
	# travel; shot by lighter guns, they fall apart outward, slower.
	return CollapseStyle.TORN


## Detached visuals outlive the dead prop: scoring, loot and collateral still happen once,
## immediately, while the collapse carries on in real time even through hitstop.
class Collapse extends Node3D:
	var style: CollapseStyle
	var age := 0.0
	var puff := 0.0
	var height := 1.0
	var width := 1.0
	var push := Vector3.FORWARD
	var axis := Vector3.RIGHT
	var start := Transform3D.IDENTITY
	var pieces: Array[MeshInstance3D] = []
	var rubble: Mesh
	var materials: Array
	var bounds: AABB

	func _process(delta: float) -> void:
		var world := World.current
		delta = world.unfrozen(delta)
		age += delta
		var burning := style == CollapseStyle.BURN and age < 2.8
		var time := maxf(age - (2.8 if style == CollapseStyle.BURN else 0.0), 0.0)
		var duration := Prop.COLLAPSE_TIME * (0.55 if style == CollapseStyle.RAM else 1.0)
		var k := clampf(time / duration, 0.0, 1.0)
		global_transform = start
		match style:
			CollapseStyle.RAM:
				global_basis = Basis(axis, k * PI * 0.42) * start.basis.scaled_local(Vector3(1.0, lerpf(1.0, 0.12, k), 1.0))
				global_position += push * width * k
			_:
				var sink := smoothstep(0.15, 1.0, k)
				global_position += Vector3(sin(time * 65.0) * 0.12 * (1.0 - k), -height * sink, cos(time * 53.0) * 0.09 * (1.0 - k))
				for piece in pieces:
					var roof := piece.mesh.get_aabb().get_center().y > height * 0.6
					piece.position.y = -height * 0.25 * smoothstep(0.0, 0.35, k) if roof else 0.0
		puff -= delta
		if puff <= 0.0:
			puff = 0.1
			for i in 4:
				# At the outside faces, not inside the solid walls where flames would be hidden.
				var local := bounds.get_center()
				local.y = 0.3
				local.x += bounds.size.x * (0.52 if i == 0 else -0.52 if i == 1 else 0.0)
				local.z += bounds.size.z * (0.52 if i == 2 else -0.52 if i == 3 else 0.0)
				var at := start * local
				world.fx.smoke_puff(at + Vector3.UP * (height * 0.35 if i % 2 else 0.0), clampf(width * 0.5, 0.8, 2.5))
				if burning:
					world.fx.tongue(at, height * 0.7, float(i) / 4.0)
			if burning:
				world.fx.light_flash(start.origin + Vector3.UP * height * 0.5, 5.0, Palette.AMBER, width * 3.0)
		if k < 1.0:
			return
		var ground := Vector3(global_position.x, Course.height_at(global_position), global_position.z)
		world.fx.shockwave(ground, width * 2.5, Palette.MIST, 0.45)
		world.fx.dust(ground, 12, width, Palette.MIST)
		var impact := global_transform * bounds if style == CollapseStyle.RAM else AABB(ground - Vector3(width, 0, width) * 0.5, Vector3(width, 1.0, width))
		world.fx.shatter(impact, materials, push if style == CollapseStyle.RAM else Vector3.ZERO, 0.35)
		world.fx.smoke_column(ground, width)
		world.shake(0.25, ground)
		Sfx.play("rubble", ground)
		if rubble != null:
			var heap := MeshInstance3D.new()
			heap.mesh = rubble
			heap.transform = Transform3D(start.basis, ground)
			world.props.add_child(heap)
		else:
			# Even structures without a bespoke rubble mesh leave their own flattened outline.
			for piece in pieces:
				piece.reparent(world.props, true)
				piece.transform = Transform3D(start.basis.scaled_local(Vector3(1.0, 0.08, 1.0)), ground)
		queue_free()


func _collapse(world: World, hit: Hit, style: CollapseStyle) -> void:
	var model := get_node("Mesh") as MeshInstance3D
	var push := Enemy.kill_push(hit)
	var direction := Vector3(push.x, 0, push.z).normalized()
	if direction == Vector3.ZERO:
		direction = Vector3.FORWARD
	if style == CollapseStyle.TOPPLE:
		# Snapped at the foot and knocked flying whole, end over end along the blow.
		# A low, short flight: it clears the tank and lands within a few lengths, not across the valley.
		var speed := KNOCK_SPEED * clampf(maxf(push.length(), hit.speed / 30.0 if _rammed(hit) else 0.0), 1.0, 2.0)
		var wreck := Wreck.launch(model, hit_center(), 1.0, hit != null and hit.by_player(), Vector3.ZERO, false)
		wreck.velocity = direction * speed + Vector3.UP * (3.0 + speed * 0.2)
		wreck.spin = Vector3.UP.cross(direction) * (5.0 + speed * 0.2) / sqrt(maxf(height * 0.3, 1.0))
		world.fx.shatter(AABB(global_position - Vector3(footprint, 0, footprint), Vector3(footprint * 2.0, 1.0, footprint * 2.0)), debris, push, 0.35)
		felled.emit(self)
		return
	var chunks := PropKit.collapse_pieces(model.mesh)
	var pieces: Array[MeshInstance3D] = []
	for chunk in chunks:
		var piece := MeshInstance3D.new()
		piece.mesh = chunk
		piece.transform = model.global_transform
		world.add_child(piece)
		pieces.append(piece)
	model.hide()
	if style == CollapseStyle.TORN:
		var biggest := 0
		for i in pieces.size():
			if pieces[i].mesh.get_aabb().get_volume() > pieces[biggest].mesh.get_aabb().get_volume():
				biggest = i
		var rammed := hit != null and hit.kind == Hit.Kind.RAM
		var shell := hit != null and hit.caliber >= 100
		var energy := clampf(pow(hit.speed / Enemy.KILL_SHELL_SPEED, 2.0), 0.5, Enemy.KILL_THROW_MAX) if shell and hit.speed > 0.0 else (1.4 if rammed else 0.6)
		for i in pieces.size():
			var piece := pieces[i]
			var at := piece.global_transform * piece.mesh.get_aabb().get_center()
			var out := at - hit_center()
			out.y = maxf(out.y, 0.0) + 2.0
			# A ram flings the walls on ahead of the hull; anything else bursts them outward.
			out = (out.normalized() + direction * (1.6 if rammed else 0.35) + Vector3.UP * 0.4).normalized()
			var size := maxf(piece.mesh.get_aabb().size.length() * 0.25, 0.3)
			Wreck.launch(piece, at, size, hit.by_player(), out * (10.0 + energy * 7.0) * sqrt(maxf(size, 1.0)), i == biggest)
		world.fx.shatter(visual_bounds(), debris, push, 0.25)
		return
	var motion := Collapse.new()
	motion.style = style
	motion.height = height
	motion.width = footprint
	motion.push = direction
	motion.axis = Vector3.UP.cross(direction)
	motion.rubble = rubble_mesh
	motion.materials = debris
	motion.bounds = model.mesh.get_aabb()
	world.props.add_child(motion)
	motion.global_transform = global_transform
	motion.start = motion.global_transform
	motion.pieces = pieces
	for piece in pieces:
		piece.reparent(motion, true)
	if style == CollapseStyle.RAM:
		world.fx.debris(hit_center(), 12, debris, 12.0 + minf(hit.speed, 30.0), 0.5, direction * 2.0)


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
	_topple_start = global_transform
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	_topple_axis = Vector3.UP.cross(away.normalized())
	always_tick = true
	set_process(true)
	felled.emit(self)


func is_falling() -> bool:
	return _topple >= 0.0


## Driven into by the tank itself, as opposed to crashing down or being shot.
static func _rammed(hit: Hit) -> bool:
	return hit != null and hit.kind == Hit.Kind.RAM and hit.source is Tank


func tick(delta: float) -> void:
	if _topple < 0.0:
		return
	delta = World.current.unfrozen(delta)
	_topple += delta
	var k := minf(_topple / (TOPPLE_TIME * (0.6 if falls else 1.0)), 1.0)
	global_basis = Basis(_topple_axis, k * k * PI * 0.5) * _topple_start.basis
	global_position.y = lerpf(_topple_start.origin.y, Course.height_at(_topple_start.origin), k)
	if k >= 1.0:
		var crash := Hit.make(Hit.Kind.RAM, 99999.0, global_position)
		if _topple_by_player:
			crash.source = World.current.player
		World.current.fx.shockwave(global_position, footprint * 2.5, Palette.MIST, 0.45)
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
	world.style_event("CRUSH", 6.0)


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
	if flattens:
		_flatten(world)
		return
	var style := CollapseStyle.NONE if is_falling() else collapse_style(hit)
	var remains := rubble_mesh != null and not overkilled and style == CollapseStyle.NONE
	if style != CollapseStyle.NONE:
		_collapse(world, hit, style)
	else:
		world.fx.shatter(visual_bounds(), debris, push * (2.0 if rammed else 1.0), 0.35 if remains else 1.0)
	world.fx.dust(global_position, int(clampf(footprint * 3.0, 3, 14)), footprint, Palette.MIST)
	# Whatever breaks catches fire and smokes, a big building for longer and thicker.
	if style in [CollapseStyle.NONE, CollapseStyle.TORN]:
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
		world.style_event("DEMOLITION", 4.0 + footprint * 3.0)
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
