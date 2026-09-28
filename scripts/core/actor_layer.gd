class_name ActorLayer
## Render layers that sort what is on screen. Everything on LAYER (the player, enemies, projectiles,
## pickups and flames) is mostly spared from dithering. The three class layers each get their own
## mask viewport: the final pass draws a glowing outline around every enemy, the tank and every
## pickup, and shows them in their true, saturated colors instead of the pastel palette.

const LAYER := 2 ## Bit value of render layer 2.
const HOSTILE := 4 ## Layer 3: enemies and their shots.
const FRIENDLY := 8 ## Layer 4: the tank and its tail.
const LOOT := 16 ## Layer 5: pickups.
const CLASSES := [HOSTILE, FRIENDLY, LOOT]


## Adds the actor layer, and `extra` class bits, to every visual under `root` (and `root` itself).
static func mark(root: Node, extra := 0) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers |= LAYER | extra
	if extra != 0 and root is MeshInstance3D and (root as MeshInstance3D).mesh:
		vivid(root as MeshInstance3D)
	for child in root.get_children():
		mark(child, extra)


## Swaps the pastel-washing default materials for their true-color versions.
static func vivid(instance: MeshInstance3D) -> void:
	for i in instance.mesh.get_surface_count():
		var material := instance.mesh.surface_get_material(i)
		if material == LowPoly.lit_material:
			instance.set_surface_override_material(i, LowPoly.vivid_lit_material)
		elif material == LowPoly.glow_material:
			instance.set_surface_override_material(i, LowPoly.vivid_glow_material)


## Removes class bits, e.g. from the wreck of a dead enemy.
static func unmark(root: Node, bits: int) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers &= ~bits
	for child in root.get_children():
		unmark(child, bits)
