extends Area3D
## Ammo / grenade / health drops, plus the persistent supply cache.

const Effects = preload("res://scripts/effects.gd")
const Sfx = preload("res://scripts/sfx.gd")

var kind := "ammo"
var persistent := false
var cooldown := 0.0
var life := 30.0
var _t := 0.0
var _vis: Node3D
var _glow_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.2 if persistent else 0.9
	cs.shape = sh
	cs.position.y = 0.6
	add_child(cs)
	body_entered.connect(_on_body)
	_vis = Node3D.new()
	_vis.position.y = 0.6
	add_child(_vis)
	var col := Color(1.0, 0.8, 0.2)
	match kind:
		"grenade": col = Color(0.4, 1.0, 0.3)
		"health": col = Color(1.0, 0.25, 0.25)
		"supply": col = Color(0.3, 0.9, 1.0)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.albedo_color = Color(col.r * 2.5, col.g * 2.5, col.b * 2.5)
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.18, 0.2, 0.17)
	base.metallic = 0.5
	base.roughness = 0.5
	if persistent:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.9, 1.0)
		body.mesh = bm
		body.material_override = base
		body.position.y = -0.15
		_vis.add_child(body)
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(1.62, 0.08, 1.02)
		strip.mesh = sm
		strip.material_override = _glow_mat
		strip.position.y = 0.15
		_vis.add_child(strip)
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.2
		l.omni_range = 4.0
		l.position.y = 0.8
		add_child(l)
	else:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.45, 0.3, 0.3)
		body.mesh = bm
		body.material_override = base
		_vis.add_child(body)
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.47, 0.06, 0.32)
		strip.mesh = sm
		strip.material_override = _glow_mat
		_vis.add_child(strip)
		if kind == "health":
			var cross := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.06, 0.2, 0.33)
			cross.mesh = cm
			cross.material_override = _glow_mat
			_vis.add_child(cross)


func _process(delta: float) -> void:
	_t += delta
	if persistent:
		cooldown = maxf(cooldown - delta, 0.0)
		var ready_now := cooldown <= 0.0
		_glow_mat.albedo_color.a = 1.0 if ready_now else 0.25
		_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if ready_now else BaseMaterial3D.TRANSPARENCY_ALPHA
		if ready_now:
			for b in get_overlapping_bodies():
				_on_body(b)
		return
	_vis.rotation.y = _t * 2.0
	_vis.position.y = 0.6 + sin(_t * 3.0) * 0.1
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body(b: Node) -> void:
	if persistent and cooldown > 0.0:
		return
	if b.has_method("apply_pickup") and b.apply_pickup(kind):
		Sfx.play_ui(self, "pickup", -3.0)
		if persistent:
			cooldown = 30.0
		else:
			queue_free()
