extends StaticBody3D
## Explosive fuel barrel. Shoot it.

const Effects = preload("res://scripts/effects.gd")

var health := 25.0
var exploded := false
var last_attacker: Node = null


func _ready() -> void:
	add_to_group("damageable")
	collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.42
	sh.height = 1.25
	cs.shape = sh
	cs.position.y = 0.625
	add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 1.25
	mi.mesh = cm
	mi.position.y = 0.625
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.12, 0.08)
	mat.roughness = 0.5
	mat.metallic = 0.4
	mi.material_override = mat
	add_child(mi)
	for y in [0.3, 0.95]:
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.44
		bm.bottom_radius = 0.44
		bm.height = 0.08
		band.mesh = bm
		band.position.y = y
		band.material_override = Effects.glow_mat(Color(1.0, 0.75, 0.1), 1.2)
		add_child(band)


func is_alive() -> bool:
	return not exploded


func take_damage(amount: float, _kind: String, _from: Vector3, _hit_pos = null) -> String:
	if exploded:
		return ""
	health -= amount
	if health <= 0.0:
		exploded = true
		remove_from_group("damageable")
		var t := get_tree().create_timer(0.12, false)
		t.timeout.connect(_boom)
	return ""


func _boom() -> void:
	if not is_inside_tree():
		return
	var pl := get_tree().get_first_node_in_group("player")
	Effects.explode(self, global_position + Vector3.UP * 0.6, 6.5, 120.0, "explosive", pl)
	queue_free()
