class_name RunUpgrades
extends RefCounted

# The upgrades offered between stretches of a run (see DESIGN.md). Each one
# changes how something works rather than a number: three categories (gun,
# deflect, movement), each with a utility, a lethality and a survivability
# role, two upgrades per slot. Every upgrade is a one-off, except Double
# The Gun, which can be taken again and again (its count is the value in
# MissionContext.upgrades).
#
# A pick deals one card per category. Within a category the role is drawn
# by weight: every role starts at 1 and gains 1 for each upgrade of that
# role already held, so a build leans the way you've been picking.
#
# Some pairs combine (COMBOS): holding both adds an extra effect, and a
# card shows when it would complete one.
#
# What's held lives on the mission (MissionContext.upgrades); the systems
# that change ask MissionContext.upgraded() and combo() as they go.

const CATEGORIES := ["gun", "deflect", "movement"]
const ROLES := ["utility", "lethality", "survivability"]
# What the cards call each role (they're narrow).
const ROLE_LABELS := {"utility": "UTILITY", "lethality": "LETHAL", "survivability": "SURVIVAL"}

# Card text is short lines: the card is about 18 characters wide.
const LIST := [
	{"id": "rubber_bullets", "name": "RUBBER BULLETS", "category": "gun", "role": "utility",
		"text": "Rounds bounce\ninto a nearby\nenemy"},
	{"id": "seeker_rounds", "name": "SEEKER ROUNDS", "category": "gun", "role": "utility",
		"text": "Rounds curve\nonto enemies\nnear your aim"},
	{"id": "shredder", "name": "SHREDDER", "category": "gun", "role": "lethality",
		"text": "Keep firing on\none target: up\nto 3x damage"},
	{"id": "incendiary", "name": "INCENDIARY", "category": "gun", "role": "lethality",
		"text": "Vehicles and\nbuildings burn,\nfire spreads"},
	# Stackable: each pick doubles the guns again (and halves accuracy again).
	{"id": "double_gun", "name": "DOUBLE THE GUN", "category": "gun", "role": "lethality", "stackable": true,
		"text": "Doubles your\nguns, but halves\nthe accuracy\nof all of them"},
	{"id": "flak_screen", "name": "FLAK SCREEN", "category": "gun", "role": "survivability",
		"text": "Your rounds\nshoot down the\nmissiles they pass"},
	{"id": "salvage", "name": "SALVAGE", "category": "gun", "role": "survivability",
		"text": "Wrecks drop\nscrap: fly over\nit to patch hull"},
	{"id": "redirect", "name": "REDIRECT", "category": "deflect", "role": "utility",
		"text": "Deflections go\nfor the enemy\nyou aim at"},
	{"id": "time_bank", "name": "TIME BANK", "category": "deflect", "role": "utility",
		"text": "Slow motion\ngrows with every\nmissile dodged"},
	{"id": "split", "name": "SPLIT", "category": "deflect", "role": "lethality",
		"text": "Deflected\nmissiles split\nin two"},
	{"id": "overcharge", "name": "OVERCHARGE", "category": "deflect", "role": "lethality",
		"text": "Each deflection\ngrows the\nmissile's blast"},
	{"id": "grace", "name": "GRACE", "category": "deflect", "role": "survivability",
		"text": "After a perfect\ndodge, missiles\ndeflect for 1.5s"},
	{"id": "absorb", "name": "ABSORB", "category": "deflect", "role": "survivability",
		"text": "Every deflected\nmissile patches\nhull"},
	{"id": "decoy", "name": "DECOY", "category": "movement", "role": "utility",
		"text": "A dash leaves\na decoy that\nmissiles chase"},
	{"id": "steer_dash", "name": "STEER DASH", "category": "movement", "role": "utility",
		"text": "Steer while\nyou dash"},
	{"id": "ram", "name": "RAM", "category": "movement", "role": "lethality",
		"text": "Dash into enemy\nhelicopters to\nsmash them"},
	{"id": "rotor_wash", "name": "ROTOR WASH", "category": "movement", "role": "lethality",
		"text": "Dashing flattens\ninfantry, rocks\nvehicles"},
	{"id": "rotor_guard", "name": "ROTOR GUARD", "category": "movement", "role": "survivability",
		"text": "A dash blasts\neverything away\n(long cooldown)"},
	{"id": "autorotate", "name": "AUTOROTATE", "category": "movement", "role": "survivability",
		"text": "Once a stretch,\nlive through a\nkilling hit"},
]

