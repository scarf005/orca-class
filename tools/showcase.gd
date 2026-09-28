extends Node
## Stages a fixed scene and saves screenshots, for checking effects and art without playing.
## Usage: xvfb-run -a godot --path . --resolution 960x540 -- --run=res://tools/showcase.gd \
##        --scene=vfx|fungus|boss --d=620 --shots=0.5,1,2 --out=builds/showcase

var screen: GameScreen


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var scene: String = args.get("scene", "vfx")
	var out: String = args.get("out", "builds/showcase")
	DirAccess.make_dir_recursive_absolute(out)
	var shots: Array = []
	for s: String in String(args.get("shots", "0.5,1,1.5,2.5")).split(",", false):
		shots.append(float(s))
	screen = GameScreen.new()
	screen.checkpoint = "boss" if scene == "boss" else ""
	add_child(screen)
	var world := screen.world
	world.player.invulnerable = true
	world.player.input_enabled = false
	var d := float(args.get("d", "620"))
	if scene != "boss":
		world.rail.d = d
		world.rail.mode = Rail.Mode.HOLD
		world.rail.hold_at = d
		world.director._next_event = world.director.events.size()
		world.director.scenery.stream(d, 100000)
	# Let terrain and scenery settle before staging.
	for _i in 30:
		await get_tree().process_frame
	match scene:
		"vfx":
			_stage_vfx(world)
		"tail":
			_stage_tail(world)
		"modules":
			var tank := world.player
			tank.modules.consume_era("front")
			tank.modules.consume_era("left")
			tank.modules.consume_era("left")
			tank.modules.damage("track_r", 999.0)
			tank.modules.damage("breech", 40.0)
			tank.tail.damage(70.0)
			world.radio.emit(&"AI_MOD_TRACK_R_OUT")
			_stage_vfx(world)
		"fungus":
			world.player.model.visible = true
		"church":
			_stage_church(world)
		"boss":
			# Past the boss event: the director spawns the gunship itself on the next frame.
			world.rail.d = Course.ARENA_CENTER_D - 60.0
	var elapsed := 0.0
	var index := 0
	while not shots.is_empty():
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if scene == "vfx":
			_drive(world, elapsed)
		elif scene == "tail":
			world.player.auto_tail()
		if elapsed >= shots[0]:
			shots.pop_front()
			get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [out, scene, index])
			index += 1
	return 0


func _stage_vfx(world: World) -> void:
	var tank := world.player
	var base := world.rail.d + tank.course_offset
	for i in 3:
		var ugv: Ugv = load("res://scripts/enemies/ugv.gd").new()
		ugv.position = Course.ground_at(base + 30.0 + i * 8.0, -8.0 + i * 8.0)
		world.add_enemy(ugv)
	for i in 4:
		var drone := FpvDrone.new()
		drone.position = Course.ground_at(base + 25.0, -6.0 + i * 4.0) + Vector3.UP * 7.0
		drone.approach_time = 99.0
		world.add_enemy(drone)
	world.fx.explosion(Course.ground_at(base + 22.0, 5.0) + Vector3.UP, 4.5)
	for i in 5:
		var barrel := Prop.new()
		barrel.setup("barrel", PropKit.mesh("barrel", i), 0.5, 1.0, 10.0)
		barrel.explosive = true
		barrel.blast_size = 4.0
		barrel.position = Course.ground_at(base + 30.0 + i * 1.2, -4.0 + (i % 2) * 1.5)
		world.props.add_child(barrel)
	world.fx.burn(Course.ground_at(base + 26.0, -9.0), 20.0, 1.3)
	world.radio.emit(&"AI_REAR")
	world.player.load_round(Armament.Round.HEAT)
	world.player.set_coax_tier(4)


## Blows out the church tower and a nave half so the spire topples.
func _stage_church(world: World) -> void:
	var pieces := world.props.get_children().filter(func(p: Node) -> bool: return p is Prop and (p as Prop).kind.begins_with("church"))
	for piece: Prop in pieces:
		if piece.kind in ["church_tower", "church_nave"] and piece.max_hp > 0.0 and randf() < (1.0 if piece.kind == "church_tower" else 0.5):
			var hit := Hit.make(Hit.Kind.SHELL, 9999.0, piece.global_position + Vector3.UP * 3.0)
			hit.source = world.player
			world.fx.explosion(hit.position, 4.0)
			piece.take_hit(hit)
	var cam := world.camera
	cam.set_process(false)
	var spot := Course.ground_at(1160.0, 26.0)
	cam.global_position = spot + Vector3(-30, 14, 30)
	cam.look_at(spot + Vector3.UP * 8.0, Vector3.UP)


func _stage_tail(world: World) -> void:
	var tank := world.player
	for i in 3:
		var crawler := Crawler.new()
		crawler.position = tank.global_position + tank.global_basis.x * (5.0 + i * 2.0) - tank.global_basis.z * (4.0 + i * 3.0)
		world.add_enemy(crawler)
		crawler.stagger = 3.0
	var ugv: Ugv = load("res://scripts/enemies/ugv.gd").new()
	ugv.position = Course.ground_at(world.rail.d + tank.course_offset + 32.0, -3.0)
	world.add_enemy(ugv)
	world.spawn_pickup("heat", tank.tail.mount.global_position - tank.global_basis.x * 6.0)


func _drive(world: World, t: float) -> void:
	var tank := world.player
	tank.using_gamepad = true
	if world.enemies.is_empty():
		return
	var target: Entity = world.enemies[int(t * 2.0) % world.enemies.size()]
	tank.aim_screen = world.camera.unproject_position(target.hit_center())
	tank.input_enabled = true
	if tank.reload <= 0.0:
		tank.fire_cannon()
