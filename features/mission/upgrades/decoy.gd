class_name Decoy
extends Node3D

# Decoy (an upgrade, see RunUpgrades): an afterimage of the helicopter left
# where a dash started. Missiles homing on the helicopter nearby chase it
# instead for a moment, then go back to the helicopter. It drifts on with a
# little of the helicopter's speed and flickers out.

const LIFETIME := 1.6
# Missiles this close to the helicopter switch to the decoy.
const RADIUS := 35.0

# Missiles read these off their target.
var dead: bool = false
var velocity: Vector3 = Vector3.ZERO
var helicopter: Helicopter
var age: float = 0.0


## Leaves a decoy where `heli` is, and pulls its nearby missiles onto it.
static func drop(heli: Helicopter) -> void:
	var decoy := Decoy.new()
	decoy.helicopter = heli
	decoy.velocity = heli.velocity * 0.3
	MissionContext.spawn_parent(heli).add_child(decoy)
	decoy.global_transform = heli.global_transform
	decoy.build(heli)
	for missile in heli.get_tree().get_nodes_in_group("aa_missiles"):
		if missile.target == heli and not missile.deflected and missile.global_position.distance_to(heli.global_position) <= RADIUS:
			missile.target = decoy


# A see-through copy of the helicopter's body: half-transparent white,
# which the 1-bit pass turns into a ghostly dither.
func build(heli: Helicopter) -> void:
	var ghost: Node3D = heli.body.duplicate()
	add_child(ghost)
	ghost.transform = heli.body.transform
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, 0.5)
	for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	age += delta
	global_position += velocity * delta
	if age > LIFETIME - 0.5:
		visible = fmod(age, 0.12) < 0.07
	if age >= LIFETIME:
		dead = true
		for missile in get_tree().get_nodes_in_group("aa_missiles"):
			if missile.target == self and is_instance_valid(helicopter):
				missile.target = helicopter
		queue_free()
