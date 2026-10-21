class_name CharacterPortrait
extends SubViewportContainer

# A character bust rendered live in 1-bit, for HUD and dialogue portraits.
# The model renders in its own small world and viewport at `resolution`,
# shaded by portrait_1bit.gdshader with ink lines from portrait_ink.gdshader,
# and is scaled up with nearest filtering by `pixel_scale`. Higher resolution
# than the game world's pixels, so a detailed sculpt keeps its face.
#
# Every part's tone comes from its material's brightness unless `tones`
# names the material; the B&W palette then only sees light and dark, so
# hair and clothes need a tone of their own to read against the skin.

const SHADE_SHADER := preload("res://shared/portrait/portrait_1bit.gdshader")
const INK_SHADER := preload("res://shared/portrait/portrait_ink.gdshader")

@export var model: PackedScene
## Size of the low-res image in pixels.
@export var resolution: Vector2i = Vector2i(160, 200)
@export var pixel_scale: int = 2
## Material name -> tone (0 black .. 1 white), overriding its brightness.
@export var tones: Dictionary = {}
## Part of the model's height to frame, from the top (1 = all of it).
@export_range(0.1, 1.0) var frame_height: float = 1.0
@export var fov: float = 22.0
## Slow side-to-side turn, degrees either way (0 = still).
@export var sway_degrees: float = 12.0
@export var sway_period: float = 6.0

var viewport: SubViewport
var camera: Camera3D
var pivot: Node3D
var ink: MeshInstance3D
# Every ShaderMaterial on the model, by material name.
var materials: Dictionary = {}
var _time: float = 0.0


func _ready() -> void:
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_detail(resolution, pixel_scale)

	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.audio_listener_enable_3d = false
	# The view is tiny, so automatic LOD would pick the coarse meshes.
	viewport.mesh_lod_threshold = 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.WHITE
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)

	pivot = Node3D.new()
	viewport.add_child(pivot)
	camera = Camera3D.new()
	camera.fov = fov
	viewport.add_child(camera)
	camera.current = true

	var material := ShaderMaterial.new()
	material.shader = INK_SHADER
	material.render_priority = -128
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.flip_faces = true
	ink = MeshInstance3D.new()
	ink.mesh = quad
	ink.material_override = material
	ink.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	camera.add_child(ink)

	if model != null:
		set_model(model)


func _process(delta: float) -> void:
	if sway_degrees <= 0.0 or pivot == null:
		return
	_time += delta
	pivot.rotation.y = deg_to_rad(sway_degrees) * sin(_time * TAU / sway_period)


func set_model(scene: PackedScene) -> void:
	for child in pivot.get_children():
		child.queue_free()
	materials.clear()
	var instance: Node3D = scene.instantiate()
	pivot.add_child(instance)

	var meshes: Array = instance.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i, shade_for(mesh.mesh.surface_get_material(i)))
	frame(instance, meshes)


## Renders at `new_resolution`, shown `new_pixel_scale` times bigger.
func set_detail(new_resolution: Vector2i, new_pixel_scale: int) -> void:
	resolution = new_resolution
	pixel_scale = new_pixel_scale
	stretch_shrink = pixel_scale
	custom_minimum_size = Vector2(resolution * pixel_scale)
	size = custom_minimum_size


## The shading material standing in for `source`, shared by every part
## painted with it.
func shade_for(source: Material) -> ShaderMaterial:
	var key := source.resource_name if source != null else ""
	if materials.has(key):
		return materials[key]
	var tone := 0.8
	var vertex_color := false
	if source is BaseMaterial3D:
		tone = source.albedo_color.get_luminance()
		vertex_color = source.vertex_color_use_as_albedo
	var material := ShaderMaterial.new()
	material.shader = SHADE_SHADER
	material.set_shader_parameter("tone", tones.get(key, tone))
	material.set_shader_parameter("use_vertex_color", vertex_color)
	materials[key] = material
	return material


## Sets a shading uniform on every part.
func set_shade(parameter: StringName, value: Variant) -> void:
	for material: ShaderMaterial in materials.values():
		material.set_shader_parameter(parameter, value)


func set_ink(parameter: StringName, value: Variant) -> void:
	ink.material_override.set_shader_parameter(parameter, value)


func set_tone(material_name: String, tone: float) -> void:
	tones[material_name] = tone
	if materials.has(material_name):
		materials[material_name].set_shader_parameter("tone", tone)


# Centres the model on the pivot and backs the camera off until the top
# `frame_height` of it fills the view.
func frame(instance: Node3D, meshes: Array) -> void:
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in meshes:
		var box: AABB = instance.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var height := bounds.size.y * frame_height
	var center := bounds.get_center()
	center.y = bounds.end.y - height * 0.5
	instance.position = -center
	var distance := height * 0.5 / tan(deg_to_rad(fov) * 0.5) * 1.05
	camera.position = Vector3(0, 0, distance + bounds.size.z * 0.5)
	camera.near = maxf(distance * 0.1, 0.01)
	camera.far = distance * 4.0 + bounds.size.z * 2.0
