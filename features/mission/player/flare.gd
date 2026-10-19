extends Node3D

# A decoy flare dropped by the helicopter: a burning magnesium spark that
# falls and drifts for a couple of seconds. Homing missiles retargeted to
# it (see Helicopter.deploy_flares) chase it instead and miss.

var velocity: Vector3 = Vector3.ZERO
var gravity: float = 7.0
var lifetime: float = 2.6
var age: float = 0.0
var light: OmniLight3D
var trail: CPUParticles3D


func _ready() -> void:
	build_visuals()


# Call after adding to the tree.
func launch(from: Vector3, start_velocity: Vector3) -> void:
	global_position = from
	velocity = start_velocity


func _physics_process(delta: float) -> void:
	age += delta
	# Air drag slows the throw, then it sinks.
	velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-1.5 * delta))
	velocity.y -= gravity * delta
	global_position += velocity * delta
	# Flickers and fades as it burns out.
	light.light_energy = (1.0 - age / lifetime) * randf_range(2.0, 3.2)

	if age >= lifetime:
		if trail != null:
			trail.emitting = false
			trail.reparent(get_parent())
			get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)
		queue_free()


func build_visuals() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.92, 0.7)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	sphere.material = glow
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.omni_range = 9.0
	add_child(light)

	# Smoke and sparks left behind in world space.
	trail = CPUParticles3D.new()
	trail.amount = 50
	trail.lifetime = 1.2
	trail.local_coords = false
	trail.spread = 25.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.6
	trail.gravity = Vector3(0, 0.6, 0)
	trail.scale_amount_min = 0.7
	trail.scale_amount_max = 1.3
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var puff := SphereMesh.new()
	puff.radius = 0.25
	puff.height = 0.5
	var smoke := StandardMaterial3D.new()
	smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.albedo_color = Color(0.95, 0.93, 0.9, 0.5)
	puff.material = smoke
	trail.mesh = puff
	add_child(trail)
