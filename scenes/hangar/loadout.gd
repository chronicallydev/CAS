extends RefCounted

# Helicopters, upgrades and prices for the hangar, and helpers that apply
# the player's purchases to the helicopter and guns at the start of a run.
# Purchases are stored on Global (money, owned_helis, selected_heli,
# upgrades) and saved with the settings.

const MAX_LEVEL := 5

# Base stats and look for each airframe.
const HELICOPTERS := {
	"littlebird": {
		"name": "Little Bird (MH-6)",
		"class": "LIGHT",
		"description": "Tiny, twitchy and quick. Darts out of a missile's path, but can't take much punishment.",
		"price": 4000,
		"speed": 31.0, "acceleration": 7.0, "health": 65.0, "turn_speed": 8.5,
		"style": {"color": Color(0.24, 0.26, 0.29), "fuselage": Vector3(1.15, 1.1, 1.7), "tail_length": 4.9,
			"rotor_radius": 4.2, "blades": 5, "wing_span": 3.0, "pods_per_side": 1, "tandem": false, "scale": 0.9},
	},
	"cobra": {
		"name": "Cobra (AH-1)",
		"class": "MEDIUM",
		"description": "Lean and lethal. The all-rounder: good speed, steady handling and a solid hull.",
		"price": 0,
		"speed": 24.0, "acceleration": 5.0, "health": 100.0, "turn_speed": 6.0,
		"style": {"color": Color(0.33, 0.37, 0.26), "fuselage": Vector3(1.3, 1.15, 2.5), "tail_length": 6.6,
			"rotor_radius": 4.75, "blades": 4, "wing_span": 3.8, "pods_per_side": 1, "tandem": true, "scale": 1.0},
	},
	"hind": {
		"name": "Hind (Mi-24)",
		"class": "HEAVY",
		"description": "A flying tank. Slow to turn and slow to stop, but shrugs off hits that would down anything else.",
		"price": 9000,
		"speed": 19.0, "acceleration": 3.4, "health": 170.0, "turn_speed": 4.5,
		"style": {"color": Color(0.47, 0.42, 0.3), "fuselage": Vector3(1.55, 1.35, 3.2), "tail_length": 7.6,
			"rotor_radius": 5.6, "blades": 5, "wing_span": 5.8, "pods_per_side": 2, "tandem": true, "wheels": true, "scale": 1.1},
	},
}
const HELI_ORDER := ["littlebird", "cobra", "hind"]

# Stat bars: [label, stat key, value that fills the bar].
const HELI_BARS := [
	["Speed", "speed", 40.0],
	["Accel", "acceleration", 10.0],
	["Hull", "health", 250.0],
	["Agility", "turn_speed", 11.0],
]

# Upgrades. Each level multiplies the stat by (1 + per_level * level), or
# adds per_level * level when "add" is true. Costs grow per level.
const UPGRADES := {
	# Airframe (applies to every helicopter).
	"speed": {"label": "Speed", "per_level": 0.06, "base_cost": 400},
	"acceleration": {"label": "Accel", "per_level": 0.10, "base_cost": 350},
	"health": {"label": "Hull", "per_level": 15.0, "add": true, "base_cost": 500},
	"turn_speed": {"label": "Agility", "per_level": 0.10, "base_cost": 300},
	# Cannon.
	"cannon_damage": {"label": "Damage", "per_level": 0.12, "base_cost": 500},
	"cannon_rate": {"label": "Fire rate", "per_level": 0.10, "base_cost": 450},
	"cannon_blast": {"label": "Blast radius", "per_level": 0.08, "base_cost": 400},
	# Minigun.
	"minigun_damage": {"label": "Damage", "per_level": 0.15, "base_cost": 450},
	"minigun_cooling": {"label": "Heat capacity", "per_level": 0.15, "base_cost": 400},
	"minigun_accuracy": {"label": "Accuracy", "per_level": 0.10, "base_cost": 350},
	# Javelin.
	"javelin_damage": {"label": "Damage", "per_level": 0.15, "base_cost": 600},
	"javelin_reload": {"label": "Reload speed", "per_level": 0.12, "base_cost": 550},
	"javelin_speed": {"label": "Missile speed", "per_level": 0.12, "base_cost": 400},
	# Rocket pods.
	"rockets_damage": {"label": "Damage", "per_level": 0.12, "base_cost": 450},
	"rockets_salvo": {"label": "Salvo size", "per_level": 1.0, "add": true, "base_cost": 500},
	"rockets_reload": {"label": "Reload speed", "per_level": 0.12, "base_cost": 400},
	# FAB bomb.
	"fab_blast": {"label": "Blast radius", "per_level": 0.08, "base_cost": 600},
	"fab_damage": {"label": "Damage", "per_level": 0.15, "base_cost": 500},
	"fab_reload": {"label": "Reload speed", "per_level": 0.12, "base_cost": 600},
}

