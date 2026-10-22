class_name OneBit
extends RefCounted

# Helpers for the game's 1-bit look (see retro_palettes.gd). After the
# palette pass only brightness survives, so things are told apart by how
# dark they are and by solid outlines:
#   ink   - enemies and everything they fire: near-black, so they stand
#           out from the bright dithered sand and from their own shadows
#   paper - the player and everything they fire: near-white, with black
#           rims (from the outline pass or a puff's own rim)
# Mid-tones and see-through effects turn into dither noise, so effects use
# solid puffs: a fill colour with a rim of the opposite colour.
#
# With a colour palette (PICO-8; see PixelArt.is_monochrome) the same rules
# hold in colour: units keep their hue (enemies darker, the player lighter),
# and effects take their fill and rim from ROLES instead of black and white.
# Styles are picked when a thing is built, so switching palettes mid-fight
# only reaches what's built after.

# Brightness range that ink and paper squeeze a model's colours into. Parts
# keep their relative shading, so a model still has some detail.
const INK_RANGE := Vector2(0.04, 0.2)
const PAPER_RANGE := Vector2(0.72, 1.0)
# In colour, enemies only darken to here: dark enough to stand off the
# sand, light enough to keep their hue.
const COLOUR_INK_RANGE := Vector2(0.1, 0.45)
# And the player only lightens to here, keeping its paint's hue.
const COLOUR_PAPER_RANGE := Vector2(0.6, 0.95)

# The PICO-8 palette, by name.
const PICO := {
	"black": Color("000000"), "dark_blue": Color("1d2b53"), "dark_purple": Color("7e2553"),
	"dark_green": Color("008751"), "brown": Color("ab5236"), "dark_grey": Color("5f574f"),
	"light_grey": Color("c2c3c7"), "white": Color("fff1e8"), "red": Color("ff004d"),
	"orange": Color("ffa300"), "yellow": Color("ffec27"), "green": Color("00e436"),
	"blue": Color("29adff"), "lavender": Color("83769c"), "pink": Color("ff77a8"),
	"peach": Color("ffccaa"),
}

# What each kind of effect is drawn in: [1-bit fill, 1-bit rim, colour fill,
# colour rim]. Enemy fire is red in colour, the colour the eye finds first
# on the sand; the player's stays white.
const ROLES := {
	"fire": [Color.WHITE, Color.BLACK, PICO.yellow, PICO.red],
	"smoke": [Color.BLACK, Color.WHITE, PICO.dark_grey, PICO.black],
	"dust": [Color.WHITE, Color.BLACK, PICO.peach, PICO.brown],
	"spark": [Color.WHITE, Color.BLACK, PICO.yellow, PICO.black],
	"trail": [Color.WHITE, Color.BLACK, PICO.light_grey, PICO.dark_grey],
	# A missile the player sent back.
	"deflect_trail": [Color.WHITE, Color.BLACK, PICO.yellow, PICO.orange],
	"enemy_fire": [Color.BLACK, Color.WHITE, PICO.red, PICO.black],
	"player_fire": [Color.WHITE, Color.BLACK, PICO.white, PICO.black],
	"warning": [Color.BLACK, Color.WHITE, PICO.red, PICO.white],
	# The heavy rocket, which can't be sent back: set apart from the rest.
	"heavy_fire": [Color.BLACK, Color.WHITE, PICO.dark_purple, PICO.black],
	# The solid drop shadow under enemy helicopters (no rim).
	"shadow": [Color.BLACK, Color.BLACK, PICO.dark_blue, PICO.dark_blue],
}

static var _puffs: Dictionary = {}


## True while the palette pass is black and white (or another monochrome
## set), false for a colour palette.
static func mono() -> bool:
	return PixelArt.is_monochrome()


## `role`'s fill colour (see ROLES).
static func fill(role: String) -> Color:
	return ROLES[role][0 if mono() else 2]


## `role`'s rim colour (see ROLES).
static func rim_color(role: String) -> Color:
	return ROLES[role][1 if mono() else 3]


## A puff (see puff) in `role`'s colours.
static func role_puff(role: String, radius: float = 0.5, rim_width: float = 0.3) -> ArrayMesh:
	return puff(fill(role), rim_color(role), radius, rim_width)


