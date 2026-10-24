extends Node

# 3D pixel-art rendering, autoloaded as "PixelArt".
#
# Whenever a scene has an active 3D camera, a second camera in a low-res
# SubViewport (sharing the same world) copies it, renders with toon shading
# and a pixel outline pass, and the result is scaled up with nearest
# filtering behind the 2D UI. With an orthographic
# camera the pixel camera is snapped to the pixel grid and the leftover
# sub-pixel offset is applied to the upscaled image, so the scene doesn't
# shimmer as the view moves. A retro colour pass on the upscaled image can
# then snap it to a limited palette with ordered dithering (RetroPalettes).
#
# It is global because it follows whichever context's camera is active.
# It holds no game state: the root context switches it on or off from
# GameSettings.pixel_art.
#
# The 2D UI goes the same way: every CanvasLayer that appears draws into a
# low-res viewport (its custom_viewport) at the same pixel size as the 3D,
# laid out in the window's usual coordinates (size_2d_override), and is
# shown scaled up with nearest filtering through the palette pass
# (ui_palette.gdshader). Input still goes through the window as before: only
# the drawing moves. Layers with the "crisp_ui" meta (the test range's dev panel) stay
# full resolution.
#
# Approach adapted from "3D Pixel Art - Tutorial" by Eduardo Schildt (MIT).

# Loaded by path, not preloaded: the full one only compiles on Forward+,
# and the web build runs Compatibility (see outline_shader).
const OUTLINE_SHADER := "res://shared/pixelart/pixel_outline.gdshader"
const OUTLINE_SHADER_COMPAT := "res://shared/pixelart/pixel_outline_compat.gdshader"
# Compatibility hands the 3D image to the palette pass brighter than
# Forward+; this darkens it back (retro_palette.gdshader's source_gamma).
const COMPAT_GAMMA := 2.6
const PALETTE_SHADER := preload("res://shared/pixelart/retro_palette.gdshader")
const UI_SHADER := preload("res://shared/pixelart/ui_palette.gdshader")

# Set by the root context from GameSettings.pixel_art.
@export var enabled: bool = true
# Height of the low-res image; the pixel size is window height / this.
@export var target_height: float = 288.0
# Draw the UI at the low resolution, in black and white (see above).
@export var pixel_ui: bool = true
# Convert every StandardMaterial3D to toon shading as it appears.
@export var toon_shading: bool = true
# Index into RetroPalettes.LIST (0 = black & white; 8 = Dusk, the look for
# now).
@export var palette: int = 8:
	set(value):
		palette = posmod(value, RetroPalettes.LIST.size())
		if palette_material != null:
			RetroPalettes.apply(palette_material, palette)
		if ui_material != null:
			RetroPalettes.apply(ui_material, palette)
# Ordered dither amount for the palette: 0 = hard bands, 1 = full step.
@export_range(0.0, 1.0) var dither: float = 0.35:
	set(value):
		dither = value
		if palette_material != null:
			palette_material.set_shader_parameter("dither", dither)

var viewport: SubViewport
var palette_material: ShaderMaterial
# The UI's own palette pass (ui_palette.gdshader), on the same palette.
var ui_material: ShaderMaterial
var pixel_camera: Camera3D
var outline: MeshInstance3D
var layer: CanvasLayer
var display: TextureRect

var pixel_size: int = 3
# Seconds the image stays inverted (see invert_flash).
var invert_left: float = 0.0
# The scene camera we're copying, and its own cull mask to restore.
var source_camera: Camera3D
var source_cull_mask: int = 0
# The low-res UI: its viewport, and the layer and rect that show it.
var ui_viewport: SubViewport
var ui_layer: CanvasLayer
var ui_display: TextureRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run after cameras have moved and shaken this frame.
	process_priority = 1000

	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.audio_listener_enable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)

	pixel_camera = Camera3D.new()
	viewport.add_child(pixel_camera)
	pixel_camera.current = true

	# Full-screen outline quad. Drawn first among transparent objects, so
	# smoke and explosions still render on top of it.
	var material := ShaderMaterial.new()
	material.shader = outline_shader()
	material.render_priority = -128
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.flip_faces = true
	outline = MeshInstance3D.new()
	outline.mesh = quad
	outline.material_override = material
	outline.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pixel_camera.add_child(outline)

	layer = CanvasLayer.new()
	layer.layer = -100
	add_child(layer)
	display = TextureRect.new()
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette_material = ShaderMaterial.new()
	palette_material.shader = PALETTE_SHADER
	display.material = palette_material
	palette = palette
	dither = dither
	if is_compatibility():
		palette_material.set_shader_parameter("source_gamma", COMPAT_GAMMA)
	layer.add_child(display)

	build_ui()
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	sync_ui()
	if invert_left > 0.0:
		invert_left -= delta
		palette_material.set_shader_parameter("invert", invert_left > 0.0)

	var camera := get_viewport().get_camera_3d()
	var active := enabled and camera != null and is_instance_valid(camera)

	if camera != source_camera or not active:
		release_source()
		if active and camera != null:
			source_camera = camera
			source_cull_mask = camera.cull_mask

	layer.visible = active
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if not active:
		return

	# The scene camera keeps working for aiming and audio, but draws nothing.
	camera.cull_mask = 0
	sync_camera(camera)


