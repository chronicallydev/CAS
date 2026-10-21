# Architecture

The build is cut down to the core: **flying and shooting**. Everything else
(menu, hangar, campaign map, waves, rigs, pickups, saving, extra airframes,
weapons and AA units) is parked in `_parked/`, outside the build. See
`_parked/README.md` for what's there and how to bring it back.
`_parked/ARCHITECTURE.md` describes the full game as it was.

## Scenes

```
TestRange (features/test_range/test_range.tscn, TestRangeContext)  <- main scene
├── Panel (TestRangePanel)   side panel: spawn, cheats, live stats
└── Mission (features/mission/mission.tscn, MissionContext)
    ├── World                everything that pauses: camera, helicopter,
    │                        guns, environment, spawned enemies/effects
    └── GameHUD              score, kill pop-ups, multi-kills, edge arrows
```

- **The test range owns the mission.** It instantiates `mission.tscn`,
  spawns enemies into `mission.world` and rebuilds the mission on RESET
  RANGE or when the helicopter is shot down (`MissionContext.request_retry`).
  Esc quits.
- **The mission wires its own children.** In `_ready()` it copies the
  airframe's stats onto the helicopter, builds the model, equips the guns
  and starts the HUD.
- Nodes spawned mid-game (projectiles, effects, enemies) reach their
  mission with `MissionContext.of(self)` and add what they spawn to
  `MissionContext.spawn_parent(self)`, the mission's `World` node, so it is
  all freed with the mission.

`Sfx` and `PixelArt` are the only autoloads. They are engine-level services
and hold no game state.

## Loadout

The loadout is fixed on the Mission node in `mission.tscn`:

- `airframe`: `features/loadout/content/helicopters/cobra.tres`
  (`HelicopterData` + `HardpointData`: stats, look and 4 hardpoints)
- `weapons`: minigun and rockets (`WeaponData`), in fire-button order
- `loadout`: weapon id per hardpoint: minigun on the chin, rockets on both
  wings, belly empty

`HeliModel` builds the mounted weapons onto the airframe (`WeaponModel`) and
returns each copy's muzzle. `GunController.equip()` gets the types and
muzzles: the minigun fires with LMB, the rockets with RMB. Each extra copy
adds firepower: the minigun gets more fire rate, and every rocket pod fires
its own salvo. Weapon tuning lives in the GunController's exported values.
(`UpgradeData` is still on the weapon resources but nothing applies it.)

## Piloting

- **Flight model** (`Helicopter.steer()`): momentum, not snapping. Speed
  spools up and brakes at constant rates set by the airframe's
  `acceleration` (`throttle_response`, `brake_ratio`), the flight path bends
  toward the input at a rate set by `turn_speed` (`path_turn_scale`) while
  keeping speed, and steering past `reverse_angle` brakes straight through.
  The body leans into the steering force (`thrust`).
- **One job per ability**: dash beats bullets, flares beat missiles.
- **Dash (Space / Shift)**: a ~14 m burst with brief invulnerability, with
  charges and a per-airframe cooldown (`HelicopterData.dash_cooldown`).
- **Flares (F)**: lock-on enemies share `EnemyBase.update_lock()`: it counts
  up `lock_timer` (which makes the HUD's edge arrow pulse), warns the
  player, and gives up while `Helicopter.can_be_locked()` is false. Flares
  make that false for a moment and retarget every missile already homing on
  the helicopter to a decoy. They're unlimited but recharge
  (`HelicopterData.flare_cooldown`).
- A soft boundary (`Helicopter.bounds`) pushes the helicopter back toward
  the map centre.

## Enemies

Every enemy hunts the helicopter (`EnemyBase.objective()`).

| Enemy | Threat | Answer |
|---|---|---|
| Infantry (`infantry`) | rifle bursts in range | minigun |
| Car (`car`) | circles the helicopter, roof gun bursts | keep moving, dash |
| Tank (`tank`) | slow turret, heavy shells; armoured | rockets, keep moving |
| SAM truck (`aa_launcher`) | locks on, single homing missile | turn hard, flares |

## Test range panel

`TestRangePanel` spawns the chosen unit and count at the cursor
(middle-click or G), clears enemies, resets the range, toggles god mode and
instant flares/no reloads, and shows live stats: damage taken per source
(`Helicopter.damage_taken`), damage dealt and DPS (`GunController.damage_dealt`),
and the hovered enemy's health, armour and lock state.

## Folders

```
features/
  loadout/     data classes (HelicopterData, HardpointData, WeaponData,
               UpgradeData) + the Cobra, minigun and rockets
  mission/     mission context, plus:
    camera/ player/ weapons/ enemies/ (projectiles/) effects/
    environment/ hud/ vfx/
  test_range/  test range context and its side panel (main scene)
shared/        audio, pixelart, ui style, prop builder, helicopter model,
               3D health bar
assets/        fonts, ui textures, audio files
_parked/       out of the build (has a .gdignore), see its README
```
