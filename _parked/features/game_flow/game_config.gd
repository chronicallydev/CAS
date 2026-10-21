class_name GameConfig
extends Resource

## The game's static data in one place: what the hangar sells, the
## campaign map, the difficulty presets and the new-player defaults.
## game_config.tres is assigned to the root context in root.tscn.

const DEFAULT_PATH := "res://features/game_flow/game_config.tres"

@export var loadout_catalog: LoadoutCatalog
@export var campaign_catalog: CampaignCatalog
## In menu order; GameSettings.difficulty indexes this list.
@export var difficulty_presets: Array[DifficultyPreset] = []
## Money a new player starts with.
@export var starting_money: int = 1500
