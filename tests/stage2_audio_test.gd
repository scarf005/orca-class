extends TestCase
## Stage 2's music per section, its boss theme and its water and gas effects.


func test_the_new_effects_are_registered_and_have_the_right_length() -> void:
	var lengths := {"rush": Vector2(0.8, 1.6), "whoomp": Vector2(0.5, 1.2), "steam": Vector2(0.5, 1.4), "slosh": Vector2(0.3, 0.9)}
	for name: String in lengths:
		check(Sfx.SOUNDS.has(name), "%s is registered" % name)
		var audio := load(Sfx.SOUNDS[name][0]) as AudioStreamWAV
		check(audio != null and not audio.stereo, "%s loads as a mono stream" % name)
		if audio:
			var seconds := audio.get_length()
			check(seconds >= lengths[name].x and seconds <= lengths[name].y, "%s is %.2f s" % [name, seconds])
		var bytes := FileAccess.get_file_as_bytes(Sfx.SOUNDS[name][0])
		var peak := 0.0
		for i in range(44, bytes.size() - 1, 2):
			peak = maxf(peak, absf(bytes.decode_s16(i) / 32768.0))
		check(peak > 0.5, "%s is audible (peak %.2f)" % [name, peak])


func test_every_section_of_stage_2_has_music_and_the_arena_leaves_it_to_the_boss() -> void:
	Course.use(2)
	var stage_2 := Course.stage
	var tracks := {}
	for section in stage_2.section_starts.size():
		var track := stage_2.music(section)
		if section == Stage2.Section.ARENA:
			check_eq(track, "", "the arena waits for the boss theme")
			continue
		check(ResourceLoader.exists(track), "section %d has a track (%s)" % [section, track])
		tracks[track] = true
		check(not track.ends_with("stage_a.ogg") and not track.ends_with("stage_b.ogg"), "and not one of stage 1's")
	check_eq(tracks.size(), 2, "two tracks alternate over the sections")
	check_eq(stage_2.music(Stage2.Section.FLOODPLAIN), stage_2.music(Stage2.Section.MARSH), "the night stretches share one")
	check(stage_2.music(Stage2.Section.PADDIES) != stage_2.music(Stage2.Section.FLOODPLAIN), "the paddies change it")
	check(ResourceLoader.exists(stage_2.boss_music), "the boss has a theme")
	check(stage_2.boss_music != Stage1.new().boss_music and not stage_2.boss_music in tracks, "of its own")
	for track: String in tracks.keys() + [stage_2.boss_music]:
		var length := (load(track) as AudioStream).get_length()
		check(length > 30.0 and length < 90.0, "%s is a loopable length (%.0f s)" % [track, length])

