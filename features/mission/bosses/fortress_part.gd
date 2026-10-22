class_name FortressPart
extends Building

# One of the fortress's weapons (fortress.gd): a concrete emplacement with
# its gun on top, destroyed like any building (staged damage, collapse).
# Always a marked target, and in "deflect_targets", so missiles you dodge
# back go for it. The fortress decides when it fires; the part only keeps
# its gun on the helicopter and says where shots leave from.
#   sam   - a launcher box of four tubes (fan salvos)
#   flak  - twin barrels (bursts of rounds)
#   heavy - one long rail (heavy rockets)

@export_enum("sam", "flak", "heavy") var weapon: String = "sam"

# Share of blast damage (deflected missiles) that gets through.
const BLAST_ARMOR := 0.5

var turret: Node3D


func _ready() -> void:
	target = true
	display_name = {"sam": "SAM BATTERY", "flak": "FLAK GUN", "heavy": "ROCKET RAIL"}.get(weapon, "EMPLACEMENT")
	super()
	add_to_group("deflect_targets")


func build_body() -> void:
	wall = P.material(Color(0.6, 0.58, 0.55), 0.95)
	var dark := P.material(Color(0.22, 0.22, 0.24), 0.9)
	var h := size.y
	# A squat bunker with a sloped glacis on the front.
	P.box(body, Vector3(size.x, h, size.z), Vector3(0, h * 0.5, 0), wall)
	P.box(body, Vector3(size.x + 0.6, 0.5, size.z + 0.6), Vector3(0, h + 0.25, 0), dark)
	P.box(body, Vector3(size.x, h * 0.6, 2.0), Vector3(0, h * 0.3, size.z * 0.5 + 0.6), wall, Vector3(-35, 0, 0))

	turret = Node3D.new()
	turret.position = Vector3(0, h + 0.5, 0)
	body.add_child(turret)
	P.cylinder(turret, size.x * 0.3, 1.0, Vector3(0, 0.5, 0), dark)
	match weapon:
		"sam":
			for x in [-0.9, 0.9]:
				for y in [1.6, 2.6]:
					P.cylinder(turret, 0.4, 4.0, Vector3(x, y, 0), wall, Vector3(-70, 0, 0))
		"flak":
			for x in [-0.6, 0.6]:
				P.cylinder(turret, 0.25, 4.5, Vector3(x, 1.6, -1.6), dark, Vector3(-60, 0, 0))
			P.box(turret, Vector3(2.4, 1.4, 2.0), Vector3(0, 1.4, 0), wall)
		"heavy":
			P.box(turret, Vector3(1.4, 1.4, 8.0), Vector3(0, 2.6, 0), dark, Vector3(-30, 0, 0))
			P.box(turret, Vector3(2.4, 0.4, 3.0), Vector3(0, 1.2, 1.0), wall)
	loose.append(turret)


func _process(delta: float) -> void:
	super(delta)
	var heli := helicopter()
	if heli == null or turret == null or not is_instance_valid(turret) or turret.get_parent() != body:
		return
	var to_heli := heli.global_position - turret.global_position
	var yaw := atan2(-to_heli.x, -to_heli.z) - global_rotation.y
	turret.rotation.y = lerp_angle(turret.rotation.y, yaw, minf(4.0 * delta, 1.0))


## Where its shots leave from: the top of the gun.
func muzzle() -> Vector3:
	if turret != null and is_instance_valid(turret):
		return turret.global_position + Vector3(0, 2.5, 0)
	return global_position + Vector3(0, size.y + 2.0, 0)


func helicopter() -> Helicopter:
	if mission == null or mission.helicopter == null or mission.helicopter.dead:
		return null
	return mission.helicopter


# Reinforced against blasts: a deflected missile does half, so a part
# takes two, not one.
func take_damage(amount: float, light_weapon: bool = false) -> bool:
	return super(amount if light_weapon else amount * BLAST_ARMOR, light_weapon)


func collapse() -> void:
	remove_from_group("deflect_targets")
	super()
