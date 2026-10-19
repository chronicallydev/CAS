extends RefCounted

# Oil rigs on the campaign map, their enemy garrisons and income, and
# helpers for capturing and upgrading them. Ownership and rig upgrade
# levels live on Global (owned_rigs, rig_upgrades) and are saved with the
# settings. Every owned rig pays out after every mission, win or lose.

const HOME := "home"
const MAX_LEVEL := 5

# Enemy mixes. Weights are relative chances for each enemy type.
const PROFILES := {
	"swarm": {"label": "Infantry swarm", "weights": {"infantry": 1.0, "car": 0.12, "tank": 0.0, "aa": 0.0}},
	"motor": {"label": "Motor pool", "weights": {"infantry": 0.4, "car": 0.6, "tank": 0.05, "aa": 0.03}},
	"aa_nest": {"label": "AA nest", "weights": {"infantry": 0.5, "car": 0.15, "tank": 0.05, "aa": 0.3}},
	"armour": {"label": "Armour column", "weights": {"infantry": 0.35, "car": 0.25, "tank": 0.35, "aa": 0.05}},
	"combined": {"label": "Combined arms", "weights": {"infantry": 0.6, "car": 0.25, "tank": 0.12, "aa": 0.1}},
}

# pos: position on the map (0-1 on each axis). level: the wave level the
# fight starts at. waves: waves to clear to capture it. income: base money
# paid after each mission while owned.
const RIGS := {
	"home": {"name": "Home Rig", "pos": Vector2(0.14, 0.7), "level": 0, "waves": 0, "income": 150,
		"profile": "combined", "links": ["wadi", "saltflat"],
		"description": "Your base of operations. Defend it to earn money from kills."},
	"wadi": {"name": "Wadi Pumpjack", "pos": Vector2(0.31, 0.47), "level": 1, "waves": 3, "income": 250,
		"profile": "swarm", "links": ["home", "ridge", "refinery"],
		"description": "A lightly held pump station. Lots of infantry, little armour."},
	"saltflat": {"name": "Salt Flat Well", "pos": Vector2(0.37, 0.83), "level": 2, "waves": 3, "income": 300,
		"profile": "motor", "links": ["home", "refinery"],
		"description": "Open ground patrolled by fast technicals."},
	"ridge": {"name": "Ridge Derrick", "pos": Vector2(0.5, 0.22), "level": 4, "waves": 4, "income": 450,
		"profile": "aa_nest", "links": ["wadi", "citadel"],
		"description": "A derrick on high ground ringed with AA launchers. Keep moving."},
	"refinery": {"name": "Sabkha Refinery", "pos": Vector2(0.59, 0.6), "level": 5, "waves": 4, "income": 600,
		"profile": "armour", "links": ["wadi", "saltflat", "terminal"],
		"description": "The enemy's armour depot. Bring something that cracks tanks."},
	"terminal": {"name": "Gulf Terminal", "pos": Vector2(0.84, 0.76), "level": 7, "waves": 5, "income": 900,
		"profile": "combined", "links": ["refinery", "citadel"],
		"description": "The export terminal. Rich and heavily defended."},
	"citadel": {"name": "Qasr Oil Field", "pos": Vector2(0.82, 0.28), "level": 9, "waves": 5, "income": 1300,
		"profile": "aa_nest", "links": ["ridge", "terminal"],
		"description": "The enemy's crown jewel. Everything they have is here."},
}
const RIG_ORDER := ["home", "wadi", "saltflat", "ridge", "refinery", "terminal", "citadel"]

# Rig upgrades. Output adds per_level x base income; hull adds rig health.
const RIG_UPGRADES := {
	"output": {"label": "Output", "per_level": 0.3, "cost_factor": 2.0},
	"hull": {"label": "Rig hull", "per_level": 25.0, "base_cost": 300},
}
# Money for capturing a rig, as a multiple of its base income.
const CAPTURE_BONUS := 3.0


static func is_owned(id: String) -> bool:
	return Global.owned_rigs.has(id)


# A rig can be attacked once a linked rig is owned.
static func can_attack(id: String) -> bool:
	if is_owned(id):
		return false
	for link in RIGS[id]["links"]:
		if is_owned(link):
			return true
	return false


static func level(id: String, key: String) -> int:
	return int(Global.rig_upgrades.get(id, {}).get(key, 0))


static func income(id: String) -> int:
	var base: int = RIGS[id]["income"]
	return int(round(base * (1.0 + RIG_UPGRADES["output"]["per_level"] * level(id, "output"))))


static func total_income() -> int:
	var total := 0
	for id in Global.owned_rigs:
		if RIGS.has(id):
			total += income(id)
	return total


static func hull_bonus(id: String) -> float:
	return RIG_UPGRADES["hull"]["per_level"] * level(id, "hull")


static func upgrade_cost(id: String, key: String) -> int:
	var next := level(id, key) + 1
	if key == "output":
		return int(RIGS[id]["income"] * RIG_UPGRADES["output"]["cost_factor"] * next * next)
	return int(RIG_UPGRADES["hull"]["base_cost"] * next * next)


# Spends the money and raises the level. Returns false if not possible.
static func buy_upgrade(id: String, key: String) -> bool:
	if not is_owned(id) or level(id, key) >= MAX_LEVEL:
		return false
	var cost := upgrade_cost(id, key)
	if Global.money < cost:
		return false
	Global.money -= cost
	var levels: Dictionary = Global.rig_upgrades.get(id, {}).duplicate()
	levels[key] = level(id, key) + 1
	Global.rig_upgrades[id] = levels
	Global.save_settings()
	return true


static func capture_bonus(id: String) -> int:
	return int(RIGS[id]["income"] * CAPTURE_BONUS)


static func profile(id: String) -> Dictionary:
	return PROFILES[RIGS[id]["profile"]]
