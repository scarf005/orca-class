extends TestCase
## Stage events as data: the saved file, the override hook, the playtest and the editor's ground picking.

const SANDBOX := "user://map_editor_test"
var _dir := StageEvents.dir


func _use_sandbox() -> void:
	StageEvents.dir = SANDBOX
	StageEvents.playtest = {}
	var path := StageEvents.path(3)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _restore() -> void:
	var path := StageEvents.path(3)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	StageEvents.dir = _dir
	StageEvents.playtest = {}


## Equal when every key matches and numbers match by value, since JSON reads every number back as a float.
func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		return a.size() == b.size() and a.keys().all(func(key: Variant) -> bool: return b.has(key) and _same(a[key], b[key]))
	if a is Array and b is Array:
		return a.size() == b.size() and range(a.size()).all(func(i: int) -> bool: return _same(a[i], b[i]))
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


func test_every_coded_stage_survives_a_save_and_load() -> void:
	_use_sandbox()
	for number in [1, 2, 3]:
		var coded := StageDef.of(number).events(false)
		check_eq(StageEvents.save(number, coded), OK, "stage %d saves" % number)
		var loaded: Variant = StageEvents.edited(number)
		check(loaded != null and _same(loaded, coded), "stage %d loads back its %d coded events" % [number, coded.size()])
		DirAccess.remove_absolute(StageEvents.path(number))
	_restore()


func test_the_comparison_notices_a_changed_event() -> void:
	var coded := Stage3.new().events(false)
	var changed := coded.duplicate(true)
	changed[0].d += 1.0
	check(not _same(coded, changed), "a moved event is different")
	changed = coded.duplicate(true)
	changed[-1].erase("type")
	check(not _same(coded, changed), "a lost key is different")


func test_without_a_file_the_stage_plays_its_coded_events() -> void:
	_use_sandbox()
	for number in [1, 2, 3]:
		var stage := StageDef.of(number)
		check_eq(StageEvents.edited(number), null, "stage %d has no saved list" % number)
		check_eq(stage.run_events(false).size(), stage.events(false).size(), "stage %d runs %d coded events" % [number, stage.events(false).size()])
		check_eq(stage.run_events(true).size(), stage.events(true).size(), "stage %d hard runs its coded events" % number)
	_restore()


func test_a_saved_file_decides_what_spawns() -> void:
	_use_sandbox()
	StageEvents.save(3, [{"d": 0.0, "type": "wave", "kind": "ugv", "count": 2, "ahead": 60.0}] as Array[Dictionary])
	var world := stage("", true, 3)
	check_eq(world.director.events.size(), 1, "the file replaces the whole coded list")
	await wait_until(func() -> bool: return world.enemies.size() >= 2)
	check_eq(world.enemies.filter(func(e: Entity) -> bool: return e is Ugv).size(), 2, "the saved wave spawns two ugvs")
	check_eq(world.enemies.size(), 2, "nothing else spawns")
	_restore()


func test_playtest_starts_at_the_chosen_distance_with_the_edited_wave() -> void:
	_use_sandbox()
	StageEvents.playtest = {"stage": 3, "events": [{"d": 1000.0, "type": "wave", "kind": "abel", "ahead": 70.0}, {"d": 200.0, "type": "wave", "kind": "ugv", "ahead": 70.0}] as Array[Dictionary], "d": 1000.0}
	var world := stage("", true, 3)
	check_near(world.rail.d, 1000.0, 0.001, "the rail starts at the chosen distance")
	check(not world.stats.ranked, "a playtest is not ranked")
	await wait_until(func() -> bool: return not world.enemies.is_empty())
	check(world.enemies.any(func(e: Entity) -> bool: return e is Abel), "the edited abel spawns")
	check(not world.enemies.any(func(e: Entity) -> bool: return e is Ugv), "events before the start are skipped")
	var other := StageDef.of(2).run_events(false)
	check_eq(other.size(), StageDef.of(2).events(false).size(), "a playtest of stage 3 leaves stage 2 alone")
	_restore()


func test_picking_finds_the_course_position_under_the_ray() -> void:
	Course.use(3)
	for spot in [Vector2(300.0, 0.0), Vector2(1200.0, -12.5), Vector2(2900.0, 20.0), Vector2(5000.0, 6.0)]:
		var ground := Course.ground_at(spot.x, spot.y)
		var from := Course.to_world(spot.x - 60.0, spot.y * 0.5, ground.y + 40.0)
		var picked := MapEditor.pick_ground(from, (ground - from).normalized())
		check_near(picked.x, spot.x, 0.5, "picked d at %s" % spot)
		check_near(picked.y, spot.y, 0.5, "picked u at %s" % spot)
	check(not MapEditor.pick_ground(Course.ground_at(300.0, 0.0) + Vector3.UP * 40.0, Vector3.UP).is_finite(), "a ray into the sky picks nothing")


func test_an_event_placed_at_its_own_spot_does_not_move() -> void:
	for event in Stage3.new().events(false):
		var before := event.duplicate(true)
		StageEvents.place(event, StageEvents.spot(event))
		check(_same(event, before) or event.has("squad") and event.d == before.d, "%s at %.0f stays put" % [event.type, event.d])
	var hold := StageEvents.create("hold", Vector2(500.0, 0.0))
	check_near(hold.d, 500.0, 0.001, "a hold is triggered where it is placed")
	check_near(hold.at, 515.0, 0.001, "its stopping point keeps its distance")
	StageEvents.place(hold, Vector2(530.0, 0.0))
	check_near(hold.at, 545.0, 0.001, "moving a hold carries its stopping point")
	var wave := StageEvents.create("wave", Vector2(800.0, -6.0))
	check_near(StageEvents.spot(wave).x, 800.0, 0.5, "a wave spawns where it was placed")
	check_near(wave.d, 710.0, 0.5, "and triggers its default 90 m earlier")
	check_near(wave.u, -6.0, 0.001, "at the picked lateral offset")


func test_the_editor_adds_a_wave_where_the_view_is_clicked_and_saves_it() -> void:
	_use_sandbox()
	var editor := MapEditor.new()
	editor.stage_number = 3
	add_child(editor)
	await frames(3)
	var coded := Stage3.new().events(false).size()
	check_eq(editor.events.size(), coded, "the editor opens with the stage's %d events" % coded)
	editor.scrub(300.0)
	editor._tool = "wave"
	var middle := get_viewport().get_visible_rect().size * 0.5
	var ground := MapEditor.pick_ground(editor.world.camera.global_position, editor.world.camera.project_ray_normal(middle))
	editor._click(middle)
	check_eq(editor.events.size(), coded + 1, "the click adds one event")
	var added: Dictionary = editor.events[editor._selected]
	check_near(StageEvents.spot(added).x, ground.x, 0.5, "it spawns at the clicked d")
	check_near(StageEvents.spot(added).y, ground.y, 0.5, "it spawns at the clicked u")
	editor.save()
	var saved: Variant = StageEvents.edited(3)
	check(saved != null and saved.size() == coded + 1, "saving writes the edited list")
	editor.delete_selected()
	check_eq(editor.events.size(), coded, "delete removes it again")
	editor.queue_free()
	_restore()
