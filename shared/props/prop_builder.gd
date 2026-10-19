class_name PropBuilder
extends RefCounted

# Small helpers for building props out of primitive meshes in code.

static var _unit_box: BoxMesh


static func material(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


static func glow_material(color: Color, energy: float = 3.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func box(parent: Node, size: Vector3, position: Vector3, mat: Material, rotation_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return add_mesh(parent, mesh, position, mat, rotation_deg)


static func cylinder(parent: Node, radius: float, height: float, position: Vector3, mat: Material, rotation_deg := Vector3.ZERO, segments: int = 16) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return add_mesh(parent, mesh, position, mat, rotation_deg)


static func sphere(parent: Node, radius: float, position: Vector3, mat: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var instance := add_mesh(parent, mesh, position, mat)
	instance.scale = scale
	return instance


static func add_mesh(parent: Node, mesh: Mesh, position: Vector3, mat: Material, rotation_deg := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position
	instance.rotation_degrees = rotation_deg
	parent.add_child(instance)
	return instance


# Square beam between two points (used for lattice towers, supports, pipes).
static func beam(parent: Node, from: Vector3, to: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	if _unit_box == null:
		_unit_box = BoxMesh.new()

	var direction := to - from
	var length := direction.length()

	if length < 0.001:
		return null

	var up := Vector3.UP
	if absf(direction.normalized().dot(up)) > 0.99:
		up = Vector3.FORWARD

	var basis := Basis.looking_at(direction, up).scaled_local(Vector3(thickness, thickness, length))

	var instance := MeshInstance3D.new()
	instance.mesh = _unit_box
	instance.material_override = mat
	instance.transform = Transform3D(basis, (from + to) * 0.5)
	parent.add_child(instance)
	return instance


# Round pipe between two points.
static func pipe(parent: Node, from: Vector3, to: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var direction := to - from
	var length := direction.length()

	if length < 0.001:
		return null

	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1

	# Cylinders run along Y; rotate Y onto the pipe direction.
	var y_axis := direction / length
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length() < 0.01:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (from + to) * 0.5)
	parent.add_child(instance)
	return instance
