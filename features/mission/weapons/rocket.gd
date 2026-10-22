extends Node3D

# Unguided rocket from the wing pods: flies straight to a point on the
# ground at a fixed speed with a smoke trail, then calls on_hit.

var target: Vector3
var speed: float = 60.0
var on_hit: Callable
var trail: CPUParticles3D


# Call after adding to the tree.
func launch(from: Vector3, to: Vector3, rocket_speed: float, hit_callback: Callable) -> void:
	global_position = from
	target = to
	speed = rocket_speed
	on_hit = hit_callback
	if from.distance_to(to) > 0.01:
		look_at(to, Vector3.UP)


func _ready() -> void:
	# The player's fire (see OneBit.ROLES), drawn about
	# twice life size so it's more than a pixel wide.
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.2
	mesh.height = 1.6
	mesh.material = OneBit.solid(OneBit.fill("player_fire"))
	body.mesh = mesh
	body.rotation_degrees.x = 90.0
	add_child(body)
	OneBit.rim(self, OneBit.rim_color("player_fire"), 0.25)

	var flame := MeshInstance3D.new()
	flame.mesh = OneBit.role_puff("fire", 0.3)
	flame.position = Vector3(0, 0, 0.95)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)

	trail = CPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.7
	trail.local_coords = false
	trail.position = Vector3(0, 0, 1.0)
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 6.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.6
	trail.gravity = Vector3(0, 0.3, 0)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.mesh = OneBit.role_puff("trail", 0.28)
	# Puffs shrink away and pop out rather than fading.
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	trail.scale_amount_curve = shrink
	add_child(trail)


func _physics_process(delta: float) -> void:
	var to_target := target - global_position
	var step := speed * delta

	if to_target.length() <= step:
		global_position = target
		arrive()
	else:
		global_position += to_target.normalized() * step


func arrive() -> void:
	if on_hit.is_valid():
		on_hit.call(target)

	# Leave the smoke trail behind to fade out.
	if trail != null and get_parent() != null:
		trail.emitting = false
		trail.reparent(get_parent())
		get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)

	queue_free()
