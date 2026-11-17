extends CharacterBody3D
## "The Thorn" — biomechanical jungle invaders. Four types:
##  stalker  : fast melee leaper, no shield
##  trooper  : shielded, fires plasma bursts, strafes, retreats to recharge
##  bulwark  : heavy, huge shield, lobs explosive mortar blobs, ground slam
##  lancer   : long-range charged beam with a visible targeting laser

signal died(enemy)

const Effects = preload("res://scripts/effects.gd")
const Sfx = preload("res://scripts/sfx.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const PickupScript = preload("res://scripts/pickup.gd")
const Shaders = preload("res://scripts/shaders.gd")

const GRAVITY := 16.0

static var M_BOX: BoxMesh
static var M_SPH: SphereMesh
static var M_CAP: CapsuleMesh
static var M_CONE: CylinderMesh

var type := "trooper"
var wave := 1
var max_health := 70.0
var health := 70.0
var max_shield := 0.0
var shield := 0.0
var shield_delay := 0.0
var shield_rate := 25.0
var speed := 4.2
var accel := 22.0
var radius := 0.45
var height := 1.8
var head_y := 1.45
var score_value := 100
var dmg_mult := 1.0
var min_range := 10.0
var max_range := 26.0

var player: Node3D
var agent: NavigationAgent3D
var collider: CollisionShape3D
var visual: Node3D
var legs: Array = []
var arms: Array = []
var skin_mat: ShaderMaterial
var dark_mat: ShaderMaterial
var glow_mat: StandardMaterial3D
var shell: MeshInstance3D
var shell_mat: StandardMaterial3D
var beam_root: Node3D
var beam_mat: StandardMaterial3D

var alive := true
var state := "fight"
var state_t := 0.0
var goal := Vector3.ZERO
var repath_t := 0.0
var los := false
var los_t := 0.0
var fire_cd := 1.5
var burst_left := 0
var burst_cd := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var melee_cd := 0.0
var leap_cd := 2.0
var leaping := false
var leap_t := 0.0
var charge_t := 0.0
var beam_aim := Vector3.ZERO
var flash_t := 0.0
var shell_t := 0.0
var walk_t := 0.0
var knock := Vector3.ZERO
var vocal_cd := 0.0
var stuck_t := 0.0
var _last_pos := Vector3.ZERO


static func _ensure_meshes() -> void:
	if M_BOX != null:
		return
	M_BOX = BoxMesh.new()
	M_SPH = SphereMesh.new()
	M_SPH.radius = 0.5
	M_SPH.height = 1.0
	M_SPH.radial_segments = 12
	M_SPH.rings = 6
	M_CAP = CapsuleMesh.new()
	M_CAP.radius = 0.5
	M_CAP.height = 2.0
	M_CAP.radial_segments = 12
	M_CAP.rings = 4
	M_CONE = CylinderMesh.new()
	M_CONE.top_radius = 0.0
	M_CONE.bottom_radius = 0.5
	M_CONE.height = 1.0
	M_CONE.radial_segments = 6


func setup(t: String, w: int) -> void:
	type = t
	wave = w
	var shield_scale := 1.0 + maxf(0.0, w - 4) * 0.06
	dmg_mult = minf(1.0 + (w - 1) * 0.04, 1.6)
	match type:
		"stalker":
			max_health = 50.0
			max_shield = 0.0
			speed = 7.2
			accel = 32.0
			radius = 0.4
			height = 1.25
			head_y = 0.85
			score_value = 50
		"trooper":
			max_health = 70.0
			max_shield = 50.0 * shield_scale
			speed = 4.3
			radius = 0.45
			height = 1.85
			head_y = 1.45
			score_value = 100
			min_range = 9.0
			max_range = 26.0
		"bulwark":
			max_health = 260.0
			max_shield = 170.0 * shield_scale
			speed = 2.7
			accel = 12.0
			radius = 0.85
			height = 2.7
			head_y = 2.15
			score_value = 400
			min_range = 6.0
			max_range = 32.0
			shield_rate = 35.0
		"lancer":
			max_health = 55.0
			max_shield = 30.0 * shield_scale
			speed = 4.0
			radius = 0.4
			height = 2.0
			head_y = 1.65
			score_value = 250
			min_range = 22.0
			max_range = 48.0
	health = max_health
	shield = max_shield
	fire_cd = randf_range(1.0, 2.5)


func is_alive() -> bool:
	return alive


func _ready() -> void:
	_ensure_meshes()
	add_to_group("enemy")
	add_to_group("damageable")
	collision_layer = 4
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(48)
	floor_snap_length = 0.4
	collider = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	collider.shape = cap
	collider.position.y = height * 0.5
	add_child(collider)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.9
	agent.target_desired_distance = 1.2
	agent.radius = radius
	agent.height = height
	agent.path_max_distance = 4.0
	add_child(agent)
	_build_visual()
	goal = global_position
	if type == "bulwark":
		Sfx.play_at(self, "roar", global_position, 6.0, 0.9)


# ---------------------------------------------------------------- visuals

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	skin_mat = Shaders.enemy_skin(Color(0.2, 0.2, 0.2), Color(1, 0.2, 0.8), 1.0)
	glow_mat = StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark_mat = Shaders.enemy_skin(Color(0.08, 0.08, 0.08), Color(1, 0.2, 0.8), 0.35)
	var dark := dark_mat
	var glow_col := Color(1, 0.2, 0.8)
	match type:
		"stalker":
			skin_mat.set_shader_parameter("albedo", Color(0.45, 0.22, 0.1))
			dark.set_shader_parameter("albedo", Color(0.15, 0.08, 0.05))
			glow_col = Color(1.0, 0.75, 0.1)
			glow_mat.albedo_color = glow_col * 3.0
			# low hunched quadruped
			_part(visual, M_CAP, skin_mat, Vector3(0, 0.75, 0), Vector3(0.75, 0.45, 0.75), Vector3(PI / 2, 0, 0))
			for i in 4:
				_part(visual, M_CONE, dark, Vector3(0, 1.05, 0.35 - i * 0.25), Vector3(0.18, 0.35, 0.18), Vector3(-0.5, 0, 0))
			var head := _part(visual, M_SPH, skin_mat, Vector3(0, 0.8, -0.65), Vector3(0.45, 0.38, 0.55))
			head.name = "Head"
			for s in [-1.0, 1.0]:
				_part(visual, M_SPH, glow_mat, Vector3(0.12 * s, 0.86, -0.88), Vector3.ONE * 0.09)
				_part(visual, M_CONE, dark, Vector3(0.14 * s, 0.68, -0.92), Vector3(0.07, 0.3, 0.07), Vector3(PI * 0.6, 0, 0))
			for corner in [Vector3(-0.3, 0.7, -0.35), Vector3(0.3, 0.7, -0.35), Vector3(-0.3, 0.7, 0.35), Vector3(0.3, 0.7, 0.35)]:
				var hip := _pivot(visual, corner)
				_part(hip, M_BOX, dark, Vector3(0, -0.35, 0), Vector3(0.12, 0.75, 0.12))
				legs.append(hip)
		"trooper":
			skin_mat.set_shader_parameter("albedo", Color(0.12, 0.2, 0.2))
			dark.set_shader_parameter("albedo", Color(0.06, 0.08, 0.08))
			glow_col = Color(1.0, 0.2, 0.75)
			glow_mat.albedo_color = glow_col * 3.0
			var torso := _part(visual, M_CAP, skin_mat, Vector3(0, 1.15, 0.05), Vector3(0.62, 0.38, 0.5), Vector3(-0.25, 0, 0))
			torso.name = "Torso"
			_part(visual, M_BOX, glow_mat, Vector3(0, 1.15, -0.2), Vector3(0.08, 0.5, 0.05), Vector3(-0.25, 0, 0))
			_part(visual, M_SPH, skin_mat, Vector3(0, 1.58, -0.12), Vector3(0.36, 0.34, 0.4))
			for e in [Vector3(-0.09, 1.62, -0.3), Vector3(0.09, 1.62, -0.3), Vector3(0, 1.7, -0.28)]:
				_part(visual, M_SPH, glow_mat, e, Vector3.ONE * 0.07)
			for i in 3:
				_part(visual, M_CONE, dark, Vector3(0, 1.45 - i * 0.25, 0.3), Vector3(0.12, 0.3, 0.12), Vector3(0.9, 0, 0))
			for s in [-1.0, 1.0]:
				var hip := _pivot(visual, Vector3(0.18 * s, 0.75, 0))
				_part(hip, M_BOX, dark, Vector3(0, -0.37, 0.05), Vector3(0.14, 0.78, 0.16), Vector3(0.15, 0, 0))
				legs.append(hip)
				var sh := _pivot(visual, Vector3(0.38 * s, 1.35, -0.05))
				_part(sh, M_BOX, dark, Vector3(0, -0.28, 0), Vector3(0.1, 0.55, 0.1))
				arms.append(sh)
			# arm cannon (organic growth)
			_part(visual, M_CAP, skin_mat, Vector3(0.38, 1.05, -0.35), Vector3(0.18, 0.25, 0.18), Vector3(PI / 2, 0, 0))
			_part(visual, M_SPH, glow_mat, Vector3(0.38, 1.05, -0.62), Vector3.ONE * 0.1)
		"bulwark":
			skin_mat.set_shader_parameter("albedo", Color(0.22, 0.25, 0.12))
			dark.set_shader_parameter("albedo", Color(0.1, 0.1, 0.06))
			glow_col = Color(0.4, 1.0, 0.3)
			glow_mat.albedo_color = glow_col * 3.0
			_part(visual, M_CAP, skin_mat, Vector3(0, 1.7, 0), Vector3(1.5, 0.75, 1.1))
			_part(visual, M_SPH, glow_mat, Vector3(0, 1.75, -0.5), Vector3(0.35, 0.35, 0.2))
			for s in [-1.0, 1.0]:
				_part(visual, M_BOX, dark, Vector3(0.55 * s, 2.25, 0), Vector3(0.7, 0.35, 0.9), Vector3(0, 0, 0.35 * s))
			_part(visual, M_SPH, skin_mat, Vector3(0, 2.35, -0.35), Vector3(0.5, 0.42, 0.5))
			for e in [Vector3(-0.12, 2.4, -0.58), Vector3(0.12, 2.4, -0.58)]:
				_part(visual, M_SPH, glow_mat, e, Vector3.ONE * 0.09)
			# mortar sac on back
			_part(visual, M_SPH, glow_mat, Vector3(0, 2.3, 0.6), Vector3(0.6, 0.6, 0.55))
			for i in 5:
				_part(visual, M_CONE, dark, Vector3(-0.5 + i * 0.25, 2.55, 0.25), Vector3(0.16, 0.5, 0.16), Vector3(0.4, 0, 0))
			for s in [-1.0, 1.0]:
				var hip := _pivot(visual, Vector3(0.45 * s, 1.0, 0))
				_part(hip, M_BOX, dark, Vector3(0, -0.5, 0), Vector3(0.38, 1.05, 0.42))
				legs.append(hip)
				var sh := _pivot(visual, Vector3(0.95 * s, 2.0, -0.1))
				_part(sh, M_BOX, dark, Vector3(0, -0.6, 0), Vector3(0.35, 1.2, 0.35))
				_part(sh, M_SPH, skin_mat, Vector3(0, -1.25, 0), Vector3.ONE * 0.5)
				arms.append(sh)
		"lancer":
			skin_mat.set_shader_parameter("albedo", Color(0.18, 0.14, 0.2))
			dark.set_shader_parameter("albedo", Color(0.07, 0.05, 0.08))
			glow_col = Color(1.0, 0.15, 0.1)
			glow_mat.albedo_color = glow_col * 3.0
			_part(visual, M_CAP, skin_mat, Vector3(0, 1.3, 0), Vector3(0.42, 0.42, 0.35))
			_part(visual, M_SPH, skin_mat, Vector3(0, 1.85, -0.05), Vector3(0.28, 0.4, 0.3))
			_part(visual, M_SPH, glow_mat, Vector3(0, 1.88, -0.2), Vector3(0.18, 0.06, 0.06))
			_part(visual, M_CONE, dark, Vector3(0, 2.15, 0.05), Vector3(0.12, 0.4, 0.12), Vector3(-0.3, 0, 0))
			for s in [-1.0, 1.0]:
				var hip := _pivot(visual, Vector3(0.14 * s, 0.85, 0))
				_part(hip, M_BOX, dark, Vector3(0, -0.42, 0), Vector3(0.1, 0.88, 0.12))
				legs.append(hip)
			# long beam rifle
			_part(visual, M_BOX, dark, Vector3(0.3, 1.4, -0.45), Vector3(0.1, 0.12, 1.2))
			_part(visual, M_SPH, glow_mat, Vector3(0.3, 1.4, -1.05), Vector3.ONE * 0.08)
			beam_root = Node3D.new()
			beam_root.position = Vector3(0.3, 1.4, -1.05)
			add_child(beam_root)
			beam_mat = StandardMaterial3D.new()
			beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			beam_mat.albedo_color = Color(3.0, 0.2, 0.1, 0.6)
			var beam := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.02, 0.02, 1.0)
			beam.mesh = bm
			beam.position.z = -0.5
			beam.material_override = beam_mat
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam_root.add_child(beam)
			beam_root.visible = false
	skin_mat.set_shader_parameter("glow", glow_col)
	dark_mat.set_shader_parameter("glow", glow_col)
	var l := OmniLight3D.new()
	l.light_color = glow_col
	l.light_energy = 0.6
	l.omni_range = 2.5
	l.position = Vector3(0, head_y, -0.4)
	visual.add_child(l)
	if max_shield > 0.0:
		shell = MeshInstance3D.new()
		shell.mesh = M_SPH
		shell.scale = Vector3(radius * 2.8, height * 1.15, radius * 2.8)
		shell.position.y = height * 0.5
		shell_mat = StandardMaterial3D.new()
		shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shell_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		shell_mat.albedo_color = Color(0.6, 0.4, 1.0, 0.0)
		shell.material_override = shell_mat
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shell)


