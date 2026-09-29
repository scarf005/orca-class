extends TestCase
## Tests and tools never play sound.


func test_script_runs_are_silent() -> void:
	check(Game.silent, "script runs flag themselves silent")
	Game.apply_settings()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "master bus stays muted after settings apply")
	var world := stage()
	check(world != null and AudioServer.is_bus_mute(0), "starting a stage (and its music) stays muted")
	check(Sfx.music.stream == null and not Sfx.music.playing, "a silent run does not start music")
	check(world.player._engine_sound == null, "a silent run does not create the engine loop")
