class_name ActorMeshes
extends RefCounted
## Immutable, shared parts from Blender exports. Gameplay owns the node hierarchy and pivots.

const ACTORS := ["tank", "crawler", "spitter", "ugv", "walker", "quad_mech", "fpv_drone", "uav", "helicopter", "tiltrotor", "colossus", "gunship", "flare"]
static var _parts := {}


static func mesh(actor: String, part: String) -> Mesh:
	if not has_part(actor, part):
		push_error("Unknown actor mesh: %s/%s" % [actor, part])
		return null
	return _parts[actor][part]


static func has_part(actor: String, part: String) -> bool:
	if actor not in ACTORS:
		return false
	if not _parts.has(actor):
		var scene: PackedScene = load("res://assets/actors/%s.glb" % actor)
		if scene == null:
			return false
		var root := scene.instantiate()
		var parts := {}
		_collect(root, parts)
		root.free()
		_parts[actor] = parts
	return _parts[actor].has(part)


static func _collect(node: Node, parts: Dictionary) -> void:
	if node is MeshInstance3D:
		var imported: Mesh = node.mesh
		for i in imported.get_surface_count():
			var source := imported.surface_get_material(i)
			var material := role(source.resource_name)
			assert(material != null, "Unknown actor material role: " + source.resource_name)
			imported.surface_set_material(i, material)
		parts[String(node.name)] = imported
	for child in node.get_children():
		_collect(child, parts)


static func role(name: String) -> Material:
	match name:
		"lit": return LowPoly.lit_material
		"glow": return LowPoly.glow_material
		"flesh": return LowPoly.flesh_material
		"flesh_glow": return LowPoly.flesh_glow_material
		"vivid_lit": return LowPoly.vivid_lit_material
		"vivid_glow": return LowPoly.vivid_glow_material
	return null
