extends RefCounted
## Weapon registry: stats, fire modes, models and per-weapon state.
##
## A weapon "state" is a Dictionary: a copy of its DEFS entry plus runtime
## fields (ammo / reserve for magazine weapons, battery for energy weapons,
## heat / overheated / charge). The player carries two; dropped and racked
## weapons keep theirs, so a half-empty gun stays half-empty when picked up.
##
## Families:
##   human - from the armory rack and human ammo caches. Magazine + reserve
##           (reload), except the Arc Caster which runs on a battery.
##   alien - carried by the Thorn and dropped when they die. Battery only, no
##           reload; most overheat. Recharged at alien caches.
##
## Fire modes: hitscan (pellets > 1 = shotgun), bolt (projectile),
## charge_bolt (tap for bolts, hold to charge a heavy shot), lob (arcing
## explosive), beam (hold to charge, then a hitscan beam).

const Shaders = preload("res://scripts/shaders.gd")
const ModelKit = preload("res://scripts/model_kit.gd")

const BREACHER_FBX := "res://assets/third_party/guns/FBX/Shotgun_ShortStock.fbx"

const DEFS := {
	# ---------------------------------------------------------------- human
	"carbine": {"name": "VK-9 CARBINE", "short": "CARBINE", "family": "human", "mode": "hitscan",
		"kind": "ballistic", "auto": true, "rate": 0.095, "damage": 13.0,
		"mag": 32, "start_reserve": 192, "max_reserve": 320, "reload": 1.8,
		"spread": 0.024, "aim_spread": 0.006, "recoil": 0.011, "zoom": 52.0,
		"sfx": "rifle", "sfx_pitch": 1.0, "tracer": 0.6, "flash": Color(1.0, 0.75, 0.4),
		"kit": ["Gun_Rifle", 0.68, false, Vector3(0, -0.115, -0.02)],
		"blurb": "All-round automatic rifle. Headshots once shields are down."},
	"sidearm": {"name": "P-7 SIDEARM", "short": "SIDEARM", "family": "human", "mode": "hitscan",
		"kind": "ballistic", "auto": false, "rate": 0.17, "damage": 24.0,
		"mag": 12, "start_reserve": 60, "max_reserve": 120, "reload": 1.3,
		"spread": 0.016, "aim_spread": 0.003, "recoil": 0.022, "zoom": 58.0,
		"sfx": "rifle", "sfx_pitch": 1.35, "tracer": 0.4, "flash": Color(1.0, 0.75, 0.4),
		"kit": ["Gun_Pistol", 0.3, false, Vector3(0, -0.075, -0.08)],
		"blurb": "Accurate semi-auto pistol. Fast reload, great for headshots."},
	"breacher": {"name": "KR-4 BREACHER", "short": "BREACHER", "family": "human", "mode": "hitscan",
		"kind": "ballistic", "auto": false, "rate": 0.8, "damage": 11.0, "pellets": 9,
		"falloff": Vector2(6.0, 24.0),
		"mag": 6, "start_reserve": 24, "max_reserve": 42, "reload": 2.4,
		"spread": 0.075, "aim_spread": 0.06, "recoil": 0.05, "zoom": 66.0,
		"sfx": "rifle", "sfx_pitch": 0.62, "sfx_vol": 3.0, "tracer": 0.25, "flash": Color(1.0, 0.7, 0.35),
		"kit": [BREACHER_FBX, 0.62, true, Vector3(0, -0.1, 0.02)],
		"blurb": "Pump shotgun. Devastating up close, useless at range."},
	"marksman": {"name": "LR-9 MARKSMAN", "short": "MARKSMAN", "family": "human", "mode": "hitscan",
		"kind": "ballistic", "auto": false, "rate": 0.75, "damage": 75.0,
		"mag": 5, "start_reserve": 20, "max_reserve": 35, "reload": 2.6,
		"spread": 0.035, "aim_spread": 0.0004, "recoil": 0.045, "zoom": 20.0,
		"sfx": "rifle", "sfx_pitch": 0.8, "sfx_vol": 2.0, "tracer": 1.0, "flash": Color(1.0, 0.75, 0.4),
		"kit": ["Gun_Sniper", 0.95, false, Vector3(0, -0.11, 0.14)],
		"blurb": "Long rifle with a strong zoom. Lancers and headshots."},
	"arc_caster": {"name": "ARC CASTER", "short": "ARC CASTER", "family": "human", "mode": "bolt",
		"kind": "plasma", "auto": true, "rate": 0.15, "damage": 19.0, "speed": 75.0,
		"drain": 0.0035, "heat_per_shot": 0.085, "cool_rate": 0.42, "overheat_time": 2.3,
		"spread": 0.014, "aim_spread": 0.005, "recoil": 0.007, "zoom": 60.0,
		"sfx": "plasma", "color": Color(0.3, 0.85, 1.0), "flash": Color(0.4, 0.8, 1.0),
		"kit": ["Gun_Revolver", 0.42, false, Vector3(0, -0.09, -0.04)],
		"blurb": "Experimental energy rifle. Shreds shields, overheats, runs on a battery."},
	# ---------------------------------------------------------------- alien (the Thorn)
	"spitter": {"name": "THORN SPITTER", "short": "SPITTER", "family": "alien", "mode": "charge_bolt",
		"kind": "plasma", "auto": false, "rate": 0.14, "damage": 11.0, "speed": 55.0,
		"drain": 0.006, "heat_per_shot": 0.07, "cool_rate": 0.55, "overheat_time": 2.0,
		"charge_time": 0.7, "charge_damage": 42.0, "charge_drain": 0.05, "charge_heat": 0.45,
		"spread": 0.02, "aim_spread": 0.008, "recoil": 0.008, "zoom": 64.0,
		"sfx": "enemy_bolt", "color": Color(1.0, 0.7, 0.15), "flash": Color(1.0, 0.7, 0.2),
		"glow": Color(1.0, 0.75, 0.1), "skin": Color(0.4, 0.22, 0.1),
		"blurb": "Stalker sidearm. Tap for quick bolts; hold to charge a seed that strips shields."},
	"repeater": {"name": "THORN REPEATER", "short": "REPEATER", "family": "alien", "mode": "bolt",
		"kind": "plasma", "auto": true, "rate": 0.11, "damage": 8.0, "speed": 62.0,
		"drain": 0.0035, "heat_per_shot": 0.045, "cool_rate": 0.5, "overheat_time": 2.2,
		"spread": 0.03, "aim_spread": 0.014, "recoil": 0.006, "zoom": 58.0,
		"sfx": "enemy_bolt", "sfx_pitch": 1.15, "color": Color(1.0, 0.2, 0.75), "flash": Color(1.0, 0.3, 0.8),
		"glow": Color(1.0, 0.2, 0.75), "skin": Color(0.12, 0.2, 0.2),
		"blurb": "Trooper rifle. Rapid plasma bolts, good against shields."},
	"spore_launcher": {"name": "SPORE LAUNCHER", "short": "SPORE LAUNCHER", "family": "alien", "mode": "lob",
		"kind": "explosive", "auto": false, "rate": 1.0, "damage": 70.0, "speed": 24.0, "grav": 14.0,
		"blast": 3.6, "drain": 0.085,
		"spread": 0.0, "aim_spread": 0.0, "recoil": 0.05, "zoom": 62.0,
		"sfx": "mortar", "color": Color(0.4, 1.0, 0.3), "flash": Color(0.5, 1.0, 0.4),
		"glow": Color(0.4, 1.0, 0.3), "skin": Color(0.22, 0.25, 0.12),
		"blurb": "Bulwark launcher. Lobs explosive spores in an arc. Mind the blast."},
	"lance": {"name": "THORN LANCE", "short": "LANCE", "family": "alien", "mode": "beam",
		"kind": "plasma", "auto": false, "rate": 0.9, "damage": 90.0, "charge_time": 0.55,
		"drain": 0.1, "spread": 0.04, "aim_spread": 0.0008, "recoil": 0.06, "zoom": 24.0,
		"sfx": "lancer_fire", "color": Color(1.0, 0.25, 0.15), "flash": Color(1.0, 0.3, 0.2),
		"glow": Color(1.0, 0.15, 0.1), "skin": Color(0.18, 0.14, 0.2),
		"blurb": "Lancer beam rifle. Hold to charge, release for a long-range beam."},
}

