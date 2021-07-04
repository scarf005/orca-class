extends Node

const MAPSTART := Vector2(0, 0)
const MAPSIZE := Vector2(40, 30)
const ATLASSIZE := Vector2(16, 16)

const TILESIZE := Vector2(32, 32)
const TILES := {  # TODO: JSON support
	"peak": {"t": 70, "p": Vector2(2, 11)},
	"dune": {"t": 55, "p": Vector2(1, 11)},
	"plain": {"t": 0, "p": Vector2(0, 11)}
}
