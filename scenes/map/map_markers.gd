extends Control

# Rig badges drawn over the 3D map: a hexagon with a derrick silhouette,
# pinned above each rig's tower, with its name and income or threat level.
# Drawn in 2D so they stay crisp with pixel-art rendering on.

const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Campaign := preload("res://scenes/map/campaign.gd")

const OWNED := Color(0.3, 0.85, 0.4)
const ENEMY := Color(0.9, 0.22, 0.16)
const INK := Color(0.08, 0.07, 0.06)
const RADIUS := 17.0
# Badge centre above the rig's tower top.
const LIFT := 30.0

var world: Node3D
var title_font: Font
var hovered: int = -1
var selected: int = -1
var time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func anchor(index: int) -> Vector2:
	return world.camera.unproject_position(world.rig_top(index))


func badge_centre(index: int) -> Vector2:
	return anchor(index) - Vector2(0, LIFT)


# Rig whose badge is under a screen point, or -1.
func badge_at(point: Vector2) -> int:
	for i in Campaign.RIG_ORDER.size():
		if badge_centre(i).distance_to(point) <= RADIUS + 4.0:
			return i
	return -1


static func hexagon(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 6:
		var angle := TAU * k / 6.0 - PI / 2.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _draw() -> void:
	if world == null or world.camera == null:
		return
	# Draw the selected badge last so it sits on top.
	var order: Array = range(Campaign.RIG_ORDER.size())
	if selected >= 0:
		order.erase(selected)
		order.append(selected)
	for i in order:
		draw_badge(i)
	if hovered >= 0 and hovered != selected:
		draw_hover_tag(hovered)


# "BRIEFING" tag over the hovered badge, inviting a click.
func draw_hover_tag(index: int) -> void:
	var size := UiStyle.px(13)
	var text := "BRIEFING"
	var width := title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var box := Rect2(badge_centre(index) + Vector2(-width / 2.0 - 10.0, -RADIUS - 36.0), Vector2(width + 20.0, 24.0))
	draw_rect(box, Color(0.08, 0.08, 0.09, 0.92))
	draw_rect(box, UiStyle.GOLD, false, 1.0)
	draw_string(title_font, box.position + Vector2(10, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiStyle.GOLD.lightened(0.2))


func draw_badge(index: int) -> void:
	var id: String = Campaign.RIG_ORDER[index]
	var owned := Campaign.is_owned(id)
	var attackable := Campaign.can_attack(id)
	var color := OWNED if owned else ENEMY
	if not owned and not attackable:
		color = ENEMY.darkened(0.35)

	var base := anchor(index)
	var centre := badge_centre(index)
	var radius := RADIUS * (1.15 if index == selected else 1.0)

	# Pin down to the tower.
	draw_line(centre + Vector2(0, radius - 2), base, INK, 3.0)
	draw_line(centre + Vector2(0, radius - 2), base, color.lightened(0.2), 1.5)
	draw_circle(base, 2.5, INK)

	if attackable:
		var pulse := fmod(time * 0.9, 1.0)
		draw_polyline(close(hexagon(centre, radius + 4.0 + pulse * 14.0)), Color(ENEMY, 0.8 * (1.0 - pulse)), 2.0)

	draw_colored_polygon(hexagon(centre + Vector2(0, 2), radius + 3.0), Color(0, 0, 0, 0.4))
	draw_colored_polygon(hexagon(centre, radius + 2.5), INK)
	var fill := color.lightened(0.15) if index == hovered else color
	draw_colored_polygon(hexagon(centre, radius), fill)
	draw_polyline(close(hexagon(centre, radius - 2.5)), Color(1, 1, 1, 0.25), 1.0)
	if index == selected:
		draw_polyline(close(hexagon(centre, radius + 5.5)), Color.WHITE, 2.5)

	draw_derrick(self, centre, radius / 17.0, owned)

	# Name and detail under the pin's top.
	var rig: Dictionary = Campaign.RIGS[id]
	var name_text: String = rig["name"].to_upper()
	var detail := "+$%d" % Campaign.income(id) if owned else ("ATTACK  |  LVL %d" % (rig["level"] + 1) if attackable else "LVL %d" % (rig["level"] + 1))
	draw_text_centered(name_text, centre + Vector2(radius + 8.0, 0.0), UiStyle.px(18), Color(0.98, 0.96, 0.92), false)
	draw_text_centered(detail, centre + Vector2(radius + 8.0, 15.0), UiStyle.px(13), color.lightened(0.35), false)


static func close(points: PackedVector2Array) -> PackedVector2Array:
	points.append(points[0])
	return points


# Text to the right of a badge with a dark outline.
func draw_text_centered(text: String, position: Vector2, size: int, color: Color, centered: bool) -> void:
	var width := title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := position - Vector2(width / 2.0 if centered else 0.0, 0.0)
	draw_string_outline(title_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(INK, 0.85))
	draw_string(title_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


# The derrick icon: base slab, tapered lattice tower with X bracing, a
# stepped crown and three oil drops (owned) or a flame (enemy). Static so
# the map panel can draw it too.
static func draw_derrick(canvas: CanvasItem, centre: Vector2, s: float, owned: bool) -> void:
	var o := centre + Vector2(0, 2.0 * s)
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s

	canvas.draw_rect(Rect2(p.call(-8.0, 9.0), Vector2(16.0, 2.5) * s), INK)
	var bl: Vector2 = p.call(-5.5, 9.0)
	var br: Vector2 = p.call(5.5, 9.0)
	var tl: Vector2 = p.call(-2.2, -4.0)
	var tr: Vector2 = p.call(2.2, -4.0)
	canvas.draw_line(bl, tl, INK, 1.8 * s)
	canvas.draw_line(br, tr, INK, 1.8 * s)
	canvas.draw_line(p.call(0.0, 9.0), p.call(0.0, -4.0), INK, 1.0 * s)
	# Rungs and X braces between them.
	var rungs := [9.0, 4.5, 0.5, -4.0]
	for k in rungs.size() - 1:
		var y0: float = rungs[k]
		var y1: float = rungs[k + 1]
		var w0 := lerpf(5.5, 2.2, (9.0 - y0) / 13.0)
		var w1 := lerpf(5.5, 2.2, (9.0 - y1) / 13.0)
		canvas.draw_line(p.call(-w1, y1), p.call(w1, y1), INK, 1.2 * s)
		canvas.draw_line(p.call(-w0, y0), p.call(w1, y1), INK, 0.9 * s)
		canvas.draw_line(p.call(w0, y0), p.call(-w1, y1), INK, 0.9 * s)
	# Stepped crown.
	canvas.draw_rect(Rect2(p.call(-3.2, -5.5), Vector2(6.4, 1.6) * s), INK)
	canvas.draw_rect(Rect2(p.call(-2.2, -7.0), Vector2(4.4, 1.6) * s), INK)
	canvas.draw_rect(Rect2(p.call(-1.2, -8.3), Vector2(2.4, 1.4) * s), INK)

	if owned:
		for drop in [[-4.2, -12.0, -0.6], [0.0, -13.5, 0.0], [4.2, -12.0, 0.6]]:
			var c: Vector2 = p.call(drop[0], drop[1])
			canvas.draw_set_transform(c, drop[2], Vector2(1.0, 1.7))
			canvas.draw_circle(Vector2.ZERO, 1.7 * s, INK)
			canvas.draw_set_transform(Vector2.ZERO)
	else:
		var flame := PackedVector2Array([p.call(-2.2, -8.5), p.call(-1.4, -12.5), p.call(0.0, -11.0), p.call(0.6, -14.5), p.call(2.2, -10.5), p.call(2.0, -8.5)])
		canvas.draw_colored_polygon(flame, INK)
