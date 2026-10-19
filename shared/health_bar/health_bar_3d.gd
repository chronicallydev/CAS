extends Sprite3D
class_name HealthBar

# A health bar floating in the 3D world: a 2D ProgressBar rendered into a
# SubViewport and shown on this sprite. Used by the rig and by vehicles
# and forts; their scripts call update_health() whenever health changes.

@onready var viewport: SubViewport = $SubViewport
@onready var health_bar: ProgressBar = $SubViewport/ProgressBar


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


func update_health(current_health: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = clampf(current_health, 0.0, max_health)

func get_health():
	return health_bar.value
