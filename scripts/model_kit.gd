extends RefCounted
## Optional animated enemy, weapon and pickup models from two CC0 Quaternius
## packs (fetched by tools/fetch_assets.py):
##   Sci-Fi Essentials Kit : QuadShell (stalker), EyeDrone (lancer), guns, props
##   Animated Mech Pack    : George / Leela / Mike (trooper), Stan (bulwark)
## Every robot gets the Thorn-vein material so the two packs read as one
## faction. When the packs are missing, `enabled` stays false and the game
## builds its procedural models instead.

const Shaders = preload("res://scripts/shaders.gd")
const ESS := "res://assets/third_party/scifi_essentials/glTF/"
const MECH := "res://assets/third_party/mechs/"

## Set by main.gd from the "models" setting.
static var enabled := false

const MECH_ANIMS := {"idle": "Idle", "walk": "Walk", "run": "Run", "shoot": "Shoot",
	"melee": "Punch", "hit": "HitRecieve_1", "death": "Death"}

## scale converts the source model to game size; the vein pattern is sized in
## metres whatever units the source file used.
const ENEMIES := {
	"stalker": [{"file": ESS + "Enemy_QuadShell.gltf", "scale": 0.8, "coverage": 0.55,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "melee": "Attack",
			"leap": "Charge", "hit": "Hit", "death": "TurnOff"}, "run_speed": 5.0}],
	"trooper": [
		{"file": MECH + "FBX/George.fbx", "tex": "George", "scale": 0.31, "anims": MECH_ANIMS, "run_speed": 4.0},
		{"file": MECH + "FBX/Leela.fbx", "tex": "Leela", "scale": 0.37, "anims": MECH_ANIMS, "run_speed": 4.0},
		{"file": MECH + "FBX/Mike.fbx", "tex": "Mike", "scale": 0.37, "anims": MECH_ANIMS, "run_speed": 4.0},
	],
	"bulwark": [{"file": MECH + "FBX/Stan.fbx", "tex": "Stan", "scale": 0.46, "coverage": 0.6,
		"anims": MECH_ANIMS, "run_speed": 99.0}],
	"lancer": [{"file": ESS + "Enemy_EyeDrone.gltf", "scale": 1.05, "hover": 1.25, "coverage": 0.35,
		"anims": {"idle": "Idle", "walk": "Look", "run": "Look", "charge": "Charging",
			"shoot": "Attack", "hit": "Hit"}}],
}

const LOOPING := ["Idle", "Walk", "Run", "Look", "Charging"]

static var _scenes := {}
static var _mech_mats := {}


static func available() -> bool:
	return ResourceLoader.exists(ESS + "Enemy_QuadShell.gltf") \
		and ResourceLoader.exists(MECH + "FBX/Stan.fbx")


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func _mech_material(tex: String) -> StandardMaterial3D:
	if not _mech_mats.has(tex):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(MECH + "Textures/%s_Texture.png" % tex)
		# the Thorn have been at these machines: a little grimier than stock
		m.albedo_color = Color(0.78, 0.8, 0.74)
		m.roughness = 0.75
		m.metallic = 0.15
		_mech_mats[tex] = m
	return _mech_mats[tex]


## Builds an animated robot for an enemy type.
## Returns {root, anim (AnimationPlayer), overlay (ShaderMaterial), anims, hover, run_speed}
static func enemy(type: String, glow: Color) -> Dictionary:
	var variants: Array = ENEMIES[type]
	var spec: Dictionary = variants[randi() % variants.size()]
	var inst: Node3D = _scene(spec.file).instantiate()
	var root := Node3D.new()
	root.add_child(inst)
	# both packs face +Z; the game's "forward" is -Z
	inst.rotation.y = PI
	inst.scale = Vector3.ONE * float(spec.scale)
	# one material per enemy so hit flashes stay individual
	var overlay: ShaderMaterial = null
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			if overlay == null:
				var base: BaseMaterial3D = _mech_material(spec.tex) if spec.has("tex") else m.get_active_material(s)
				# vertex units -> metres: the mech FBX meshes sit under a x100 node
				var unit := float(spec.scale) * _chain_scale(m, inst)
				overlay = Shaders.thorn_robot(base, glow, unit, float(spec.get("coverage", 0.45)))
			m.set_surface_override_material(s, overlay)
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	if ap:
		for n in LOOPING:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		ap.play(spec.anims.idle)
		ap.seek(randf() * 1.0, true)
	return {"root": root, "anim": ap, "overlay": overlay, "anims": spec.anims,
		"hover": float(spec.get("hover", 0.0)), "run_speed": float(spec.get("run_speed", 4.0))}


# ---------------------------------------------------------------- weapons / props

## Gun model scaled to `length` metres, pointing down -Z with the grip near
## the origin. `path` is a full res:// path or a Sci-Fi Essentials gun name.
## Essentials guns are modelled barrel-towards -X; the Ultimate Gun Pack ones
## barrel-towards +X (barrel_plus_x).
static func gun(path: String, length: float, barrel_plus_x := false) -> Node3D:
	if not path.begins_with("res://"):
		path = ESS + path + ".gltf"
	var inst: Node3D = _scene(path).instantiate()
	var root := Node3D.new()
	root.add_child(inst)
	var aabb := _aabb(inst)
	var s := length / maxf(aabb.size.x, 0.01)
	inst.scale = Vector3.ONE * s
	inst.rotation.y = PI / 2 if barrel_plus_x else -PI / 2
	root.set_meta("barrel_plus_x", barrel_plus_x)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func gun_available(path: String) -> bool:
	if not path.begins_with("res://"):
		path = ESS + path + ".gltf"
	return ResourceLoader.exists(path)


## Returns the barrel tip of a gun built by gun(), in the gun root's space.
static func gun_muzzle(root: Node3D) -> Vector3:
	var inst := root.get_child(0) as Node3D
	var aabb := _aabb(inst)
	var x := aabb.end.x if root.get_meta("barrel_plus_x", false) else aabb.position.x
	var tip := Vector3(x, aabb.position.y + aabb.size.y * 0.78, 0.0)
	return inst.transform * tip


static func prop(name: String, height: float) -> Node3D:
	var inst: Node3D = _scene(ESS + name + ".gltf").instantiate()
	var aabb := _aabb(inst)
	var s := height / maxf(maxf(aabb.size.y, aabb.size.x), 0.01)
	inst.scale = Vector3.ONE * s
	var root := Node3D.new()
	root.add_child(inst)
	inst.position = -aabb.get_center() * s
	return root


static func _chain_scale(n: Node3D, top: Node3D) -> float:
	var sc := 1.0
	var c: Node = n
	while c != null and c != top:
		if c is Node3D:
			sc *= (c as Node3D).scale.x
		c = c.get_parent()
	return sc


static func _aabb(n: Node3D) -> AABB:
	var acc: Array = [null]
	_aabb_walk(n, Transform3D.IDENTITY, acc, true)
	return acc[0] if acc[0] != null else AABB()


static func _aabb_walk(n: Node, xf: Transform3D, acc: Array, is_root := false) -> void:
	var t := xf
	if n is Node3D and not is_root:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_aabb_walk(c, t, acc)
