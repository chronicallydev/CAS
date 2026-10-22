class_name Reticle
extends RefCounted

# The gun reticle, drawn in code as 1-bit pixel art: white shapes with a
# solid black outline, so it reads over white sand, black enemies and
# dither alike. Shown with nearest filtering at a whole-number scale.
#   normal - four crosshair arms around a gap, and a centre dot
#   locked - on an enemy helicopter: the arms pull in, and corner brackets
#            close round it

const SIZE := 35
const CENTER := 17


static func make(locked: bool) -> ImageTexture:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var white: Array[Vector2i] = []

	# Crosshair arms, 3 pixels thick, from the gap out.
	var gap := 4 if locked else 6
	var reach := 11 if locked else 13
	for d in range(gap, reach + 1):
		for t in range(-1, 2):
			white.append(Vector2i(CENTER + d, CENTER + t))
			white.append(Vector2i(CENTER - d, CENTER + t))
			white.append(Vector2i(CENTER + t, CENTER + d))
			white.append(Vector2i(CENTER + t, CENTER - d))
	# Centre dot.
	for x in range(-1, 2):
		for y in range(-1, 2):
			white.append(Vector2i(CENTER + x, CENTER + y))

	if locked:
		# Corner brackets, 2 pixels thick, 6 long.
		var edge := 15
		for corner in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
			for d in 6:
				for t in 2:
					white.append(Vector2i(CENTER + corner.x * (edge - d), CENTER + corner.y * (edge - t)))
					white.append(Vector2i(CENTER + corner.x * (edge - t), CENTER + corner.y * (edge - d)))

	for pixel in white:
		image.set_pixelv(pixel, Color.WHITE)
	# A black outline round every white pixel (8 neighbours).
	for pixel in white:
		for x in range(-1, 2):
			for y in range(-1, 2):
				var around := pixel + Vector2i(x, y)
				if around.x < 0 or around.y < 0 or around.x >= SIZE or around.y >= SIZE:
					continue
				if image.get_pixelv(around).a == 0.0:
					image.set_pixelv(around, Color.BLACK)
	return ImageTexture.create_from_image(image)
