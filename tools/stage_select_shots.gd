extends Node
## Captures the real title -> stage-select screen in both locales.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/stage_select_shots.gd --out=/home/scarf/repo/etc/orca-class/screenshots/stage-select

func run() -> int:
	var args := preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "/home/scarf/repo/etc/orca-class/screenshots/stage-select")
	DirAccess.make_dir_recursive_absolute(out)
	var title: Control = load("res://scripts/ui/title.gd").new()
	add_child(title)
	for _i in 30:
		await get_tree().process_frame
	for locale in ["ko", "en"]:
		TranslationServer.set_locale(locale)
		title._show_stage_select(Game.Difficulty.NORMAL)
		for _i in 12:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/stage-select-%s.png" % [out, locale])
		print("saved stage select %s" % locale)
	return 0
