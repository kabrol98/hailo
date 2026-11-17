extends CharacterBody3D
## First-person player: movement, recharging shield + health, two weapons,
## frag grenades and melee.

signal died

const Effects = preload("res://scripts/effects.gd")
const Sfx = preload("res://scripts/sfx.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const Decals = preload("res://scripts/decals.gd")

const WALK_SPEED := 6.2
const SPRINT_SPEED := 9.6
const CROUCH_SPEED := 3.2
const JUMP_VELOCITY := 5.8
const GRAVITY := 15.5
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.15
const SHIELD_DELAY := 4.5
const SHIELD_RATE := 34.0
const BASE_FOV := 78.0
const HIP_POS := Vector3(0.21, -0.2, -0.36)
const AIM_POS := Vector3(0.0, -0.105, -0.28)

var max_health := 100.0
var health := 100.0
var max_shield := 100.0
var shield := 100.0
var shield_delay := 0.0
var shield_charging := false
var alive := true
var godmode := false

var mouse_sens := 0.0025
var base_fov := BASE_FOV
var invert_y := false
var flashlight: SpotLight3D
var flash_mesh: MeshInstance3D
var flash_t := 0.0
var in_flashlight := false
var head: Node3D
var camera: Camera3D
var viewmodel: Node3D
var weapon_models: Array = []
var muzzles: Array = []
var heat_mat: StandardMaterial3D
var muzzle_light: OmniLight3D
var collider: CollisionShape3D
var capsule: CapsuleShape3D

var weapons: Array = []
var current := 0
var fire_cd := 0.0
var reloading := 0.0
var switching := 0.0
var aiming := false
var sprinting := false
var crouching := false
var grenades := 2
var max_grenades := 4
var grenade_cd := 0.0
var melee_cd := 0.0
var recoil_pitch := 0.0
var vm_kick := 0.0
var shake := 0.0
var bob_t := 0.0
var sway := Vector2.ZERO
var hitmarker := 0.0
var hit_kill := false
var aim_enemy := false
var kills := 0
var score := 0
var damage_dirs: Array = []
var msg := ""
var msg_t := 0.0
var low_beep_t := 0.0
var knock := Vector3.ZERO

# input intents (filled from devices or from the autotest bot)
var in_move := Vector2.ZERO
var in_fire := false
var in_fire_just := false
var in_aim := false
var in_jump := false
var in_sprint := false
var in_crouch := false
var in_reload := false
var in_switch := false
var in_select := -1
var in_grenade := false
var in_melee := false
var _wheel_switch := false

var autobot := false
var _bot_strafe := 1.0
var _bot_strafe_t := 0.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(46)
	floor_snap_length = 0.45
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = STAND_HEIGHT
	collider = CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = STAND_HEIGHT * 0.5
	add_child(collider)
	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.03
	camera.far = 450.0
	head.add_child(camera)
	camera.current = true
	viewmodel = Node3D.new()
	viewmodel.position = HIP_POS
	camera.add_child(viewmodel)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 5.0
	muzzle_light.light_color = Color(1.0, 0.75, 0.4)
	camera.add_child(muzzle_light)
	muzzle_light.position = Vector3(0.2, -0.1, -0.9)
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.light_energy = 3.0
	flashlight.spot_range = 32.0
	flashlight.spot_angle = 24.0
	flashlight.spot_angle_attenuation = 1.6
	flashlight.light_volumetric_fog_energy = 0.6
	flashlight.position = Vector3(0.25, -0.15, -0.2)
	flashlight.visible = false
	camera.add_child(flashlight)
	weapons = [
		{"name": "VK-9 CARBINE", "kind": "ballistic", "auto": true, "rate": 0.095, "damage": 13.0,
			"mag": 32, "ammo": 32, "reserve": 192, "max_reserve": 320, "reload": 1.8,
			"spread": 0.024, "aim_spread": 0.006, "recoil": 0.011, "zoom": 52.0},
		{"name": "ARC CASTER", "kind": "plasma", "auto": true, "rate": 0.15, "damage": 19.0,
			"heat": 0.0, "heat_per_shot": 0.085, "cool_rate": 0.42, "overheated": 0.0, "speed": 75.0,
			"spread": 0.014, "aim_spread": 0.005, "recoil": 0.007, "zoom": 60.0},
	]
	_build_weapon_models()
	_build_muzzle_flash()
	_select_weapon(0, true)


func is_alive() -> bool:
	return alive


# ---------------------------------------------------------------- weapon models

func _mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _vm(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _bm(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _build_weapon_models() -> void:
	var gun := _mat(Color(0.17, 0.18, 0.19), 0.4, 0.7)
	var grip := _mat(Color(0.07, 0.07, 0.07), 0.85)
	var olive := _mat(Color(0.25, 0.28, 0.17), 0.7, 0.1)
	var orange := Effects.glow_mat(Color(1.0, 0.55, 0.15), 2.0)
	# --- VK-9 carbine
	var c := Node3D.new()
	_vm(c, _bm(Vector3(0.07, 0.09, 0.42)), gun, Vector3(0, 0, -0.05))
	_vm(c, _bm(Vector3(0.062, 0.07, 0.3)), olive, Vector3(0, -0.005, -0.38))
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.015
	barrel.bottom_radius = 0.015
	barrel.height = 0.22
	_vm(c, barrel, gun, Vector3(0, 0.01, -0.62), Vector3(PI / 2, 0, 0))
	_vm(c, _bm(Vector3(0.045, 0.17, 0.07)), grip, Vector3(0, -0.12, -0.12), Vector3(0.25, 0, 0))
	_vm(c, _bm(Vector3(0.042, 0.12, 0.05)), grip, Vector3(0, -0.1, 0.09), Vector3(-0.3, 0, 0))
	_vm(c, _bm(Vector3(0.05, 0.08, 0.22)), olive, Vector3(0, -0.02, 0.25))
	_vm(c, _bm(Vector3(0.035, 0.045, 0.1)), grip, Vector3(0, 0.068, -0.06))
	_vm(c, _bm(Vector3(0.012, 0.012, 0.012)), Effects.glow_mat(Color(1.0, 0.2, 0.1), 4.0), Vector3(0, 0.095, -0.1))
	_vm(c, _bm(Vector3(0.002, 0.025, 0.08)), orange, Vector3(-0.037, 0.01, 0.0))
	var m0 := Node3D.new()
	m0.position = Vector3(0, 0.01, -0.74)
	c.add_child(m0)
	# --- Arc caster
	var a := Node3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.065
	body.height = 0.42
	_vm(a, body, _mat(Color(0.82, 0.84, 0.8), 0.3, 0.3), Vector3(0, 0, -0.14), Vector3(PI / 2, 0, 0))
	for s in [-1.0, 1.0]:
		_vm(a, _bm(Vector3(0.016, 0.016, 0.22)), gun, Vector3(0.045 * s, 0.0, -0.42))
	heat_mat = StandardMaterial3D.new()
	heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	heat_mat.albedo_color = Color(0.3, 2.0, 3.0)
	for z in [-0.04, -0.14, -0.24]:
		var tor := TorusMesh.new()
		tor.inner_radius = 0.055
		tor.outer_radius = 0.078
		_vm(a, tor, heat_mat, Vector3(0, 0, z), Vector3(PI / 2, 0, 0))
	_vm(a, _bm(Vector3(0.042, 0.12, 0.05)), grip, Vector3(0, -0.1, 0.03), Vector3(-0.3, 0, 0))
	_vm(a, _bm(Vector3(0.03, 0.03, 0.08)), heat_mat, Vector3(0, 0.07, -0.1))
	var m1 := Node3D.new()
	m1.position = Vector3(0, 0, -0.5)
	a.add_child(m1)
	viewmodel.add_child(c)
	viewmodel.add_child(a)
	weapon_models = [c, a]
	muzzles = [m0, m1]


func _build_muzzle_flash() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := PI * k / 3.0
		var r := Vector3(cos(a), sin(a), 0) * 0.07
		for v in [Vector3.ZERO, r, Vector3(0, 0, -0.22), Vector3.ZERO, -r, Vector3(0, 0, -0.22)]:
			st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(4.0, 2.6, 1.2)
	flash_mesh = MeshInstance3D.new()
	flash_mesh.mesh = st.commit()
	flash_mesh.material_override = m
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_mesh.visible = false
	(muzzles[0] as Node3D).add_child(flash_mesh)


func set_flashlight(on: bool) -> void:
	flashlight.visible = on


func _select_weapon(i: int, instant := false) -> void:
	if i == current and not instant:
		return
	current = i
	reloading = 0.0
	for j in weapon_models.size():
		(weapon_models[j] as Node3D).visible = j == i
	if not instant:
		switching = 0.45
		Sfx.play_ui(self, "switch", -4.0)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var sens := mouse_sens * (0.55 if aiming else 1.0)
		rotate_y(-m.relative.x * sens)
		head.rotation.x = clampf(head.rotation.x - m.relative.y * sens * (-1.0 if invert_y else 1.0), deg_to_rad(-88), deg_to_rad(88))
		sway += Vector2(m.relative.x, m.relative.y) * 0.0004
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel_switch = true


func _read_input() -> void:
	in_move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	in_fire = Input.is_action_pressed("fire")
	in_fire_just = Input.is_action_just_pressed("fire")
	in_aim = Input.is_action_pressed("aim")
	in_jump = Input.is_action_just_pressed("jump")
	in_sprint = Input.is_action_pressed("sprint")
	in_crouch = Input.is_action_pressed("crouch")
	in_reload = Input.is_action_just_pressed("reload")
	in_switch = Input.is_action_just_pressed("switch_weapon") or _wheel_switch
	_wheel_switch = false
	in_select = -1
	if Input.is_action_just_pressed("weapon_1"):
		in_select = 0
	elif Input.is_action_just_pressed("weapon_2"):
		in_select = 1
	in_grenade = Input.is_action_just_pressed("grenade")
	in_melee = Input.is_action_just_pressed("melee")
	in_flashlight = Input.is_action_just_pressed("flashlight")


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	_update_feedback(delta)
	if flash_t > 0.0:
		flash_t -= delta
		flash_mesh.visible = flash_t > 0.0
	if not alive:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	if autobot:
		_bot(delta)
	else:
		_read_input()
	if in_flashlight:
		set_flashlight(not flashlight.visible)
		Sfx.play_ui(self, "empty", -8.0, 1.5)
		in_flashlight = false
	crouching = in_crouch or (crouching and test_move(global_transform, Vector3.UP * 0.7))
	sprinting = in_sprint and in_move.y < -0.3 and not crouching and not in_aim and not in_fire and reloading <= 0.0
	var spd := WALK_SPEED
	if sprinting:
		spd = SPRINT_SPEED
	elif crouching:
		spd = CROUCH_SPEED
	if aiming:
		spd *= 0.65
	var wish := transform.basis * Vector3(in_move.x, 0, in_move.y)
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var acc := 65.0 if is_on_floor() else 14.0
	velocity.x = move_toward(velocity.x, wish.x * spd, acc * delta)
	velocity.z = move_toward(velocity.z, wish.z * spd, acc * delta)
	if is_on_floor():
		if in_jump and not crouching:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	velocity += knock
	knock = Vector3.ZERO
	move_and_slide()
	_update_crouch(delta)
	_update_shield(delta)
	_update_weapons(delta)
	_update_viewmodel(delta)
	_update_aim_probe()


func _update_crouch(delta: float) -> void:
	var target_h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	capsule.height = move_toward(capsule.height, target_h, 5.0 * delta)
	collider.position.y = capsule.height * 0.5
	head.position.y = capsule.height - 0.18


func _update_shield(delta: float) -> void:
	if shield_delay > 0.0:
		shield_delay -= delta
		return
	if shield < max_shield:
		if not shield_charging:
			shield_charging = true
			Sfx.play_ui(self, "shield_charge", -6.0)
		shield = minf(max_shield, shield + SHIELD_RATE * delta)
	else:
		shield_charging = false


func _update_feedback(delta: float) -> void:
	hitmarker = maxf(hitmarker - delta, 0.0)
	msg_t = maxf(msg_t - delta, 0.0)
	for d in damage_dirs:
		d.t -= delta
	damage_dirs = damage_dirs.filter(func(d): return d.t > 0.0)
	shake = maxf(shake - delta * 2.5, 0.0)
	camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.06
	camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.06
	recoil_pitch = lerpf(recoil_pitch, 0.0, 9.0 * delta)
	camera.rotation.x = recoil_pitch
	muzzle_light.light_energy = maxf(muzzle_light.light_energy - delta * 40.0, 0.0)
	if alive and shield <= 0.0:
		low_beep_t -= delta
		if low_beep_t <= 0.0:
			low_beep_t = 0.55
			Sfx.play_ui(self, "beep", -12.0)


# ---------------------------------------------------------------- weapons

func _update_weapons(delta: float) -> void:
	var w: Dictionary = weapons[current]
	fire_cd -= delta
	grenade_cd -= delta
	melee_cd -= delta
	# arc caster cooling (both weapons cool even when holstered)
	var ac: Dictionary = weapons[1]
	if ac.overheated > 0.0:
		ac.overheated -= delta
		ac.heat = maxf(ac.heat - delta * 0.45, 0.0)
		if ac.overheated <= 0.0:
			ac.heat = 0.0
	elif fire_cd < -0.1 or current != 1:
		ac.heat = maxf(ac.heat - ac.cool_rate * delta, 0.0)
	var hc: float = ac.heat
	heat_mat.albedo_color = Color(0.3, 2.0, 3.0).lerp(Color(3.5, 0.6, 0.1), hc)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			var need: int = w.mag - w.ammo
			var take: int = mini(need, w.reserve)
			w.ammo += take
			w.reserve -= take
	if switching > 0.0:
		switching -= delta
	aiming = in_aim and switching <= 0.0 and reloading <= 0.0
	var target_fov: float = w.zoom * base_fov / BASE_FOV if aiming else base_fov
	camera.fov = lerpf(camera.fov, target_fov, 14.0 * delta)
	if in_select >= 0:
		_select_weapon(in_select)
	elif in_switch:
		_select_weapon(1 - current)
	w = weapons[current]
	if in_reload and w.kind == "ballistic" and reloading <= 0.0 and w.ammo < w.mag and w.reserve > 0:
		_start_reload()
	if in_grenade and grenades > 0 and grenade_cd <= 0.0 and switching <= 0.0:
		_throw_grenade()
	if in_melee and melee_cd <= 0.0:
		_melee()
	var want: bool = in_fire if w.auto else in_fire_just
	if want and fire_cd <= 0.0 and reloading <= 0.0 and switching <= 0.0 and melee_cd < 0.35:
		if w.kind == "ballistic":
			_fire_carbine(w)
		else:
			_fire_arc(w)


func _start_reload() -> void:
	var w: Dictionary = weapons[current]
	reloading = w.reload
	Sfx.play_ui(self, "reload", -3.0)


func _aim_ray(spread: float) -> Dictionary:
	var b := camera.global_transform.basis
	var dir := -b.z
	dir = (dir + b.x * randf_range(-spread, spread) + b.y * randf_range(-spread, spread)).normalized()
	var from := camera.global_position
	var to := from + dir * 250.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	hit["from"] = from
	hit["end"] = hit.position if hit.has("position") else to
	return hit


func _current_spread(w: Dictionary) -> float:
	var s: float = w.aim_spread if aiming else w.spread
	if not is_on_floor():
		s += 0.03
	s += Vector2(velocity.x, velocity.z).length() * 0.0018
	return s


func _fire_carbine(w: Dictionary) -> void:
	if w.ammo <= 0:
		fire_cd = 0.25
		Sfx.play_ui(self, "empty", -2.0)
		if w.reserve > 0:
			_start_reload()
		return
	w.ammo -= 1
	fire_cd = w.rate
	var hit := _aim_ray(_current_spread(w))
	var end: Vector3 = hit.end
	if hit.has("collider"):
		var c: Object = hit.collider
		if c != null and c.has_method("take_damage"):
			register_hit(c.take_damage(w.damage, "ballistic", global_position, end))
		if not (c is Node and (c as Node).is_in_group("enemy")):
			Decals.bullet_hole(self, end, hit.normal)
		Effects.impact(self, end, hit.normal, Color(1.0, 0.7, 0.3))
	var mz: Vector3 = (muzzles[0] as Node3D).global_position
	if randf() < 0.6:
		Effects.tracer(self, mz, end)
	_kick(w.recoil)
	muzzle_light.light_color = Color(1.0, 0.75, 0.4)
	muzzle_light.light_energy = 3.0
	flash_t = 0.04
	flash_mesh.visible = true
	flash_mesh.rotation.z = randf() * TAU
	Sfx.play_ui(self, "rifle", -5.0)
	if w.ammo == 0 and w.reserve > 0:
		_start_reload()


func _fire_arc(w: Dictionary) -> void:
	if w.overheated > 0.0:
		return
	fire_cd = w.rate
	var hit := _aim_ray(_current_spread(w))
	var mz: Vector3 = (muzzles[1] as Node3D).global_position
	var end: Vector3 = hit.end
	var dir := (end - mz).normalized()
	if mz.distance_to(end) < 1.0:
		dir = -camera.global_transform.basis.z
	var p := ProjectileScript.new()
	p.vel = dir * float(w.speed)
	p.damage = w.damage
	p.kind = "plasma"
	p.color = Color(0.3, 0.85, 1.0)
	p.size = 0.08
	p.from_player = true
	p.shooter = self
	p.source_pos = global_position
	get_parent().add_child(p)
	p.global_position = mz
	_kick(w.recoil)
	muzzle_light.light_color = Color(0.4, 0.8, 1.0)
	muzzle_light.light_energy = 2.5
	Sfx.play_ui(self, "plasma", -6.0)
	w.heat += w.heat_per_shot
	if w.heat >= 1.0:
		w.heat = 1.0
		w.overheated = 2.3
		Sfx.play_ui(self, "overheat", -2.0)
		notify("ARC CASTER OVERHEATED")


func _kick(amount: float) -> void:
	recoil_pitch += amount * (0.5 if aiming else 1.0)
	rotate_y(randf_range(-amount, amount) * 0.25)
	vm_kick = 0.04
	shots_fired_tick()


func shots_fired_tick() -> void:
	pass


func _throw_grenade() -> void:
	grenades -= 1
	grenade_cd = 0.9
	var g := GrenadeScript.new()
	g.thrower = self
	var fwd := -camera.global_transform.basis.z
	get_parent().add_child(g)
	g.global_position = camera.global_position + fwd * 0.6 + Vector3.DOWN * 0.1
	g.linear_velocity = fwd * 17.0 + Vector3.UP * 4.0 + velocity * 0.5
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	Sfx.play_ui(self, "throw", -2.0)


func _melee() -> void:
	melee_cd = 0.8
	vm_kick = -0.15
	var fwd := -global_transform.basis.z
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemy"):
		var d: Vector3 = (e as Node3D).global_position - global_position
		var flat := Vector3(d.x, 0, d.z)
		if flat.length() < 2.6 + e.radius and absf(d.y) < 2.0 and fwd.dot(flat.normalized()) > 0.45:
			register_hit(e.take_damage(75.0, "melee", global_position, null))
			e.apply_knockback(fwd * 6.0)
			hit_any = true
	if hit_any:
		velocity += fwd * 3.0
		add_shake(0.25)
	Sfx.play_ui(self, "melee", -2.0 if hit_any else -10.0, 1.0 if hit_any else 1.6)


func _update_aim_probe() -> void:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	aim_enemy = not hit.is_empty() and hit.collider is Node and (hit.collider as Node).is_in_group("enemy")


func _update_viewmodel(delta: float) -> void:
	var target := AIM_POS if aiming else HIP_POS
	var rot := Vector3.ZERO
	var hv := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hv > 0.5:
		bob_t += delta * hv * 1.5
	var bob_amt := 0.25 if aiming else 1.0
	target += Vector3(sin(bob_t) * 0.012, -absf(cos(bob_t)) * 0.014, 0) * bob_amt * clampf(hv / WALK_SPEED, 0.0, 1.5)
	if sprinting:
		target += Vector3(-0.04, -0.06, 0.02)
		rot += Vector3(-0.15, 0.55, 0.25)
	if reloading > 0.0:
		var w: Dictionary = weapons[current]
		var prog: float = 1.0 - reloading / float(w.reload)
		var dip := sin(prog * PI)
		target += Vector3(0, -0.08, 0) * dip
		rot += Vector3(-0.5, 0.2, 0.6) * dip
	if switching > 0.0:
		target += Vector3(0, -0.35, 0) * (switching / 0.45)
	if melee_cd > 0.55:
		target += Vector3(-0.12, 0.03, -0.18)
		rot += Vector3(0.0, 0.6, 0.0)
	vm_kick = lerpf(vm_kick, 0.0, 18.0 * delta)
	target.z += vm_kick
	sway = sway.lerp(Vector2.ZERO, 10.0 * delta)
	rot += Vector3(-sway.y, -sway.x, 0) * (0.3 if aiming else 1.0)
	viewmodel.position = viewmodel.position.lerp(target, 16.0 * delta)
	viewmodel.rotation = viewmodel.rotation.lerp(rot, 12.0 * delta)


# ---------------------------------------------------------------- damage / pickups

func take_damage(amount: float, _kind: String, from: Vector3, _hit_pos = null) -> String:
	if not alive:
		return ""
	if godmode:
		amount *= 0.0
	shield_delay = SHIELD_DELAY
	shield_charging = false
	var had_shield := shield > 0.0
	if shield > 0.0:
		var s := minf(shield, amount)
		shield -= s
		amount -= s
		if shield <= 0.0 and had_shield:
			Sfx.play_ui(self, "shield_break", -2.0)
	if amount > 0.0:
		health -= amount
		Sfx.play_ui(self, "hurt", -2.0)
	else:
		Sfx.play_ui(self, "shield_hit", -6.0)
	damage_dirs.append({"pos": from, "t": 1.3})
	add_shake(0.12)
	if health <= 0.0:
		health = 0.0
		_die()
		return "kill"
	return "hit"


func apply_knockback(v: Vector3) -> void:
	knock += v


func add_shake(a: float) -> void:
	shake = minf(shake + a, 1.2)


func register_hit(res) -> void:
	if res == "hit" or res == "kill":
		hitmarker = 0.18
		hit_kill = res == "kill"
		Sfx.play_ui(self, "kill" if hit_kill else "hit", -6.0 if hit_kill else -10.0)


func add_score(v: int) -> void:
	score += v
	kills += 1


func notify(t: String) -> void:
	msg = t
	msg_t = 2.5


func apply_pickup(kind: String) -> bool:
	var carbine: Dictionary = weapons[0]
	match kind:
		"ammo":
			if carbine.reserve >= carbine.max_reserve:
				return false
			carbine.reserve = mini(carbine.reserve + 96, carbine.max_reserve)
			notify("+96 CARBINE ROUNDS")
			return true
		"grenade":
			if grenades >= max_grenades:
				return false
			grenades += 1
			notify("+1 FRAG")
			return true
		"health":
			if health >= max_health:
				return false
			health = minf(max_health, health + 40.0)
			notify("+40 HEALTH")
			return true
		"supply":
			var changed := false
			if carbine.reserve < carbine.max_reserve:
				carbine.reserve = carbine.max_reserve
				changed = true
			if grenades < 3:
				grenades = 3
				changed = true
			if changed:
				notify("RESUPPLIED  (cache recharges in 30s)")
			return changed
	return false


func on_wave_cleared() -> void:
	health = minf(max_health, health + 30.0)
	grenades = mini(grenades + 1, max_grenades)
	var carbine: Dictionary = weapons[0]
	carbine.reserve = mini(carbine.reserve + 64, carbine.max_reserve)
	notify("WAVE CLEARED  +30 HEALTH  +1 FRAG  +64 ROUNDS")


func _die() -> void:
	alive = false
	died.emit()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(head, "position:y", 0.35, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "rotation:z", 0.6, 0.8)
	tw.tween_property(viewmodel, "position:y", -0.8, 0.5)


# ---------------------------------------------------------------- autotest bot

func _bot(delta: float) -> void:
	in_move = Vector2.ZERO
	in_fire = false
	in_fire_just = false
	in_aim = false
	in_jump = false
	in_sprint = false
	in_crouch = false
	in_reload = false
	in_switch = false
	in_select = -1
	in_grenade = false
	in_melee = false
	var best: Node3D = null
	var best_d := 1e9
	var space := get_world_3d().direct_space_state
	for e in get_tree().get_nodes_in_group("enemy"):
		var d := global_position.distance_to((e as Node3D).global_position)
		if d < best_d and d < 70.0:
			var q := PhysicsRayQueryParameters3D.create(camera.global_position, (e as Node3D).global_position + Vector3.UP * 1.0, 1)
			if space.intersect_ray(q).is_empty():
				best = e
				best_d = d
	_bot_strafe_t -= delta
	if _bot_strafe_t <= 0.0:
		_bot_strafe_t = randf_range(1.0, 2.5)
		_bot_strafe = -_bot_strafe
	if best != null:
		var tgt := best.global_position + Vector3.UP * 1.0
		var to := tgt - camera.global_position
		var yaw := atan2(-to.x, -to.z)
		var pitch := atan2(to.y, Vector2(to.x, to.z).length())
		rotation.y = lerp_angle(rotation.y, yaw, minf(8.0 * delta, 1.0))
		head.rotation.x = lerpf(head.rotation.x, pitch, minf(8.0 * delta, 1.0))
		var err := absf(angle_difference(rotation.y, yaw)) + absf(head.rotation.x - pitch)
		in_fire = err < 0.08
		in_aim = best_d > 20.0
		in_move = Vector2(_bot_strafe, 0.3 if best_d > 15.0 else -0.3)
		if best_d < 2.5:
			in_melee = true
		if best_d < 22.0 and best_d > 8.0 and randf() < 0.004:
			in_grenade = true
	else:
		var to_c := Vector3(0, 0, 8) - global_position
		if to_c.length() > 4.0:
			rotation.y = lerp_angle(rotation.y, atan2(-to_c.x, -to_c.z), minf(4.0 * delta, 1.0))
			in_move = Vector2(0, -1)
	var w: Dictionary = weapons[current]
	if current == 1 and w.overheated > 0.0:
		in_switch = true
	elif current == 0 and w.ammo == 0 and w.reserve == 0:
		in_switch = true
	elif current == 0 and w.ammo == 0:
		in_reload = true