# ---------------------------------------------------------------- damage

func take_damage(amount: float, kind: String, from: Vector3, hit_pos = null) -> String:
	if not alive:
		return ""
	var ms := 1.0
	var mh := 1.0
	match kind:
		"ballistic":
			ms = 0.75
			mh = 1.0
		"plasma":
			ms = 1.9
			mh = 0.7
		"melee":
			ms = 1.2
	var headshot := false
	if hit_pos is Vector3 and kind == "ballistic" and shield <= 0.0:
		if (hit_pos as Vector3).y > global_position.y + head_y - 0.15:
			amount *= 2.5
			headshot = true
	var leftover := amount
	if shield > 0.0:
		var sd := amount * ms
		if sd >= shield:
			leftover = (sd - shield) / ms
			shield = 0.0
			_shield_break()
		else:
			shield -= sd
			leftover = 0.0
			shell_t = 0.25
			Sfx.play_at(self, "shield_hit", global_position + Vector3.UP, -6.0)
	shield_delay = 5.0 if type != "bulwark" else 6.0
	if leftover > 0.0:
		health -= leftover * mh
		flash_t = 0.1
	# react: being shot pulls attention / makes troopers dodge
	if state == "fight" and randf() < 0.3:
		strafe_dir = -strafe_dir
	if health <= 0.0:
		_die(from)
		return "kill"
	if headshot:
		Effects.burst(self, hit_pos, Vector3.UP, Color(1, 0.4, 0.8), 6, 4.0, 0.3, 0.05)
	return "hit"


