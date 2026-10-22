class_name HitFlash
extends Node

# Retro hit flash: the whole model turns pure white (or another colour:
# black for the white 1-bit helicopter) for a couple of frames when it takes
# a hit, optionally followed by a second colour (enemies go white, then red
# in colour). Hits closer together than COOLDOWN don't restart it, so sustained
# fire makes the target flicker instead of staying lit.
# Added on demand as a child of whatever was hit (HitFlash.trigger).

# Switched from the test range's LOOK section.
static var enabled: bool = true

const DURATION := 0.06
const COOLDOWN := 0.12

# Flash colour -> its unlit material.
static var materials: Dictionary = {}

var color: Color = Color.WHITE
# Flashed in after `color` (see trigger); transparent for none.
var then_color: Color = Color.TRANSPARENT

var flash_left: float = 0.0
var cooldown_left: float = 0.0
# Flashed mesh -> its own material override, restored afterwards. (An
# overlay doesn't work: the pixel outline pass redraws the screen from a
# copy taken before overlays are drawn.)
var flashed: Dictionary = {}


## Flashes `target` in `flash_color`, then, if `then_color` is given (alpha
## above zero), in that for as long again.
static func trigger(target: Node, flash_color: Color = Color.WHITE, then_color: Color = Color.TRANSPARENT) -> void:
	if not enabled or target == null or not target.is_inside_tree():
		return
	var flash := target.get_node_or_null("HitFlash") as HitFlash
	if flash == null:
		flash = HitFlash.new()
		flash.name = "HitFlash"
		target.add_child(flash)
	if flash.cooldown_left > 0.0:
		return
	flash.color = flash_color
	flash.then_color = then_color
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
	if not materials.has(color):
		materials[color] = OneBit.solid(color)
	restore()
	for mesh: MeshInstance3D in get_parent().find_children("*", "MeshInstance3D", true, false):
		# See-through parts (the rotor disc) would turn into solid white.
		var material := mesh.get_active_material(0) as BaseMaterial3D
		# 1-bit rims stay black, or a white flash would vanish into the sand;
		# meshes tagged "no_hit_flash" (drop shadows) are left alone too.
		if mesh.visible and not mesh.has_meta("one_bit_rim") and not mesh.has_meta("no_hit_flash") and (material == null or material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED):
			flashed[mesh] = mesh.material_override
			mesh.material_override = materials[color]
	flash_left = DURATION
	# A second colour doubles the flash; the cooldown stretches with it, so
	# sustained fire still flickers.
	cooldown_left = COOLDOWN + (DURATION if then_color.a > 0.0 else 0.0)


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
		if flash_left <= 0.0 and then_color.a > 0.0:
			if not materials.has(then_color):
				materials[then_color] = OneBit.solid(then_color)
			for mesh: Variant in flashed:
				if is_instance_valid(mesh):
					mesh.material_override = materials[then_color]
			then_color = Color.TRANSPARENT
			flash_left = DURATION
		elif flash_left <= 0.0:
			restore()
