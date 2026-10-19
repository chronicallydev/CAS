class_name DifficultyPreset
extends Resource

## Multipliers the enemy generator applies for one difficulty setting.
## The list of presets (and their menu order) is in game_config.tres.

@export var display_name: String = "Normal"
@export var health: float = 1.0
@export var speed: float = 1.0
## Damage enemies deal (contact, shells, bullets, missiles).
@export var damage: float = 1.0
## 2.0 = enemies spawn twice as often.
@export var spawn_rate: float = 1.0
## 2.0 = difficulty levels (and wave sizes) grow twice as fast.
@export var progression: float = 1.0
