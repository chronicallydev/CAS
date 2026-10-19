extends Control

# The drawn tactical map: desert ground, grid, supply links and rig markers.
# Click a rig to select it; the map screen shows its details.

const Campaign := preload("res://scenes/map/campaign.gd")

signal rig_selected(id: String)

const SAND := Color(0.62, 0.52, 0.36)
const SAND_DARK := Color(0.5, 0.41, 0.28)
const GRID := Color(0.2, 0.15, 0.08, 0.16)
const OWNED := Color(0.35, 0.85, 0.45)
const TARGET := Color(0.95, 0.45, 0.12)
const ENEMY := Color(0.55, 0.16, 0.12)
const INK := Color(0.12, 0.09, 0.05)

const MARKER_RADIUS := 15.0

var selected: String = ""
var hovered: String = ""
var title_font: Font
var time: float = 0.0
# Dunes, generated once so they stay put.
var dunes: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 46:
		dunes.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.04, 0.12), rng.randf_range(0.015, 0.04), rng.randf_range(-0.5, 0.5)])


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func rig_point(id: String) -> Vector2:
	var pos: Vector2 = Campaign.RIGS[id]["pos"]
	return pos * size


func rig_at(point: Vector2) -> String:
	for id in Campaign.RIG_ORDER:
		if rig_point(id).distance_to(point) <= MARKER_RADIUS + 10.0:
			return id
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var id := rig_at(event.position)
		if id != hovered:
			hovered = id
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if id != "" else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := rig_at(event.position)
		if id != "":
			Sfx.play_2d("ui_click")
			rig_selected.emit(id)


func rig_color(id: String) -> Color:
	if Campaign.is_owned(id):
		return OWNED
	if Campaign.can_attack(id):
		return TARGET
	return ENEMY


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SAND)

	# Dunes: soft darker ellipses.
	for dune in dunes:
		var center: Vector2 = dune[0] * size
		var radius := Vector2(dune[1] * size.x, dune[2] * size.y)
		draw_set_transform(center, dune[3], radius / 40.0)
		draw_circle(Vector2.ZERO, 40.0, Color(SAND_DARK, 0.35))
	draw_set_transform(Vector2.ZERO)

	# Map grid with sector labels.
	var cell := size.x / 12.0
	var x := 0.0
	var column := 0
	while x <= size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID, 1.0)
		if column < 12:
			draw_string(title_font, Vector2(x + 4, 16), char(65 + column), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.4))
		x += cell
		column += 1
	var y := 0.0
	var row := 1
	while y <= size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 1.0)
		if y > 0.0:
			draw_string(title_font, Vector2(4, y - 4), str(row), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.4))
			row += 1
		y += cell

	# Supply links, drawn once per pair.
	for id in Campaign.RIG_ORDER:
		for link in Campaign.RIGS[id]["links"]:
			if id < link:
				draw_link(id, link)

	for id in Campaign.RIG_ORDER:
		draw_rig(id)

	# Frame.
	draw_rect(Rect2(Vector2.ZERO, size), Color(INK, 0.8), false, 3.0)


func draw_link(a: String, b: String) -> void:
	var from := rig_point(a)
	var to := rig_point(b)
	var both := Campaign.is_owned(a) and Campaign.is_owned(b)
	var frontline := Campaign.is_owned(a) != Campaign.is_owned(b)

	if both:
		draw_line(from, to, Color(OWNED.darkened(0.3), 0.9), 4.0)
		return

	# Dashed line; the front line toward an attackable rig marches.
	var color := Color(TARGET, 0.9) if frontline else Color(INK, 0.35)
	var length := from.distance_to(to)
	var direction := (to - from) / length
	if frontline and Campaign.is_owned(b):
		direction = -direction
		var swap := from
		from = to
		to = swap
	var dash := 12.0
	var offset := fmod(time * 20.0, dash * 2.0) if frontline else 0.0
	var d := -dash * 2.0 + offset
	while d < length:
		var start := maxf(d, 0.0)
		var end := minf(d + dash, length)
		if end > start:
			draw_line(from + direction * start, from + direction * end, color, 3.0)
		d += dash * 2.0


func draw_rig(id: String) -> void:
	var point := rig_point(id)
	var color := rig_color(id)
	var radius := MARKER_RADIUS

	# Pulse on rigs you can attack.
	if Campaign.can_attack(id):
		var pulse := fmod(time * 0.8, 1.0)
		draw_arc(point, radius + 4.0 + pulse * 18.0, 0.0, TAU, 32, Color(TARGET, 0.7 * (1.0 - pulse)), 2.0)

	if id == selected:
		draw_arc(point, radius + 7.0, 0.0, TAU, 32, Color.WHITE, 3.0)
	elif id == hovered:
		draw_arc(point, radius + 6.0, 0.0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)

	draw_circle(point, radius + 2.0, INK)
	draw_circle(point, radius, color)

	# Derrick icon: a lattice tower on a base with a crown block on top.
	var top := point + Vector2(0, -8)
	draw_line(point + Vector2(-6, 7), top, INK, 2.0)
	draw_line(point + Vector2(6, 7), top, INK, 2.0)
	draw_line(point + Vector2(-4.5, 3), point + Vector2(4.5, 3), INK, 1.5)
	draw_line(point + Vector2(-4.5, 3), point + Vector2(2.5, -2), INK, 1.0)
	draw_line(point + Vector2(-8, 8), point + Vector2(8, 8), INK, 2.0)
	draw_rect(Rect2(top + Vector2(-2.5, -2.5), Vector2(5, 3)), INK)

	var rig: Dictionary = Campaign.RIGS[id]
	var name_text: String = rig["name"].to_upper()
	var name_width := title_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var label_pos := point + Vector2(-name_width / 2.0, radius + 22.0)
	draw_string_outline(title_font, label_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(INK, 0.8))
	draw_string(title_font, label_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.97, 0.95, 0.9))

	var sub := "+$%d" % Campaign.income(id) if Campaign.is_owned(id) else "LVL %d" % (rig["level"] + 1)
	var sub_width := title_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var sub_pos := point + Vector2(-sub_width / 2.0, radius + 38.0)
	draw_string_outline(title_font, sub_pos, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(INK, 0.8))
	draw_string(title_font, sub_pos, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color.lightened(0.3))
