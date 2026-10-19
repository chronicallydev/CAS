extends Node3D

# FAB-style free-fall bomb. It keeps the helicopter's speed when released,
# falls under gravity, tips nose-down, whistles, and calls on_hit where it
# meets the ground.

var velocity: Vector3 = Vector3.ZERO
var gravity: float = 12.0
var ground_y: float = -0.4
var on_hit: Callable


# Where a bomb dropped from `from` with `start_velocity` lands, and when.
static func predict(from: Vector3, start_velocity: Vector3, fall_gravity: float, ground: float) -> Dictionary:
	var height := maxf(from.y - ground, 0.0)
	# Solve ground = y + vy*t - g*t^2/2 for t.
	var vy := start_velocity.y
	var time := (vy + sqrt(vy * vy + 2.0 * fall_gravity * height)) / fall_gravity
	var landing := from + Vector3(start_velocity.x, 0.0, start_velocity.z) * time
	landing.y = ground
	return {"position": landing, "time": time}


func _ready() -> void:
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.3, 0.33, 0.24)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.2, 0.2)

	# Body along -Z (forward), so look_at points the nose where it's going.
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.38
	mesh.height = 2.0
	mesh.material = olive
	body.mesh = mesh
	body.rotation_degrees.x = 90.0
	add_child(body)

	# Tail fins.
	for angle in [0.0, 90.0]:
		var fin := MeshInstance3D.new()
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(1.1, 0.05, 0.45)
		fin_mesh.material = dark
		fin.mesh = fin_mesh
		fin.position = Vector3(0, 0, 0.95)
		fin.rotation_degrees.z = angle
		add_child(fin)

	# Falling whistle.
	var whistle := AudioStreamPlayer3D.new()
	whistle.stream = Sfx.get_stream("bomb_whistle")
	whistle.volume_db = Sfx.mix_db("bomb_whistle")
	whistle.unit_size = 45.0
	add_child(whistle)
	whistle.play()


func _physics_process(delta: float) -> void:
	velocity.y -= gravity * delta
	global_position += velocity * delta

	# Tip nose-down as it falls.
	if velocity.length() > 0.1:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.FORWARD
		look_at(global_position + velocity, up)

	if global_position.y <= ground_y:
		var impact := global_position
		impact.y = ground_y
		if on_hit.is_valid():
			on_hit.call(impact)
		queue_free()
