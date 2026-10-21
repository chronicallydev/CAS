# Architecture

## Contexts

The game runs as one persistent **root context** with one child **context** at a time:

```
Root (features/game_flow/root.tscn, RootContext)
├── owns GameServices: PlayerProfile, GameSettings, SaveService, Loadout, Campaign
└── one of:
    ├── MenuContext     features/menu/      main menu, options
    ├── HangarContext   features/hangar/    buy helicopters and upgrades
    ├── MapContext      features/map/       campaign map, rig upgrades
    ├── MissionContext  features/mission/   the battle
    └── TestRangeContext features/test_range/ sandbox: spawn any unit, try any loadout
```

Every context follows the same rules:

- **The root hands it services.** It calls `bind(services, ...)` before adding
  the context to the tree. A context never creates or saves the profile on
  its own.
- **It only asks to leave.** It emits `request_menu`, `request_map`,
  `request_mission(rig_id)` and so on, and the root decides what opens next.
  No context knows about any other context.
- **It wires its own children.** In `_ready()` it hands its systems what they
  need, through `initialize(...)` or `start(...)` calls and signal
  connections.
- **It runs on its own.** Any context scene can be run with F6. With no root
  around, it loads the save from disk (`GameServices.create_default()`).

Inside a mission, nodes spawned mid-game (projectiles, effects, enemies)
reach their mission with `MissionContext.of(self)`. They add what they spawn
to `MissionContext.spawn_parent(self)`, the mission's `World` node, so it is
all freed with the mission. `World` pauses with the tree. The context and
the HUD keep running, so the end screen works while the game is paused.

`Sfx` and `PixelArt` are the only autoloads. They are engine-level services
and hold no game state.

## Data

Static game data is stored as Resources, so it can be tuned in the
Inspector without touching code:

| Resource | Files | What it holds |
|---|---|---|
| `GameConfig` | `features/game_flow/game_config.tres` | the catalogs, difficulty presets, starting money |
| `LoadoutCatalog` | `features/loadout/content/loadout_catalog.tres` | helicopters, weapons, airframe upgrades, pricing |
| `HelicopterData` + `HardpointData` | `features/loadout/content/helicopters/*.tres` | stats and look of one airframe, usable weapons, hardpoints (position + look) and default loadout |
| `WeaponData` + `UpgradeData` | `features/loadout/content/weapons/*.tres` | price, model style, and its upgrades |
| `CampaignCatalog` | `features/campaign/content/campaign_catalog.tres` | rigs and rig upgrade rules |
| `RigData` | `features/campaign/content/rigs/*.tres` | one rig: position, links, waves, forts, biome, income |
| `GarrisonData` | `features/campaign/content/garrisons/*.tres` | enemy mix weights |
| `DifficultyPreset` | `features/mission/waves/difficulty/*.tres` | enemy multipliers |

An upgrade names the properties it changes (`UpgradeData.target_properties`)
on the helicopter or the gun controller. You can add one without writing
code.

Player progress lives in `PlayerProfile` and options in `GameSettings`.
`SaveService` writes both to `user://settings.cfg`, in the same format as
before the refactor.

## Folders

```
features/
  game_flow/   root context, services bundle, game config
  profile/     player profile, settings, save service
  loadout/     hangar rules (Loadout) + helicopter/weapon/upgrade data
  campaign/    campaign rules (Campaign) + rig/garrison data
  menu/        menu context and UI
  hangar/      hangar context, UI and 3D hangar
  map/         map context, UI, 3D map, terrain, markers
  mission/     mission context and state, plus:
    camera/ player/ weapons/ enemies/ (forts/ projectiles/) effects/
    waves/ rig/ environment/ hud/ vfx/
  test_range/  test range context and its side panel
shared/        used by several contexts: audio, pixelart, ui style,
               prop builder, helicopter model, 3D health bar
assets/        fonts, ui textures, audio files
```

## Weapons and loadouts

Each helicopter has hardpoints (`HelicopterData.hardpoints`): Little Bird 2,
Cobra 4, Hind 6. Any weapon fits any slot. Instead, each airframe lists the
weapons it can use (`HelicopterData.allowed_weapons`): the Little Bird takes
the minigun and rockets, the Cobra everything except the FAB, the Hind all
five. A slot's kind (chin, wing or belly) only changes how the weapon is
drawn.