## Darkens every mesh under `root`: to near-black in 1-bit, a darker shade
## of its own colour otherwise.
static func ink(root: Node) -> void:
	if mono():
		_restyle(root, INK_RANGE, "one_bit_ink")
	else:
		_restyle(root, COLOUR_INK_RANGE, "colour_ink")


## Lightens every mesh under `root`: to near-white in 1-bit, a lighter
## shade of its own colour otherwise.
static func paper(root: Node) -> void:
	if mono():
		_restyle(root, PAPER_RANGE, "one_bit_paper")
	else:
		_restyle(root, COLOUR_PAPER_RANGE, "colour_paper")


static func _restyle(root: Node, span: Vector2, tag: String) -> void:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mesh: MeshInstance3D in meshes:
		_squeeze(mesh.material_override, span, tag)
		for i in mesh.get_surface_override_material_count():
			_squeeze(mesh.get_surface_override_material(i), span, tag)
		if mesh.mesh != null:
			for i in mesh.mesh.get_surface_count():
				_squeeze(mesh.mesh.surface_get_material(i), span, tag)


# Materials can be shared between copies of a model, so each is squeezed
# once and tagged.
static func _squeeze(material: Material, span: Vector2, tag: String) -> void:
	var standard := material as BaseMaterial3D
	# Unlit parts (glows, the hit flash's white) are already what they mean
	# to be; see-through ones would only dither.
	if standard == null or standard.has_meta(tag) or standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			or standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	standard.set_meta(tag, true)
	var color := standard.albedo_color
	var brightness := maxf(color.get_luminance(), 0.01)
	var target := lerpf(span.x, span.y, brightness)
	standard.albedo_color = Color(
		clampf(color.r * target / brightness, 0.0, 1.0),
		clampf(color.g * target / brightness, 0.0, 1.0),
		clampf(color.b * target / brightness, 0.0, 1.0), color.a)


## Gives every solid mesh under `root` a `width`-thick rim of `color`: a
## slightly bigger copy behind it, drawn inside out so only the edge shows.
## For the player's white helicopter, which the thin outline-pass line
## alone doesn't separate from bright sand. Rims are tagged "one_bit_rim"
## (the hit flash leaves them alone).
static func rim(root: Node, color: Color = Color.BLACK, width: float = 0.3) -> void:
	var material := solid(color)
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var surface := mesh.get_active_material(0) as BaseMaterial3D
		if mesh.mesh == null or mesh.has_meta("one_bit_rim") or (surface != null and surface.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
			continue
		var box := mesh.mesh.get_aabb()
		var shell := MeshInstance3D.new()
		shell.set_meta("one_bit_rim", true)
		shell.mesh = mesh.mesh
		shell.material_override = material
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Grow by `width` on every side, around the mesh's own centre.
		var grow := (box.size + Vector3.ONE * width * 2.0) / box.size.max(Vector3.ONE * 0.001)
		var centre := box.get_center()
		shell.scale = grow
		shell.position = centre - centre * grow
		mesh.add_child(shell)


## A low-poly ball of `fill` inside a rim of `rim`, as one mesh, so particle
## systems can emit outlined puffs. `rim_width` is a fraction of the radius.
## Cached: puffs with the same colours share a mesh.
static func puff(fill: Color, rim: Color, radius: float = 0.5, rim_width: float = 0.3) -> ArrayMesh:
	var key := "%s %s %s %s" % [fill, rim, radius, rim_width]
	if _puffs.has(key):
		return _puffs[key]
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, solid(fill))
	# The rim: the same ball, bigger and drawn inside out, so only the edge
	# around the fill shows.
	var rim_arrays := arrays.duplicate()
	var vertices: PackedVector3Array = rim_arrays[Mesh.ARRAY_VERTEX].duplicate()
	for i in vertices.size():
		vertices[i] *= 1.0 + rim_width
	rim_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rim_arrays)
	var rim_material := solid(rim)
	rim_material.cull_mode = BaseMaterial3D.CULL_FRONT
	mesh.surface_set_material(1, rim_material)
	_puffs[key] = mesh
	return mesh


## An opaque, unlit material: stays exactly black or white through the
## palette pass.
static func solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
