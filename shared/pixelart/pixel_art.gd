extends Node

# 3D pixel-art rendering, autoloaded as "PixelArt".
#
# Whenever a scene has an active 3D camera, a second camera in a low-res
# SubViewport (sharing the same world) copies it, renders with toon shading
# and a pixel outline pass, and the result is scaled up with nearest
# filtering behind the 2D UI, which stays crisp. With an orthographic
# camera the pixel camera is snapped to the pixel grid and the leftover
# sub-pixel offset is applied to the upscaled image, so the scene doesn't
# shimmer as the view moves. A retro colour pass on the upscaled image can
# then snap it to a limited palette with ordered dithering (RetroPalettes).
#
# It is global because it follows whichever context's camera is active.
# It holds no game state: the root context switches it on or off from
# GameSettings.pixel_art.
#
# Approach adapted from "3D Pixel Art - Tutorial" by Eduardo Schildt (MIT).

const OUTLINE_SHADER := preload("res://shared/pixelart/pixel_outline.gdshader")
const PALETTE_SHADER := preload("res://shared/pixelart/retro_palette.gdshader")

# Set by the root context from GameSettings.pixel_art.
@export var enabled: bool = true
# Height of the low-res image; the pixel size is window height / this.
@export var target_height: float = 240.0
# Convert every StandardMaterial3D to toon shading as it appears.
@export var toon_shading: bool = true
# Index into RetroPalettes.LIST (0 = black & white, the game's look).
@export var palette: int = 0:
	set(value):
		palette = posmod(value, RetroPalettes.LIST.size())
		if palette_material != null:
			RetroPalettes.apply(palette_material, palette)
# Ordered dither amount for the palette: 0 = hard bands, 1 = full step.
@export_range(0.0, 1.0) var dither: float = 0.5:
	set(value):
		dither = value
		if palette_material != null:
			palette_material.set_shader_parameter("dither", dither)

var viewport: SubViewport
var palette_material: ShaderMaterial
var pixel_camera: Camera3D
var outline: MeshInstance3D
var layer: CanvasLayer
var display: TextureRect

var pixel_size: int = 3
# The scene camera we're copying, and its own cull mask to restore.
var source_camera: Camera3D
var source_cull_mask: int = 0


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
	material.shader = OUTLINE_SHADER
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
	layer.add_child(display)

	get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
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


# --- Toon materials -----------------------------------------------------

func _on_node_added(node: Node) -> void:
	if toon_shading and enabled and node is GeometryInstance3D:
		# Deferred, so code that builds a mesh can finish setting it up.
		convert_node.call_deferred(node)


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
