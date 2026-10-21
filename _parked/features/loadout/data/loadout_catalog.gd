class_name LoadoutCatalog
extends Resource

## Everything sold in the hangar. Edit loadout_catalog.tres (and the
## helicopter / weapon resources it lists) to add or rebalance items.

## In the order the hangar shows them.
@export var helicopters: Array[HelicopterData] = []
## Id of the helicopter a new player starts with (and the fallback when a
## save names one that no longer exists).
@export var default_helicopter: String = "cobra"
## In the order the hangar shows them.
@export var weapons: Array[WeaponData] = []
## Upgrades that apply to every airframe. They target helicopter
## properties, and their order sets the hangar's stat bars.
@export var airframe_upgrades: Array[UpgradeData] = []

@export_group("Weapons")
## Weapon id -> units a new player owns (existing saves get these too).
@export var starting_weapons: Dictionary = {"cannon": 1, "rockets": 2}
## Most different weapon types one loadout may mix. The first type (in
## the order of `weapons`) fires with the left mouse button, the second
## with the right.
@export var max_weapon_types: int = 2

@export_group("Pricing")
@export var max_level: int = 5
## Each level costs base_cost * (1 + level * cost_growth).
@export var cost_growth: float = 0.75
