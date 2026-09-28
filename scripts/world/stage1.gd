class_name Stage1
## Stage 1 "Hypha": hand-placed encounters by rail distance. Pacing per section:
## quiet opening, build, peak, then a short release before the next section.


static func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var radio := func(d: float, line: String) -> void: e.append({"d": d, "type": "radio", "line": line})
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind}
		event.merge(extra)
		e.append(event)

	# Farm road: learn to shoot, let the CIWS work, first pickups.
	radio.call(5.0, "AI_BOOT")
	radio.call(40.0, "AI_ROUTE")
	wave.call(90.0, "fpv", {"count": 3, "formation": "line", "height": 9.0, "spacing": 7.0, "hover": 26.0})
	radio.call(100.0, "AI_FPV")
	e.append({"d": 125.0, "type": "hint", "key": "HINT_TAIL"})
	wave.call(170.0, "fpv", {"count": 5, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(250.0, "fpv", {"count": 6, "formation": "ring", "height": 10.0, "spacing": 8.0, "stagger": 0.25})
	wave.call(330.0, "crawler", {"count": 4, "formation": "sides", "spacing": 16.0, "ahead": 70.0})
	wave.call(400.0, "fpv", {"count": 4, "formation": "line", "height": 7.0, "spacing": 5.0, "u": -6.0})
	e.append({"d": 435.0, "type": "hint", "key": "HINT_ANCHOR"})
	wave.call(450.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 6.0, "hover": 14.0, "approach": 1.2})
	radio.call(452.0, "AI_REAR")
	wave.call(510.0, "ugv", {"count": 1, "u": 5.0, "ahead": 100.0})
	radio.call(515.0, "AI_UGV")

	# Village: UGVs in the lanes, crawlers from greenhouses, first bombing runs.
	wave.call(600.0, "ugv", {"count": 2, "formation": "sides", "spacing": 8.0, "ahead": 95.0})
	wave.call(655.0, "fpv", {"count": 4, "formation": "line", "height": 9.0, "spacing": 6.0})
	wave.call(700.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 18.0, "ahead": 60.0, "u": 0.0})
	radio.call(702.0, "AI_BIO")
	wave.call(760.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb"}})
	radio.call(755.0, "AI_UAV")
	wave.call(830.0, "ugv", {"count": 1, "u": -6.0, "ahead": 110.0, "props": {"weapon": "atgm"}})
	wave.call(840.0, "fpv", {"count": 5, "formation": "v", "height": 9.0, "spacing": 5.0})
	wave.call(900.0, "spitter", {"count": 2, "formation": "sides", "spacing": 15.0, "ahead": 80.0})
	radio.call(905.0, "AI_SPITTER")
	wave.call(960.0, "crawler", {"count": 8, "formation": "scatter", "spacing": 20.0, "ahead": 55.0})
	wave.call(1010.0, "fpv", {"count": 8, "formation": "ring", "height": 10.0, "spacing": 9.0, "stagger": 0.2})
	wave.call(1060.0, "ugv", {"count": 3, "formation": "column", "spacing": 14.0, "ahead": 100.0, "u": 4.0, "drop": "coax"})
	wave.call(1120.0, "uav", {"count": 2, "formation": "line", "spacing": 12.0, "props": {"attack": "strafe"}})
	wave.call(1180.0, "spitter", {"count": 3, "formation": "line", "spacing": 12.0, "ahead": 85.0})
	wave.call(1190.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 16.0, "ahead": 50.0})
	wave.call(1250.0, "fpv", {"count": 4, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
	wave.call(1260.0, "ugv", {"count": 2, "formation": "sides", "spacing": 10.0, "ahead": 90.0, "props": {"weapon": "atgm"}})
	wave.call(1330.0, "fpv", {"count": 5, "formation": "line", "height": 8.0, "spacing": 5.0})
	wave.call(1340.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 14.0, "ahead": 60.0})
	radio.call(1420.0, "AI_BIO_LARGE")

	# Branch school: the mid-boss holds the rail.
	e.append({"d": 1470.0, "type": "checkpoint", "name": "midboss"})
	wave.call(1500.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 20.0, "ahead": 60.0})
	e.append({"d": Course.MIDBOSS_D - 110.0, "type": "midboss", "kind": "colossus", "hold": Course.MIDBOSS_D - 56.0})

	# Reservoir: drones rise out of the reeds, UAV passes over water, spore storms.
	radio.call(1790.0, "AI_REEDS")
	wave.call(1830.0, "fpv", {"count": 6, "formation": "scatter", "height": 1.5, "spacing": 12.0, "u": -14.0, "ahead": 60.0})
	wave.call(1900.0, "uav", {"count": 3, "formation": "v", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(1960.0, "spitter", {"count": 2, "formation": "line", "spacing": 12.0, "u": 18.0, "ahead": 85.0})
	e.append({"d": 1965.0, "type": "storm", "duration": 22.0})
	radio.call(1968.0, "AI_STORM")
	wave.call(2020.0, "ugv", {"count": 2, "formation": "sides", "spacing": 9.0, "ahead": 100.0})
	wave.call(2030.0, "fpv", {"count": 5, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(2100.0, "crawler", {"count": 8, "formation": "scatter", "spacing": 16.0, "ahead": 60.0})
	wave.call(2180.0, "uav", {"count": 2, "formation": "line", "spacing": 12.0, "props": {"attack": "bomb"}})
	wave.call(2190.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
	wave.call(2250.0, "ugv", {"count": 3, "formation": "sides", "spacing": 9.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
	wave.call(2330.0, "fpv", {"count": 8, "formation": "ring", "height": 9.0, "spacing": 9.0, "stagger": 0.18})
	wave.call(2400.0, "spitter", {"count": 3, "formation": "line", "spacing": 10.0, "u": 16.0, "ahead": 80.0})
	wave.call(2410.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 14.0, "ahead": 55.0})
	wave.call(2480.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb"}})
	wave.call(2500.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(2560.0, "ugv", {"count": 1, "u": 0.0, "ahead": 90.0, "props": {"weapon": "supply"}, "drop": "repair"})
	wave.call(2570.0, "fpv", {"count": 6, "formation": "line", "height": 8.0, "spacing": 4.0})

	# Overpass: under the bridge, up the ramp, the heaviest gauntlet on the deck.
	wave.call(2720.0, "fpv", {"count": 6, "formation": "line", "height": 6.0, "spacing": 5.0, "hover": 22.0})
	wave.call(2790.0, "ugv", {"count": 3, "formation": "column", "spacing": 12.0, "ahead": 100.0})
	wave.call(2860.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb"}})
	wave.call(2870.0, "fpv", {"count": 4, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(2925.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 10.0, "ahead": 70.0})
	wave.call(3000.0, "ugv", {"count": 2, "formation": "sides", "spacing": 7.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
	wave.call(3010.0, "fpv", {"count": 4, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
	wave.call(3060.0, "uav", {"count": 3, "formation": "v", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(3120.0, "fpv", {"count": 10, "formation": "ring", "height": 9.0, "spacing": 9.0, "stagger": 0.15})
	wave.call(3180.0, "ugv", {"count": 3, "formation": "line", "spacing": 7.0, "ahead": 100.0})
	wave.call(3190.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 10.0, "ahead": 60.0})
	wave.call(3250.0, "fpv", {"count": 6, "formation": "line", "height": 8.0, "spacing": 4.0})
	wave.call(3255.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb"}})
	wave.call(3260.0, "ugv", {"count": 2, "formation": "sides", "spacing": 8.0, "ahead": 90.0, "props": {"weapon": "atgm"}})
	radio.call(3340.0, "AI_AREA_CLEAR")
	radio.call(3385.0, "AI_ROTOR")
	e.append({"d": 3395.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": 3465.0, "type": "boss", "kind": "helicopter"})

	if hard:
		# Hard adds flankers to the calm stretches so there is no free breathing room.
		wave.call(60.0, "fpv", {"count": 2, "formation": "sides", "height": 7.0, "spacing": 10.0})
		wave.call(1400.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "strafe"}})
		wave.call(1800.0, "ugv", {"count": 2, "formation": "sides", "spacing": 9.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
		wave.call(2650.0, "fpv", {"count": 6, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
		wave.call(3320.0, "fpv", {"count": 8, "formation": "ring", "height": 9.0, "spacing": 9.0})
	return e
