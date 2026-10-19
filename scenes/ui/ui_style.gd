extends RefCounted

# Shared UI look: the Monogram pixel font (also the project's default
# theme font), font sizes snapped to its pixel grid, and dark gradient
# panels with a thin border.

const FONT := preload("res://assets/fonts/monogram.ttf")

const PANEL_TOP := Color(0.15, 0.16, 0.17, 0.93)
const PANEL_BOTTOM := Color(0.05, 0.06, 0.07, 0.95)
const PANEL_BORDER := Color(0.62, 0.56, 0.44, 0.38)
const GOLD := Color(0.88, 0.68, 0.34)


# Monogram is drawn on an 8px grid; anything else gives uneven pixels. It
# also reads smaller than most fonts, so sizes are scaled up a little.
static func px(size: float) -> int:
	return maxi(16, roundi(size * 1.3 / 8.0) * 8)


static var _panel_textures: Dictionary = {}


# A vertical gradient panel with a 1px border, as a 9-slice texture. The
# texture is wide so filtering doesn't smear the border into the fill.
static func gradient_panel(top: Color = PANEL_TOP, bottom: Color = PANEL_BOTTOM, border: Color = PANEL_BORDER, margin: float = 12.0) -> StyleBoxTexture:
	var key := [top, bottom, border]
	if not _panel_textures.has(key):
		var width := 256
		var height := 128
		var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
		for y in height:
			var fill := top.lerp(bottom, float(y) / (height - 1))
			image.fill_rect(Rect2i(0, y, width, 1), fill)
			image.set_pixel(0, y, fill.blend(border))
			image.set_pixel(width - 1, y, fill.blend(border))
		image.fill_rect(Rect2i(0, 0, width, 1), top.blend(border))
		image.fill_rect(Rect2i(0, height - 1, width, 1), bottom.blend(border))
		_panel_textures[key] = ImageTexture.create_from_image(image)

	var style := StyleBoxTexture.new()
	style.texture = _panel_textures[key]
	style.set_texture_margin_all(1)
	style.set_content_margin_all(margin)
	return style


# Horizontal strip that fades out to the sides (for section headers).
static func header_line(color: Color = PANEL_BORDER) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 1
	var line := TextureRect.new()
	line.texture = texture
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