const WEAPONS := {
	"cannon": {
		"name": "M230 30mm Cannon",
		"class": "HEAVY",
		"description": "Explosive shells aimed at the cursor. Lead your targets: one good hit clears a squad or a car.",
		"upgrades": ["cannon_damage", "cannon_rate", "cannon_blast"],
	},
	"minigun": {
		"name": "M134 Minigun",
		"class": "LIGHT",
		"description": "A hose of lead for infantry and stragglers. Spins up, blooms as it heats and jams if you hold it too long.",
		"upgrades": ["minigun_damage", "minigun_cooling", "minigun_accuracy"],
	},
	"javelin": {
		"name": "Javelin Missile",
		"class": "GUIDED",
		"description": "Locks the nearest enemy to your click, climbs and dives onto it. The answer to tanks and SAMs.",
		"upgrades": ["javelin_damage", "javelin_reload", "javelin_speed"],
	},
	"rockets": {
		"name": "Hydra 70 Rocket Pods",
		"class": "HEAVY",
		"description": "A rippling salvo of unguided rockets from the wing pods. Saturates an area, then needs a few seconds to reload.",
		"upgrades": ["rockets_damage", "rockets_salvo", "rockets_reload"],
	},
	"fab": {
		"name": "FAB-500 Bomb",
		"class": "BOMB",
		"description": "Half a tonne of high explosive dropped from the belly. Aim with the helicopter, not the cursor: the red ring shows where it lands.",
		"upgrades": ["fab_blast", "fab_damage", "fab_reload"],
	},
}
const WEAPON_ORDER := ["cannon", "minigun", "javelin", "rockets", "fab"]

# Base gun values as set up in main.tscn, for the workshop stat bars.
const GUN_DEFAULTS := {
	"damage": 5.0, "rpm": 180.0, "explosion_radius": 7.0,
	"minigun_damage": 1.0, "minigun_heat_time": 3.0,
	"javelin_damage": 15.0, "javelin_speed": 15.0,
	"rockets_damage": 6.0, "rockets_salvo": 6.0, "fab_damage": 40.0, "fab_radius": 16.0,
}


static func level(key: String) -> int:
	return int(Global.upgrades.get(key, 0))


static func upgrade_cost(key: String) -> int:
	var lvl := level(key)
	if lvl >= MAX_LEVEL:
		return -1
	return int(UPGRADES[key]["base_cost"] * (1.0 + lvl * 0.75))


# Total money spent on upgrades so far (for the reset refund).
static func spent_on_upgrades() -> int:
	var total := 0
	for key in Global.upgrades.keys():
		for lvl in int(Global.upgrades[key]):
			total += int(UPGRADES[key]["base_cost"] * (1.0 + lvl * 0.75))
	return total


# The value a stat has after upgrades.
static func upgraded(key: String, base: float) -> float:
	var def: Dictionary = UPGRADES[key]
	if def.get("add", false):
		return base + def["per_level"] * level(key)
	return base * (1.0 + def["per_level"] * level(key))


# Final stats for an airframe with the current upgrades.
static func heli_stats(id: String) -> Dictionary:
	var heli: Dictionary = HELICOPTERS[id]
	return {
		"speed": upgraded("speed", heli["speed"]),
		"acceleration": upgraded("acceleration", heli["acceleration"]),
		"health": upgraded("health", heli["health"]),
		"turn_speed": upgraded("turn_speed", heli["turn_speed"]),
	}


static func selected() -> String:
	return Global.selected_heli if HELICOPTERS.has(Global.selected_heli) else "cobra"


