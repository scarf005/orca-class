class_name Stage1
## Stage 1 "Hypha": hand-placed encounters by rail distance. Pacing per section:
## quiet opening, build, peak, then a short release before the next section.


static func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind}
		event.merge(extra)
		e.append(event)

	# Farm road (quiet -> build): FPVs alone while the CIWS learns its job, then the first ground contact.
	wave.call(90.0, "fpv", {"count": 2, "formation": "line", "height": 9.0, "spacing": 7.0, "hover": 26.0})
	wave.call(170.0, "fpv", {"count": 4, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(250.0, "fpv", {"count": 5, "formation": "ring", "height": 10.0, "spacing": 8.0, "stagger": 0.25})
	wave.call(330.0, "crawler", {"count": 4, "formation": "sides", "spacing": 16.0, "ahead": 70.0})
	# Release 330-460: nothing spawns.
	wave.call(460.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 6.0, "hover": 14.0, "approach": 1.2})
	wave.call(510.0, "ugv", {"count": 2, "u": 5.0, "spacing": 8.0, "ahead": 100.0})
	wave.call(540.0, "ugv", {"count": 2, "formation": "behind", "spacing": 10.0})

	# Village, a ground war. Intro: UGVs in the lanes. Build: a lone bombing run, walkers, a crawler flank.
	# Release 945-1085. Peak 1085-1195: helicopter, UGV column, missile walkers, crawlers, FPVs from behind.
	# Release to the mid-boss, broken only by a quad duel.
	wave.call(600.0, "ugv", {"count": 4, "formation": "sides", "spacing": 8.0, "ahead": 95.0})
	wave.call(650.0, "crawler", {"count": 4, "formation": "scatter", "spacing": 18.0, "ahead": 60.0, "u": 0.0})
	wave.call(705.0, "fpv", {"count": 4, "formation": "line", "height": 9.0, "spacing": 6.0})
	wave.call(770.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb"}})
	wave.call(840.0, "walker", {"count": 4, "formation": "behind", "spacing": 9.0})
	wave.call(890.0, "spitter", {"count": 4, "formation": "sides", "spacing": 15.0, "ahead": 80.0})
	wave.call(945.0, "crawler", {"count": 6, "formation": "flank", "u": -1.0, "spacing": 6.0, "ahead": 10.0})
	wave.call(1085.0, "helicopter", {"count": 1, "height": 13.0, "ahead": 110.0, "u": -10.0})
	wave.call(1100.0, "ugv", {"count": 3, "formation": "column", "spacing": 14.0, "ahead": 100.0, "u": 4.0, "drop": "coax"})
	wave.call(1125.0, "walker", {"count": 3, "formation": "line", "spacing": 7.0, "ahead": 85.0, "props": {"weapon": "missile"}})
	wave.call(1150.0, "crawler", {"count": 7, "formation": "scatter", "spacing": 16.0, "ahead": 50.0})
	wave.call(1175.0, "fpv", {"count": 4, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
	wave.call(1195.0, "ugv", {"count": 2, "formation": "sides", "spacing": 10.0, "ahead": 90.0, "props": {"weapon": "atgm"}})
	wave.call(1300.0, "quad", {"count": 1, "u": 0.0, "ahead": 100.0, "props": {"weapon": "mortar"}})

	# Branch school: the mid-boss holds the rail.
	e.append({"d": 1470.0, "type": "checkpoint", "name": "midboss"})
	wave.call(1500.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 20.0, "ahead": 60.0})
	e.append({"d": Course.MIDBOSS_D - 110.0, "type": "midboss", "kind": "colossus", "hold": Course.MIDBOSS_D - 56.0})

	# Reservoir, an air war over the water (ground units stay a minority). Intro: drones rise out of the reeds.
	# Build: UAV passes, a helicopter, spitters on the bank. Release 2050-2185. Peak 2185-2400 with the storm:
	# bombers from behind, helicopters, a reed ring, ATGM UGVs. Release to the overpass, only the supply UGV.
	wave.call(1830.0, "fpv", {"count": 4, "formation": "scatter", "height": 1.5, "spacing": 3.0, "u": -17.0, "ahead": 60.0})
	wave.call(1885.0, "fpv", {"count": 4, "formation": "scatter", "height": 1.5, "spacing": 3.0, "u": -17.0, "ahead": 60.0})
	wave.call(1940.0, "uav", {"count": 4, "formation": "v", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(1995.0, "helicopter", {"count": 1, "formation": "line", "height": 14.0, "spacing": 24.0, "ahead": 105.0})
	wave.call(2050.0, "spitter", {"count": 5, "formation": "line", "spacing": 4.0, "u": 20.0, "ahead": 85.0})
	e.append({"d": 2185.0, "type": "storm", "duration": 22.0})
	wave.call(2185.0, "uav", {"count": 3, "formation": "line", "spacing": 12.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(2215.0, "fpv", {"count": 10, "formation": "ring", "height": 1.5, "spacing": 4.0, "u": -17.0, "stagger": 0.18})
	wave.call(2245.0, "helicopter", {"count": 2, "formation": "sides", "height": 14.0, "spacing": 22.0, "ahead": 65.0})
	wave.call(2270.0, "ugv", {"count": 2, "formation": "line", "spacing": 8.0, "u": 4.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
	wave.call(2300.0, "uav", {"count": 3, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(2340.0, "fpv", {"count": 5, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(2370.0, "uav", {"count": 3, "formation": "v", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(2560.0, "ugv", {"count": 1, "u": 0.0, "ahead": 90.0, "props": {"weapon": "supply"}, "drop": "repair"})


	# Overpass, a ground gauntlet. Intro: an ambush under the bridge. Build: up the ramp. Peak 3065-3240 on the
	# deck. Release from there to the boss.
	wave.call(2740.0, "ugv", {"count": 5, "formation": "behind", "spacing": 9.0})
	wave.call(2775.0, "crawler", {"count": 5, "formation": "flank", "u": 1.0, "spacing": 6.0, "ahead": 15.0})
	wave.call(2830.0, "ugv", {"count": 7, "formation": "column", "spacing": 12.0, "ahead": 100.0})
	wave.call(2890.0, "walker", {"count": 5, "formation": "behind", "spacing": 8.0})
	wave.call(2945.0, "crawler", {"count": 4, "formation": "scatter", "spacing": 10.0, "ahead": 70.0})
	wave.call(3065.0, "quad", {"count": 2, "formation": "sides", "spacing": 7.0, "ahead": 100.0})
	wave.call(3090.0, "walker", {"count": 4, "formation": "line", "spacing": 6.0, "ahead": 80.0, "props": {"weapon": "missile"}})
	wave.call(3115.0, "helicopter", {"count": 3, "formation": "v", "height": 15.0, "spacing": 20.0, "ahead": 105.0})
	wave.call(3145.0, "ugv", {"count": 5, "formation": "column", "spacing": 10.0, "ahead": 100.0})
	wave.call(3175.0, "fpv", {"count": 8, "formation": "ring", "height": 9.0, "spacing": 9.0, "stagger": 0.15})
	wave.call(3205.0, "uav", {"count": 3, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(3235.0, "walker", {"count": 3, "formation": "line", "spacing": 6.0, "ahead": 80.0, "props": {"weapon": "missile"}})
	e.append({"d": 3395.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": 3465.0, "type": "boss", "kind": "gunship"})

	if hard:
		# Hard adds flankers to the build beats, never inside a release, so the peaks keep their breathing room.
		wave.call(60.0, "fpv", {"count": 2, "formation": "sides", "height": 7.0, "spacing": 10.0})
		wave.call(915.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "strafe"}})
		wave.call(1800.0, "ugv", {"count": 2, "formation": "sides", "spacing": 9.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
		wave.call(2665.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
		wave.call(2990.0, "fpv", {"count": 4, "formation": "ring", "height": 9.0, "spacing": 9.0})
	return e
