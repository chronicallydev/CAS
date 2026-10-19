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


## For contexts started directly from the editor, without the root context.
static func create_default() -> GameServices:
	return create(load(GameConfig.DEFAULT_PATH))


## Writes the profile and settings to disk.
func save() -> void:
	_save_service.save(profile, settings)


## The difficulty preset picked in the menu.
func difficulty() -> DifficultyPreset:
	var presets := config.difficulty_presets
	return presets[clampi(settings.difficulty, 0, presets.size() - 1)]