- Weapon units are bought one at a time (`PlayerProfile.owned_weapons`).
  A unit can be mounted on every helicopter, since only one is flown at a
  time.
- Every helicopter has its own loadout (`PlayerProfile.loadouts`). The
  `Loadout` service enforces the rules: the airframe must be able to use
  the weapon, you need enough units, and at most `max_weapon_types` (2)
  types can be mixed.
- `HeliModel` builds the mounted weapons onto the airframe (`WeaponModel`),
  in the hangar and in the mission alike, and returns each copy's muzzle.
- In a mission, `GunController.equip()` gets the types and muzzles. The
  first type fires with LMB and the second with RMB. Each extra copy adds
  firepower: guns get more fire rate, every rocket pod fires its own salvo,
  and every Javelin rail or FAB rack reloads on its own.

## Anti-air and flares

Lock-on enemies share `EnemyBase.update_lock()`: it counts up `lock_timer`
(which makes the HUD's edge arrow pulse), warns the player, and gives up
while `Helicopter.can_be_locked()` is false. Dropping flares (F)
makes that false for a moment and retargets every missile already homing
on the helicopter to a decoy. Flares are unlimited but recharge: each
airframe has its own `HelicopterData.flare_cooldown` (Little Bird 6 s,
Cobra 8 s, Hind 11 s), shortened by the "Flare rate" upgrade.

| Enemy | Where | Threat | Answer |
|---|---|---|---|
| SAM truck (`aa_launcher`) | waves | single homing missile | turn hard, flares |
| Stinger (`stinger`) | waves, in infantry crowds | fast lock, small agile missile | sweep crowds, flares |
| Shilka (`shilka`) | waves | radar lock, then a long leading flak stream; minigun-proof | heavy weapons, keep moving, flares cut a burst |
| Ripple launcher (`ripple_launcher`) | waves | locks, then fires 6 slow, weakly homing missiles in a fan | fly through a gap, flares |
| Flak gun (`forts/flak_gun`) | assault forts | leading flak bursts | keep moving |
| SAM site (`forts/sam_radar` + `sam_launcher`) | assault forts (`RigData.sam_sites`) | locks from off-screen, 2-missile salvos | kill the radar first, flares |

How often each wave enemy shows up comes from the rig's `GarrisonData`
weights.

## Test range

`TestRangeContext` (main menu → TEST RANGE) runs a real `mission.tscn` in
sandbox mode (`MissionContext.sandbox`). There are no waves, no payout and
no records, and losing the helicopter just resets the range. It works on
`GameServices.create_sandbox()`, a copy that owns every helicopter and
weapon and never saves, so the real profile is never touched. The side panel
(`TestRangePanel`) spawns any unit at the cursor (middle-click or G), picks
the airframe, loadout and upgrade levels (APPLY rebuilds), toggles god mode
and instant flares/no reloads, and shows live stats: damage taken per source
(`Helicopter.damage_taken`), damage dealt and DPS (`GunController.damage_dealt`),
and the hovered enemy's health, armour and lock state.

## Piloting, pickups and pacing

- **Flight model** (`Helicopter.steer()`): momentum, not snapping. Speed
  spools up and brakes at constant rates set by the airframe's
  `acceleration` (`throttle_response`, `brake_ratio`), the flight path bends
  toward the input at a rate set by `turn_speed` (`path_turn_scale`) while
  keeping speed, and steering past `reverse_angle` brakes straight through.
  The body leans into the steering force (`thrust`).
- **One job per ability**: dash beats bullets, flares beat missiles.
- **Dash (Space / Shift)**: a ~14 m burst with brief invulnerability, with
  charges and a per-airframe cooldown (`HelicopterData.dash_cooldown`).
- **Pickups** (`mission/pickups/`): `PickupDropper` rolls on every kill and
  drops cash (added to the payout) or weapon frenzy (double fire rate, no
  reloads). Fly over them to collect.
- **Pacing**: waves overlap (the next starts when the current one's spawns
  are out and at most `overlap_fraction` of it is alive), breaks are short,
  waves are bigger, AA arrives earlier, assaults fly in only 90 m past a
  patrol, and in defences infantry and car gunners shoot the helicopter
  when it comes close (`EnemyBase.defence_target()`).