const START := ["carbine", "sidearm"]
## The bunker armory, left to right.
const RACK := ["breacher", "marksman", "arc_caster", "carbine", "sidearm"]
## What each Thorn type carries (and drops).
const ENEMY_WEAPON := {"stalker": "spitter", "trooper": "repeater", "bulwark": "spore_launcher", "lancer": "lance"}


## A fresh state. `fill` (0..1) sets how loaded it is: magazine weapons get a
## full mag and that fraction of their starting reserve, battery weapons that
## much charge.
static func new_state(id: String, fill := 1.0) -> Dictionary:
	var st: Dictionary = DEFS[id].duplicate(true)
	st.id = id
	st.heat = 0.0
	st.overheated = 0.0
	st.charge = 0.0
	if st.has("mag"):
		st.ammo = int(st.mag)
		st.reserve = int(round(float(st.start_reserve) * fill))
	if st.get("drain", 0.0) > 0.0:
		st.battery = clampf(fill, 0.0, 1.0)
	return st


static func uses_mag(st: Dictionary) -> bool:
	return st.has("mag")


static func uses_battery(st: Dictionary) -> bool:
	return st.has("battery")


static func is_empty(st: Dictionary) -> bool:
	if uses_mag(st):
		return st.ammo <= 0 and st.reserve <= 0
	return st.battery <= 0.0005


