extends Node3D

# Tank shell: flies along an arc from start to target, then calls on_hit.

var start: Vector3
var target: Vector3
var flight_time: float = 1.2
var arc_height: float = 4.0
var on_hit: Callable
# Set before adding to the tree.
var radius: float = 0.3
var color: Color = Color(1.0, 0.85, 0.4)
# Above zero, drawn as a streak this long along its flight instead of a
# ball, so fast fire reads as a stream (for straight shots, arc_height 0).
var length: float = 0.0

var elapsed: float = 0.0


func setup(from: Vector3, to: Vector3, time: float, height: float, hit_callback: Callable) -> void:
	start = from
	target = to
	flight_time = maxf(time, 0.05)
	arc_height = height
	on_hit = hit_callback
	global_position = from


func _ready() -> void:
	var shell := MeshInstance3D.new()
	var mesh: PrimitiveMesh
	if length > 0.0:
		var box := BoxMesh.new()
		box.size = Vector3(radius * 2.0, radius * 2.0, length)
		mesh = box
	else:
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material = material
	shell.mesh = mesh
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)


func _physics_process(delta: float) -> void:
	elapsed += delta
	var t := clampf(elapsed / flight_time, 0.0, 1.0)

	var position_on_line := start.lerp(target, t)
	position_on_line.y += sin(t * PI) * arc_height
	global_position = position_on_line
	if length > 0.0 and not target.is_equal_approx(global_position):
		look_at(target, Vector3.UP if absf((target - start).normalized().y) < 0.99 else Vector3.FORWARD)

	if t >= 1.0:
		if on_hit.is_valid():
			on_hit.call(target)
		queue_free()
