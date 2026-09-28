class_name ActorLayer
## Things drawn on this render layer (the player, enemies, projectiles, pickups and flames) are
## mostly spared from dithering: a mask viewport renders only this layer and the dither pass
## reads it.

const LAYER := 2 ## Bit value of render layer 2.


## Adds the actor layer to every mesh under `root` (and `root` itself).
static func mark(root: Node) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers |= LAYER
	for child in root.get_children():
		mark(child)
