extends Node
## Captures the real title -> stage-select screen in both locales.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/stage_select_shots.gd --out=/home/scarf/repo/etc/orca-class/screenshots/stage-select [--verify]
## For --verify, capture each stage map with capture_course's --reference=<out>/stageN-reference.png.
## The map and reference must come from the same native frame; no resizing is permitted.

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
		title._show_main()
		await get_tree().process_frame
		_press_key(KEY_ENTER) # Open the cards through the real sortie menu input path.
		for _i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame := get_viewport().get_texture().get_image()
		frame.save_png("%s/stage-select-%s.png" % [out, locale])
		if args.has("verify") and not _verify_card(frame, 1, locale, out):
			return 1
		_press_key(KEY_D)
		for _i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		frame = get_viewport().get_texture().get_image()
		frame.save_png("%s/stage-select-%s-stage2.png" % [out, locale])
		if args.has("verify") and not _verify_card(frame, 2, locale, out):
			return 1
		print("saved stage select %s" % locale)
	return 0


func _verify_card(frame: Image, stage: int, locale: String, out: String) -> bool:
	var reference := Image.new()
	if reference.load_png_from_buffer(FileAccess.get_file_as_bytes("%s/stage%d-reference.png" % [out, stage])) != OK:
		return false
	if reference.get_size() != DitherView.RESOLUTION:
		push_error("Reference must be the displayed 960x540 frame")
		return false
	var map_size := Vector2i(StageSelect.CARD_SIZE)
	var origin := (DitherView.RESOLUTION - map_size) / 2
	var map := Image.new()
	map.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ui/stage%d.png" % stage))
	var native_crop := reference.get_region(Rect2i(origin, map_size))
	map.convert(Image.FORMAT_RGBA8)
	native_crop.convert(Image.FORMAT_RGBA8)
	if map.get_data() != native_crop.get_data():
		push_error("Stage %d asset differs from the native frame crop" % stage)
		return false
	# Exclude text and border only; compare every image pixel in the unobscured interior.
	var interior := Rect2i(8, 40, 240, 180)
	var card_origin := Vector2i(StageSelect.CARD_LEFT + (stage - 1) * (StageSelect.CARD_SIZE.x + StageSelect.CARD_GAP), StageSelect.CARD_TOP)
	var card := frame.get_region(Rect2i(card_origin + interior.position, interior.size))
	var expected := reference.get_region(Rect2i(origin + interior.position, interior.size))
	card.convert(Image.FORMAT_RGBA8)
	expected.convert(Image.FORMAT_RGBA8)
	card.save_png("%s/stage%d-card-%s.png" % [out, stage, locale])
	expected.save_png("%s/stage%d-reference-crop.png" % [out, stage])
	var mismatches := 0
	for y in interior.size.y:
		for x in interior.size.x:
			if card.get_pixel(x, y) != expected.get_pixel(x, y):
				mismatches += 1
	print("stage %d %s: native asset crop exact; focused card %d/%d pixel mismatches" % [stage, locale, mismatches, interior.size.x * interior.size.y])
	return mismatches == 0


func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
