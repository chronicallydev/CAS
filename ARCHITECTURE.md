# Architecture

The build is cut down to the core: **flying and shooting**. Everything else
(the old menu, hangar, campaign map, waves, rigs, pickups, saving, extra airframes,
weapons and AA units) is parked in `_parked/`, outside the build. See
`_parked/README.md` for what's there and how to bring it back.
`_parked/ARCHITECTURE.md` describes the full game as it was.

## Scenes

```
MainMenu (features/menu/main_menu.tscn)  <- main scene
                             play, test range, language, fullscreen, quit

Run (features/run/run.tscn, RunContext)
├── RunScreens               banners, upgrade picks, end screen
├── TakeoffIntro             the opening takeoff (skippable), then gone
├── Mission (features/mission/mission.tscn, MissionContext)
│   ├── World                everything that pauses: camera, helicopter,
│   │                        guns, environment, spawned enemies/effects
│   └── GameHUD              score, kill pop-ups, multi-kills, edge arrows
└── RunDirector              stretches, spawns, view and corridor

TestRange (features/test_range/test_range.tscn, TestRangeContext)
├── Panel (TestRangePanel)   side panel: spawn, cheats, live stats
└── Mission                  as above
```

- **A run** (see DESIGN.md) is 6 stretches. `RunDirector` leads the
  mission through each: *travel* (the view only scrolls forward,
  `TopDownCamera.max_focus_z`, and the bottom of the screen is a wall,
  `Helicopter.corridor`; SAM trucks and `TravelObjective`s appear ahead,
  and the view won't scroll past a live one), then a *lock arena* (view
  pinned, helicopter waves; from the second stretch it's over a `City`,
  reinforced while its marked targets stand, and clears once they're
  destroyed), then an upgrade pick (`RunUpgrades`) with the
  game paused. What each stretch holds is the table `RunDirector.PLAN`.
- **Buildings** (`features/mission/structures/building.gd`) aren't
  enemies: they're in the `structures` group, which `GunController`
  damages by footprint, and break in stages down to rubble. `City` and
  `TravelObjective` build from them plus the existing tanks, cars and
  infantry (`dug_in` holds those in place).
- **Upgrades** (`RunUpgrades`): the list, the weighted dealing and the
  combos. What's held lives in `MissionContext.upgrades`; the systems it
  changes (`GunController`, `aa_missile.gd`, `ChainDodge`, `Helicopter`)
  ask `mission.upgraded(id)` / `combo(a, b)` where they act. Helper nodes
  are in `features/mission/upgrades/` (Burn, Scrap, Decoy). The test range
  panel can switch any of them on.
- **The boss** (`features/mission/bosses/`): the last stretch's arena is a
  `Fortress` instead of a city. Its weapons are `FortressPart`s (buildings
  with guns, in `deflect_targets` so deflected missiles go for them); the
  fortress schedules one big attack at a time and runs the phases.
  `RunDirector.PLAN`'s `boss` flag places it.
  Terrain streams in ahead, a `DesertEnvironment` per stretch. The Cobra
  flies with the minigun only. Shot down or done, the end screen offers
  retry (R) or the menu (M); Esc goes to the menu any time.
- **The ace** (`enemy_ace.gd`, the mini boss; `PLAN`'s `ace` flag): an
  enemy helicopter whose `STAGES` change how it fights as its hull drops
  (passive, then full salvos, then heavy rockets alternating with
  missiles). Beating it gives all three upgrades on offer.
- **The test range owns the mission.** It instantiates `mission.tscn`,
  spawns enemies into `mission.world` and rebuilds the mission on RESET
  RANGE or when the helicopter is shot down (`MissionContext.request_retry`).
  Esc goes back to the menu.
- **The mission wires its own children.** In `_ready()` it copies the
  airframe's stats onto the helicopter, builds the model, equips the guns
  and starts the HUD.
- Nodes spawned mid-game (projectiles, effects, enemies) reach their
  mission with `MissionContext.of(self)` and add what they spawn to
  `MissionContext.spawn_parent(self)`, the mission's `World` node, so it is
  all freed with the mission.

`Sfx`, `Music`, `PixelArt` and `Settings` are the only autoloads. They are
engine-level services and hold no game state. `PixelArt` also redirects every UI
CanvasLayer into its low-res, 1-bit UI viewport (the test range panel opts
out with the `crisp_ui` meta); `UiStyle.px` sizes text to that grid, and
`PixelArt.fit_canvas` scales the canvas so a low-res pixel is a whole
number of canvas units at any window size (otherwise the pixel font loses
columns).

`Settings` holds the player's options (language, fullscreen; F11 or
Alt+Enter) in `user://options.cfg`. **Text** is written in English and
translated by the `TranslationServer`: `UkrainianStrings` maps each English
string to Ukrainian. A Label whose whole text is a key translates itself;
text put together in code uses `tr()` (or `Settings.t()` in static code)
with the format string as the key. New player-facing text needs an entry
there.

