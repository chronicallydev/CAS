extends Node3D

# Burning wreck left behind by a destroyed vehicle: a charred copy of its
# meshes with fire and smoke, which sinks into the ground and disappears.

const BURNT_COLOR := Color(0.27, 0.24, 0.21)

@export var lifetime: float = 7.0
@export var sink_time: float = 1.5

var age: float = 0.0
var start_y: float = 0.0
var smoke: CPUParticles3D
var fire: CPUParticles3D


# Copy the meshes of `source` (skipping health bars and markers) into a
# charred wreck at the same place and size.
static func create_from(source: Node3D) -> Node3D:
	var wreck: Node3D = load("res://features/mission/effects/wreck.gd").new()
	# Place before adding, so _ready sees the final height.
	wreck.transform = source.global_transform
	MissionContext.spawn_parent(source).add_child(wreck)

	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = BURNT_COLOR
	burnt.roughness = 1.0

	for child in source.get_children():
		# Live smoke/fire is skipped: the wreck makes its own.
		if child is Sprite3D or child is Marker3D or child is CPUParticles3D or not child is Node3D:
			continue
		var copy: Node3D = child.duplicate()
		wreck.add_child(copy)
		for mesh in copy.find_children("*", "MeshInstance3D", true, false) + ([copy] if copy is MeshInstance3D else []):
			mesh.material_override = burnt
		# Health bars and markers can sit deeper in the tree too.
		for extra in copy.find_children("*", "Sprite3D", true, false):
			extra.queue_free()

	# Knocked askew by the blast.
	wreck.rotate_object_local(Vector3.RIGHT, randf_range(-0.12, 0.12))
	wreck.rotate_object_local(Vector3.FORWARD, randf_range(-0.15, 0.15))
	return wreck


func _ready() -> void:
	start_y = position.y
	fire = make_particles(Color(1.0, 0.55, 0.15), 24, 0.7, 1.2, 0.35, 2.0, true)
	smoke = make_particles(Color(0.25, 0.24, 0.23, 0.6), 30, 2.5, 0.8, 0.6, 4.0, false)


func make_particles(color: Color, amount: int, life: float, size: float, radius: float, rise: float, glow: bool) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = life
	particles.local_coords = false
	particles.position = Vector3(0, 1.5, 0)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * 2.0
	particles.direction = Vector3.UP
	particles.spread = 15.0
	particles.initial_velocity_min = rise * 0.6
	particles.initial_velocity_max = rise
	particles.gravity = Vector3(0, 0.5, 0)
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.2 if glow else 1.0))
	particles.scale_amount_curve = curve

	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	mesh.material = material
	particles.mesh = mesh

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = ramp

	add_child(particles)
	return particles


func _process(delta: float) -> void:
	age += delta

	# Fire dies down before the smoke does.
	if fire != null and age > lifetime * 0.6:
		fire.emitting = false

	if age > lifetime - sink_time:
		smoke.emitting = false
		var t := (age - (lifetime - sink_time)) / sink_time
		position.y = start_y - t * 2.5

	if age >= lifetime:
		queue_free()
