extends RigidBody3D
## Player frag grenade.

const Effects = preload("res://scripts/effects.gd")
const Sfx = preload("res://scripts/sfx.gd")

var fuse := 2.2
var thrower: Node = null
var _light: OmniLight3D
var _blink := 0.0
var _bounces := 0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 4
	mass = 0.4
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.11
	cs.shape = sh
	add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.2
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.26, 0.14)
	mat.roughness = 0.6
	mi.material_override = mat
	add_child(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.1)
	_light.omni_range = 1.5
	_light.light_energy = 0.0
	add_child(_light)


func _on_body_entered(_b: Node) -> void:
	if _bounces < 4 and linear_velocity.length() > 2.0:
		Sfx.play_at(self, "bounce", global_position, -4.0)
	_bounces += 1


func _physics_process(delta: float) -> void:
	fuse -= delta
	_blink += delta * (6.0 if fuse > 0.8 else 16.0)
	_light.light_energy = 2.0 if fmod(_blink, 1.0) < 0.3 else 0.0
	if fuse <= 0.0:
		Effects.explode(self, global_position, 7.0, 135.0, "explosive", thrower)
		queue_free()