func _shield_break() -> void:
	shell_t = 0.6
	Sfx.play_at(self, "shield_break", global_position + Vector3.UP, 0.0)
	Effects.burst(self, global_position + Vector3.UP * height * 0.6, Vector3.UP, Color(0.6, 0.4, 1.0), 18, 6.0, 0.5, 0.06, 4.0, 180.0)
	if type == "trooper" and randf() < 0.75:
		state = "retreat"
		state_t = randf_range(2.5, 4.0)
		repath_t = 0.0


func apply_knockback(v: Vector3) -> void:
	knock += v * (0.3 if type == "bulwark" else 1.0)


func _die(_from: Vector3) -> void:
	alive = false
	remove_from_group("enemy")
	remove_from_group("damageable")
	collider.set_deferred("disabled", true)
	if beam_root:
		beam_root.visible = false
	Sfx.play_at(self, "enemy_die", global_position + Vector3.UP, 0.0, 1.3 if type == "stalker" else (0.7 if type == "bulwark" else 1.0))
	Effects.burst(self, global_position + Vector3.UP * height * 0.5, Vector3.UP, glow_mat.albedo_color / 3.0, 20, 5.0, 0.7, 0.07, 9.8, 120.0)
	_drop()
	died.emit(self)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(visual, "rotation:x", -PI / 2 * 0.9, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position:y", -0.2, 0.5)
	tw.chain().tween_interval(1.2)
	tw.chain().tween_property(visual, "position:y", -2.5, 1.0)
	tw.chain().tween_callback(queue_free)
	if shell:
		shell.visible = false


func _drop() -> void:
	var r := randf()
	var k := ""
	var bonus := 0.15 if type == "bulwark" else 0.0
	if r < 0.32 + bonus:
		k = "ammo"
	elif r < 0.45 + bonus:
		k = "grenade"
	elif r < 0.55 + bonus * 2.0:
		k = "health"
	if k == "":
		return
	var p := PickupScript.new()
	p.kind = k
	get_parent().add_child(p)
	p.global_position = global_position + Vector3.UP * 0.1


# ---------------------------------------------------------------- AI

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if global_position.y < -20.0:
		_die(global_position)
		return
	if player == null or not is_instance_valid(player):
		return
	_timers(delta)
	var player_alive: bool = player.is_alive()
	var to_p := player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	los_t -= delta
	if los_t <= 0.0:
		los_t = 0.2
		los = _check_los()
	if player_alive:
		_think(delta, dist, to_p)
	else:
		goal = global_position
	# steering
	repath_t -= delta
	if repath_t <= 0.0:
		repath_t = 0.3
		agent.target_position = goal
	var move_dir := Vector3.ZERO
	if not agent.is_navigation_finished():
		var nxt := agent.get_next_path_position()
		move_dir = nxt - global_position
		move_dir.y = 0.0
		if move_dir.length_squared() > 0.0001:
			move_dir = move_dir.normalized()
	move_dir += _separation() * 0.8
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()
	var spd := speed
	if state == "retreat":
		spd *= 1.25
	if type == "lancer" and charge_t > 0.0:
		spd *= 0.2
	if leaping:
		leap_t -= delta
		if leap_t <= 0.0 and is_on_floor():
			leaping = false
	else:
		var tv := move_dir * spd
		velocity.x = move_toward(velocity.x, tv.x, accel * delta)
		velocity.z = move_toward(velocity.z, tv.z, accel * delta)
	velocity += knock
	knock = Vector3.ZERO
	velocity.y -= GRAVITY * delta
	move_and_slide()
	_unstick(delta, move_dir)
	# facing
	var face := to_p if (los or dist < 12.0) and player_alive else Vector3(velocity.x, 0, velocity.z)
	if face.length_squared() > 0.01:
		var yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, yaw, 8.0 * delta)
	if player_alive:
		_combat(delta, dist)
	_animate(delta)


