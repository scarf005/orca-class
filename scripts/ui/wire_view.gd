class_name WireView
extends SubViewport
## A tiny isolated 3D view that draws real game models as colored wireframes for the HUD, in the
## spirit of War Thunder's x-ray: the HUD shows the actual tank, rounds and guns, not drawn icons.

static var _materials := {}

var root := Node3D.new()
var camera := Camera3D.new()


func _init(view_size: Vector2i, camera_position: Vector3, look_at_point: Vector3, ortho_size: float, up := Vector3.UP) -> void:
	size = view_size
	own_world_3d = true
	transparent_bg = true
	debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	msaa_3d = Viewport.MSAA_DISABLED
	render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(root)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ortho_size
	var clear := Environment.new()
	clear.background_mode = Environment.BG_CLEAR_COLOR
	camera.environment = clear
	add_child(camera)
	camera.transform = Transform3D(Basis.looking_at(look_at_point - camera_position, up), camera_position)


func refresh() -> void:
	render_target_update_mode = SubViewport.UPDATE_ONCE


## An unlit line color shared by every view.
static func line(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		_materials[key] = material
	return _materials[key]


## Colors every mesh under `node` (the node itself included).
static func paint(node: Node, color: Color) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = line(color)
	for child in node.get_children():
		paint(child, color)


## A view holding a single mesh at the origin.
func show_mesh(mesh: Mesh, color: Color) -> MeshInstance3D:
	for child in root.get_children():
		child.queue_free()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = line(color)
	root.add_child(instance)
	refresh()
	return instance
