class_name RetroPalettes
extends RefCounted

# The colour sets the retro pass (retro_palette.gdshader) can snap to.
# Each entry: name, shader mode, then either a list of sRGB hex colours
# (mode 1) or the steps per channel (mode 2). "lightness" matches on
# brightness only, for monochrome palettes (colours listed dark to light),
# and "curve" darkens the image first so the bright sand isn't all white.
#
# The game is designed as 1-bit: Black & White comes first. Dusk is the
# default for now (PixelArt.palette = 8); the rest are for comparison.
#
# A colour palette can also name its colours ("named", looked up by
# OneBit.colour; PICO-8's names otherwise), restyle units its own way
# ("ink" and "paper": [tint, brightness range, how far toward the tint];
# see OneBit.ink) and ask for a dark ground ("night"; see
# DesertEnvironment.night).

const LIST := [
	{"name": "Black & White", "mode": 1, "lightness": true, "curve": 1.4, "colors": [
		"000000", "ffffff"]},
	{"name": "Off", "mode": 0},
	{"name": "Mega Drive 512", "mode": 2, "levels": 8},
	{"name": "Endesga 32", "mode": 1, "colors": [
		"be4a2f", "d77643", "ead4aa", "e4a672", "b86f50", "733e39", "3e2731", "a22633",
		"e43b44", "f77622", "feae34", "fee761", "63c74d", "3e8948", "265c42", "193c3e",
		"124e89", "0099db", "2ce8f5", "ffffff", "c0cbdc", "8b9bb4", "5a6988", "3a4466",
		"262b44", "181425", "ff0044", "68386c", "b55088", "f6757a", "e8b796", "c28569"]},
	{"name": "PICO-8", "mode": 1, "colors": [
		"000000", "1d2b53", "7e2553", "008751", "ab5236", "5f574f", "c2c3c7", "fff1e8",
		"ff004d", "ffa300", "ffec27", "00e436", "29adff", "83769c", "ff77a8", "ffccaa"]},
	{"name": "Game Boy", "mode": 1, "lightness": true, "curve": 1.3, "colors": [
		"0f380f", "306230", "8bac0f", "9bbc0f"]},
	{"name": "Master System 64", "mode": 2, "levels": 4},
	{"name": "Grey 4", "mode": 1, "lightness": true, "curve": 1.5, "colors": [
		"000000", "555555", "aaaaaa", "ffffff"]},
	# After 20 Minutes Till Dawn: a near-black plum ground, bone white for
	# the player and what they fire, muted teal for enemies, coral for danger.
	{"name": "Dusk", "mode": 1, "night": true, "colors": [
		"140f17", "211a26", "2e2433", "433548", "5e4d5e",
		"1f3a36", "2f5248", "4a7563", "7aa08a",
		"a8968e", "d9c2b0", "f2dfcc", "fff4e6",
		"9e2f45", "e64a5f", "f58a7a"],
		"named": {
			"black": "140f17", "dark_blue": "140f17", "dark_purple": "9e2f45",
			"dark_green": "2f5248", "brown": "433548", "dark_grey": "5e4d5e",
			"light_grey": "a8968e", "white": "f2dfcc", "red": "e64a5f",
			"orange": "f58a7a", "yellow": "fff4e6", "green": "7aa08a",
			"blue": "7aa08a", "lavender": "2e2433", "pink": "f58a7a",
			"peach": "d9c2b0"},
		# Enemies go teal, light enough to read on the dark ground; the
		# player goes bone.
		"ink": ["4a7563", Vector2(0.35, 0.72), 0.85],
		"paper": ["f2dfcc", Vector2(0.82, 1.0), 0.85]},
]


## Sets the shader's uniforms for palette `index`.
static func apply(material: ShaderMaterial, index: int) -> void:
	var entry: Dictionary = LIST[index]
	material.set_shader_parameter("mode", entry.mode)
	material.set_shader_parameter("levels", float(entry.get("levels", 8)))
	material.set_shader_parameter("lightness_only", entry.get("lightness", false))
	material.set_shader_parameter("lightness_curve", entry.get("curve", 1.0))

	var rgb := PackedVector3Array()
	var lab := PackedVector3Array()
	for hex: String in entry.get("colors", []):
		var color := Color(hex)
		rgb.append(Vector3(color.r, color.g, color.b))
		lab.append(to_oklab(color))
	material.set_shader_parameter("palette_size", rgb.size())
	# Uniform arrays must be set to their full length.
	rgb.resize(32)
	lab.resize(32)
	material.set_shader_parameter("palette_rgb", rgb)
	material.set_shader_parameter("palette_lab", lab)


## Same conversion as the shader's to_oklab().
static func to_oklab(color: Color) -> Vector3:
	var c := color.srgb_to_linear()
	var l := pow(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b, 1.0 / 3.0)
	var m := pow(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b, 1.0 / 3.0)
	var s := pow(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
