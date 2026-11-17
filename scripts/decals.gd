extends RefCounted
## Bullet holes and scorch marks, recycled from a fixed-size pool.

const Shaders = preload("res://scripts/shaders.gd")

static var enabled := true
static var _holes: Array = []
static var _scorches: Array = []
const MAX_HOLES := 48
const MAX_SCORCH := 14


static func _spawn(pool: Array, cap: int, node: Node, pos: Vector3, normal: Vector3, tex: Texture2D, size: float, depth: float) -> void:
	if not enabled or node == null or not node.is_inside_tree():
		return
	var d: Decal
	# drop pooled decals whose world was freed (scene reload)
	while not pool.is_empty() and not is_instance_valid(pool[0]):
		pool.pop_front()
	if pool.size() >= cap:
		d = pool.pop_front()
	else:
		d = Decal.new()
		d.texture_albedo = tex
		d.cull_mask = 1
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		var w := node.get_tree().get_first_node_in_group("world")
		(w if w != null else node.get_tree().current_scene).add_child(d)
	pool.append(d)
	d.size = Vector3(size, depth, size)
	var n := normal.normalized()
	var ref := Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(n).normalized()
	var z := x.cross(n).normalized()
	var b := Basis(x, n, z).rotated(n, randf() * TAU)
	d.global_transform = Transform3D(b, pos)
	d.modulate = Color(1, 1, 1, 1)


static func bullet_hole(node: Node, pos: Vector3, normal: Vector3) -> void:
	_spawn(_holes, MAX_HOLES, node, pos, normal, Shaders.decal_texture("hole"), randf_range(0.14, 0.2), 0.25)


static func scorch(node: Node, pos: Vector3, radius: float) -> void:
	_spawn(_scorches, MAX_SCORCH, node, pos, Vector3.UP, Shaders.decal_texture("scorch"), radius * 1.1, 3.0)


static func clear() -> void:
	_holes.clear()
	_scorches.clear()
