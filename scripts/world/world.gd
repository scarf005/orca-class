class_name World
extends Node3D
## Root of a running stage: lighting, terrain, registries of everything that fights, and the shared
## combat helpers (blasts, projectile spawning, score, shake and hitstop).

signal scored(points: int, position: Vector3, combo: int)
signal boss_changed(boss: Entity) ## Null when the boss bar should hide.
signal killed(victim: Entity, hit: Hit)
signal stage_cleared
signal game_over
signal intercepted(position: Vector3) ## The laser CIWS burned something out of the air.
signal hit_confirmed(killed: bool) ## Player damage accepted by an enemy, including boss modules.

const NANITE_LIFE := Vector2(0.5, 1.0)
const NANITE_HP := 0.5
const CHAIN_GAP := 0.5 ## Kills closer together than this keep a chain going.
## Chain size -> [trick, style]. Each is awarded once as the chain grows through it.
const CHAIN_TRICKS := {3: ["MULTIKILL", 90.0], 6: ["MASSACRE", 160.0], 10: ["ANNIHILATION", 260.0]}

static var current: World

var terrain := Terrain.new()
var props := PropField.new()
var fx := Fx.new()
var enemy_marks := TrackMarks.new(TrackMarks.SHARED_COUNT) ## Tread and wheel prints of every enemy ground vehicle.
var camera := ChaseCamera.new()
var sun := DirectionalLight3D.new()
var environment := Environment.new()
var rail := Rail.new()
var stats := RunStats.new()
var player: Tank
var director: Director
var view: DitherView ## Set by whoever displays the world; used for screen flashes.

var enemies: Array[Entity] = []
var projectiles: Array[Projectile] = []
var pickups: Array[Pickup] = []
var boss: Entity

var difficulty_override := -1 ## Duel-only; the normal run's selected difficulty stays untouched.

var _nanites: Array[Dictionary] = []
var _hitstop := 0.0
var game_speed := 1.0:
	set(value):
		game_speed = value
		if current == self:
			Engine.time_scale = game_speed * (0.05 if _hitstop > 0.0 else 1.0)
var _chain := 0
var _last_kill := -INF
var _enemy_container := Node3D.new()
var _projectile_container := Node3D.new()


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
		Engine.time_scale = 1.0


func _ready() -> void:
	killed.connect(_release_nanites)
	_setup_environment()
	add_child(terrain)
	props.name = "Props"
	add_child(props)
	add_child(fx)
	add_child(enemy_marks)
	_enemy_container.name = "Enemies"
	add_child(_enemy_container)
	_projectile_container.name = "Projectiles"
	add_child(_projectile_container)
	add_child(camera)
	add_child(_drop_shadows)
	terrain.stream(rail.d, true)


## Starts a playable stage with the player, the director and scenery.
func start_stage(checkpoint := "") -> void:
	difficulty_override = GameTuning.duel_difficulty if checkpoint == "duel" else -1
	game_speed = GameTuning.duel_speed if checkpoint == "duel" else 1.0
	director = Director.new()
	director.name = "Director"
	add_child(director)
	player = Tank.new()
	player.name = "Player"
	add_child(player)
	director.begin(checkpoint)
	terrain.stream(rail.d, true)


func _process(delta: float) -> void:
	if _hitstop > 0.0:
		_hitstop -= delta / maxf(Engine.time_scale, 0.001)
		if _hitstop <= 0.0:
			Engine.time_scale = game_speed
	var step := minf(delta, 1.0 / 30.0)
	for projectile in projectiles.duplicate():
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			projectile.step(step)
	terrain.stream(rail.d)
	stats.tick(step)
	_update_nanites(step)
	_update_drop_shadows()


## Drop shadows: a dithered disc on the ground under the tank, every enemy and every shot, sized by
## the body and fading as it rises, so heights and paths read at a glance (tuned live in the duel mode).
static var DROP_SHADOW := 0.85 ## Density right under a body on the ground (0 turns them off).
const DROP_SHADOW_FADE := 30.0 ## Metres of height at which a shadow is gone.
const DROP_SHADOW_MAX := 400
var _drop_shadows := _make_drop_shadows()


func _make_drop_shadows() -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.orientation = PlaneMesh.FACE_Y
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/drop_shadow.gdshader")
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = DROP_SHADOW_MAX
	multimesh.visible_instance_count = 0
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.top_level = true
	return instance


