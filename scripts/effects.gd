extends RefCounted
## Visual effects and explosion damage helpers.

const Sfx = preload("res://scripts/sfx.gd")

static var _mat_cache: Dictionary = {}


static func world(node: Node) -> Node3D:
	var w := node.get_tree().get_first_node_in_group("world")
	if w == null:
		w = node.get_tree().current_scene
	return w as Node3D


static func glow_mat(color: Color, energy := 3.0, additive := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color, energy, additive]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	if color.a < 1.0 or additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_cache[key] = m
	return m


static func safe_look_at(n: Node3D, target: Vector3) -> void:
	var d := target - n.global_position
	if d.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT
	n.look_at(target, up)


static func tracer(node: Node, from: Vector3, to: Vector3, color := Color(1.0, 0.85, 0.5), width := 0.012) -> void:
	if from.distance_to(to) > 3.0:
		from = from.move_toward(to, 1.5)
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, length)
	mi.mesh = bm
	mi.material_override = glow_mat(color, 2.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world(node).add_child(mi)
	mi.global_position = (from + to) * 0.5
	safe_look_at(mi, to)
	var tw := mi.create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.08)
	tw.tween_callback(mi.queue_free)


static func burst(node: Node, pos: Vector3, normal: Vector3, color: Color, amount := 10, speed := 5.0,
		lifetime := 0.4, size := 0.05, grav := 9.8, spread := 50.0, energy := 3.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 1.0
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = glow_mat(color, energy)
	p.mesh = m
	p.direction = normal if normal.length_squared() > 0.01 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -grav, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world(node).add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(lifetime + 0.4)
	tw.tween_callback(p.queue_free)


static func smoke(node: Node, pos: Vector3, amount := 14, size := 0.9, lifetime := 1.6) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.9
	var m := SphereMesh.new()
	m.radius = size * 0.5
	m.height = size
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.17, 0.15, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.mesh = m
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, 0.8, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.8
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world(node).add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(lifetime + 0.4)
	tw.tween_callback(p.queue_free)


static func flash(node: Node, pos: Vector3, color: Color, energy: float, light_range: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	world(node).add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)


static func impact(node: Node, pos: Vector3, normal: Vector3, color: Color) -> void:
	burst(node, pos + normal * 0.05, normal, color, 8, 5.0, 0.3, 0.04)


static func explode(node: Node, pos: Vector3, radius: float, damage: float, kind: String, source: Node) -> void:
	var w := world(node)
	var tree := node.get_tree()
	# fireball
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	mi.material_override = glow_mat(Color(1.0, 0.55, 0.15), 5.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.55, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "transparency", 1.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)
	flash(w, pos + Vector3.UP * 0.6, Color(1.0, 0.6, 0.25), 10.0, radius * 3.0, 0.5)
	burst(w, pos, Vector3.UP, Color(1.0, 0.5, 0.1), 26, 12.0, 0.7, 0.08, 14.0, 80.0)
	burst(w, pos, Vector3.UP, Color(0.15, 0.12, 0.1), 14, 8.0, 1.0, 0.14, 16.0, 70.0, 0.4)
	smoke(w, pos + Vector3.UP * 0.4)
	Sfx.play_at(w, "explosion", pos, 4.0)
	# damage
	var space := w.get_world_3d().direct_space_state
	for n in tree.get_nodes_in_group("damageable"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var center: Vector3 = (n as Node3D).global_position + Vector3.UP * 0.8
		var d := center.distance_to(pos)
		if d > radius + 0.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, center, 1)
		if n is CollisionObject3D:
			q.exclude = [(n as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			continue
		var f := clampf(1.0 - d / (radius + 0.5), 0.0, 1.0)
		var dmg := damage * (0.25 + 0.75 * f)
		var res = n.take_damage(dmg, kind, pos, center)
		if source != null and is_instance_valid(source) and n != source and source.has_method("register_hit"):
			source.register_hit(res)
		if n.has_method("apply_knockback"):
			n.apply_knockback((center - pos).normalized() * 9.0 * f)
	var pl := tree.get_first_node_in_group("player")
	if pl != null and pl.has_method("add_shake"):
		pl.add_shake(clampf(1.2 - (pl as Node3D).global_position.distance_to(pos) / (radius * 4.0), 0.0, 1.0))
