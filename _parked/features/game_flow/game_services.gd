class_name GameServices
extends RefCounted

## The services that outlive any single context, bundled so the root
## context can hand them to whichever context is open.
##
## Contexts read and change these but never own them: the root context
## creates them once at startup. A context run on its own from the editor
## (F6) builds a default bundle from the save on disk instead.

var config: GameConfig
var profile: PlayerProfile
var settings: GameSettings
var loadout: Loadout
var campaign: Campaign
var _save_service := SaveService.new()
## False for the test range's throwaway copy: save() does nothing.
var saving_enabled: bool = true


## Builds the services from `game_config` and loads the save on disk.
static func create(game_config: GameConfig) -> GameServices:
	var services := GameServices.new()
	services.config = game_config
	services.profile = PlayerProfile.create_new(game_config.starting_money,
			game_config.loadout_catalog.default_helicopter,
			game_config.loadout_catalog.starting_weapons,
			game_config.campaign_catalog.home_rig)
	services.settings = GameSettings.new()
	services._save_service.load_into(services.profile, services.settings)
	services.loadout = Loadout.new(game_config.loadout_catalog, services.profile)
	services.campaign = Campaign.new(game_config.campaign_catalog, services.profile)
	return services


## A throwaway copy for the test range: the same data and settings, but a
## profile that owns every helicopter and plenty of every weapon, and that
## is never saved. Changes there never reach the real profile.
static func create_sandbox(from: GameServices) -> GameServices:
	var services := GameServices.new()
	services.config = from.config
	services.settings = from.settings
	services.saving_enabled = false

	var real := from.profile
	var profile := PlayerProfile.new()
	profile.money = 999999
	profile.selected_heli = real.selected_heli
	profile.upgrades = real.upgrades.duplicate(true)
	profile.loadouts = real.loadouts.duplicate(true)
	profile.owned_rigs.assign(real.owned_rigs)
	for heli in from.config.loadout_catalog.helicopters:
		profile.owned_helis.append(heli.id)
	for weapon in from.config.loadout_catalog.weapons:
		profile.owned_weapons[weapon.id] = 99
	services.profile = profile
	services.loadout = Loadout.new(from.config.loadout_catalog, profile)
	services.campaign = Campaign.new(from.config.campaign_catalog, profile)
	return services


## For contexts started directly from the editor, without the root context.
static func create_default() -> GameServices:
	return create(load(GameConfig.DEFAULT_PATH))


## Writes the profile and settings to disk.
func save() -> void:
	if not saving_enabled:
		return
	_save_service.save(profile, settings)


## The difficulty preset picked in the menu.
func difficulty() -> DifficultyPreset:
	var presets := config.difficulty_presets
	return presets[clampi(settings.difficulty, 0, presets.size() - 1)]