## Web build

`export_presets.cfg` has a Web preset (output `build/web/`, ignored by
git). The web runs the Compatibility renderer, so `PixelArt` swaps in
`pixel_outline_compat.gdshader` (silhouettes only: there's no normal
buffer) and darkens the image to match Forward+ (`COMPAT_GAMMA`). Threads
are off, so it runs on any host without special headers (itch.io
included). Exporting needs the standard (non-.NET) Godot 4.7 editor with
its export templates: the .NET editor can't export to the web.

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
- **One ability, the dash**: it beats bullets, and a well-timed one beats
  missiles (the chain dodge). There are no flares.
- **Dash (Space / Shift)**: a ~14 m burst with brief invulnerability, with
  charges and a per-airframe cooldown (`HelicopterData.dash_cooldown`).
- **Chain dodge** (`ChainDodge`, owned by the helicopter): a dash started
  within `perfect_window` seconds of a missile hitting is a perfect dodge.
  It refunds the dash, drops the game to `slow_scale` for a real-time
  window (`MissionContext.base_time_scale`, which hit stops leave alone),
  and a dash out of the slow motion cancels the current one, so it can be
  the next link. Dodged missiles are deflected (`deflect()` in
  `aa_missile.gd`): they home on the nearest enemy and blast it. Tuning
  is static, so the test range's sliders last across resets; H fires a
  practice salvo. All the feedback (callouts, shockwave ring, letterbox,
  next-missile brackets, sounds) is `DodgeFx` on the HUD, driven by
  ChainDodge's signals and animated in real time.
- **Lock-ons**: lock-on enemies share `EnemyBase.update_lock()`: it counts
  up `lock_timer` (which makes the HUD's edge arrow pulse) and warns the
  player.
- A soft boundary (`Helicopter.bounds`) pushes the helicopter back toward
  the map centre.

## Enemies

Every enemy hunts the helicopter (`EnemyBase.objective()`).

| Enemy | Threat | Answer |
|---|---|---|
| Infantry (`infantry`) | rifle bursts in range | minigun |
| Car (`car`) | circles the helicopter, roof gun bursts | keep moving, dash |
| Tank (`tank`) | slow turret, heavy shells; armoured | rockets, keep moving |
| SAM truck (`aa_launcher`) | locks on, single homing missile | turn hard, chain dodge |
| Scout (`enemy_scout`) | fast helicopter, circles close, 2-missile salvos, jinks often | chain dodge, deflect |
| Gunship (`enemy_gunship`) | slow armoured helicopter, 4-missile salvos | chain dodge, deflect, rockets |

Enemy helicopters (`enemy_helicopter.gd`, one script, a scene per type)
fly at the player's altitude in the `air_enemies` group. They circle at a
preferred range, lock on and fire salvos spaced for chain dodges, send
deflected missiles back at the player (`reflect_chance`, falling off per
rally; `aa_missile.reflect()` re-arms it, faster each rally, so a missile
can go back and forth) or else dash clear of them, jink (swap direction and dash) after
`jink_damage` of sustained fire, and spin down and crash when killed.
`GunController.air_target()` picks a helicopter when the cursor is over it
on screen (the ground under it is far off with the camera's angle): the
reticle (`Reticle`, drawn in code) snaps onto it in its locked form, and
minigun rounds lead it and hit if its hull is within `air_hit_radius` on
arrival (`fire_air_round`).

## Test range panel

`TestRangePanel` spawns the chosen unit and count at the cursor
(middle-click or G), clears enemies, resets the range, toggles god mode and
instant dashes/no reloads, and shows live stats: damage taken per source
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
  menu/        the main menu (main scene)
  run/         run context, director, screens, upgrades, takeoff intro
  test_range/  test range context and its side panel
shared/        audio, pixelart, settings and translations, ui style, prop
			   builder, helicopter model, 3D health bar
assets/        fonts, ui textures, audio files
_parked/       out of the build (has a .gdignore), see its README
```