func _unstick(delta: float, move_dir: Vector3) -> void:
	# hop over small ledges we walk into
	if is_on_floor() and is_on_wall() and move_dir.length_squared() > 0.25 and not leaping:
		var n := get_wall_normal()
		if n.dot(move_dir) < -0.5:
			velocity.y = 4.5
	# detect stalls: wanting to move but not making progress
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	if move_dir.length_squared() > 0.25 and moved < speed * delta * 0.25:
		stuck_t += delta
	else:
		stuck_t = maxf(stuck_t - delta * 2.0, 0.0)
	if stuck_t > 1.2:
		stuck_t = 0.0
		var a := randf() * TAU
		goal = _nav_point(global_position + Vector3(cos(a), 0, sin(a)) * 5.0)
		agent.target_position = goal
		repath_t = 1.5
		if is_on_floor():
			velocity = Vector3(cos(a) * speed, 4.5, sin(a) * speed)


func _timers(delta: float) -> void:
	state_t -= delta
	strafe_t -= delta
	melee_cd -= delta
	leap_cd -= delta
	vocal_cd -= delta
	shield_delay -= delta
	if shield_delay <= 0.0 and shield < max_shield:
		shield = minf(max_shield, shield + shield_rate * delta)
	if flash_t > 0.0:
		flash_t -= delta
	skin_mat.set_shader_parameter("flash", 1.0 if flash_t > 0.0 else 0.0)
	if shell_mat:
		shell_t = maxf(shell_t - delta, 0.0)
		shell_mat.albedo_color.a = clampf(shell_t * 2.0, 0.0, 0.7)