# The Compatibility renderer: what the web build runs.
func is_compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


# The outline pass for the renderer in use: Compatibility has no normal
# buffer, so it gets the silhouette-only version.
func outline_shader() -> Shader:
	return load(OUTLINE_SHADER_COMPAT if is_compatibility() else OUTLINE_SHADER)


## Inverts the whole image for `seconds`: the 1-bit way to flash the
## screen, where a coloured tint would only come out grey or dithered.
func invert_flash(seconds: float) -> void:
	invert_left = maxf(invert_left, seconds)
	palette_material.set_shader_parameter("invert", true)


## True while the palette is black and white or another monochrome set.
func is_monochrome() -> bool:
	return RetroPalettes.LIST[palette].get("lightness", false)


func release_source() -> void:
	if source_camera != null and is_instance_valid(source_camera):
		source_camera.cull_mask = source_cull_mask
	source_camera = null


func sync_camera(camera: Camera3D) -> void:
	# Work in physical window pixels: the canvas is stretched by the project's
	# content scale, so undo that on our layer to keep pixels crisp and even.
	var window := Vector2(get_window().size)
	var canvas_scale: float = window.y / get_viewport().get_visible_rect().size.y
	layer.transform = Transform2D.IDENTITY.scaled(Vector2.ONE / canvas_scale)
	pixel_size = maxi(1, roundi(window.y / target_height))

	# One extra low-res pixel on every side to hide the sub-pixel shift.
	var low := (window / pixel_size).ceil() + Vector2(2, 2)
	if Vector2i(low) != viewport.size:
		viewport.size = Vector2i(low)
	display.size = low * pixel_size

	pixel_camera.projection = camera.projection
	pixel_camera.near = camera.near
	pixel_camera.far = camera.far
	pixel_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	pixel_camera.environment = camera.environment
	pixel_camera.attributes = camera.attributes

	# How much taller the low-res image is than the window (the margin).
	var scale_y: float = low.y * pixel_size / window.y
	var shift := Vector2.ZERO
	# The camera's whole-pixel position, to pin the dither to the ground.
	var dither_offset := Vector2i.ZERO

	# Fold the camera's shake offsets into its position.
	var xform := camera.global_transform
	xform.origin += xform.basis.x * camera.h_offset + xform.basis.y * camera.v_offset

	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		pixel_camera.size = camera.size * scale_y
		# Snap to whole low-res pixels in the camera's own plane...
		var world_per_pixel: float = camera.size / (window.y / pixel_size)
		var local := xform.basis.inverse() * xform.origin
		var snapped := Vector3(
			roundf(local.x / world_per_pixel) * world_per_pixel,
			roundf(local.y / world_per_pixel) * world_per_pixel,
			local.z)
		xform.origin = xform.basis * snapped
		# ...and move the upscaled image by what was left over.
		var residual := Vector2(local.x - snapped.x, local.y - snapped.y) / world_per_pixel
		shift = Vector2(-residual.x, residual.y) * pixel_size
		# Image y runs down, the camera's y up.
		dither_offset = Vector2i(roundi(snapped.x / world_per_pixel), -roundi(snapped.y / world_per_pixel))
	else:
		pixel_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(camera.fov) * 0.5) * scale_y))

	palette_material.set_shader_parameter("dither_offset", dither_offset)
	pixel_camera.global_transform = xform
	display.position = (window - display.size) * 0.5 + shift


# --- Low-res UI -----------------------------------------------------------

func build_ui() -> void:
	ui_viewport = SubViewport.new()
	ui_viewport.transparent_bg = true
	ui_viewport.disable_3d = true
	ui_viewport.size_2d_override_stretch = true
	# Every item on whole low-res pixels (see fit_canvas).
	ui_viewport.snap_2d_transforms_to_pixel = true
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(ui_viewport)

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 120
	add_child(ui_layer)
	ui_display = TextureRect.new()
	ui_display.texture = ui_viewport.get_texture()
	ui_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui_display.stretch_mode = TextureRect.STRETCH_SCALE
	ui_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ui_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = UI_SHADER
	ui_display.material = material
	ui_material = material
	RetroPalettes.apply(ui_material, palette)
	ui_layer.add_child(ui_display)


