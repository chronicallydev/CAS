class_name UiStyle
extends RefCounted

# Shared UI look: the Monogram pixel font (also the project's default
# theme font), font sizes snapped to its pixel grid, and dark gradient
# panels with a thin border.

const FONT := preload("res://assets/fonts/monogram.ttf")

const PANEL_TOP := Color(0.15, 0.16, 0.17, 0.93)
const PANEL_BOTTOM := Color(0.05, 0.06, 0.07, 0.95)
const PANEL_BORDER := Color(0.62, 0.56, 0.44, 0.38)
const GOLD := Color(0.88, 0.68, 0.34)


# Monogram's own size: at 16 one font pixel is one unit.
const FONT_GRID := 16.0


# Game UI is drawn at the pixel art's resolution (see PixelArt), so text is
# sized to whole low-res pixels per font pixel: anything else comes out
# mangled. Requested sizes up to ~60 get one, bigger ones (banners) two.
static func px(size: float) -> int:
	return roundi(FONT_GRID * PixelArt.ui_pixel_units() * maxi(1, roundi(size / 48.0)))


## Extra line spacing for a label at `font_size` (from px), so its later
## lines sit on the low-res pixel grid like its first: off it, every other
## line loses a row of pixels.
static func line_gap(font_size: int) -> int:
	var units := PixelArt.ui_pixel_units()
	var height := FONT.get_height(font_size)
	return roundi(ceilf(height / units - 0.001) * units - height)


## A solid black backing for HUD text, so it reads over the dithered ground
## in 1-bit.
static func plate(margin: float = 10.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.set_content_margin_all(margin)
	return style


# For full-resolution UI (the test range's dev panel): Monogram on its 8px
# grid, scaled up a little as it reads small.
static func crisp_px(size: float) -> int:
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


# 1234567 -> "1,234,567" (negative numbers keep their sign).
static func format_money(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + out