func _update_drop_shadows() -> void:
	var multimesh := _drop_shadows.multimesh
	var count := 0
	if DROP_SHADOW > 0.0:
		var bodies: Array = []
		bodies.append_array(enemies)
		bodies.append_array(projectiles)
		if player and not player.dead:
			bodies.append(player)
		for body: Node3D in bodies:
			if count >= DROP_SHADOW_MAX:
				break
			if not is_instance_valid(body) or body.is_queued_for_deletion() or (body is Enemy and (body as Enemy).hidden):
				continue
			var at := body.global_position
			var ground := Course.height_at(at)
			var height := at.y - ground
			var fade := 1.0 - clampf(height / DROP_SHADOW_FADE, 0.0, 1.0)
			if fade <= 0.0:
				continue
			var size := (body as Entity).radius if body is Entity else 0.5
			size = maxf(size, 0.4) * (1.0 + clampf(height / DROP_SHADOW_FADE, 0.0, 1.0) * 0.6)
			multimesh.set_instance_transform(count, Transform3D(Basis.from_scale(Vector3(size, 1.0, size)), Vector3(at.x, ground + 0.12, at.z)))
			multimesh.set_instance_custom_data(count, Color(DROP_SHADOW * fade, 0, 0, 0))
			count += 1
	multimesh.visible_instance_count = count


## Melee salvage follows the moving claw mount; a missing tail receives it at the hull's rear.
func _release_nanites(victim: Entity, hit: Hit) -> void:
	if not victim is Enemy or not hit or not hit.salvage or not hit.source is Tank:
		return
	var total := clampf((victim as Enemy).death_radius * 4.0, 2.0, 15.0)
	var count := ceili(total / NANITE_HP)
	for i in count:
		var at := victim.hit_center()
		_nanites.append({"start": at, "at": at, "bend": Vector3(randf_range(-2, 2), randf_range(1, 3), randf_range(-2, 2)), "time": 0.0, "life": randf_range(NANITE_LIFE.x, NANITE_LIFE.y), "hp": total / count})


func _update_nanites(delta: float) -> void:
	if not is_instance_valid(player) or player.dead:
		_nanites.clear()
		return
	var target := player.global_position + player.global_basis.z * 2.5 + Vector3.UP
	if not player.tail.destroyed and is_instance_valid(player.tail.mount):
		target = player.tail.mount.global_position
	for i in range(_nanites.size() - 1, -1, -1):
		var particle := _nanites[i]
		particle.time += delta
		var progress := clampf(particle.time / particle.life, 0.0, 1.0)
		var at: Vector3 = particle.start.lerp(target, progress * progress) + particle.bend * sin(progress * PI)
		fx.spawn(Fx.Kind.GLOW, at, Vector3.ZERO, 0.07, 0.24, Palette.NANITE, {"end_size": 0.08})
		fx.beam(particle.at, at, Palette.NANITE, 0.08, 0.06)
		particle.at = at
		if progress >= 1.0:
			if player._respawn <= 0.0:
				var before := player.hp
				player.hp = minf(player.max_hp, player.hp + particle.hp)
				stats.melee_healing += player.hp - before
			_nanites.remove_at(i)


func register(entity: Entity) -> void:
	if entity is Prop:
		props.add(entity)
	elif entity.team == Entity.Team.ENEMY and entity not in enemies:
		enemies.append(entity)


func unregister(entity: Entity) -> void:
	if entity is Prop:
		props.remove(entity)
	else:
		enemies.erase(entity)


func add_enemy(enemy: Entity) -> Entity:
	_enemy_container.add_child(enemy)
	return enemy


func targets_for(team: Entity.Team) -> Array[Entity]:
	if team == Entity.Team.PLAYER:
		return enemies
	var result: Array[Entity] = []
	if team == Entity.Team.NEUTRAL:
		result.append_array(enemies)
	if player and not player.dead:
		result.append(player)
	return result


## shape -> [look, caliber width, tracer length, halo scale]. Rounds have a pointed nose, a round
## body and a tracer tail tapering away behind them; darts are finned rods; orbs are round;
## missiles have a lit body and a glowing exhaust. Every shape gets an ink outline and a glow halo.
const PROJECTILE_SHAPES := {
	"bullet": ["streak", 0.26, 5.0, 2.2],
	"fragment": ["streak", 0.16, 1.8, 2.0],
	"pellet": ["orb", 0.18, 0.0, 1.8],
	"shell": ["streak", 0.55, 7.0, 2.4],
	"dart": ["streak", 0.22, 10.0, 2.4],
	"orb": ["streak", 0.22, 6.5, 2.0], ## Enemy machine-gun rounds: as lean as the coax's tracers.
	"mortar": ["orb", 0.5, 0.0, 1.5],
	"fire": ["orb", 0.55, 0.0, 2.0],
	"rocket": ["missile", 0.2, 1.1, 2.0],
	"atgm": ["missile", 0.24, 1.3, 2.2],
	"micro": ["missile", 0.2, 1.1, 1.8],
	"bomb": ["missile", 0.3, 0.9, 1.8],
}
const HOSTILE_CORE := 1.8 ## Enemy shot core size relative to a player round's.
static var _shape_meshes := {}
static var _halo_material := _make_halo_material()
static var _core_material := _make_core_material()
static var _ink_material := _make_ink_material()
const INK_SHAPES := ["shell", "dart"] ## The tank's own rounds, whose rim the final pass does not draw.


