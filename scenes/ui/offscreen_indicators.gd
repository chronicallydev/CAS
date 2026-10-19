extends Control

# Arrows at the screen edge pointing at enemies (and the rig) that are
# outside the view. Colour and size show the enemy type; an AA launcher
# that is locking on pulses red, and the boss gets the biggest arrow.

const UiStyle := preload("res://scenes/ui/ui_style.gd")
const MARGIN := 34.0
# Keeps bottom arrows above the hull bar and warning text.
const BOTTOM_MARGIN := 140.0

const COLORS := {
	"": Color(0.95, 0.9, 0.75), # infantry
	"CAR": Color(1.0, 0.5, 0.25),
	"TANK": Color(0.95, 0.8, 0.2),
	"SAM": Color(0.95, 0.35, 0.85),
	"BUNKER": Color(0.75, 0.75, 0.72),
	"FLAK": Color(1.0, 0.6, 0.45),
	"BOSS": Color(1.0, 0.2, 0.15),
}
const SIZES := {"": 8.0, "CAR": 11.0, "TANK": 13.0, "SAM": 13.0, "BUNKER": 15.0, "FLAK": 15.0, "BOSS": 20.0}

const RIG_COLOR := Color(0.45, 0.75, 1.0)
const DANGER := Color(1.0, 0.2, 0.15)

# The rig; also gets an arrow while off-screen.
var home: Node3D
# Seconds of "under attack" flashing left for the rig arrow.
var rig_alert: float = 0.0

var time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	time += delta
	rig_alert = maxf(rig_alert - delta, 0.0)
	queue_redraw()


# Screen point for a world position, and whether it is inside the view.
func project(camera: Camera3D, world: Vector3) -> Dictionary:
	var rect := get_viewport_rect()
	var point := camera.unproject_position(world)
	var behind := camera.is_position_behind(world)
	if behind:
		# Mirror points behind the camera so the arrow still points the right way.
		point = rect.size - point
	var on_screen := not behind and rect.grow(-4.0).has_point(point)
	return {"point": point, "on_screen": on_screen}


func is_on_screen(world: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera != null and project(camera, world)["on_screen"]


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.is_queued_for_deletion():
			continue

		var info := project(camera, enemy.global_position)
		if info["on_screen"]:
			continue

		var kind: String = enemy.get("display_name") if enemy.get("display_name") != null else ""
		var color: Color = COLORS.get(kind, COLORS[""])
		var size: float = SIZES.get(kind, 8.0)

		# A SAM that is locking on pulses red.
		var lock = enemy.get("lock_timer")
		if lock != null and lock > 0.0:
			var pulse := 0.5 + 0.5 * sin(time * 18.0)
			color = DANGER.lerp(Color.WHITE, pulse * 0.4)
			size *= 1.25 + 0.2 * pulse

		draw_arrow(info["point"], color, size)

	if home != null and is_instance_valid(home):
		var info := project(camera, home.global_position)
		if not info["on_screen"]:
			var color := RIG_COLOR
			var size := 16.0
			if rig_alert > 0.0:
				var pulse := 0.5 + 0.5 * sin(time * 14.0)
				color = DANGER.lerp(Color.WHITE, pulse * 0.3)
				size = 18.0 + 4.0 * pulse
			var tip := draw_arrow(info["point"], color, size)
			draw_label("RIG", tip, color)


# Draws an arrow on the screen edge pointing toward `target`; returns where
# its base sits (for a label).
func draw_arrow(target: Vector2, color: Color, size: float) -> Vector2:
	var rect := get_viewport_rect()
	var center := rect.size * 0.5
	var direction := (target - center)
	if direction.length() < 0.001:
		direction = Vector2.UP
	direction = direction.normalized()
	# Walk from the centre toward the target until we hit the inset border.
	var border := Rect2(Vector2(MARGIN, MARGIN), rect.size - Vector2(MARGIN * 2.0, MARGIN + BOTTOM_MARGIN))
	var to_x := INF
	if direction.x > 0.0001:
		to_x = (border.end.x - center.x) / direction.x
	elif direction.x < -0.0001:
		to_x = (border.position.x - center.x) / direction.x
	var to_y := INF
	if direction.y > 0.0001:
		to_y = (border.end.y - center.y) / direction.y
	elif direction.y < -0.0001:
		to_y = (border.position.y - center.y) / direction.y
	var tip := center + direction * minf(to_x, to_y)

	var side := direction.orthogonal()
	var base := tip - direction * size * 1.6
	var points := PackedVector2Array([tip, base + side * size, base - side * size])

	draw_colored_polygon(points, color)
	points.append(tip)
	draw_polyline(points, Color(0, 0, 0, 0.6), 2.0, true)
	return base - direction * 14.0


func draw_label(text: String, at: Vector2, color: Color) -> void:
	var font := get_theme_default_font()
	var size := UiStyle.px(16)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := at + Vector2(-width * 0.5, size * 0.35)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.7))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
