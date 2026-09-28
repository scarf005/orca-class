class_name World
extends Node3D
## Root of a running stage: lighting, terrain, registries of everything that fights, and the shared
## combat helpers (blasts, projectile spawning, score, shake and hitstop).

signal radio(line: StringName)
signal scored(points: int, position: Vector3, combo: int)
signal boss_changed(boss: Entity) ## Null when the boss bar should hide.
signal stage_cleared
signal game_over

static var current: World

var terrain := Terrain.new()
var props := PropField.new()
var fx := Fx.new()
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

var _hitstop := 0.0
var _enemy_container := Node3D.new()
var _projectile_container := Node3D.new()


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	Engine.time_scale = 1.0


func _ready() -> void:
	_setup_environment()
	add_child(terrain)
	props.name = "Props"
	add_child(props)
	add_child(fx)
	_enemy_container.name = "Enemies"
	add_child(_enemy_container)
	_projectile_container.name = "Projectiles"
	add_child(_projectile_container)
	add_child(camera)
	terrain.stream(rail.d, true)


## Starts a playable stage with the player, the director and scenery.
func start_stage(checkpoint := "") -> void:
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
			Engine.time_scale = 1.0
	var step := minf(delta, 1.0 / 30.0)
	for projectile in projectiles.duplicate():
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			projectile.step(step)
	terrain.stream(rail.d)
	stats.tick(step)


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


## shape -> [look, core width, length, halo scale]. Streaks trail behind the head; orbs are round;
## missiles have a lit body and a glowing exhaust. Every shape gets a dithered glow halo.
const PROJECTILE_SHAPES := {
	"bullet": ["streak", 0.3, 4.0, 3.0],
	"fragment": ["streak", 0.18, 1.4, 2.5],
	"pellet": ["streak", 0.24, 1.6, 2.5],
	"shell": ["streak", 0.55, 5.0, 2.8],
	"dart": ["streak", 0.28, 7.0, 3.0],
	"orb": ["orb", 0.55, 0.0, 2.2],
	"mortar": ["orb", 0.5, 0.0, 2.0],
	"fire": ["orb", 0.4, 0.0, 2.2],
	"rocket": ["missile", 0.2, 1.1, 2.6],
	"atgm": ["missile", 0.24, 1.3, 2.8],
	"bomb": ["missile", 0.3, 0.9, 2.0],
}
static var _shape_meshes := {}
static var _halo_material := _make_halo_material()


static func _make_halo_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/dither_fade.gdshader")
	material.set_shader_parameter("unshaded", true)
	material.set_shader_parameter("alpha_scale", 0.5)
	return material


static func _projectile_meshes(shape: String, color: Color) -> Array[Mesh]:
	var key := "%s_%s" % [shape, color.to_html()]
	if _shape_meshes.has(key):
		return _shape_meshes[key]
	var spec: Array = PROJECTILE_SHAPES[shape]
	var width: float = spec[1]
	var length: float = spec[2]
	var halo_scale: float = spec[3]
	var hot := color.lerp(Palette.WHITE, 0.65)
	var core := LowPoly.new()
	var halo := LowPoly.new()
	core.glow = true
	halo.glow = true
	match spec[0]:
		"streak":
			core.box(Transform3D(Basis(), Vector3(0, 0, length * 0.5)), Vector3(width, width, length), hot)
			halo.box(Transform3D(Basis(), Vector3(0, 0, length * 0.55)), Vector3(width * halo_scale, width * halo_scale, length * 1.1), color)
		"orb":
			core.blob(Transform3D(), width, hot, 0, 0.15, 5)
			halo.blob(Transform3D(), width * halo_scale, color, 0, 0.2, 6)
		"missile":
			core.glow = false
			core.box(Transform3D(Basis(), Vector3(0, 0, length * 0.5)), Vector3(width, width, length), Palette.SLATE)
			core.box(Transform3D(Basis(), Vector3(0, 0, length * 0.8)), Vector3(width * 2.2, 0.03, width * 1.2), Palette.STONE)
			core.glow = true
			core.box(Transform3D(Basis(), Vector3(0, 0, length + 0.15)), Vector3(width, width, 0.3) * 1.3, Palette.WHITE)
			halo.blob(Transform3D(Basis(), Vector3(0, 0, length + 0.3)), width * halo_scale, color, 0, 0.2, 7)
	var meshes: Array[Mesh] = [core.mesh(), halo.mesh()]
	_shape_meshes[key] = meshes
	return meshes


func spawn_projectile(team: Entity.Team, position: Vector3, velocity: Vector3, shape: String, color := Color(0, 0, 0, 0)) -> Projectile:
	var projectile := Projectile.new()
	projectile.team = team
	projectile.velocity = velocity
	projectile.hit.source = player if team == Entity.Team.PLAYER else null
	if color.a == 0.0:
		color = Palette.BUTTER if team == Entity.Team.PLAYER else Palette.RED
	var meshes := _projectile_meshes(shape, color)
	for i in meshes.size():
		var mesh := MeshInstance3D.new()
		mesh.mesh = meshes[i]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i == 1:
			mesh.material_override = _halo_material
		projectile.add_child(mesh)
	_projectile_container.add_child(projectile)
	projectile.global_position = position
	if velocity.length_squared() > 0.01:
		projectile.look_at(position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
	return projectile


## Area damage with linear falloff to 30% at the edge. Hits entities of the opposing team and props.
func blast(point: Vector3, radius: float, damage: float, team: Entity.Team, template: Hit = null, exclude: Entity = null, colors: Array = []) -> void:
	fx.explosion(point, radius * 0.6, colors if not colors.is_empty() else [Palette.WHITE, Palette.BUTTER, Palette.PEACH, Palette.CORAL])
	shake(clampf(radius * 0.08, 0.05, 0.6), point)
	Sfx.play("blast_small" if radius < 3.5 else "blast", point, 0.0, randf_range(0.9, 1.15))
	var hit := template.copy() if template else Hit.new()
	hit.kind = Hit.Kind.BLAST
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
		applied.direction = (entity.hit_center() - point).normalized()
		entity.take_hit(applied)


func spawn_pickup(id: String, position: Vector3) -> Pickup:
	var pickup := Pickup.new()
	pickup.id = id
	add_child(pickup)
	pickup.global_position = position
	return pickup


## Adds score for a kill or bonus; kills also feed the combo.
func award(points: int, position: Vector3, is_kill := true) -> void:
	var gained := stats.add_score(points, is_kill)
	scored.emit(gained, position, stats.combo)


func shake(amount: float, source := Vector3.INF) -> void:
	var falloff := 1.0
	if source != Vector3.INF:
		falloff = clampf(1.0 - camera.global_position.distance_to(source) / 120.0, 0.15, 1.0)
	camera.add_trauma(amount * falloff * Game.settings.screen_shake)


## Freezes time briefly so heavy hits land.
func hitstop(duration: float) -> void:
	if duration <= _hitstop:
		return
	_hitstop = duration
	Engine.time_scale = 0.05


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