## Canvas units per low-res UI pixel, for sizing UI to the pixel grid (see
## UiStyle.px). Always a whole number (see fit_canvas).
func ui_pixel_units() -> float:
	var window := Vector2(get_window().size)
	return ceilf(ui_pixel_size(window) / natural_scale(window) - 0.001)


# Window pixels per low-res UI pixel.
func ui_pixel_size(window: Vector2) -> int:
	return maxi(1, roundi(window.y / target_height))


# Window pixels per canvas unit as the project's stretch settings give it
# (canvas_items, expand: the base size scaled to fit, the rest added on).
func natural_scale(window: Vector2) -> float:
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	return maxf(minf(window.x / base.x, window.y / base.y), 0.001)


# A low-res UI pixel has to be a whole number of canvas units, or the pixel
# font and 1px lines fall between low-res pixels and come out with columns
# missing. The canvas is scaled (content_scale_factor) to round it up to
# the next whole number, so the UI only ever comes out a little smaller
# than laid out, never bigger than the screen.
func fit_canvas() -> void:
	var window := Vector2(get_window().size)
	var factor := 1.0
	if pixel_ui and window.y > 0.0:
		factor = ui_pixel_size(window) / (natural_scale(window) * ui_pixel_units())
	if absf(get_window().content_scale_factor - factor) > 0.0001:
		get_window().content_scale_factor = factor


# Sizes the UI viewport to the window in low-res pixels (as the 3D image),
# with its 2D laid out in the usual canvas coordinates over the same area.
func sync_ui() -> void:
	fit_canvas()
	ui_layer.visible = pixel_ui
	if not pixel_ui:
		return
	var window := Vector2(get_window().size)
	var canvas := get_viewport().get_visible_rect().size
	var canvas_scale: float = window.y / canvas.y
	ui_layer.transform = Transform2D.IDENTITY.scaled(Vector2.ONE / canvas_scale)
	var ui_pixel := maxi(1, roundi(window.y / target_height))
	var low := Vector2i((window / ui_pixel).ceil())
	if low != ui_viewport.size:
		ui_viewport.size = low
	ui_viewport.size_2d_override = Vector2i((Vector2(low) * ui_pixel / canvas_scale).round())
	ui_display.size = Vector2(low) * ui_pixel


# --- Toon materials -----------------------------------------------------

func _on_node_added(node: Node) -> void:
	if pixel_ui and node is CanvasLayer and node != layer and node != ui_layer and not node.has_meta("crisp_ui") and not node.has_meta("pixel_ui"):
		adopt_layer.call_deferred(node)
	if toon_shading and enabled and node is GeometryInstance3D:
		# Deferred, so code that builds a mesh can finish setting it up.
		convert_node.call_deferred(node)


# Moves a UI layer onto the low-res viewport. The engine only gets that
# right for a layer outside the tree (set inside, it later disconnects the
# wrong viewport), so it's taken out and put back where it was.
# Untyped: it may have been freed before this deferred call.
func adopt_layer(node: Variant) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	node.set_meta("pixel_ui", true)
	var parent: Node = node.get_parent()
	var index: int = node.get_index()
	parent.remove_child(node)
	node.custom_viewport = ui_viewport
	parent.add_child(node)
	parent.move_child(node, index)


# Untyped: the node may have been freed before this deferred call runs, and
# a freed object fails a typed parameter before is_instance_valid can run.
func convert_node(node: Variant) -> void:
	if not is_instance_valid(node):
		return

	var geometry := node as GeometryInstance3D
	toon(geometry.material_override)

	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = node.mesh
		for i in node.get_surface_override_material_count():
			toon(node.get_surface_override_material(i))
	elif node is MultiMeshInstance3D and node.multimesh != null:
		mesh = node.multimesh.mesh
	elif node is CPUParticles3D:
		mesh = node.mesh

	if mesh != null:
		for i in mesh.get_surface_count():
			toon(mesh.surface_get_material(i))
		if mesh is PrimitiveMesh:
			toon(mesh.material)


func toon(material: Material) -> void:
	var standard := material as BaseMaterial3D
	if standard == null or standard.has_meta("pixel_toon"):
		return
	standard.set_meta("pixel_toon", true)
	if standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return

	standard.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	standard.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Metal goes dark without specular; keep the painted colour instead.
	standard.metallic = 0.0
	standard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
