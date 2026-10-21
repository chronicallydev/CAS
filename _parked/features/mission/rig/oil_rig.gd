@tool
extends Node3D

# Land drilling rig built from primitives: concrete pad, substructure,
# lattice derrick, doghouse, mud tanks, pipe rack, generators and a flare
# stack. Built in code so it also shows in the editor.

const P := preload("res://shared/props/prop_builder.gd")

# Local height of the ground surface under the rig.
@export var ground_y: float = -1.53:
	set(value):
		ground_y = value
		rebuild()
@export var derrick_height: float = 14.0:
	set(value):
		derrick_height = value
		rebuild()

var flare_light: OmniLight3D
var flare_flame: MeshInstance3D
var beacon: MeshInstance3D
var time: float = 0.0


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	if not is_inside_tree():
		return

	for child in get_children():
		child.queue_free()

	build()


func build() -> void:
	var g := ground_y

	var concrete := P.material(Color(0.62, 0.6, 0.56), 0.95)
	var steel := P.material(Color(0.32, 0.34, 0.36), 0.5, 0.6)
	var derrick_red := P.material(Color(0.78, 0.22, 0.12), 0.6, 0.3)
	var derrick_white := P.material(Color(0.88, 0.88, 0.85), 0.6, 0.2)
	var yellow := P.material(Color(0.95, 0.72, 0.12), 0.6, 0.2)
	var cabin_white := P.material(Color(0.86, 0.87, 0.85), 0.7)
	var cabin_blue := P.material(Color(0.2, 0.36, 0.6), 0.6)
	var glass := P.material(Color(0.15, 0.22, 0.3), 0.15, 0.5)
	var tank_green := P.material(Color(0.36, 0.45, 0.36), 0.7, 0.2)
	var pipe_grey := P.material(Color(0.5, 0.5, 0.48), 0.4, 0.7)

	# Concrete pad.
	P.box(self, Vector3(10.0, 0.3, 10.0), Vector3(0, g + 0.15, 0), concrete)

	# Substructure: legs, bracing and the drill floor.
	var floor_y := g + 3.5
	for x in [-2.2, 2.2]:
		for z in [-2.2, 2.2]:
			P.box(self, Vector3(0.5, 3.2, 0.5), Vector3(x, g + 1.9, z), steel)
	for z in [-2.2, 2.2]:
		P.beam(self, Vector3(-2.2, g + 0.5, z), Vector3(2.2, floor_y - 0.3, z), 0.2, steel)
	for x in [-2.2, 2.2]:
		P.beam(self, Vector3(x, g + 0.5, -2.2), Vector3(x, floor_y - 0.3, 2.2), 0.2, steel)
	P.box(self, Vector3(6.0, 0.4, 6.0), Vector3(0, floor_y, 0), steel)
	P.box(self, Vector3(6.2, 0.12, 6.2), Vector3(0, floor_y + 0.26, 0), yellow)

	# Railings around the drill floor.
	var rail_y := floor_y + 1.2
	for i in 4:
		var a := Vector3(-3.0, rail_y, -3.0).rotated(Vector3.UP, i * PI / 2.0)
		var b := Vector3(3.0, rail_y, -3.0).rotated(Vector3.UP, i * PI / 2.0)
		P.beam(self, a, b, 0.08, yellow)

	# Lattice derrick tapering to the crown.
	build_derrick(floor_y + 0.3, derrick_red, derrick_white)

	var top_y := floor_y + 0.3 + derrick_height

	# Crown block, travelling block and drill line.
	P.box(self, Vector3(1.8, 0.8, 1.8), Vector3(0, top_y + 0.4, 0), yellow)
	P.cylinder(self, 0.03, derrick_height * 0.55, Vector3(0, top_y - derrick_height * 0.275, 0), steel)
	P.box(self, Vector3(0.6, 1.0, 0.4), Vector3(0, top_y - derrick_height * 0.55, 0), yellow)
	P.cylinder(self, 0.12, 2.2, Vector3(0, top_y - derrick_height * 0.55 - 1.6, 0), steel)

	# Red aviation beacon on the crown.
	beacon = P.sphere(self, 0.25, Vector3(0, top_y + 1.0, 0), P.glow_material(Color(1.0, 0.1, 0.05), 6.0))

	# Doghouse (driller's cabin) on the drill floor edge.
	P.box(self, Vector3(2.4, 2.0, 1.8), Vector3(-1.6, floor_y + 1.2, 3.6), cabin_white)
	P.box(self, Vector3(2.45, 0.5, 1.85), Vector3(-1.6, floor_y + 1.4, 3.6), glass)
	P.box(self, Vector3(2.5, 0.15, 1.9), Vector3(-1.6, floor_y + 2.25, 3.6), cabin_blue)

	# Stairs from the pad to the drill floor.
	P.beam(self, Vector3(-3.5, g + 0.3, 4.8), Vector3(-3.5, floor_y, 2.2), 0.5, steel)

	# V-door ramp (catwalk) the pipe slides up.
	P.beam(self, Vector3(0, g + 0.6, -4.8), Vector3(0, floor_y, -2.6), 1.0, steel)

	# Pipe rack beside the catwalk.
	for x in [-2.6, -1.6]:
		for z in [-4.6, -3.0]:
			P.box(self, Vector3(0.2, 0.8, 0.2), Vector3(x, g + 0.7, z), steel)
	for i in 6:
		var px := -2.9 + i * 0.32
		P.pipe(self, Vector3(px, g + 1.2, -4.9), Vector3(px, g + 1.2, -2.7), 0.13, pipe_grey)

	# Mud tanks with a walkway on top.
	for i in 2:
		var z := -1.5 + i * 2.3
		P.box(self, Vector3(2.0, 1.8, 2.1), Vector3(3.9, g + 1.2, z), tank_green)
	P.box(self, Vector3(2.2, 0.1, 4.6), Vector3(3.9, g + 2.15, -0.35), yellow)

	# Generators.
	for i in 2:
		var x := -4.0 + i * 1.6
		P.box(self, Vector3(1.3, 1.3, 2.4), Vector3(x, g + 0.95, -0.4), yellow)
		P.cylinder(self, 0.12, 0.8, Vector3(x + 0.3, g + 2.0, -1.2), steel)

	# Flare stack with a burning flame.
	var flare_pos := Vector3(-4.3, g, -4.3)
	P.cylinder(self, 0.18, 7.5, flare_pos + Vector3(0, 3.75, 0), derrick_white)
	P.cylinder(self, 0.22, 0.8, flare_pos + Vector3(0, 1.0, 0), derrick_red)
	P.cylinder(self, 0.22, 0.8, flare_pos + Vector3(0, 5.5, 0), derrick_red)

	var flame_mat := P.glow_material(Color(1.0, 0.55, 0.15), 5.0)
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.6, 0.2)
	flare_flame = P.sphere(self, 0.55, flare_pos + Vector3(0, 8.2, 0), flame_mat, Vector3(1.0, 1.8, 1.0))
	flare_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	flare_light = OmniLight3D.new()
	flare_light.light_color = Color(1.0, 0.6, 0.25)
	flare_light.light_energy = 2.0
	flare_light.omni_range = 12.0
	flare_light.position = flare_pos + Vector3(0, 8.5, 0)
	add_child(flare_light)


