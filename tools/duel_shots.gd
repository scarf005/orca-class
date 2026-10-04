extends Node
## Plays a stage 2 duel against the listed hunters with the tank holding still and shoots the real game view.
## Usage: xvfb-run -a godot --path . --resolution 960x540 -- --run=res://tools/duel_shots.gd \
##        --kind=abel[,kain] [--seconds=14] [--every=0.7] [--out=builds/duel]

func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "builds/duel")
	DirAccess.make_dir_recursive_absolute(out)
	for kind: String in Director.duel_counts:
		Director.duel_counts[kind] = 0
	for kind: String in String(args.get("kind", "abel")).split(",", false):
		Director.duel_counts[kind] = 1
	var screen := GameScreen.new()
	screen.stage = 2
	screen.checkpoint = "duel"
	add_child(screen)
	screen.world.player.invulnerable = true
	var elapsed := 0.0
	var next := 0.0
	var index := 0
	var every := float(args.get("every", "0.7"))
	while elapsed < float(args.get("seconds", "14")):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		screen.world.player.input_enabled = false
		if elapsed >= next:
			next += every
			get_viewport().get_texture().get_image().save_png("%s/%s_%02d.png" % [out, String(args.get("kind", "abel")).replace(",", "-"), index])
			index += 1
	return 0
