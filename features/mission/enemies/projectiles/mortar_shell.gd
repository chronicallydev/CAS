extends Node3D

# Mortar shell, for show only (its danger zone does the damage). It shoots
# up out of the tube and out of sight, then drops into the zone's marker,
# landing exactly as the zone goes off.

var zone: Node3D
var rise_speed: float = 70.0
var rise_time: float = 0.35
# The last stretch of the fall, timed to end at the zone's impact.
var fall_time: float = 0.4
var fall_height: float = 28.0

var age: float = 0.0
var falling: bool = false
var model: Node3D


func _ready() -> void:
	model = Node3D.new()
	add_child(model)
	var body := MeshInstance3D.new()
	# 1-bit: solid black with a white rim like all enemy fire, and about
	# twice life size so it's more than a pixel or two.
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.5
	mesh.material = OneBit.solid(Color.BLACK)
	body.mesh = mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(body)
	OneBit.rim(model, Color.WHITE, 0.2)


func _physics_process(delta: float) -> void:
	age += delta
	if not is_instance_valid(zone) or zone.done:
		queue_free()
		return

	if not falling:
		if age < rise_time:
			global_position += Vector3.UP * rise_speed * delta
		else:
			model.visible = false
		if zone.time_left <= fall_time:
			falling = true
			model.visible = true
		return

	var t := clampf(1.0 - zone.time_left / fall_time, 0.0, 1.0)
	# Into the drawn square, which is where it looks like it lands.
	global_position = zone.marker_position() + Vector3.UP * lerpf(fall_height, 0.3, t * t)
