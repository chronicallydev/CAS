class_name RunUpgrades
extends RefCounted

# The upgrades offered between stretches of a run. Placeholders for now
# (a proper set is still to be designed): small stat bumps to the
# helicopter, the minigun and the chain dodge. Each is
# {id, name, text}; apply() makes it happen.
#
# The chain dodge's tuning is static (ChainDodge), so a run snapshots it
# at the start and restores it (save_defaults / restore_defaults).

const LIST := [
	{"id": "repair", "name": "REPAIR", "text": "Patch up 50 hull"},
	{"id": "plating", "name": "PLATING", "text": "+34 max hull\n(and patch it)"},
	{"id": "extra_dash", "name": "EXTRA DASH", "text": "+1 dash charge"},
	{"id": "quick_dash", "name": "QUICK DASH", "text": "Dashes recharge\n25% faster"},
	{"id": "focus", "name": "FOCUS", "text": "Perfect dodge window\n+0.08s"},
	{"id": "bullet_time", "name": "BULLET TIME", "text": "Slow motion lasts\n+0.4s"},
	{"id": "spin_up", "name": "SPIN UP", "text": "Minigun fires\n25% faster"},
	{"id": "coolant", "name": "COOLANT", "text": "Minigun heats up\n40% slower"},
]

static var _defaults: Dictionary = {}


## `count` different upgrades to choose from; no repair at full hull.
static func offer(mission: MissionContext, count: int = 3) -> Array:
	var heli := mission.helicopter
	var pool := LIST.filter(func(upgrade: Dictionary) -> bool:
		return upgrade.id != "repair" or heli.health < heli.max_health)
	pool.shuffle()
	return pool.slice(0, count)


static func apply(id: String, mission: MissionContext) -> void:
	var heli := mission.helicopter
	var guns := mission.guns
	match id:
		"repair":
			heal(heli, 50.0)
		"plating":
			heli.max_health += 34.0
			heli.health_bar.max_value = heli.max_health
			heal(heli, 34.0)
		"extra_dash":
			heli.dash_charges += 1
			heli.dash_charges_left += 1
		"quick_dash":
			heli.dash_cooldown *= 0.75
		"focus":
			ChainDodge.tune("perfect_window", ChainDodge.perfect_window + 0.08)
		"bullet_time":
			ChainDodge.tune("slow_time", ChainDodge.slow_time + 0.4)
		"spin_up":
			guns.minigun_rpm *= 1.25
		"coolant":
			guns.minigun_heat_time *= 1.4


static func heal(heli: Helicopter, amount: float) -> void:
	heli.health = minf(heli.health + amount, heli.max_health)
	heli.health_bar.value = heli.health


static func save_defaults() -> void:
	if _defaults.is_empty():
		for property in ["perfect_window", "slow_time"]:
			_defaults[property] = ChainDodge.tuning(property)


static func restore_defaults() -> void:
	for property in _defaults:
		ChainDodge.tune(property, _defaults[property])
