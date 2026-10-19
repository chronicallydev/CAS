class_name HangarWorld
extends Node3D

# The 3D hangar behind the hangar UI: a rusty Quonset hut with props and
# lights, and the selected helicopter turning slowly on a painted landing
# circle, carrying the weapons mounted in the loadout. Everything is built
# from primitives in code.

const P := preload("res://shared/props/prop_builder.gd")

var turntable: Node3D
var heli_parts: Dictionary = {}


func _ready() -> void:
	build_world()


func _process(delta: float) -> void:
	turntable.rotate_y(delta * 0.25)
	if heli_parts.has("main_rotor"):
		heli_parts["main_rotor"].rotate_y(delta * 1.5)
		heli_parts["tail_rotor"].rotate_x(delta * 2.5)


func build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.08, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.7, 0.55)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var camera := Camera3D.new()
	camera.fov = 46.0
	camera.position = Vector3(8.0, 4.6, 16.0)
	add_child(camera)
	camera.look_at(Vector3(1.8, 1.7, 0))
	camera.current = true

	build_shell()
	build_props()
	build_lights()

	turntable = Node3D.new()
	add_child(turntable)
	# Painted landing circle under the helicopter.
	P.cylinder(self, 4.2, 0.02, Vector3(0, 0.01, 0), P.material(Color(0.85, 0.65, 0.15), 0.8), Vector3.ZERO, 48)
	P.cylinder(self, 3.9, 0.03, Vector3(0, 0.02, 0), P.material(Color(0.5, 0.45, 0.38), 0.95), Vector3.ZERO, 48)


# Quonset hut: a half cylinder of rusty corrugated steel with ribs.
func build_shell() -> void:
	var floor_mat := P.material(Color(0.55, 0.48, 0.4), 0.95)
	P.box(self, Vector3(34, 0.2, 44), Vector3(0, -0.1, 0), floor_mat)

	var radius := 13.0
	var length := 44.0
	var arch_mat := P.material(Color(0.5, 0.2, 0.14), 0.85, 0.3)
	arch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arch := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 48
	mesh.cap_top = false
	mesh.cap_bottom = false
	arch.mesh = mesh
	arch.material_override = arch_mat
	arch.rotation_degrees.x = 90.0
	arch.position = Vector3(0, -1.0, 0)
	add_child(arch)

	# Ribs every few metres and a back wall.
	var rib_mat := P.material(Color(0.32, 0.14, 0.1), 0.7, 0.4)
	for z in range(-20, 21, 5):
		var prev := Vector3.ZERO
		for i in 25:
			var a := PI * float(i) / 24.0
			var point := Vector3(cos(a) * (radius - 0.15), -1.0 + sin(a) * (radius - 0.15), z)
			if i > 0:
				P.beam(self, prev, point, 0.25, rib_mat)
			prev = point
	var wall_mat := P.material(Color(0.6, 0.55, 0.48), 0.9)
	P.box(self, Vector3(28, 14, 0.3), Vector3(0, 6, -21.5), wall_mat)

	# Skylights along the roof.
	var glass := P.material(Color(0.55, 0.65, 0.75), 0.2, 0.3)
	glass.emission_enabled = true
	glass.emission = Color(0.6, 0.7, 0.8)
	glass.emission_energy_multiplier = 0.6
	for z in [-14.0, -6.0, 2.0]:
		for side in [-1.0, 1.0]:
			var a: float = PI * (0.5 + side * 0.18)
			var pos: Vector3 = Vector3(cos(a) * (radius - 0.1), -1.0 + sin(a) * (radius - 0.1), z)
			var light := P.box(self, Vector3(2.4, 0.1, 3.5), pos, glass)
			light.rotation.z = a - PI * 0.5


func build_props() -> void:
	var crate := P.material(Color(0.42, 0.36, 0.22), 0.9)
	var crate_dark := P.material(Color(0.3, 0.32, 0.22), 0.9)
	var barrel := P.material(Color(0.28, 0.33, 0.25), 0.7, 0.3)
	var steel := P.material(Color(0.35, 0.36, 0.38), 0.5, 0.6)
	var white := P.material(Color(0.9, 0.9, 0.88), 0.6)
	var red := P.material(Color(0.8, 0.15, 0.1), 0.6)

	# Stacks of ammo crates.
	for i in 4:
		P.box(self, Vector3(1.6, 0.9, 1.0), Vector3(-9.5 + (i % 2) * 1.7, 0.45 + (i / 2) * 0.92, -8.0), crate if i % 3 else crate_dark)
	for i in 3:
		P.box(self, Vector3(1.2, 0.8, 0.9), Vector3(9.0, 0.4 + i * 0.82, -10.0 + i * 0.1), crate_dark)

	# Barrels.
	for i in 6:
		P.cylinder(self, 0.4, 1.1, Vector3(-10.5 + (i % 3) * 0.85, 0.55, -2.5 + (i / 3) * 0.85), barrel)

	# Missile rack like in a real hangar.
	P.box(self, Vector3(2.4, 0.15, 0.8), Vector3(-6.0, 0.6, -10.0), steel)
	for i in 4:
		var x := -6.9 + i * 0.6
		P.cylinder(self, 0.14, 2.4, Vector3(x, 1.9, -10.0), white)
		P.cylinder(self, 0.15, 0.4, Vector3(x, 3.2, -10.0), red)

	# Shelving with boxes along the back.
	for x in [3.0, 6.5]:
		for shelf in 3:
			P.box(self, Vector3(3.0, 0.08, 1.0), Vector3(x, 0.6 + shelf * 1.1, -12.0), steel)
			P.box(self, Vector3(0.7, 0.6, 0.6), Vector3(x - 0.8 + shelf * 0.5, 0.95 + shelf * 1.1, -12.0), crate)
		for side in [-1.5, 1.5]:
			P.box(self, Vector3(0.08, 3.4, 0.08), Vector3(x + side, 1.7, -12.0), steel)

	# Work lamp on a tripod.
	var lamp := Vector3(-4.5, 0, 3.5)
	for i in 3:
		var a := TAU * i / 3.0
		P.beam(self, lamp + Vector3(cos(a) * 0.6, 0, sin(a) * 0.6), lamp + Vector3(0, 1.6, 0), 0.05, steel)
	P.cylinder(self, 0.04, 1.2, lamp + Vector3(0, 2.2, 0), steel)
	P.box(self, Vector3(0.7, 0.45, 0.2), lamp + Vector3(0, 2.9, 0), steel, Vector3(-20, 30, 0))


func build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-60, -30, 0)
	add_child(sun)

	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.92, 0.8)
	spot.light_energy = 6.0
	spot.spot_range = 20.0
	spot.spot_angle = 35.0
	spot.shadow_enabled = true
	spot.position = Vector3(0, 10, 2)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	add_child(spot)

	for pos in [Vector3(-8, 6, -6), Vector3(8, 6, -6), Vector3(0, 5, 8)]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.75, 0.5)
		lamp.light_energy = 1.2
		lamp.omni_range = 14.0
		lamp.position = pos
		add_child(lamp)


# Puts `heli` on the turntable in place of the one shown before, with
# `weapons` (a WeaponData or null per hardpoint) attached.
func show_heli(heli: HelicopterData, weapons: Array) -> void:
	for child in turntable.get_children():
		child.queue_free()
	var style := heli.style()
	var holder := Node3D.new()
	# Sit the skids on the floor.
	holder.position.y = (style["fuselage"].y + 0.3) * float(style.get("scale", 1.0)) + 0.05
	turntable.add_child(holder)
	heli_parts = HeliModel.build(holder, heli, weapons)


