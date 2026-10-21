class_name HitFlash
extends Node

# Retro hit flash: the whole model turns pure white for a couple of frames
# when it takes a hit. Hits closer together than COOLDOWN don't restart it,
# so sustained fire makes the target flicker instead of staying white.
# Added on demand as a child of whatever was hit (HitFlash.trigger).

# Switched from the test range's LOOK section.
static var enabled: bool = true

const DURATION := 0.06
const COOLDOWN := 0.12

static var white: StandardMaterial3D

var flash_left: float = 0.0
var cooldown_left: float = 0.0
# Flashed mesh -> its own material override, restored afterwards. (An
# overlay doesn't work: the pixel outline pass redraws the screen from a
# copy taken before overlays are drawn.)
var flashed: Dictionary = {}


static func trigger(target: Node) -> void:
	if not enabled or target == null or not target.is_inside_tree():
		return
	var flash := target.get_node_or_null("HitFlash") as HitFlash
	if flash == null:
		flash = HitFlash.new()
		flash.name = "HitFlash"
		target.add_child(flash)
	flash.start()


## Ends any flash on `target` at once, e.g. before its meshes are copied
## into a wreck or thrown off as debris.
static func clear(target: Node) -> void:
	var flash := target.get_node_or_null("HitFlash") as HitFlash
	if flash != null:
		flash.restore()


func start() -> void:
	if cooldown_left > 0.0:
		return
	if white == null:
		white = StandardMaterial3D.new()
		white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		white.albedo_color = Color.WHITE
	restore()
	for mesh: MeshInstance3D in get_parent().find_children("*", "MeshInstance3D", true, false):
		# See-through parts (the rotor disc) would turn into solid white.
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if mesh.visible and (material == null or material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED):
			flashed[mesh] = mesh.material_override
			mesh.material_override = white
	flash_left = DURATION
	cooldown_left = COOLDOWN


func restore() -> void:
	for mesh: Variant in flashed:
		if is_instance_valid(mesh):
			mesh.material_override = flashed[mesh]
	flashed.clear()
	flash_left = 0.0


func _process(delta: float) -> void:
	cooldown_left -= delta
	if flash_left > 0.0:
		flash_left -= delta
		if flash_left <= 0.0:
			restore()
