extends Node3D
## Simple raycast-stepped projectile (plasma bolts, mortar blobs).

const Effects = preload("res://scripts/effects.gd")

var vel := Vector3.ZERO
var damage := 10.0
var kind := "plasma"
var from_player := false
var shooter: Node = null
var grav := 0.0
var blast_radius := 0.0
var life := 4.0
var color := Color(1.0, 0.2, 0.8)
var size := 0.1
var stretch := 3.0
var with_light := false
var source_pos := Vector3.ZERO
## Optional: steer toward this node (charged Spitter seed). `homing` = turn rate.
var homing_target: Node3D = null
var homing := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.scale = Vector3(1.0, 1.0, stretch)
	mi.material_override = Effects.glow_mat(color, 5.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if with_light:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 1.6
		l.omni_range = 3.5
		add_child(l)
	if vel.length_squared() > 0.01:
		Effects.safe_look_at(self, global_position + vel)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		if blast_radius > 0.0:
			Effects.explode(self, global_position, blast_radius, damage, kind, shooter)
		queue_free()
		return
	vel.y -= grav * delta
	if homing > 0.0 and homing_target != null and is_instance_valid(homing_target):
		var aim: Vector3 = homing_target.global_position + Vector3.UP * float(homing_target.get("head_y") if homing_target.get("head_y") != null else 1.0) * 0.7
		var spd := vel.length()
		vel = vel.normalized().slerp((aim - global_position).normalized(), clampf(homing * delta, 0.0, 1.0)) * spd
	var from := global_position
	var to := from + vel * delta
	var mask := (1 | 4) if from_player else (1 | 2)
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_impact(hit)
		return
	global_position = to
	if vel.length_squared() > 0.01:
		Effects.safe_look_at(self, to + vel)


func _impact(hit: Dictionary) -> void:
	var pos: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	if blast_radius > 0.0:
		Effects.explode(self, pos + normal * 0.2, blast_radius, damage, kind, shooter)
	else:
		var c: Object = hit.collider
		if c != null and c.has_method("take_damage"):
			var res = c.take_damage(damage, kind, source_pos, pos)
			if from_player and shooter != null and is_instance_valid(shooter) and shooter.has_method("register_hit"):
				shooter.register_hit(res)
		Effects.impact(self, pos, normal, color)
	queue_free()
