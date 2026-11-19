extends Node
## Renders a side-on silhouette of each weapon's model once (in its own
## SubViewport), for HUD icons, so icons always match the models in use.
## Without a real renderer (headless tests) icons stay null and the HUD
## falls back to text.

const Weapons = preload("res://scripts/weapons.gd")
const ICON_SIZE := Vector2i(320, 120)

static var icons := {}
var _queue: Array = []
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in Weapons.DEFS:
		request(id)


func request(id: String) -> void:
	if icons.has(id) or id in _queue:
		return
	_queue.append(id)
	if not _busy:
		_busy = true
		_render_next.call_deferred()


static func icon(id: String) -> Texture2D:
	return icons.get(id)


func _render_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var id: String = _queue[0]
	if DisplayServer.get_name() == "headless":
		icons[id] = null
		_queue.pop_front()
		_render_next.call_deferred()
		return
	var vp := SubViewport.new()
	vp.size = ICON_SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var m := Weapons.model(id)
	vp.add_child(m)
	var aabb := _aabb(m)
	var c := aabb.get_center()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aspect := float(ICON_SIZE.x) / float(ICON_SIZE.y)
	cam.size = maxf(aabb.size.y * 1.15, aabb.size.z * 1.08 / aspect)
	vp.add_child(cam)
	# look from the gun's right side so the barrel points right on screen
	cam.look_at_from_position(c + Vector3.RIGHT * 4.0, c, Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	vp.add_child(sun)
	sun.look_at_from_position(c + Vector3(3, 2, 1), c, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGBA8)
		# flatten to a light silhouette with a hint of shading
		for y in img.get_height():
			for x in img.get_width():
				var p := img.get_pixel(x, y)
				if p.a < 0.04:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
				else:
					var l := 0.72 + 0.28 * clampf(p.get_luminance() * 2.5, 0.0, 1.0)
					img.set_pixel(x, y, Color(l, l, l, minf(p.a * 1.4, 1.0)))
		icons[id] = ImageTexture.create_from_image(img)
	else:
		icons[id] = null
	vp.queue_free()
	_queue.pop_front()
	_render_next.call_deferred()


static func _aabb(n: Node3D) -> AABB:
	var acc: Array = [null]
	_walk(n, Transform3D.IDENTITY, acc, true)
	return acc[0] if acc[0] != null else AABB(Vector3(-0.1, -0.1, -0.5), Vector3(0.2, 0.2, 1.0))


static func _walk(n: Node, xf: Transform3D, acc: Array, root := false) -> void:
	var t := xf
	if n is Node3D and not root:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for ch in n.get_children():
		_walk(ch, t, acc)
