extends Sprite3D
class_name HealthBar

# A health bar floating in the 3D world: a 2D ProgressBar rendered into a
# SubViewport and shown on this sprite. Used by the rig and by vehicles
# and forts; their scripts call update_health() whenever health changes.
# Styled for 1-bit: a black fill in a white bar with a black border.
#
# Damage shows as a chunk: health just lost stays lit (grey in 1-bit, red
# with a colour palette) behind the fill until hits stop for LAG_DELAY,
# then drains away, so sustained fire visibly piles up. Each hit also
# jolts the bar. It stays hidden until the first damage, so untouched
# units don't add clutter, and is drawn at twice the scene's size once
# shown: small, the chunk was too thin to see.

# Seconds without a hit before the lost chunk drains, and how long it takes.
const LAG_DELAY := 0.35
const LAG_DRAIN := 0.25
# How far (texture pixels) and how long (seconds) a hit shakes the bar.
const SHAKE := 10.0
const SHAKE_TIME := 0.12

@onready var viewport: SubViewport = $SubViewport
@onready var health_bar: ProgressBar = $SubViewport/ProgressBar

# Behind the real bar: its fill is the chunk of health just lost.
var lag_bar: ProgressBar
var lag_tween: Tween
var shake_left: float = 0.0


func _ready() -> void:
	# Display the SubViewport as a 3D texture.
	texture = viewport.get_texture()

	# Make the bar fill the viewport.
	health_bar.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	health_bar.min_value = 0
	health_bar.max_value = 100
	health_bar.value = 100
	visible = false
	pixel_size *= 2.0

	# The lag bar takes the real bar's background; the real bar keeps only
	# the border, so the chunk shows through where its fill has gone.
	lag_bar = health_bar.duplicate()
	var lag_fill := StyleBoxFlat.new()
	lag_fill.bg_color = Color(0.5, 0.5, 0.5) if OneBit.mono() else OneBit.PICO.red
	lag_bar.add_theme_stylebox_override("fill", lag_fill)
	viewport.add_child(lag_bar)
	viewport.move_child(lag_bar, 0)
	var frame := (health_bar.get_theme_stylebox("background") as StyleBoxFlat).duplicate() as StyleBoxFlat
	frame.draw_center = false
	health_bar.add_theme_stylebox_override("background", frame)


func _process(delta: float) -> void:
	if shake_left <= 0.0:
		return
	shake_left -= delta
	offset = Vector2(randf_range(-SHAKE, SHAKE), randf_range(-SHAKE, SHAKE)) * 0.5 if shake_left > 0.0 else Vector2.ZERO


func update_health(current_health: float, max_health: float) -> void:
	var value := clampf(current_health, 0.0, max_health)
	# A new maximum (the first update) just sets the bar.
	var lost := is_equal_approx(max_health, health_bar.max_value) and value < health_bar.value
	health_bar.max_value = max_health
	health_bar.value = value
	lag_bar.max_value = max_health
	if not lost:
		if lag_tween != null:
			lag_tween.kill()
		lag_bar.value = value
		return
	visible = true
	shake_left = SHAKE_TIME
	# Every hit holds the chunk a little longer before it drains.
	if lag_tween != null:
		lag_tween.kill()
	lag_tween = create_tween()
	lag_tween.tween_interval(LAG_DELAY)
	lag_tween.tween_property(lag_bar, "value", value, LAG_DRAIN).set_ease(Tween.EASE_IN)

func get_health():
	return health_bar.value