func _check_los() -> bool:
	var from := global_position + Vector3.UP * head_y
	var to: Vector3 = player.global_position + Vector3.UP * 1.3
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _nav_point(p: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_closest_point(map, p)


func _think(_delta: float, dist: float, to_p: Vector3) -> void:
	var dir := to_p.normalized() if dist > 0.01 else Vector3.FORWARD
	var perp := Vector3(-dir.z, 0, dir.x)
	var ppos: Vector3 = player.global_position
	match type:
		"stalker":
			goal = ppos
			if vocal_cd <= 0.0 and dist < 25.0:
				vocal_cd = randf_range(3.0, 6.0)
				Sfx.play_at(self, "screech", global_position, -2.0, randf_range(0.9, 1.2))
		"bulwark":
			if not los or dist > 16.0:
				goal = ppos
			else:
				if strafe_t <= 0.0:
					strafe_t = randf_range(2.0, 4.0)
					strafe_dir = -strafe_dir
				goal = _nav_point(global_position + perp * strafe_dir * 3.0 + dir * 1.5)
		_:
			if state == "retreat":
				if state_t <= 0.0 or shield >= max_shield * 0.9:
					state = "fight"
				elif repath_t <= 0.05:
					goal = _nav_point(global_position - dir * 8.0 + perp * strafe_dir * 4.0)
				return
			if not los or dist > max_range:
				goal = ppos
			elif dist < min_range:
				goal = _nav_point(global_position - dir * 6.0 + perp * strafe_dir * 2.0)
			else:
				if strafe_t <= 0.0:
					strafe_t = randf_range(1.2, 2.8)
					if randf() < 0.6:
						strafe_dir = -strafe_dir
					goal = _nav_point(global_position + perp * strafe_dir * randf_range(3.0, 6.0))


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self:
			continue
		var d: Vector3 = global_position - (e as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		var min_d: float = radius + e.radius + 0.4
		if l < min_d and l > 0.001:
			push += d / l * (1.0 - l / min_d)
	return push


func _combat(delta: float, dist: float) -> void:
	match type:
		"stalker":
			if dist < 1.8 and melee_cd <= 0.0:
				melee_cd = 1.0
				player.take_damage(18.0 * dmg_mult, "melee", global_position, null)
				Sfx.play_at(self, "melee", global_position, 0.0)
			elif los and dist > 3.0 and dist < 9.0 and leap_cd <= 0.0 and is_on_floor():
				leap_cd = randf_range(2.5, 4.0)
				var d: Vector3 = (player.global_position - global_position)
				d.y = 0.0
				var lv := d.normalized() * minf(d.length() * 1.6, 13.0)
				velocity = Vector3(lv.x, 5.0, lv.z)
				leaping = true
				leap_t = 0.25
				Sfx.play_at(self, "screech", global_position, 2.0, 1.4)
		"trooper":
			if burst_left > 0:
				burst_cd -= delta
				if burst_cd <= 0.0:
					burst_left -= 1
					burst_cd = 0.13
					_shoot_bolt()
				return
			if los and dist < max_range + 8.0 and state != "retreat":
				fire_cd -= delta
				if fire_cd <= 0.0:
					fire_cd = randf_range(1.5, 2.5) / minf(dmg_mult, 1.3)
					burst_left = 3 if wave < 6 else 4
					burst_cd = 0.0
		"bulwark":
			if dist < 3.4 and melee_cd <= 0.0:
				melee_cd = 2.0
				Effects.burst(self, global_position, Vector3.UP, Color(0.5, 0.4, 0.3), 20, 6.0, 0.6, 0.12, 12.0, 80.0, 0.5)
				Effects.flash(self, global_position + Vector3.UP, Color(0.4, 1.0, 0.3), 4.0, 6.0, 0.3)
				Sfx.play_at(self, "melee", global_position, 6.0, 0.6)
				player.take_damage(35.0 * dmg_mult, "melee", global_position, null)
				if player.has_method("apply_knockback"):
					var kd: Vector3 = (player.global_position - global_position).normalized()
					player.apply_knockback(kd * 9.0 + Vector3.UP * 4.0)
				return
			if los and dist > 6.0 and dist < 42.0:
				fire_cd -= delta
				if fire_cd <= 0.0:
					fire_cd = randf_range(2.6, 3.6)
					_lob_mortar()
		"lancer":
			if charge_t > 0.0:
				charge_t -= delta
				var target: Vector3 = player.global_position + Vector3.UP * 1.2
				# tracking slows in the last moments so the player can dodge
				var track := 10.0 if charge_t > 0.45 else 1.2
				beam_aim = beam_aim.lerp(target, clampf(track * delta, 0.0, 1.0))
				_update_beam(charge_t < 0.45)
				if charge_t <= 0.0:
					_fire_beam()
				return
			if los and dist < max_range + 10.0:
				fire_cd -= delta
				if fire_cd <= 0.0:
					fire_cd = randf_range(4.0, 5.5)
					charge_t = 1.4
					beam_aim = player.global_position + Vector3.UP * 1.2
					beam_root.visible = true
					Sfx.play_at(self, "lancer_charge", global_position, 2.0)


func _muzzle() -> Vector3:
	return global_transform * Vector3(0.38, 1.05, -0.7)


func _shoot_bolt() -> void:
	var from := _muzzle()
	var target: Vector3 = player.global_position + Vector3.UP * 1.1
	var spd := 36.0
	var t := from.distance_to(target) / spd
	target += player.velocity * t * 0.55
	var dir := (target - from).normalized()
	var spread := 0.035 + from.distance_to(target) * 0.0006
	dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread) * 0.6, randf_range(-spread, spread))).normalized()
	var p := ProjectileScript.new()
	p.vel = dir * spd
	p.damage = 6.5 * dmg_mult
	p.kind = "plasma"
	p.color = Color(1.0, 0.2, 0.75)
	p.size = 0.09
	p.from_player = false
	p.shooter = self
	p.source_pos = global_position
	get_parent().add_child(p)
	p.global_position = from
	Sfx.play_at(self, "enemy_bolt", from, -2.0)


