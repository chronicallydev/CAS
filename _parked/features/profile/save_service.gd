class_name SaveService
extends RefCounted

## Reads and writes the player profile and settings to one ConfigFile.
##
## The file layout (sections and keys) is the same as before the refactor,
## so existing saves keep working.

const PATH := "user://settings.cfg"


## Fills `profile` and `settings` from disk. Values missing from the file
## keep what the objects already hold. Returns false when there is no save.
func load_into(profile: PlayerProfile, settings: GameSettings) -> bool:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return false

	settings.difficulty = config.get_value("game", "difficulty", settings.difficulty)
	settings.infantry_enabled = config.get_value("game", "infantry_enabled", settings.infantry_enabled)
	settings.car_enabled = config.get_value("game", "car_enabled", settings.car_enabled)
	settings.tank_enabled = config.get_value("game", "tank_enabled", settings.tank_enabled)
	settings.aa_enabled = config.get_value("game", "aa_enabled", settings.aa_enabled)
	settings.starting_level = config.get_value("game", "starting_level", settings.starting_level)
	settings.pixel_art = config.get_value("graphics", "pixel_art", settings.pixel_art)
	settings.blood = config.get_value("graphics", "blood", settings.blood)

	profile.best_score = config.get_value("records", "best_score", profile.best_score)
	profile.best_wave = config.get_value("records", "best_wave", profile.best_wave)
	profile.money = config.get_value("hangar", "money", profile.money)
	# Typed arrays are filled with assign(): saves hold untyped arrays.
	profile.owned_helis.assign(config.get_value("hangar", "owned_helis", profile.owned_helis))
	profile.selected_heli = config.get_value("hangar", "selected_heli", profile.selected_heli)
	profile.upgrades = config.get_value("hangar", "upgrades", profile.upgrades)
	profile.owned_weapons = config.get_value("hangar", "owned_weapons", profile.owned_weapons)
	profile.loadouts = config.get_value("hangar", "loadouts", profile.loadouts)
	profile.owned_rigs.assign(config.get_value("campaign", "owned_rigs", profile.owned_rigs))
	profile.rig_upgrades = config.get_value("campaign", "rig_upgrades", profile.rig_upgrades)
	return true


func save(profile: PlayerProfile, settings: GameSettings) -> void:
	var config := ConfigFile.new()
	config.set_value("game", "difficulty", settings.difficulty)
	config.set_value("game", "infantry_enabled", settings.infantry_enabled)
	config.set_value("game", "car_enabled", settings.car_enabled)
	config.set_value("game", "tank_enabled", settings.tank_enabled)
	config.set_value("game", "aa_enabled", settings.aa_enabled)
	config.set_value("game", "starting_level", settings.starting_level)
	config.set_value("graphics", "pixel_art", settings.pixel_art)
	config.set_value("graphics", "blood", settings.blood)
	config.set_value("records", "best_score", profile.best_score)
	config.set_value("records", "best_wave", profile.best_wave)
	config.set_value("hangar", "money", profile.money)
	config.set_value("hangar", "owned_helis", Array(profile.owned_helis))
	config.set_value("hangar", "selected_heli", profile.selected_heli)
	config.set_value("hangar", "upgrades", profile.upgrades)
	config.set_value("hangar", "owned_weapons", profile.owned_weapons)
	config.set_value("hangar", "loadouts", profile.loadouts)
	config.set_value("campaign", "owned_rigs", Array(profile.owned_rigs))
	config.set_value("campaign", "rig_upgrades", profile.rig_upgrades)
	config.save(PATH)