## Fraction of "full" (for HUD and ammo transfer).
static func fullness(st: Dictionary) -> float:
	if uses_mag(st):
		return float(st.ammo + st.reserve) / float(st.mag + st.max_reserve)
	return st.battery


## Moves ammo from a dropped copy of the same weapon into the carried one.
## Returns true if anything was taken.
static func scavenge(into: Dictionary, from: Dictionary) -> bool:
	if uses_mag(into):
		var room: int = int(into.max_reserve) - int(into.reserve)
		var avail: int = int(from.ammo) + int(from.reserve)
		var take := mini(room, avail)
		if take <= 0:
			return false
		into.reserve += take
		var left := avail - take
		from.ammo = mini(left, int(from.mag))
		from.reserve = left - from.ammo
		return true
	# batteries can't be split: swap to the fuller one
	if from.battery > into.battery + 0.01:
		var t: float = into.battery
		into.battery = from.battery
		from.battery = t
		return true
	return false


# ---------------------------------------------------------------- models

static var _mesh := {}


static func _m(key: String) -> Mesh:
	if _mesh.is_empty():
		var cap := CapsuleMesh.new()
		cap.radius = 0.5
		cap.height = 2.0
		cap.radial_segments = 10
		cap.rings = 3
		var sph := SphereMesh.new()
		sph.radius = 0.5
		sph.height = 1.0
		sph.radial_segments = 10
		sph.rings = 5
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.5
		cone.height = 1.0
		cone.radial_segments = 6
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		cyl.height = 1.0
		cyl.radial_segments = 10
		var box := BoxMesh.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.75
		tor.outer_radius = 1.0
		_mesh = {"cap": cap, "sph": sph, "cone": cone, "cyl": cyl, "box": box, "tor": tor}
	return _mesh[key]


