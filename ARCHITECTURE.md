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
    └── MissionContext  features/mission/   the battle
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
