extends RefCounted
## Production representations and their mesh parts, in depth-first node order.
## Repeated names are shared parts; random_* entries are runtime-deformed bodies.

const VARIANTS := {
	"crawler": [""], "spitter": [""], "ugv": ["gun", "atgm", "supply"],
	"walker": ["gun", "missile"], "quad_mech": ["flak", "mortar"],
	"fpv_drone": [""], "uav": ["bomb", "strafe"], "helicopter": [""],
	"tiltrotor": ["", "drones", "crawlers"], "colossus": [""], "gunship": [""], "flare": [""],
}


static func create(actor: String, variant: String) -> Entity:
	var entity: Entity = load("res://scripts/enemies/%s.gd" % actor).new()
	if actor in ["ugv", "walker", "quad_mech"]:
		entity.set("weapon", variant)
	elif actor == "uav":
		entity.set("attack", variant)
	elif actor == "tiltrotor":
		entity.set("squad", variant)
	return entity


static func names(actor: String, variant: String) -> Array:
	match actor:
		"crawler": return ["random_body", "leg_left", "leg_left", "leg_left", "leg_right", "leg_right", "leg_right"]
		"spitter": return ["base", "stalk", "sac"]
		"ugv":
			return ["body_supply", "eye"] if variant == "supply" else ["body", "turret", "barrel_" + variant, "eye"]
		"walker":
			return ["body", "eye", "arm", "pod", "lid", "thigh", "shin", "foot", "wheels", "thigh", "shin", "foot", "wheels"]
		"quad_mech":
			return ["body", "turret", variant, "thigh_left", "shin_left", "wheel", "thigh_right", "shin_right", "wheel", "thigh_left", "shin_left", "wheel", "thigh_right", "shin_right", "wheel"]
		"fpv_drone": return ["body", "rotor", "rotor", "rotor", "rotor", "light"]
		"uav": return ["body", "prop", "gun"] if variant == "strafe" else ["body", "prop"]
		"helicopter": return ["body", "rotor", "tail_rotor", "chin", "pod", "pod"]
		"tiltrotor": return ["body", "ramp", "nacelle", "blades", "nacelle", "blades", "gun"]
		"colossus":
			var result := ["body", "node_left", "cap_left", "node_right", "cap_right", "node_top", "cap_top", "core"]
			for i in 9:
				result.append("tendril_%d" % i)
			return result
		"gunship":
			return ["body", "mast", "blades", "disc", "mast", "blades", "disc", "gatling_mount", "gatling_barrels", "gatling_mount", "gatling_barrels", "chin", "panel_left", "panel_right", "nose", "pod", "pod", "nose_gun", "bay", "random_fungus_0", "random_fungus_1", "random_fungus_2", "random_fungus_3", "random_fungus_4", "random_fungus_5"]
		"flare": return ["body"]
	return []


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root.is_queued_for_deletion():
		return result
	if root is MeshInstance3D:
		result.append(root)
	for child in root.get_children():
		result.append_array(meshes(child))
	return result
