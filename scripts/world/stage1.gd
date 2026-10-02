class_name Stage1
## Stage 1 "Hypha": hand-placed encounters by rail distance. Few enemies, each one a question with
## its own answer (coax, a charged shot, a dodge, a ram), paced per section: quiet, build, peak,
## release. One hold per section stops the rail until its group is dealt with.


static func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind}
		event.merge(extra)
		e.append(event)

	# Farm road, the lessons one at a time: drones for the coax, a lone UGV whose front armor shrugs
	# off the coax (charge the gun), a crawler pack to ram for healing, drones from behind to dash.
	wave.call(90.0, "fpv", {"count": 3, "formation": "line", "height": 9.0, "spacing": 7.0, "hover": 26.0})
	wave.call(180.0, "fpv", {"count": 4, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(260.0, "ugv", {"count": 1, "u": 0.0, "ahead": 90.0})
	wave.call(330.0, "crawler", {"count": 5, "formation": "sides", "spacing": 16.0, "ahead": 70.0})
	# Release 330-460: nothing spawns.
	wave.call(460.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 6.0, "hover": 14.0, "approach": 1.2})
	wave.call(510.0, "ugv", {"count": 2, "formation": "behind", "spacing": 10.0})

	# Village, a ground war. Build: UGVs in the lanes, crawlers to ram, walkers that kick a rammer,
	# a lone bombing carpet, spitters, a crawler flank. Release 930-1085. Peak 1085-1195. Then the
	# quad duel holds the rail until the quad is down.
	wave.call(600.0, "ugv", {"count": 2, "formation": "sides", "spacing": 8.0, "ahead": 95.0})
	wave.call(650.0, "crawler", {"count": 5, "formation": "scatter", "spacing": 18.0, "ahead": 60.0, "u": 0.0})
	wave.call(720.0, "walker", {"count": 2, "formation": "behind", "spacing": 9.0})
	wave.call(790.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb"}})
	wave.call(860.0, "spitter", {"count": 3, "formation": "sides", "spacing": 15.0, "ahead": 80.0})
	wave.call(930.0, "crawler", {"count": 4, "formation": "flank", "u": -1.0, "spacing": 6.0, "ahead": 10.0})
	wave.call(1085.0, "helicopter", {"count": 1, "height": 13.0, "ahead": 110.0, "u": -10.0})
	wave.call(1100.0, "ugv", {"count": 3, "formation": "column", "spacing": 14.0, "ahead": 100.0, "u": 4.0, "drop": "coax"})
	wave.call(1130.0, "walker", {"count": 2, "formation": "line", "spacing": 7.0, "ahead": 85.0, "props": {"weapon": "missile"}})
	wave.call(1160.0, "crawler", {"count": 5, "formation": "scatter", "spacing": 16.0, "ahead": 50.0})
	wave.call(1185.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
	wave.call(1300.0, "quad", {"count": 1, "u": 0.0, "ahead": 100.0, "props": {"weapon": "mortar"}})
	e.append({"d": 1330.0, "type": "hold", "at": 1345.0, "timeout": 30.0})

	# Branch school: the mid-boss holds the rail.
	e.append({"d": 1470.0, "type": "checkpoint", "name": "midboss"})
	wave.call(1500.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 20.0, "ahead": 60.0})
	e.append({"d": Course.MIDBOSS_D - 110.0, "type": "midboss", "kind": "colossus", "hold": Course.MIDBOSS_D - 56.0})

	# Reservoir, an air war over the water. Build: drones from the reeds, a strafing pair, a lone
	# helicopter (airburst), spitters on the bank. Release 2060-2185. Peak with the storm: bombers
	# from behind, a reed ring, a helicopter pair that holds the rail, ATGM UGVs. Release to the
	# overpass, only the supply UGV.
	wave.call(1830.0, "fpv", {"count": 4, "formation": "scatter", "height": 1.5, "spacing": 3.0, "u": -17.0, "ahead": 60.0})
	wave.call(1890.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(1960.0, "helicopter", {"count": 1, "height": 14.0, "ahead": 105.0})
	wave.call(2030.0, "spitter", {"count": 3, "formation": "line", "spacing": 4.0, "u": 20.0, "ahead": 85.0})
	wave.call(2060.0, "fpv", {"count": 4, "formation": "scatter", "height": 1.5, "spacing": 3.0, "u": -17.0, "ahead": 60.0})
	e.append({"d": 2185.0, "type": "storm", "duration": 22.0})
	wave.call(2185.0, "uav", {"count": 2, "formation": "line", "spacing": 12.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(2215.0, "fpv", {"count": 6, "formation": "ring", "height": 1.5, "spacing": 4.0, "u": -17.0, "stagger": 0.18})
	wave.call(2245.0, "helicopter", {"count": 2, "formation": "sides", "height": 14.0, "spacing": 22.0, "ahead": 65.0})
	e.append({"d": 2255.0, "type": "hold", "at": 2270.0, "timeout": 25.0})
	wave.call(2290.0, "ugv", {"count": 2, "formation": "line", "spacing": 8.0, "u": 4.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
	wave.call(2325.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(2360.0, "fpv", {"count": 4, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(2560.0, "ugv", {"count": 1, "u": 0.0, "ahead": 90.0, "props": {"weapon": "supply"}, "drop": "repair"})

	# Overpass, the exam. Build: an ambush from behind under the bridge, a crawler flank, walkers, a
	# UGV column, a flak quad. Peak 3065-3235 on the deck: two quads and missile walkers hold the
	# rail, then helicopters, bombers from behind and a drone ring. Release from there to the boss.
	wave.call(2740.0, "ugv", {"count": 3, "formation": "behind", "spacing": 9.0})
	wave.call(2775.0, "crawler", {"count": 5, "formation": "flank", "u": 1.0, "spacing": 6.0, "ahead": 15.0})
	wave.call(2860.0, "walker", {"count": 3, "formation": "line", "spacing": 7.0, "ahead": 80.0})
	wave.call(2900.0, "ugv", {"count": 3, "formation": "column", "spacing": 12.0, "ahead": 100.0})
	wave.call(2980.0, "quad", {"count": 1, "u": 0.0, "ahead": 100.0, "props": {"weapon": "flak"}})
	wave.call(3065.0, "quad", {"count": 2, "formation": "sides", "spacing": 7.0, "ahead": 100.0})
	wave.call(3090.0, "walker", {"count": 3, "formation": "line", "spacing": 6.0, "ahead": 80.0, "props": {"weapon": "missile"}})
	e.append({"d": 3105.0, "type": "hold", "at": 3120.0, "timeout": 40.0})
	wave.call(3150.0, "helicopter", {"count": 2, "formation": "v", "height": 15.0, "spacing": 20.0, "ahead": 105.0})
	wave.call(3185.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(3215.0, "fpv", {"count": 5, "formation": "ring", "height": 9.0, "spacing": 9.0, "stagger": 0.15})
	e.append({"d": 3395.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": 3465.0, "type": "boss", "kind": "gunship"})

	if hard:
		# Hard adds flankers to the build beats, never inside a release, so the peaks keep their breathing room.
		wave.call(60.0, "fpv", {"count": 2, "formation": "sides", "height": 7.0, "spacing": 10.0})
		wave.call(890.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "strafe"}})
		wave.call(1800.0, "ugv", {"count": 2, "formation": "sides", "spacing": 9.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
		wave.call(2665.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
		wave.call(2940.0, "fpv", {"count": 4, "formation": "ring", "height": 9.0, "spacing": 9.0})
	return e
