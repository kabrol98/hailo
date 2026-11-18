extends RefCounted
## Loads optional third-party vegetation models (Quaternius Stylized Nature
## MegaKit, CC0; fetched by tools/fetch_assets.py) and prepares them for
## instancing. Leaf/grass materials are swapped for the wind foliage shader.
## When the pack isn't present, available() is false and the arena uses its
## procedural vegetation instead.

const Shaders = preload("res://scripts/shaders.gd")
const DIR := "res://assets/third_party/stylized_nature/glTF/"

const JUNGLE_GREEN := {
	"Leaves_NormalTree": Color(0.36, 0.6, 0.16),
	"Leaves_TwistedTree": Color(0.2, 0.47, 0.14),
}

var protos := {}
var _mat_cache := {}


static func available() -> bool:
	return ResourceLoader.exists(DIR + "CommonTree_1.gltf")


## Returns {"parts": [{"mesh": Mesh, "xform": Transform3D}], "aabb": AABB}
func proto(name: String, sway := 1.0, sway_height := 0.0, tint := Color(1, 1, 1)) -> Dictionary:
	var key := "%s|%s|%s|%s" % [name, sway, sway_height, tint]
	if protos.has(key):
		return protos[key]
	var ps: PackedScene = load(DIR + name + ".gltf")
	var inst := ps.instantiate()
	var parts: Array = []
	_collect(inst, Transform3D.IDENTITY, parts)
	inst.free()
	var aabb := AABB()
	for i in parts.size():
		var p: Dictionary = parts[i]
		var src: Mesh = p.mesh
		# duplicate so different sway settings don't fight over one mesh
		var mesh: Mesh = src.duplicate()
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, _convert(src.surface_get_material(s), sway, sway_height, tint))
		p.mesh = mesh
		var b: AABB = p.xform * mesh.get_aabb()
		aabb = b if i == 0 else aabb.merge(b)
	var d := {"parts": parts, "aabb": aabb}
	protos[key] = d
	return d


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"mesh": (n as MeshInstance3D).mesh, "xform": t})
	for c in n.get_children():
		_collect(c, t, out)


func _convert(m: Material, sway: float, sway_height: float, tint: Color) -> Material:
	if not (m is BaseMaterial3D):
		return m
	var bm := m as BaseMaterial3D
	var n := bm.resource_name.to_lower()
	var foliage := n.contains("leaf") or n.contains("leaves") or n.contains("grass") or n.contains("flower")
	if not foliage or bm.albedo_texture == null:
		bm.roughness = maxf(bm.roughness, 0.85)
		return bm
	var tex: Texture2D = bm.albedo_texture
	var col := bm.albedo_color
	# Some leaf textures ship pre-coloured (the twisted tree's is autumn red).
	# Use the pack's white mask instead and tint it jungle green.
	var path := tex.resource_path
	if path.ends_with("_C.png") and ResourceLoader.exists(path.replace("_C.png", ".png")):
		tex = load(path.replace("_C.png", ".png"))
		col = JUNGLE_GREEN.get(path.get_file().replace("_C.png", ""), Color(0.3, 0.55, 0.16))
	var key := "%s|%s|%s|%s" % [tex.resource_path, sway, sway_height, tint]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var fm := Shaders.foliage_material(tex, Color(col.r * tint.r, col.g * tint.g, col.b * tint.b), sway, 0.5, sway_height)
	_mat_cache[key] = fm
	return fm