func build_derrick(base_y: float, leg_mat: Material, brace_mat: Material) -> void:
	var base_half := 2.0
	var top_half := 0.55
	var sections := 7

	# Corner of the derrick at height fraction t (0 = floor, 1 = crown).
	var corner := func(i: int, t: float) -> Vector3:
		var half: float = lerpf(base_half, top_half, t)
		var signs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		return Vector3(signs[i].x * half, base_y + t * derrick_height, signs[i].y * half)

	for i in 4:
		P.beam(self, corner.call(i, 0.0), corner.call(i, 1.0), 0.28, leg_mat)

	for s in sections + 1:
		var t0 := float(s) / sections
		for i in 4:
			var j := (i + 1) % 4
			P.beam(self, corner.call(i, t0), corner.call(j, t0), 0.14, brace_mat)

			if s < sections:
				var t1 := float(s + 1) / sections
				# Diagonals alternate direction each section.
				if s % 2 == 0:
					P.beam(self, corner.call(i, t0), corner.call(j, t1), 0.09, brace_mat)
				else:
					P.beam(self, corner.call(j, t0), corner.call(i, t1), 0.09, brace_mat)


func _process(delta: float) -> void:
	time += delta

	# Flickering flare.
	if flare_flame != null and is_instance_valid(flare_flame):
		var flicker := 1.0 + sin(time * 13.0) * 0.08 + sin(time * 7.3) * 0.06
		flare_flame.scale = Vector3(1.0, 1.8 * flicker, 1.0) * (0.95 + 0.05 * sin(time * 21.0))
	if flare_light != null and is_instance_valid(flare_light):
		flare_light.light_energy = 2.0 + sin(time * 11.0) * 0.4

	# Blinking aviation beacon.
	if beacon != null and is_instance_valid(beacon):
		beacon.visible = fmod(time, 1.5) < 0.75
