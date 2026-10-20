extends Node3D

# A pickup dropped by a kill (see pickup_dropper.gd): a glowing, spinning
# token that floats over the ground for a few seconds. Fly over it to grab
# it; the mission context applies its effect. It blinks before it fades.
#   CASH     - bonus money added to the mission's payout
#   RECHARGE - flares, dash and slam ready at once
#   FRENZY   - a few seconds of double fire rate and no reloads

enum Kind { CASH, RECHARGE, FRENZY }

const COLORS := {
	Kind.CASH: Color(0.45, 0.95, 0.45),
	Kind.RECHARGE: Color(0.45, 0.8, 1.0),
	Kind.FRENZY: Color(1.0, 0.45, 0.25),
}

var kind: Kind = Kind.CASH
# Money for CASH pickups.
var value: int = 0
var lifetime: float = 9.0
# Horizontal grab distance; generous, so a pass overhead collects it.
var collect_radius: float = 5.0

var age: float = 0.0
var token: Node3D
var mission: MissionContext


func _ready() -> void:
	mission = MissionContext.of(self)
	build_visuals()


func _physics_process(delta: float) -> void:
	age += delta
	token.rotate_y(delta * 2.5)
	token.position.y = 1.5 + sin(age * 3.0) * 0.35
	# Blink for the last few seconds.
	var left := lifetime - age
	token.visible = left > 2.5 or fmod(age, 0.3) < 0.18
	if left <= 0.0:
		queue_free()
		return

	var heli := mission.helicopter if mission != null else null
	if heli == null or heli.dead:
		return
	var offset := heli.global_position - global_position
	# Flying low reaches a little further.
	var reach := collect_radius + (2.0 if heli.is_low() else 0.0)
	if Vector2(offset.x, offset.z).length() <= reach:
		mission.collect_pickup(kind, value, global_position)
		queue_free()


func build_visuals() -> void:
	var color: Color = COLORS[kind]
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	var dark := StandardMaterial3D.new()
	dark.albedo_color = color.darkened(0.6)

	token = Node3D.new()
	# Larger than life, so it reads from cruise altitude.
	token.scale = Vector3.ONE * 1.4
	add_child(token)
	var core := MeshInstance3D.new()
	match kind:
		Kind.CASH:
			# A stack of notes.
			var box := BoxMesh.new()
			box.size = Vector3(1.6, 0.5, 1.0)
			core.mesh = box
		Kind.RECHARGE:
			var sphere := SphereMesh.new()
			sphere.radius = 0.7
			sphere.height = 1.4
			core.mesh = sphere
		_:
			var prism := PrismMesh.new()
			prism.size = Vector3(1.4, 1.4, 0.5)
			core.mesh = prism
	core.material_override = glow
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	token.add_child(core)

	# Dark ring around it so it reads against bright sand.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.1
	torus.outer_radius = 1.35
	ring.mesh = torus
	ring.material_override = dark
	ring.rotation_degrees.x = 90.0
	token.add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 6.0
	token.add_child(light)
