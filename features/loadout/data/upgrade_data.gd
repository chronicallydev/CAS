class_name UpgradeData
extends Resource

## One upgrade that can be bought in the hangar, up to
## LoadoutCatalog.max_level times.
##
## Each level changes one or more properties on the helicopter or the gun
## controller (target_properties). How a level changes them is set by `mode`.

enum Mode {
	## value * (1 + per_level * level)
	MULTIPLY,
	## value + per_level * level
	ADD,
	## value / (1 + per_level * level). Used for reload times and spread,
	## where smaller is better.
	SPEED_UP,
}

## Saved in PlayerProfile.upgrades, so don't rename existing ids.
@export var id: String = ""
@export var label: String = ""
@export var mode: Mode = Mode.MULTIPLY
@export var per_level: float = 0.1
## Price of the first level; later levels cost more (see cost()).
@export var base_cost: int = 400
## Property names on the helicopter or gun controller this upgrade changes.
@export var target_properties: PackedStringArray = []

@export_group("Hangar bar")
## The stat's value before upgrades, for the hangar's stat bar. Airframe
## upgrades read the base from the HelicopterData instead.
@export var bar_base: float = 1.0
## The value that fills the bar.
@export var bar_max: float = 1.0


## 1.0 at level 0, growing by per_level each level.
func factor(level: int) -> float:
	return 1.0 + per_level * level


## `base` after `level` levels of this upgrade.
func apply(base: float, level: int) -> float:
	match mode:
		Mode.ADD:
			return base + per_level * level
		Mode.SPEED_UP:
			return base / factor(level)
		_:
			return base * factor(level)


## What the hangar bar shows: the upgraded stat, or for SPEED_UP upgrades
## the speed-up factor itself (a reload time going down reads badly as a
## shrinking bar).
func bar_value(level: int, base: float = bar_base) -> float:
	if mode == Mode.SPEED_UP:
		return factor(level)
	return apply(base, level)


## Price of the next level when `level` levels are already bought.
func cost(level: int, growth: float) -> int:
	return int(base_cost * (1.0 + level * growth))


## Applies this upgrade to every target property found on `target`.
func apply_to(target: Object, level: int) -> void:
	if level <= 0:
		return
	for property in target_properties:
		var value: Variant = target.get(property)
		if value == null:
			push_warning("Upgrade %s: %s has no property '%s'." % [id, target, property])
			continue
		var upgraded := apply(float(value), level)
		target.set(property, int(upgraded) if value is int else upgraded)
