class_name WeaponModel
extends RefCounted

# Builds the model of a mounted weapon from primitives, at a hardpoint.
# Used by HeliModel, so the same weapons show in the hangar and in game.
#
# `mount` is a node at the hardpoint's position; the weapon is built around
# its origin with the barrel pointing along -Z. Returns a marker at the
# muzzle, where rounds, rockets and bombs leave from.

const P := preload("res://shared/props/prop_builder.gd")


static func build(mount: Node3D, weapon: WeaponData, hardpoint: HardpointData) -> Marker3D:
	var dark := P.material(Color(0.18, 0.19, 0.2), 0.5, 0.5)
	var muzzle := Marker3D.new()
	mount.add_child(muzzle)

	# Wing stations hang from a pylon under the stub wing.
	if hardpoint.kind == HardpointData.Kind.WING:
		P.box(mount, Vector3(0.08, 0.3, 0.5), Vector3(0, 0.22, 0.05), dark)

	match weapon.model:
		"turret":
			build_turret(mount, dark, muzzle)
		"minigun":
			build_minigun(mount, dark, muzzle, hardpoint.kind == HardpointData.Kind.CHIN)
		"rail":
			build_rail(mount, dark, muzzle)
		"bomb":
			build_bomb(mount, dark, muzzle)
		_:
			build_pod(mount, dark, muzzle)
	return muzzle


# 30mm chin turret: a ball with one long barrel.
static func build_turret(mount: Node3D, dark: Material, muzzle: Marker3D) -> void:
	P.sphere(mount, 0.3, Vector3.ZERO, dark)
	P.cylinder(mount, 0.07, 1.1, Vector3(0, -0.05, -0.55), dark, Vector3(90, 0, 0))
	muzzle.position = Vector3(0, -0.05, -1.1)


# Six-barrel minigun: a housing with a cluster of thin barrels.
static func build_minigun(mount: Node3D, dark: Material, muzzle: Marker3D, chin: bool) -> void:
	if chin:
		P.sphere(mount, 0.22, Vector3.ZERO, dark)
	P.cylinder(mount, 0.14, 0.6, Vector3(0, 0, -0.1), dark, Vector3(90, 0, 0))
	for k in 3:
		var angle := TAU * k / 3.0
		var offset := Vector3(cos(angle), sin(angle), 0.0) * 0.06
		P.cylinder(mount, 0.03, 0.8, offset + Vector3(0, 0, -0.75), dark, Vector3(90, 0, 0), 6)
	muzzle.position = Vector3(0, 0, -1.15)


# Javelin launch rail with a missile on it.
static func build_rail(mount: Node3D, dark: Material, muzzle: Marker3D) -> void:
	var white := P.material(Color(0.88, 0.88, 0.85), 0.6)
	var red := P.material(Color(0.8, 0.15, 0.1), 0.6)
	P.box(mount, Vector3(0.12, 0.06, 1.4), Vector3(0, 0.06, 0), dark)
	P.cylinder(mount, 0.1, 1.3, Vector3(0, -0.08, 0), white, Vector3(90, 0, 0), 10)
	P.sphere(mount, 0.1, Vector3(0, -0.08, -0.65), red, Vector3(1, 1, 1.6))
	for side in [-1.0, 1.0]:
		P.box(mount, Vector3(0.32, 0.02, 0.16), Vector3(0, -0.08, 0.55), white, Vector3(0, 0, 45 * side))
	muzzle.position = Vector3(0, -0.08, -0.85)


# Unguided rocket pod: a fat tube.
static func build_pod(mount: Node3D, dark: Material, muzzle: Marker3D) -> void:
	P.cylinder(mount, 0.22, 1.4, Vector3.ZERO, dark, Vector3(90, 0, 0))
	P.cylinder(mount, 0.16, 0.05, Vector3(0, 0, -0.71), P.material(Color(0.05, 0.05, 0.05), 0.9), Vector3(90, 0, 0))
	muzzle.position = Vector3(0, 0, -0.8)


# FAB-500 on a belly rack: a fat body, rounded nose and tail fins.
static func build_bomb(mount: Node3D, dark: Material, muzzle: Marker3D) -> void:
	var olive := P.material(Color(0.32, 0.34, 0.24), 0.7, 0.2)
	P.box(mount, Vector3(0.18, 0.15, 0.6), Vector3(0, 0.28, 0), dark)
	P.cylinder(mount, 0.26, 1.1, Vector3.ZERO, olive, Vector3(90, 0, 0))
	P.sphere(mount, 0.26, Vector3(0, 0, -0.55), olive, Vector3(1, 1, 1.4))
	for angle in [0.0, 90.0]:
		P.box(mount, Vector3(0.7, 0.03, 0.3), Vector3(0, 0, 0.65), dark, Vector3(0, 0, angle))
	muzzle.position = Vector3(0, -0.1, 0)