func _lob_mortar() -> void:
	var from := global_transform * Vector3(0, 2.6, 0.4)
	var target: Vector3 = player.global_position + player.velocity * 0.6
	var g := 14.0
	var tof := clampf(from.distance_to(target) / 14.0, 0.9, 2.4)
	var v := (target - from) / tof + Vector3.UP * 0.5 * g * tof
	var p := ProjectileScript.new()
	p.vel = v
	p.grav = g
	p.damage = 42.0 * dmg_mult
	p.kind = "explosive"
	p.blast_radius = 3.8
	p.color = Color(0.4, 1.0, 0.3)
	p.size = 0.28
	p.stretch = 1.4
	p.with_light = true
	p.life = 6.0
	p.shooter = self
	p.source_pos = global_position
	get_parent().add_child(p)
	p.global_position = from
	Sfx.play_at(self, "mortar", from, 3.0)


func _update_beam(locked: bool) -> void:
	var from := beam_root.global_position
	var len := from.distance_to(beam_aim)
	var q := PhysicsRayQueryParameters3D.create(from, from + (beam_aim - from).normalized() * 120.0, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		len = from.distance_to(hit.position)
	Effects.safe_look_at(beam_root, beam_aim)
	beam_root.scale = Vector3(1.0 if not locked else 2.0, 1.0 if not locked else 2.0, maxf(len, 0.1))
	beam_mat.albedo_color = Color(3.0, 0.2, 0.1, 0.35 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.03))) if not locked else Color(4.0, 1.5, 1.0, 0.9)