## Shots are drawn at their true saturated color: vertex colors read as sRGB, unlit. The scene's
## default material treats them as linear, which washes everything else toward pastel on purpose.
static func _make_core_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	return material


## An inverted hull: only the back faces of a slightly fatter copy show, as a dark rim around the round.
static func _make_ink_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.albedo_color = Palette.INK
	return material


static func _make_halo_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/dither_fade.gdshader")
	material.set_shader_parameter("unshaded", true)
	material.set_shader_parameter("alpha_scale", 0.45)
	return material


static func _projectile_meshes(shape: String, color: Color, hostile := false) -> Array[Mesh]:
	var key := "%s_%s_%s" % [shape, color.to_html(), hostile]
	if _shape_meshes.has(key):
		return _shape_meshes[key]
	var spec: Array = PROJECTILE_SHAPES[shape]
	var width: float = spec[1]
	var length: float = spec[2]
	var halo_scale: float = spec[3]
	# A white-hot head, a saturated tail tapering to nothing, and a dithered glow around it all.
	# Enemy shots read by form, not rim: a much bigger white-hot core inside the hot halo.
	var hot := color.lerp(Palette.WHITE, 0.92 if hostile else 0.55)
	var head := HOSTILE_CORE if hostile else 1.0
	var core := LowPoly.new()
	var halo := LowPoly.new()
	core.glow = true
	halo.glow = true
	var forward := Basis.from_euler(Vector3(0, PI, 0))
	match spec[0]:
		"streak":
			# A tracer: a short pointed head along -Z (the flight direction) and a long tapered tail.
			var r := width * 0.5
			core.tube(Transform3D(forward, Vector3.ZERO), r * head, width * 0.9 * head, 6, hot, 0.0)
			core.tube(Transform3D(Basis(), Vector3.ZERO), r * head, width * 0.8 * head, 6, hot, r * 0.8 * head)
			core.tube(Transform3D(Basis(), Vector3(0, 0, width * 0.8)), r * 0.8, length, 6, color, 0.0)
			halo.tube(Transform3D(forward, Vector3.ZERO), r * halo_scale, width * 1.2, 6, color, 0.0)
			halo.tube(Transform3D(Basis(), Vector3.ZERO), r * halo_scale, length * 1.1, 6, color, 0.0)
		"orb":
			core.blob(Transform3D(), width, color, 1, 0.1, 5)
			core.blob(Transform3D(), width * 0.55 * head, hot, 0, 0.1, 5)
			halo.blob(Transform3D(), width * halo_scale, color, 0, 0.2, 6)
		"missile":
			# Round body with a pointed nose, a colored band and four tail fins; glowing motor behind.
			var r := width * 0.5
			core.glow = false
			core.tube(Transform3D(forward, Vector3.ZERO), r, width * 1.6, 8, Palette.STONE, 0.0)
			core.tube(Transform3D(Basis(), Vector3.ZERO), r, length, 8, Palette.SLATE)
			core.tube(Transform3D(Basis(), Vector3(0, 0, length * 0.25)), r * 1.05, width * 0.5, 8, color)
			for k in 4:
				core.box(Transform3D(Basis(Vector3.BACK, k * PI * 0.5 + PI * 0.25), Vector3(0, 0, length * 0.85)), Vector3(width * 2.4, 0.03, width * 1.4), Palette.DUSK)
			core.glow = true
			core.tube(Transform3D(Basis(), Vector3(0, 0, length)), r * 0.8 * head, width * 1.5 * head, 6, hot, 0.0)
			halo.blob(Transform3D(Basis(), Vector3(0, 0, length + 0.3)), width * halo_scale, color, 0, 0.2, 7)
	var meshes: Array[Mesh] = [core.mesh(), halo.mesh()]
	if not hostile and shape in INK_SHAPES:
		# The tank's rounds have no rim from the final pass, so they carry an ink outline of their own.
		var ink := LowPoly.new()
		var r := width * 0.5 + 0.09
		ink.tube(Transform3D(forward, Vector3.ZERO), r, width * 0.9 + 0.12, 6, Palette.INK, 0.0)
		ink.tube(Transform3D(Basis(), Vector3.ZERO), r, length + 0.15, 6, Palette.INK, 0.0)
		meshes.append(ink.mesh())
	_shape_meshes[key] = meshes
	return meshes