static func _part(parent: Node3D, mesh: String, mat: Material, pos: Vector3, scl: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _m(mesh)
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _std(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _glow(c: Color, e := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r * e, c.g * e, c.b * e)
	return m


## Model for a weapon, pointing down -Z with the grip near the origin. The
## muzzle position is stored in meta "muzzle" (Vector3, model space).
## Human weapons use the textured asset-pack guns when available.
static func model(id: String) -> Node3D:
	var d: Dictionary = DEFS[id]
	var root: Node3D
	if d.family == "human" and ModelKit.enabled and d.has("kit") and ModelKit.gun_available(d.kit[0]):
		var g := ModelKit.gun(d.kit[0], d.kit[1], d.kit[2])
		root = Node3D.new()
		g.position = d.kit[3]
		root.add_child(g)
		root.set_meta("muzzle", g.position + ModelKit.gun_muzzle(g))
	elif d.family == "human":
		root = _human_proc(id)
	else:
		root = _alien(id)
	root.name = id
	return root


## Simple box-and-cylinder guns for when the asset packs aren't downloaded.
static func _human_proc(id: String) -> Node3D:
	var r := Node3D.new()
	var gun := _std(Color(0.17, 0.18, 0.19), 0.4, 0.7)
	var grip := _std(Color(0.07, 0.07, 0.07), 0.85)
	var olive := _std(Color(0.25, 0.28, 0.17), 0.7, 0.1)
	var wood := _std(Color(0.35, 0.22, 0.12), 0.7)
	# [body length, barrel length, body height, stock?, furniture]
	var spec: Array = {"carbine": [0.42, 0.22, 0.09, true, olive], "sidearm": [0.2, 0.05, 0.07, false, gun],
		"breacher": [0.36, 0.3, 0.08, true, wood], "marksman": [0.5, 0.4, 0.08, true, olive],
		"arc_caster": [0.38, 0.12, 0.11, false, _std(Color(0.82, 0.84, 0.8), 0.3, 0.3)]}[id]
	var bl: float = spec[0]
	var brl: float = spec[1]
	var bh: float = spec[2]
	_part(r, "box", gun, Vector3(0, 0, -bl * 0.35), Vector3(0.06, bh, bl))
	_part(r, "box", spec[4], Vector3(0, -0.01, -bl * 0.75), Vector3(0.055, bh * 0.75, bl * 0.4))
	_part(r, "cyl", gun, Vector3(0, 0.01, -bl * 0.85 - brl * 0.5), Vector3(0.03, brl, 0.03), Vector3(PI / 2, 0, 0))
	_part(r, "box", grip, Vector3(0, -0.11, -0.05), Vector3(0.045, 0.16, 0.06), Vector3(0.25, 0, 0))
	if spec[3]:
		_part(r, "box", spec[4], Vector3(0, -0.02, bl * 0.3), Vector3(0.05, 0.08, 0.2))
	if id == "marksman":
		_part(r, "cyl", grip, Vector3(0, 0.08, -0.1), Vector3(0.05, 0.2, 0.05), Vector3(PI / 2, 0, 0))
	if id == "breacher":
		_part(r, "cyl", gun, Vector3(0, -0.03, -bl * 0.85 - brl * 0.5), Vector3(0.028, brl, 0.028), Vector3(PI / 2, 0, 0))
	r.set_meta("muzzle", Vector3(0, 0.01, -bl * 0.85 - brl))
	return r


## Organic Thorn weapons: veined skin, glowing sacs and spines.
static func _alien(id: String) -> Node3D:
	var d: Dictionary = DEFS[id]
	var r := Node3D.new()
	var skin := Shaders.enemy_skin(d.skin, d.glow, 1.0)
	var dark := Shaders.enemy_skin(Color(d.skin.r * 0.4, d.skin.g * 0.4, d.skin.b * 0.4), d.glow, 0.3)
	var glow := _glow(d.glow, 3.0)
	var muzzle := Vector3.ZERO
	match id:
		"spitter":
			_part(r, "cap", skin, Vector3(0, 0, -0.1), Vector3(0.09, 0.15, 0.09), Vector3(PI / 2, 0, 0))
			_part(r, "sph", glow, Vector3(0, 0.05, -0.05), Vector3(0.07, 0.06, 0.1))
			for s in [-1.0, 1.0]:
				_part(r, "cone", dark, Vector3(0.028 * s, 0, -0.27), Vector3(0.025, 0.09, 0.025), Vector3(-PI / 2, 0, 0.2 * s))
			_part(r, "cap", dark, Vector3(0, -0.08, 0.02), Vector3(0.05, 0.06, 0.05), Vector3(0.3, 0, 0))
			muzzle = Vector3(0, 0, -0.28)
		"repeater":
			_part(r, "cap", skin, Vector3(0, 0, -0.16), Vector3(0.11, 0.24, 0.11), Vector3(PI / 2, 0, 0))
			for z in [-0.08, -0.18, -0.28]:
				_part(r, "tor", glow, Vector3(0, 0, z), Vector3.ONE * 0.065, Vector3(PI / 2, 0, 0))
			for a in 3:
				var ang := TAU * a / 3.0
				_part(r, "cone", dark, Vector3(cos(ang) * 0.035, sin(ang) * 0.035, -0.43), Vector3(0.022, 0.1, 0.022), Vector3(-PI / 2, 0, 0))
			_part(r, "sph", glow, Vector3(0, -0.06, -0.14), Vector3(0.06, 0.05, 0.12))
			_part(r, "cap", dark, Vector3(0, -0.1, 0.03), Vector3(0.05, 0.07, 0.05), Vector3(0.3, 0, 0))
			muzzle = Vector3(0, 0, -0.44)
		"spore_launcher":
			_part(r, "cap", skin, Vector3(0, 0, -0.14), Vector3(0.17, 0.24, 0.17), Vector3(PI / 2, 0, 0))
			_part(r, "sph", glow, Vector3(0, 0.08, -0.22), Vector3.ONE * 0.13)
			_part(r, "cyl", dark, Vector3(0, 0, -0.38), Vector3(0.09, 0.12, 0.09), Vector3(PI / 2, 0, 0))
			for i in 4:
				_part(r, "cone", dark, Vector3(-0.06 + i * 0.04, 0.1, 0.02), Vector3(0.025, 0.08, 0.025), Vector3(0.6, 0, 0))
			_part(r, "cap", dark, Vector3(0, -0.12, 0.04), Vector3(0.055, 0.07, 0.055), Vector3(0.3, 0, 0))
			muzzle = Vector3(0, 0, -0.45)
		"lance":
			_part(r, "cap", skin, Vector3(0, 0, -0.3), Vector3(0.065, 0.45, 0.065), Vector3(PI / 2, 0, 0))
			_part(r, "box", dark, Vector3(0, 0.045, -0.25), Vector3(0.012, 0.05, 0.6))
			for s in [-1.0, 1.0]:
				_part(r, "box", dark, Vector3(0.045 * s, 0, -0.15), Vector3(0.05, 0.012, 0.18), Vector3(0, 0.3 * s, 0))
			_part(r, "sph", glow, Vector3(0, 0, -0.72), Vector3.ONE * 0.055)
			_part(r, "box", glow, Vector3(0, 0.02, -0.3), Vector3(0.008, 0.008, 0.4))
			_part(r, "cap", dark, Vector3(0, -0.09, 0.0), Vector3(0.045, 0.065, 0.045), Vector3(0.3, 0, 0))
			muzzle = Vector3(0, 0, -0.75)
	r.set_meta("muzzle", muzzle)
	r.set_meta("glow_mat", glow)
	return r
