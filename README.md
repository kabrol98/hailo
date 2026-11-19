# Verdant Hold

An original first-person wave-defense shooter built in Godot 4. You hold a jungle
outpost against escalating waves of **the Thorn**, biomechanical creatures that
come out of the jungle trails. The level, effects and sounds are generated in
code. Optional free CC0 packs provide the vegetation, robot enemies and guns
(see [Third-party assets](#third-party-assets-not-committed)).

## Install (Apple Silicon Mac)

Prebuilt builds are attached to each [GitHub release](https://github.com/kabrol98/hailo/releases).
They need an M1 or newer Mac on macOS 11+. Install with:

```bash
curl -fsSL https://raw.githubusercontent.com/kabrol98/hailo/main/install.sh | bash
```

The script downloads the latest release and checks its SHA-256. It installs
`Verdant Hold.app` into `/Applications`, or `~/Applications` if that isn't
writable, and clears the quarantine flag so it opens without a Gatekeeper
prompt. Then launch it from Launchpad or Spotlight.

**While the repo is private** the raw URL above returns 404. Run the script
through the GitHub CLI instead (after `gh auth login`):

```bash
gh api repos/kabrol98/hailo/contents/install.sh -H "Accept: application/vnd.github.raw" | bash
```

The script then downloads the release with `gh` (or with `GITHUB_TOKEN` if
that's set).

Options, passed as environment variables or after `bash -s --`:

| | |
|---|---|
| `VERDANT_VERSION=v0.2.0` | install a specific release instead of the latest (downgrades work too) |
| `VERDANT_DIR=~/Games` | install somewhere else; an existing copy elsewhere is moved there |
| `--force` | reinstall even if that version is already installed |
| `--uninstall` | remove the app (add `--purge` to also delete settings and best scores) |

**Updating:** run the same command again.
- **Version check.** The script reads which version is installed. If it's
  already the target release, it says "Already up to date" without
  downloading anything.
- **Same location.** Otherwise it upgrades in place, wherever the app is
  installed, including a custom `VERDANT_DIR` from an earlier run.
- **Game running.** If the game is open, it offers to quit it first. Without
  a terminal to ask on, it warns that the new version is used next launch.
- **Safe swap.** The new version is staged in the same folder and swapped in
  with a rename. The old app is only deleted once the new one is in place. If
  anything fails, the old one stays untouched.
- **Settings and best scores are kept.**

e.g. `curl -fsSL …/install.sh | bash -s -- --uninstall`

The app is ad-hoc signed but **not notarized**, which needs a paid Apple
Developer account. Installing with the script or `curl` avoids the warning. If
you download the zip in a browser instead, macOS will say it "can't be
verified". Right-click the app and choose **Open**, or run
`xattr -dr com.apple.quarantine "/Applications/Verdant Hold.app"`.

## Run it from source on a Mac

1. Download **Godot 4.3 or newer** (the standard build, not .NET) from
   https://godotengine.org/download/macos/ and drag it into Applications.
   If macOS blocks it the first time, right-click the app and choose **Open**.
2. Launch Godot. In the Project Manager click **Import**, pick this folder's
   `project.godot`, then **Import & Edit**. The first import takes a few seconds.
3. *(Optional, recommended)* Download the asset packs. From this folder in
   Terminal, run `python3 tools/fetch_assets.py` (~220 MB total, under a
   minute), then reopen the project so Godot imports them. Without them the
   game uses its procedural vegetation, enemies and guns.
4. Press **Play** (▶ at top right, or `Cmd+B`). The home screen opens. Pick **Settings** to adjust graphics or time of day, or **Deploy** to play.

To build the `.app` yourself, use **Project → Export → macOS** (a preset is
included). First run the template step from [Releasing](#releasing) once.

## Controls

Keyboard + mouse and controllers both work, and you can switch at any time.
Prompts and menus follow whichever you touched last. An Xbox controller pairs
with macOS over Bluetooth or plugs in by USB. PlayStation and most other
controllers Godot recognises use the same button positions.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD / arrows | Left stick (analog: tilt gently to walk slowly) |
| Look | Mouse | Right stick |
| Fire | Left click | RT |
| Aim / zoom | Right click | LT |
| Jump | Space | A |
| Sprint | Shift (hold) | Click left stick (stays on until you stop moving forward) |
| Crouch | C / Ctrl | B |
| Reload | R | X (tap) |
| Pick up / swap weapon | E | X (hold) |
| Switch weapon | Q, mouse wheel, 1 / 2 | Y or LB |
| Throw frag grenade | G | RB |
| Melee | F / V | Click right stick |
| Flashlight (on automatically at night) | T | D-pad up |
| Pause menu | Esc | Menu |
| Mouse sensitivity down / up (saved) | `[` / `]` | Settings → Controller |

**Menus with a controller:** use the D-pad or left stick to move, A to
select, and B to go back. In Settings, LB / RB switch tabs and D-pad
left / right changes values. The mouse pointer hides while you're using the
controller.

**Controller settings** (Settings → Controller):
- **Look sensitivity.** Turning speeds up a little when you hold the stick at
  the edge, and is halved while aiming.
- **Invert Y.**
- **Stick dead zone.** Raise it if the view drifts on an older controller.
- **Aim assist.** On by default, controller only. The view slows slightly with
  an enemy under the crosshair, and aiming down sights eases onto a nearby
  target and follows it gently.
- **Vibration.** Firing, hits, shield break and nearby explosions. macOS
  doesn't pass rumble through for every controller; Xbox controllers over
  Bluetooth often get none.

Crouch and aim can each be set to **hold or toggle** under Settings → Gameplay
(applies to keyboard and controller). Unplugging the controller mid-game
pauses it.

Trackpad: two-finger click is aim. Tap-to-click works for firing if it's enabled in macOS settings.

## Third-party assets (not committed)

Four free packs by Quaternius, all CC0 (public domain):

| Pack | Used for |
|---|---|
| Stylized Nature MegaKit | Trees, ferns, big-leaf plants, bushes, grass clumps, flowers, mushrooms, rocks, pebbles. They sway via the game's foliage shader. |
| Sci-Fi Essentials Kit | Stalker (QuadShell spider bot), Lancer (EyeDrone, hovers), the Carbine, Sidearm, Marksman and Arc Caster models, ammo / grenade / health pickups |
| Animated Mech Pack | Troopers (three mech variants, picked at random) and the Bulwark |
| Ultimate Gun Pack | The KR-4 Breacher shotgun (only that one model is extracted) |

All the robots use one shared "Thorn" material: the model's own textures plus
glowing veins that pulse across the metal (colour per enemy type), a rim
glow, and the hit flash. That's what makes the two robot packs look like one
faction. The four alien weapons are procedural (veined, glowing organic
guns), and so are palms and all buildings.

Assets are **not stored in git**. Instead:

- `assets/manifest.json` (committed) pins each pack's URL, SHA-256, size,
  author and license.
- `tools/fetch_assets.py` (committed, standard-library Python) downloads the
  packs, verifies the checksum, and extracts them into
  `assets/third_party/` (git-ignored).
- If a pack is missing, the game falls back to procedural visuals. You can
  also switch between the two under **Settings → World** (*Vegetation style*
  and *Enemy & weapon models*).

Why not Git LFS? It would work, but every clone and CI run would count
against GitHub's LFS storage and bandwidth quotas. These packs are
already public, CC0 and permanently hosted, so a pinned manifest gives the
same reproducibility for free. LFS is the better fit later for assets we
create ourselves, or for anything without a stable public URL. To add a pack,
append an entry to the manifest. Get the checksum with `shasum -a 256 file.zip`.

## Settings & graphics

On first launch the game reads your chip and picks a preset: **High** for an
M1/M2/M3 Pro or a base M4, **Ultra** for an M4 Pro/Max or M2/M3 Max, otherwise
**Medium**. You can change it anytime from the home screen or the pause menu.
Every option saves to `user://settings.cfg`.

| Preset | Main differences | Aimed at |
|---|---|---|
| Low | Low shadows, no SSAO/volumetric fog, 35% grass, 67% render scale + FSR 1 | Base M1 / Air |
| Medium | Medium shadows, SSAO, 70% grass, 80% scale + FSR 1 | Base M2/M3 |
| High | High soft shadows, SSAO, volumetric fog, 100% grass, 85% scale + FSR 1 | M1 Pro laptop |
| Ultra | Ultra shadows, SSAO + SSIL, SDFGI global illumination, high-res volumetric fog, 160% grass, native res, MSAA 4x | M4 Pro Mac mini |

Each option can also be set by hand: shadows, SSAO, SSIL, SDFGI, volumetric
fog, glow, grass density, wind animation, decals, render scale, upscaler
(bilinear / FSR 1 / FSR 2), anti-aliasing, FPS cap, V-Sync, fullscreen and an
FPS counter. **Render scale** is the main performance setting on Retina
displays. Turn on *Show FPS counter* to compare.

**Time of day** (World tab): Day, Dusk or Night. At night the floodlights and
lamps come on, fireflies come out, the Thorn's glowing veins stand out, and
you carry a flashlight.

To add a new option, add a default to `DEFAULTS` and a row to `OPTIONS` in
`scripts/settings.gd`. The settings screen builds itself from that list.

## What's procedural

There are no image or model files. Everything is generated at startup:

- **Sky shader:** gradient, sun/moon disk, drifting clouds and twinkling stars.
- **Terrain:** rolling heightmap with flat building pads, a creek bed, and
  worn dirt trails from each jungle entrance. It blends grass, dirt and mud
  textures with detail normals.
- **Foliage:** canopies built from alpha-cut leaf cards (leaf textures painted
  procedurally) with soft spherical normals and backlit translucency. Palm
  fronds, ferns, reeds and grass sway in the wind.
- **Structures:** concrete, stone, wood and metal use one triplanar shader
  that adds moss creeping up from the ground and grime toward the base.
- **Effects:** an animated water shader, bullet-hole and scorch-mark decals,
  and muzzle flashes.
- **Thorn skin shader:** pulsing bioluminescent veins, chitin banding, rim glow
  and a hit flash.

## How it plays

- **Shields** recharge 4.5 s after you stop taking damage. **Health** does not
  regenerate. Red med-packs dropped by enemies restore it, and you get +30
  between waves.
- **Two weapons at a time.** Switch with Y / LB / Q / mouse wheel. The HUD
  shows icons for the gun in hand (big) and the one on your back (small).
  You start with the VK-9 Carbine and P-7 Sidearm.
- **Picking up:** stand at a weapon and hold X (controller) or press E. It
  replaces the gun in your hand, which drops at your feet. Walking over a
  dropped copy of a gun you already carry takes its ammo automatically.
- **Dropped weapons disappear** after 5 waves without being touched. At most
  30 lie around at once; the oldest go first.
- Red **fuel barrels** explode when shot.

### Weapons

**Human weapons** come from the **armory rack** on the bunker's back wall.
Taken guns restock every 5 waves (waves 6, 11, 16...).

| Weapon | Type | Notes |
|---|---|---|
| VK-9 Carbine | Automatic rifle, 32-round mag | All-rounder. 2.5× headshots once shields are down |
| P-7 Sidearm | Semi-auto pistol, 12-round mag | Accurate and quick to reload. Great for headshots |
| KR-4 Breacher | Pump shotgun, 6 shells, 9 pellets | Devastating up close, damage falls off past ~6 m |
| LR-9 Marksman | Bolt rifle, 5-round mag, strong zoom | 75 damage per shot. For lancers and headshots |
| Arc Caster | Energy rifle, battery | Plasma bolts do 1.9× shield damage. Overheats |

**Alien weapons** are carried by every Thorn and dropped when it dies, with a
partly charged battery (35–85%). They don't reload, and most overheat.
Plasma does extra damage to shields and less to flesh.

| Weapon | Dropped by | Notes |
|---|---|---|
| Thorn Spitter | Stalker | Sidearm. Tap for quick bolts. Hold to charge a seed that curves onto targets and strips most shields in one hit |
| Thorn Repeater | Trooper | Rapid plasma bolts. Overheats with sustained fire |
| Spore Launcher | Bulwark | Lobs explosive spores in an arc. Watch the blast radius |
| Thorn Lance | Lancer | Hold to charge, release for a long-range beam that does 90 damage |

The usual combo is to strip shields with plasma (Arc Caster or any Thorn
weapon), then switch and finish with a human gun.

### Ammo caches

The single infinite supply cache has been replaced by two limited ones:

- **Human ammo cache** (crate by the bunker's east wall). It refills human
  magazine reserves, the Arc Caster's battery and frags (to 3).
- **Alien ammo cache** (a glowing Thorn pod grown out of the crashed craft,
  south-east). It recharges alien weapon batteries.

Walk into one to use it. Each has a few refills (Easy 4, Normal 3, Hard 2),
shown as dots above it. A refill is only spent if something actually needed
topping up. Both refill every 5 waves, alongside the armory restock. Enemies
still drop ammo, frags and med-packs, and clearing a wave gives +20% reserve
ammo.

### Difficulty

Settings → Gameplay → Difficulty (shown on the home screen).

| | Easy | Normal | Hard |
|---|---|---|---|
| Enemy damage | 60% | 100% | 140% |
| Enemy health + shields | 80% | 100% | 125% |
| Enemy accuracy / fire rate | lower / slower | — | higher / faster |
| Wave size | 75% | 100% | 130% |
| Cache refills | 4 | 3 | 2 |
| Drop chance (ammo / frags / health) | higher | — | lower |

Best wave and score are kept per difficulty. Changing difficulty mid-run
applies to enemies that spawn afterwards.


### The Thorn

| Enemy | Shows up | Behaviour |
|---|---|---|
| Stalker | Wave 1 | Fast and unshielded. Fires Spitter bolts on the approach, then leaps in and claws |
| Trooper | Wave 1 | Shielded, fires plasma bursts, strafes, falls back to recharge when its shield breaks |
| Bulwark | Wave 3 | Huge shield and health, lobs explosive spores, ground-slams if you get close |
| Lancer | Wave 4 | Long-range sniper. A red targeting beam tracks you, then locks (turns white) just before firing, so move when it locks |

Every enemy carries its weapon (in hand, on its back, or slung under the
drone) and drops it when killed. Every 5th wave is a stalker swarm. Waves are
endless.

### The map

A concrete command bunker in the centre. A ramp on its north side leads to a
roof with a parapet. Around it are two wooden watchtowers with ramps, temple
ruins on a raised platform to the north-west, a crashed cargo craft to the
south-east, a creek to the south, and eight jungle trails where the Thorn come in.

## Project layout

```
main.tscn            entry scene (just runs scripts/main.gd)
scripts/main.gd      input map, game states, applies settings, save file
scripts/settings.gd  options, presets, chip detection (drives the settings UI)
scripts/ui.gd        home / settings / controls / pause / death menus
scripts/atmosphere.gd  sky, sun/moon, post-processing, time of day, fireflies
scripts/shaders.gd   all shaders + procedural textures and foliage meshes
scripts/decals.gd    pooled bullet holes and scorch marks
scripts/nature_kit.gd  loads the optional vegetation pack, swaps in the wind shader
scripts/model_kit.gd   loads the optional robot / gun / pickup models
scripts/showcase.gd  scripted camera paths for recording videos
assets/manifest.json third-party asset packs (fetched, not committed)
tools/fetch_assets.py  downloads + verifies the packs
tools/make_arm64_template.py  arm64-only macOS export template (for releases)
install.sh           curl | bash installer for the release builds
export_presets.cfg   macOS (arm64) export preset
.github/workflows/release.yml  builds + attaches the app on each release
scripts/arena.gd     procedural level + runtime navmesh bake
scripts/player.gd    movement, shields/health, weapons, grenades, melee
scripts/enemy.gd     the four Thorn enemy types and their AI
scripts/waves.gd     wave composition and spawning
scripts/hud.gd       in-game HUD and radar
scripts/projectile.gd, grenade.gd, barrel.gd, pickup.gd
scripts/effects.gd   particles, tracers, explosions (with area damage)
scripts/sfx.gd       synthesized sound effects
scripts/gamepad.gd   controller state: active device, rumble, prompts, stick shaping
scripts/weapons.gd   weapon registry: stats, fire modes, models, ammo state
scripts/weapon_pickup.gd  dropped / racked weapons, expiry and restock
scripts/weapon_icons.gd   renders HUD weapon silhouettes from the models
scripts/ammo_cache.gd     human + alien ammo caches with limited refills
scripts/difficulty.gd     Easy / Normal / Hard multipliers
tests/weapontest.gd  weapon-system test (godot --headless -- --weapontest)
tests/padtest.gd     simulated-controller test (godot --headless -- --padtest)
```

Tuning lives near the top of each script: weapon stats in `player.gd`
(`weapons = [...]`), enemy stats in `enemy.gd` (`setup()`), and wave sizes in
`waves.gd` (`_composition()`).

## Releasing

`.github/workflows/release.yml` builds the Apple Silicon app whenever a GitHub
release is **published**:

1. Create a tag and release, e.g. `gh release create v0.2.0 --generate-notes`,
   or use **Releases → Draft a new release** on GitHub.
2. The workflow runs on Ubuntu. It installs Godot 4.3 and its macOS export
   template (cached after the first run) and downloads the asset packs from the
   manifest. It stamps the tag into the app version, then exports.
3. It checks that the executable is a thin arm64 Mach-O with a code signature,
   then uploads to the release:
   - `VerdantHold-macos-arm64.zip`
   - its `.sha256`
   - `install.sh`

You can also run it by hand from **Actions → Release build → Run workflow**.
Leave the tag empty and you get a test build as a workflow artifact, with no
release needed.

Godot only ships *universal* (Intel + Apple Silicon) macOS templates.
`tools/make_arm64_template.py` cuts the arm64 slice out of the universal
binary with plain Python, so the shipped app is arm64-only. The executable is
about 73 MB instead of 153 MB. To export locally the same way:

```bash
mkdir -p build/templates && touch build/.gdignore
```
```bash
python3 tools/make_arm64_template.py ~/Library/Application\ Support/Godot/export_templates/4.3.stable/macos.zip build/templates/macos_arm64.zip
```
```bash
godot --headless --export-release macOS build/VerdantHold-macos-arm64.zip
```

(Install the export templates once via **Editor → Manage Export Templates**.)

## Automated test mode

A bot plays the game by itself (used for headless testing):

```bash
godot --headless -- --autotest --godmode --seconds=120
```

Extra flags: `--tod=day|dusk|night`, `--preset=low|medium|high|ultra`,
`--shots=<dir>` (saves screenshots; needs a real renderer, not `--headless`),
`--veg=kit|procedural`, `--models=kit|procedural`, `--wave=N` (start at wave
N), `--shot-times=a,b,c` (when to take screenshots) and `--debug` (prints
straggler enemy state). `--gallery` lines up one of each enemy in front of a
frozen player and steps through hip fire and aiming on both guns. Add
`--live` and the enemies attack, then the bot fights back.

Weapon test: `godot --headless -- --weapontest` checks:
- armory pick-up and swapping, plus ammo scavenging
- enemy weapon drops
- alien weapons: battery, charged shot, overheat
- ground-weapon expiry and the armory restock
- both caches: limited refills and the 5-wave reset
- difficulty scaling

Add `--difficulty=easy|normal|hard` to any run.

Controller test: `godot --headless -- --padtest` feeds simulated Xbox
controller input into the real game. It checks menu navigation, look and
dead zone, analog movement, sprint, firing, weapon switching, aim assist (on
and off), pause and the Settings tab buttons. It prints PASS / FAIL per check
and exits non-zero on any failure.

To record a fly-through video with Godot's Movie Maker, run:

```bash
godot --write-movie out.avi --fixed-fps 24 -- --autotest --godmode --showcase=overview,trail,ruins,creek,crash,fps
```
