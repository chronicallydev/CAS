class_name HeliModel
extends RefCounted

# Builds a helicopter model from primitives, with its mounted weapons
# attached to the hardpoints. Used by the player helicopter in game and by
# the hangar preview. The airframe's look comes from HelicopterData.style();
# the nose points along -Z.
#
# `weapons` holds a WeaponData (or null for an empty hardpoint) per entry
# in heli.hardpoints.
#
# Returns {"body", "main_rotor", "tail_rotor", "muzzle", "bomb_bay",
# "muzzles"}: muzzle is a marker at the nose, and muzzles maps a weapon id
# to the muzzle markers of its mounted copies, in hardpoint order.

const P := preload("res://shared/props/prop_builder.gd")


static func build(parent: Node3D, heli: HelicopterData, weapons: Array = []) -> Dictionary:
	var style := heli.style()
	var color: Color = style.get("color", Color(0.33, 0.37, 0.26))
	var fuselage: Vector3 = style.get("fuselage", Vector3(1.3, 1.15, 2.5))
	var tail_length: float = style.get("tail_length", 6.6)
	var rotor_radius: float = style.get("rotor_radius", 4.75)
	var blades: int = style.get("blades", 4)
	var wing_span: float = style.get("wing_span", 3.8)
	var tandem: bool = style.get("tandem", true)
	var wheels: bool = style.get("wheels", false)

	var paint := P.material(color, 0.6, 0.2)
	var dark := P.material(Color(0.18, 0.19, 0.2), 0.5, 0.5)
	var glass := P.material(Color(0.12, 0.2, 0.28), 0.1, 0.6)

	var body := Node3D.new()
	body.scale = Vector3.ONE * float(style.get("scale", 1.0))
	parent.add_child(body)

	var nose_z := -fuselage.z * 0.65

	# Fuselage and cockpit glass.
	P.sphere(body, 1.0, Vector3.ZERO, paint, fuselage)
	if tandem:
		# Two stepped canopies, gunner in front.
		P.sphere(body, 1.0, Vector3(0, 0.25, nose_z), glass, Vector3(fuselage.x * 0.7, 0.75, 1.1))
		P.sphere(body, 1.0, Vector3(0, 0.55, nose_z + 1.3), glass, Vector3(fuselage.x * 0.68, 0.75, 0.9))
	else:
		# One big bubble canopy.
		P.sphere(body, 1.0, Vector3(0, 0.2, nose_z * 0.75), glass, Vector3(fuselage.x * 0.95, fuselage.y * 0.85, fuselage.z * 0.6))

	# Tail boom, fin and stabiliser.
	var tail_start := fuselage.z * 0.7
	P.beam(body, Vector3(0, 0.2, tail_start), Vector3(0, 0.55, tail_length), 0.4, paint)
	P.box(body, Vector3(0.15, 1.5, 0.9), Vector3(0, 1.15, tail_length), paint, Vector3(-15, 0, 0))
	P.box(body, Vector3(2.0, 0.1, 0.6), Vector3(0, 0.5, tail_length - 0.8), paint)

	var tail_rotor := Node3D.new()
	tail_rotor.position = Vector3(0.25, 1.1, tail_length + 0.2)
	body.add_child(tail_rotor)
	P.box(tail_rotor, Vector3(0.05, 1.8, 0.2), Vector3.ZERO, dark)
	P.box(tail_rotor, Vector3(0.05, 0.2, 1.8), Vector3.ZERO, dark)

	# Main rotor: mast, blades and a faint blur disc.
	var mast_top := fuselage.y + 0.65
	P.cylinder(body, 0.15, 0.7, Vector3(0, mast_top - 0.4, 0), dark)
	var main_rotor := Node3D.new()
	main_rotor.position = Vector3(0, mast_top, 0)
	body.add_child(main_rotor)
	for i in blades:
		var blade := P.box(main_rotor, Vector3(rotor_radius, 0.06, 0.38), Vector3(rotor_radius * 0.5, 0, 0), dark)
		blade.position = Vector3(rotor_radius * 0.5, 0, 0).rotated(Vector3.UP, TAU * i / blades)
		blade.rotation.y = TAU * i / blades

	var blur := P.material(Color(0.2, 0.2, 0.2, 0.12), 1.0)
	blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := P.cylinder(body, rotor_radius, 0.02, Vector3(0, mast_top, 0), blur, Vector3.ZERO, 32)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Landing gear.
	var belly := -fuselage.y - 0.3
	if wheels:
		for z in [nose_z * 0.8, fuselage.z * 0.35]:
			for x in ([0.0] if z < 0 else [-1.0, 1.0]):
				P.beam(body, Vector3(x * 0.8, belly + 0.6, z), Vector3(x, belly, z), 0.12, dark)
				P.cylinder(body, 0.3, 0.22, Vector3(x, belly, z), dark, Vector3(0, 0, 90))
	else:
		for x in [-0.95, 0.95]:
			P.pipe(body, Vector3(x, belly, -1.8), Vector3(x, belly, 1.6), 0.08, dark)
			P.beam(body, Vector3(x, belly, -0.9), Vector3(x * 0.6, belly + 0.75, -0.9), 0.1, dark)
			P.beam(body, Vector3(x, belly, 0.9), Vector3(x * 0.6, belly + 0.75, 0.9), 0.1, dark)

	# Stub wings (the wing hardpoints hang under them).
	if wing_span > 0.0:
		P.box(body, Vector3(wing_span, 0.12, 0.8), Vector3(0, -0.15, 0.2), paint)

	# Weapons on their hardpoints.
	var muzzles: Dictionary = {}
	for i in heli.hardpoints.size():
		var weapon: WeaponData = weapons[i] if i < weapons.size() else null
		if weapon == null:
			continue
		var hardpoint := heli.hardpoints[i]
		var mount := Node3D.new()
		mount.position = hardpoint.position
		body.add_child(mount)
		var weapon_muzzle := WeaponModel.build(mount, weapon, hardpoint)
		if not muzzles.has(weapon.id):
			muzzles[weapon.id] = []
		muzzles[weapon.id].append(weapon_muzzle)

	# The nose: where sounds play and hit marks are aimed from.
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0, -fuselage.y * 0.87, nose_z - 1.4)
	body.add_child(muzzle)

	# Just under the belly: a fallback drop point for bombs.
	var bomb_bay := Marker3D.new()
	bomb_bay.position = Vector3(0, belly + 0.2, 0.2)
	body.add_child(bomb_bay)

	return {"body": body, "main_rotor": main_rotor, "tail_rotor": tail_rotor, "muzzle": muzzle, "bomb_bay": bomb_bay, "muzzles": muzzles}