## Mesh instances for a projectile look: core and glow halo. `hostile` shots get a bigger white
## core and the orange shot rim; only enemies wear the red one.
static func projectile_visual(shape: String, color: Color, hostile := false) -> Array[MeshInstance3D]:
	var meshes := _projectile_meshes(shape, color, hostile)
	var result: Array[MeshInstance3D] = []
	for i in meshes.size():
		var mesh := MeshInstance3D.new()
		mesh.mesh = meshes[i]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.layers |= ActorLayer.LAYER | (ActorLayer.HOSTILE_SHOT if hostile else 0)
		mesh.material_override = _halo_material.duplicate() if i == 1 and hostile else [_core_material, _halo_material, _ink_material][i]
		result.append(mesh)
	return result


func spawn_projectile(team: Entity.Team, position: Vector3, velocity: Vector3, shape: String, color := Color(0, 0, 0, 0)) -> Projectile:
	var projectile := Projectile.new()
	projectile.team = team
	projectile.shape = shape
	projectile.velocity = velocity
	projectile.hit.source = player if team == Entity.Team.PLAYER else null
	projectile.color = team_color(team, shape, color)
	var hostile := team != Entity.Team.PLAYER
	var visuals := projectile_visual(shape, projectile.color, hostile)
	for mesh in visuals:
		projectile.add_child(mesh)
	if hostile:
		projectile.core = visuals[0]
		projectile.halo = visuals[1]
	_projectile_container.add_child(projectile)
	projectile.global_position = position
	if velocity.length_squared() > 0.01:
		projectile.look_at(position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
	return projectile


## Dresses a shot that changed sides in the tank's colors.
func reskin_projectile(projectile: Projectile) -> void:
	for child in projectile.get_children():
		if child is MeshInstance3D:
			child.queue_free()
	projectile.color = team_color(Entity.Team.PLAYER, projectile.shape, Color(0, 0, 0, 0))
	for mesh in projectile_visual(projectile.shape, projectile.color):
		projectile.add_child(mesh)
	projectile.halo = null
	projectile.core = null


## Every enemy shot is HOSTILE; the tank's own shots are warm (flames keep their fire colors), so
## whose fire is whose never depends on the weapon.
static func team_color(team: Entity.Team, shape: String, requested: Color) -> Color:
	if team != Entity.Team.PLAYER:
		return Palette.HOSTILE
	if shape in ["fire", "atgm", "micro"] and requested.a > 0.0:
		return requested
	return Palette.BUTTER if shape in ["shell", "dart", "pellet"] else Palette.FRIENDLY


## Area damage with linear falloff to 30% at the edge. Hits entities of the opposing team and props.
## `push` is the direction the blast was delivered in (a shell's flight); zero for a plain burst.
## How far past a blast's damage radius its shockwave throws wrecks; the ring it draws is that wide
## (tuned live in the duel mode).
static var SHOCKWAVE_SCALE := 1.5


func blast(point: Vector3, radius: float, damage: float, team: Entity.Team, template: Hit = null, exclude: Entity = null, colors: Array = [], push := Vector3.ZERO) -> void:
	fx.explosion(point, radius * 0.8, colors if not colors.is_empty() else [Palette.BUTTER, Palette.AMBER, Palette.HOT, Palette.CORAL], push, radius * SHOCKWAVE_SCALE)
	shake(clampf(radius * 0.08, 0.05, 0.6), point)
	Sfx.play("blast_small" if radius < 3.5 else "blast", point, 0.0, randf_range(0.9, 1.15))
	var hit := template.copy() if template else Hit.new()
	hit.kind = Hit.Kind.BLAST
	hit.salvage = false
	hit.position = point
	var victims: Array = targets_for(team).duplicate()
	victims.append_array(props.in_radius(point, radius))
	for entity: Entity in victims:
		if entity == exclude or entity.dead:
			continue
		var distance := entity.hit_center().distance_to(point) - entity.radius
		if entity is Prop:
			distance = Vector2(entity.global_position.x - point.x, entity.global_position.z - point.z).length() - (entity as Prop).footprint
		if distance > radius:
			continue
		var falloff := lerpf(1.0, 0.3, clampf(distance / radius, 0.0, 1.0))
		var applied := hit.copy()
		applied.damage = damage * falloff
		applied.direction = ((entity.hit_center() - point).normalized() + push).normalized()
		entity.take_hit(applied)
	Wreck.blast_push(point, radius, damage, push)


## Spawns a pickup, swapped for something the tank can use if it would be wasted.
func spawn_pickup(id: String, position: Vector3) -> Pickup:
	var pickup := Pickup.new()
	pickup.id = player.useful_pickup(id) if player else id
	add_child(pickup)
	pickup.global_position = position
	return pickup


## Adds score for a kill or bonus; kills also feed the combo.
func award(points: int, position: Vector3, is_kill := true) -> void:
	var gained := stats.add_score(points, is_kill)
	scored.emit(gained, position, stats.combo)


## Style for a trick multiplies score, never hull health.
func style_event(trick: String, points: float) -> void:
	stats.add_style(trick, points)


## Style for a kill, named after how it died (a full-charge main-gun kill is CHARGED whatever it hit). Quick kills chain, and a chain that grows through 3,
## 6 and 10 kills earns a bigger trick at each step.
func kill_style(hit: Hit, victim: Entity) -> void:
	if hit == null or not hit.by_player():
		return
	var trick := "DIRECT"
	var points := 35.0
	match hit.kind:
		Hit.Kind.RAM:
			trick = "CRUSH"
			points = 90.0
		Hit.Kind.TAIL:
			trick = "LASH"
			points = 80.0
		Hit.Kind.THROWN:
			trick = "THROWN"
			points = 90.0
		Hit.Kind.FIRE:
			trick = "BURNED"
			points = 50.0
		Hit.Kind.FRAGMENT:
			trick = "AIRBURST"
			points = 50.0
		Hit.Kind.LASER:
			trick = "ZAPPED"
			points = 10.0
		Hit.Kind.BULLET:
			trick = "COAX"
			points = 20.0
		Hit.Kind.BLAST:
			trick = "COLLATERAL" if hit.is_collateral() else "SPLASH"
			points = 70.0 if hit.is_collateral() else 40.0
		Hit.Kind.SHELL:
			if hit.power >= 1.0:
				trick = "CHARGED"
				points = 80.0
			elif victim.flying:
				trick = "SKYSHOT"
				points = 60.0
	if hit.incendiary and hit.kind != Hit.Kind.FIRE:
		trick = "BURNED"
	if hit.weapon == "reflect":
		trick = "REFLECT"
		points = 70.0
	style_event(trick, points)
	_chain = _chain + 1 if stats.time - _last_kill < CHAIN_GAP else 1
	_last_kill = stats.time
	if CHAIN_TRICKS.has(_chain):
		var step: Array = CHAIN_TRICKS[_chain]
		style_event(step[0], step[1])


func shake(amount: float, source := Vector3.INF) -> void:
	var falloff := 1.0
	if source != Vector3.INF:
		falloff = clampf(1.0 - camera.global_position.distance_to(source) / 120.0, 0.15, 1.0)
	camera.add_trauma(amount * falloff * Game.settings.screen_shake)


## Freezes time briefly so heavy hits land.
## `delta` as real time while a hitstop slows the world: debris and wrecks burst out at once
## instead of hanging frozen for the stop.
func unfrozen(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.001) if _hitstop > 0.0 else delta


func hitstop(duration: float) -> void:
	if duration <= _hitstop:
		return
	_hitstop = duration
	Engine.time_scale = game_speed * 0.05


func screen_flash(color: Color, amount: float) -> void:
	if view:
		view.flash(color, amount)


func _setup_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("8f9fe0")
	sky_material.sky_horizon_color = Color("f7d6c4")
	sky_material.ground_horizon_color = Color("f7d6c4")
	sky_material.ground_bottom_color = Color("c3a6e8")
	sky_material.sun_angle_max = 8.0
	sky_material.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8a8d8")
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color("f3d9d0")
	environment.fog_depth_begin = 90.0
	environment.fog_depth_end = 420.0
	environment.fog_depth_curve = 1.4
	environment.fog_sky_affect = 0.0
	# Fire, flashes and tracers bloom into the scene around them.
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_strength = 1.1
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 0.85
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	sun.rotation_degrees = Vector3(-32.0, 125.0, 0.0)
	sun.light_color = Color("fff0dc")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.85
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