func _fire_beam() -> void:
	beam_root.visible = false
	var from := beam_root.global_position
	var dir := (beam_aim - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + dir * 120.0
	if not hit.is_empty():
		end = hit.position
		var c: Object = hit.collider
		if c != null and c.has_method("take_damage"):
			c.take_damage(38.0 * dmg_mult, "plasma", global_position, end)
		Effects.impact(self, end, hit.normal, Color(1, 0.3, 0.1))
	Effects.tracer(self, from, end, Color(1.0, 0.35, 0.2), 0.08)
	Effects.flash(self, from, Color(1, 0.3, 0.2), 4.0, 6.0, 0.2)
	Sfx.play_at(self, "lancer_fire", from, 4.0)


func _animate(delta: float) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	var ratio := clampf(hv / maxf(speed, 0.1), 0.0, 1.5)
	walk_t += delta * (4.0 + hv * 1.6)
	for i in legs.size():
		var phase := PI if i % 2 == 1 else 0.0
		if type == "stalker" and i >= 2:
			phase += PI * 0.5
		(legs[i] as Node3D).rotation.x = sin(walk_t + phase) * 0.6 * ratio
	for i in arms.size():
		(arms[i] as Node3D).rotation.x = -sin(walk_t + (PI if i % 2 == 0 else 0.0)) * 0.3 * ratio
	visual.position.y = absf(sin(walk_t)) * 0.05 * ratio
	if leaping:
		visual.rotation.x = 0.3
	else:
		visual.rotation.x = lerpf(visual.rotation.x, 0.0, 6.0 * delta)
