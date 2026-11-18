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
| `VERDANT_VERSION=v0.2.0` | install a specific release instead of the latest |
| `VERDANT_DIR=~/Games` | install somewhere else |
| `--uninstall` | remove the app (add `--purge` to also delete settings and best scores) |

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
| T | Flashlight (comes on automatically at night) |
| Esc | Pause menu (resume, settings, controls, quit) |
| `[` / `]` | Mouse sensitivity down / up (saved) |

Trackpad: two-finger click is aim. Tap-to-click works for firing if it's enabled in macOS settings.

## Third-party assets (not committed)

Three free packs by Quaternius, all CC0 (public domain):

| Pack | Used for |
|---|---|
| Stylized Nature MegaKit | Trees, ferns, big-leaf plants, bushes, grass clumps, flowers, mushrooms, rocks, pebbles. They sway via the game's foliage shader. |
| Sci-Fi Essentials Kit | Stalker (QuadShell spider bot), Lancer (EyeDrone, hovers), the VK-9 Carbine and Arc Caster viewmodels, ammo / grenade / health pickups |
| Animated Mech Pack | Troopers (three mech variants, picked at random) and the Bulwark |

All the robots use one shared "Thorn" material: the model's own textures plus
glowing veins that pulse across the metal (colour per enemy type), a rim
glow, and the hit flash. That's what makes the two robot packs look like one
faction. Palms and all buildings are still procedural.

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

To record a fly-through video with Godot's Movie Maker, run:

```bash
godot --write-movie out.avi --fixed-fps 24 -- --autotest --godmode --showcase=overview,trail,ruins,creek,crash,fps
```
