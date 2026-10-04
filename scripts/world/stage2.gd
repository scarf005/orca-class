class_name Stage2
extends StageDef
## Stage 2 "Submerged City": a bare rail for now. Its terrain, props, events and look get filled in here.

enum Section { CITY }

const SECTION_STARTS := [0.0]
const LENGTH := 2000.0
const PLAN := [[650.0, 0.0], [300.0, 40.0], [250.0, 0.0], [350.0, -60.0], [450.0, 0.0]]


func _init() -> void:
	number = 2
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	start_rws = true
	coax_tiers = {"": 2}
	arena_center_d = LENGTH
	arena_radius = 85.0
	sky_top = Color("5f6f9c")
	sky_horizon = Color("b8c0d0")
	sky_ground = Color("6a7488")
	ambient = Color("a0a8c0")
	fog_color = Color("aab4c8")
	sun_color = Color("e8ecf8")
	sun_energy = 0.85


func music(_section: int) -> String:
	return "res://assets/music/stage_a.ogg"