# Pairs that combine, and what holding both adds.
const COMBOS := [
	{"a": "rubber_bullets", "b": "incendiary", "name": "HOT RICOCHETS", "text": "Ricochets set fires"},
	{"a": "split", "b": "overcharge", "name": "CHAIN REACTION", "text": "Split halves keep the growth"},
	{"a": "seeker_rounds", "b": "redirect", "name": "PAINTED", "text": "Deflections go for enemies your seekers hit"},
	{"a": "shredder", "b": "ram", "name": "FINISHER", "text": "Rams cash in the shred"},
	{"a": "decoy", "b": "grace", "name": "MIRROR", "text": "Missiles hitting a decoy deflect"},
	{"a": "rotor_guard", "b": "absorb", "name": "REGEN GUARD", "text": "Missiles blasted away patch hull"},
	{"a": "flak_screen", "b": "split", "name": "SHRAPNEL", "text": "Missiles you shoot down split into deflections"},
	{"a": "salvage", "b": "rotor_wash", "name": "SCAVENGER", "text": "Flattened infantry drop scrap"},
	{"a": "time_bank", "b": "steer_dash", "name": "LONG DRIFT", "text": "Dashes go twice as far in slow motion"},
	{"a": "autorotate", "b": "grace", "name": "SECOND WIND", "text": "Surviving a killing hit gives slow motion and grace"},
]


static func find(id: String) -> Dictionary:
	for upgrade: Dictionary in LIST:
		if upgrade.id == id:
			return upgrade
	return {}


## Up to one card per category, each not yet held, its role drawn by
## weight (see above). Empty once everything is held.
static func offer(mission: MissionContext) -> Array:
	var weights := {}
	for role in ROLES:
		weights[role] = 1.0
	for id in mission.upgrades:
		var held := find(id)
		if not held.is_empty():
			weights[held.role] += 1.0

	var cards: Array = []
	for category in CATEGORIES:
		var pool := LIST.filter(func(upgrade: Dictionary) -> bool:
			return upgrade.category == category and (upgrade.get("stackable", false) or not mission.upgrades.has(upgrade.id)))
		if pool.is_empty():
			continue
		var total := 0.0
		for upgrade: Dictionary in pool:
			total += weights[upgrade.role]
		var roll := randf() * total
		for upgrade: Dictionary in pool:
			roll -= weights[upgrade.role]
			if roll <= 0.0:
				cards.append(upgrade)
				break
	return cards


## The combos `id` would complete with what's already held.
static func combos_with(id: String, mission: MissionContext) -> Array:
	return COMBOS.filter(func(combo: Dictionary) -> bool:
		return (combo.a == id and mission.upgrades.has(combo.b)) or (combo.b == id and mission.upgrades.has(combo.a)))


## Takes `id`; returns the combos it completed.
static func apply(id: String, mission: MissionContext) -> Array:
	var completed := combos_with(id, mission)
	if find(id).get("stackable", false):
		mission.upgrades[id] = int(mission.upgrades.get(id, 0)) + 1
	else:
		mission.upgrades[id] = true
	if id == "autorotate":
		mission.helicopter.autorotate_ready = true
	if id == "double_gun":
		mission.helicopter.double_gun(mission.upgrades[id])
	return completed


## The held upgrades' names, in the order taken, for the HUD.
static func held_names(mission: MissionContext) -> Array:
	var names: Array = []
	for id in mission.upgrades:
		var upgrade := find(id)
		if upgrade.is_empty():
			continue
		var name := Settings.t(upgrade.name)
		if upgrade.get("stackable", false):
			name += " x%d" % int(mission.upgrades[id])
		names.append(name)
	return names


## Card text: number, name, category and role, what it does, and any
## combo it would complete, in the current language.
static func card_text(index: int, upgrade: Dictionary, mission: MissionContext) -> String:
	var category := Settings.t(upgrade.category.to_upper())
	var role := Settings.t(ROLE_LABELS[upgrade.role])
	var text := "%d  %s\n%s - %s\n\n%s" % [index, Settings.t(upgrade.name), category, role, Settings.t(upgrade.text)]
	if upgrade.get("stackable", false) and mission.upgrades.has(upgrade.id):
		text += "\n\n" + Settings.t("(%d GUNS NOW)") % roundi(pow(2.0, int(mission.upgrades[upgrade.id])))
	for combo: Dictionary in combos_with(upgrade.id, mission):
		text += "\n\n" + Settings.t("COMBO: %s") % Settings.t(combo.name)
	return text