static func apply_to_helicopter(heli: Node) -> void:
	var stats := heli_stats(selected())
	heli.speed = stats["speed"]
	heli.acceleration = stats["acceleration"]
	heli.max_health = stats["health"]
	heli.turn_speed = stats["turn_speed"]


static func apply_to_guns(gun: Node) -> void:
	gun.damage = upgraded("cannon_damage", gun.damage)
	gun.rpm = upgraded("cannon_rate", gun.rpm)
	gun.explosion_radius = upgraded("cannon_blast", gun.explosion_radius)

	gun.minigun_damage = upgraded("minigun_damage", gun.minigun_damage)
	gun.minigun_heat_time = upgraded("minigun_cooling", gun.minigun_heat_time)
	# Accuracy shrinks the spread and bloom.
	var accuracy := 1.0 / (1.0 + UPGRADES["minigun_accuracy"]["per_level"] * level("minigun_accuracy"))
	gun.minigun_spread *= accuracy
	gun.minigun_bloom *= accuracy

	gun.javelin_damage = upgraded("javelin_damage", gun.javelin_damage)
	gun.javelin_reload /= 1.0 + UPGRADES["javelin_reload"]["per_level"] * level("javelin_reload")
	gun.javelin_speed = upgraded("javelin_speed", gun.javelin_speed)
	gun.javelin_dive_speed = upgraded("javelin_speed", gun.javelin_dive_speed)

	gun.rockets_damage = upgraded("rockets_damage", gun.rockets_damage)
	gun.rockets_salvo = int(upgraded("rockets_salvo", gun.rockets_salvo))
	gun.rockets_reload /= 1.0 + UPGRADES["rockets_reload"]["per_level"] * level("rockets_reload")

	gun.fab_radius = upgraded("fab_blast", gun.fab_radius)
	gun.fab_damage = upgraded("fab_damage", gun.fab_damage)
	gun.fab_reload /= 1.0 + UPGRADES["fab_reload"]["per_level"] * level("fab_reload")


# Weapon stat bars for the workshop: [label, current value, bar max].
static func weapon_bars(id: String) -> Array:
	var gun_defaults := GUN_DEFAULTS
	match id:
		"cannon":
			return [
				["Damage", upgraded("cannon_damage", gun_defaults["damage"]), 12.0],
				["Fire rate", upgraded("cannon_rate", gun_defaults["rpm"]), 400.0],
				["Blast radius", upgraded("cannon_blast", gun_defaults["explosion_radius"]), 14.0],
			]
		"minigun":
			var accuracy: float = 1.0 + UPGRADES["minigun_accuracy"]["per_level"] * level("minigun_accuracy")
			return [
				["Damage", upgraded("minigun_damage", gun_defaults["minigun_damage"]), 2.5],
				["Heat capacity", upgraded("minigun_cooling", gun_defaults["minigun_heat_time"]), 7.0],
				["Accuracy", accuracy, 2.0],
			]
		"rockets":
			var rocket_reload: float = 1.0 + UPGRADES["rockets_reload"]["per_level"] * level("rockets_reload")
			return [
				["Damage", upgraded("rockets_damage", gun_defaults["rockets_damage"]), 15.0],
				["Salvo size", upgraded("rockets_salvo", gun_defaults["rockets_salvo"]), 12.0],
				["Reload speed", rocket_reload, 2.0],
			]
		"fab":
			var fab_reload: float = 1.0 + UPGRADES["fab_reload"]["per_level"] * level("fab_reload")
			return [
				["Blast radius", upgraded("fab_blast", gun_defaults["fab_radius"]), 26.0],
				["Damage", upgraded("fab_damage", gun_defaults["fab_damage"]), 90.0],
				["Reload speed", fab_reload, 2.0],
			]
		_:
			var reload: float = 1.0 + UPGRADES["javelin_reload"]["per_level"] * level("javelin_reload")
			return [
				["Damage", upgraded("javelin_damage", gun_defaults["javelin_damage"]), 40.0],
				["Reload speed", reload, 2.0],
				["Missile speed", upgraded("javelin_speed", gun_defaults["javelin_speed"]), 35.0],
			]
