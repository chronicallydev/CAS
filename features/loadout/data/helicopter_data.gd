class_name HelicopterData
extends Resource

## One airframe sold in the hangar: its stats and its look.

## Saved in PlayerProfile.owned_helis / selected_heli, so don't rename ids.
@export var id: String = ""
@export var display_name: String = ""
## Short tag shown on cards: LIGHT, MEDIUM, HEAVY.
@export var weight_class: String = ""
@export_multiline var description: String = ""
@export var price: int = 0

@export_group("Flight")
## Property names match the helicopter script, so airframe upgrades can
## target them directly (see UpgradeData.target_properties).
@export var speed: float = 24.0
@export var acceleration: float = 5.0
@export var max_health: float = 100.0
@export var turn_speed: float = 6.0
## Seconds for the decoy flares to recharge after a drop.
@export var flare_cooldown: float = 8.0
## Seconds before the dash (Shift) can be used again.
@export var dash_cooldown: float = 3.0

@export_group("Weapons")
## Ids of the weapons this airframe can use (see WeaponData.id).
@export var allowed_weapons: PackedStringArray = []
## Where weapons can be mounted. The count sets how many weapons this
## airframe carries; any allowed weapon fits any slot.
@export var hardpoints: Array[HardpointData] = []
## Weapon id per hardpoint (same order, "" = empty) used the first time
## the player flies this airframe, as far as their owned weapons allow.
@export var default_loadout: PackedStringArray = []

@export_group("Look")
@export var color: Color = Color(0.33, 0.37, 0.26)
## Half-size of the cabin box (x = width, y = height, z = length).
@export var fuselage: Vector3 = Vector3(1.3, 1.15, 2.5)
@export var tail_length: float = 6.6
@export var rotor_radius: float = 4.75
@export var blades: int = 4
@export var wing_span: float = 3.8
## Two-seat stepped canopy, like an attack helicopter.
@export var tandem: bool = true
## Wheels instead of skids.
@export var wheels: bool = false
@export var model_scale: float = 1.0


## The style dictionary HeliModel.build() expects.
func style() -> Dictionary:
	return {
		"color": color, "fuselage": fuselage, "tail_length": tail_length,
		"rotor_radius": rotor_radius, "blades": blades, "wing_span": wing_span,
		"tandem": tandem, "wheels": wheels,
		"scale": model_scale,
	}
