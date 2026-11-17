# Verdant Hold

An original first-person wave-defense shooter built in Godot 4. You hold a jungle
outpost against escalating waves of **the Thorn**, biomechanical creatures that
come out of the jungle trails. The level, enemies, weapons, effects and sounds
are all generated in code, so the project needs no external assets.

## Run it on a Mac

1. Download **Godot 4.3 or newer** (the standard build, not .NET) from
   https://godotengine.org/download/macos/ and drag it into Applications.
   If macOS blocks it the first time, right-click the app and choose **Open**.
2. Launch Godot. In the Project Manager click **Import**, pick this folder's
   `project.godot`, then **Import & Edit**. The first import takes a few seconds.
3. Press **Play** (▶ at top right, or `Cmd+B`). Click to deploy.

To get a standalone `.app`, use **Project → Export → Add… → macOS**. Godot will
offer to download the export templates.

## Controls

| Key | Action |
|---|---|
| WASD / arrows | Move |
| Mouse | Look |
| Left click | Fire |
| Right click (or E) | Aim / zoom |
| Space | Jump |
| Shift | Sprint |
| C / Ctrl | Crouch |
| R | Reload |
| Q, mouse wheel, 1 / 2 | Switch weapon |
| G | Throw frag grenade |
| F / V | Melee |
| Esc | Pause (Q on the pause screen quits) |
| `[` / `]` | Mouse sensitivity down / up (saved) |

Trackpad: two-finger click is aim. Tap-to-click works for firing if it's enabled in macOS settings.

## How it plays

- **Shields** recharge 4.5 s after you stop taking damage. **Health** does not
  regenerate. Red med-packs dropped by enemies restore it, and you get +30
  between waves.
- **VK-9 Carbine**: hitscan rifle. It's weak against shields but strong against
  flesh, and does 2.5× headshot damage once an enemy's shield is down.
- **Arc Caster**: plasma projectile weapon with no ammo. It does 1.9× damage to
  shields but builds heat, and overheating locks it for about 2 s.
- The usual combo is to strip shields with plasma, then switch and finish with
  the carbine.
- The glowing **supply cache** inside the bunker refills carbine ammo and frags.
  It recharges every 30 s.
- Red **fuel barrels** explode when shot.

### The Thorn

| Enemy | Shows up | Behaviour |
|---|---|---|
| Stalker | Wave 1 | Fast, unshielded, leaps at you and claws in melee |
| Trooper | Wave 1 | Shielded, fires plasma bursts, strafes, falls back to recharge when its shield breaks |
| Bulwark | Wave 3 | Huge shield and health, lobs explosive mortar blobs, ground-slams if you get close |
| Lancer | Wave 4 | Long-range sniper. A red targeting beam tracks you, then locks (turns white) just before firing, so move when it locks |

Every 5th wave is a stalker swarm. Waves are endless. Your best wave and score
are saved.

### The map

A concrete command bunker in the centre. A ramp on its north side leads to a
roof with a parapet. Around it are two wooden watchtowers with ramps, temple
ruins on a raised platform to the north-west, a crashed cargo craft to the
south-east, a creek to the south, and eight jungle trails where the Thorn come in.

## Project layout

```
main.tscn            entry scene (just runs scripts/main.gd)
scripts/main.gd      input map, environment/lighting, game states, save file
scripts/arena.gd     procedural level + runtime navmesh bake
scripts/player.gd    movement, shields/health, weapons, grenades, melee
scripts/enemy.gd     the four Thorn enemy types and their AI
scripts/waves.gd     wave composition and spawning
scripts/hud.gd       HUD, radar, title/pause/game-over screens
scripts/projectile.gd, grenade.gd, barrel.gd, pickup.gd
scripts/effects.gd   particles, tracers, explosions (with area damage)
scripts/sfx.gd       synthesized sound effects
```

Tuning lives near the top of each script: weapon stats in `player.gd`
(`weapons = [...]`), enemy stats in `enemy.gd` (`setup()`), and wave sizes in
`waves.gd` (`_composition()`).

## Automated test mode

A bot plays the game by itself (used for headless testing):

```bash
godot --headless -- --autotest --godmode --seconds=120
```
