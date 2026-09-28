class_name DitherView
extends TextureRect
## Shows a low-resolution SubViewport through the palette dither shader, scaled with nearest filtering.

const RESOLUTION := Vector2i(480, 270)

var viewport := SubViewport.new()
## Renders only actors, unlit, over a transparent background: its alpha marks where the dither
## pass should hold back. It shares the 3D world with `viewport`.
var mask := SubViewport.new()
var _mask_camera := Camera3D.new()
var _material := ShaderMaterial.new()
var _flash := Color(0, 0, 0, 0)


func _ready() -> void:
	viewport.size = RESOLUTION
	viewport.audio_listener_enable_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.positional_shadow_atlas_size = 1024
	add_child(viewport)
	mask.size = RESOLUTION
	mask.transparent_bg = true
	mask.msaa_3d = Viewport.MSAA_DISABLED
	mask.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	mask.positional_shadow_atlas_size = 0
	mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(mask)
	_mask_camera.cull_mask = ActorLayer.LAYER
	var clear := Environment.new()
	clear.background_mode = Environment.BG_CLEAR_COLOR
	_mask_camera.environment = clear
	mask.add_child(_mask_camera)
	_mask_camera.current = true
	texture = viewport.get_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = preload("res://shaders/dither.gdshader")
	var labs := PackedVector3Array()
	var rgbs := PackedVector3Array()
	for color in Palette.ALL:
		labs.append(oklab(color))
		rgbs.append(Vector3(color.r, color.g, color.b))
	_material.set_shader_parameter("palette_lab", labs)
	_material.set_shader_parameter("palette_rgb", rgbs)
	_material.set_shader_parameter("palette_size", Palette.ALL.size())
	_material.set_shader_parameter("actor_mask", mask.get_texture())
	material = _material


func _process(delta: float) -> void:
	var camera := viewport.get_camera_3d()
	if camera:
		_mask_camera.global_transform = camera.global_transform
		_mask_camera.fov = camera.fov
		_mask_camera.near = camera.near
		_mask_camera.far = camera.far
	_material.set_shader_parameter("strength", Game.settings.dither)
	_flash.a = move_toward(_flash.a, 0.0, delta * 3.0)
	_material.set_shader_parameter("flash", _flash)


## Tints the whole screen briefly, e.g. white for a big blast or coral for a hit.
func flash(color: Color, amount: float) -> void:
	_flash = Color(color, maxf(_flash.a, amount))


static func oklab(color: Color) -> Vector3:
	var c := color.srgb_to_linear()
	var l := 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
	var m := 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
	var s := 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b
	l = pow(l, 1.0 / 3.0)
	m = pow(m, 1.0 / 3.0)
	s = pow(s, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
