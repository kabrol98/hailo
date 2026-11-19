extends CharacterBody3D
## First-person player: movement, recharging shield + health, two weapons,
## frag grenades and melee.

signal died

const Effects = preload("res://scripts/effects.gd")
const Sfx = preload("res://scripts/sfx.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const Decals = preload("res://scripts/decals.gd")
const ModelKit = preload("res://scripts/model_kit.gd")
const Gamepad = preload("res://scripts/gamepad.gd")
const Weapons = preload("res://scripts/weapons.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")

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
# controller (set from settings by main.gd)
var pad_look_speed := 4.5      # x 40 deg/s at full tilt
var pad_invert_y := false
var pad_deadzone := 0.15
var aim_assist := true
var crouch_toggle := false
var aim_toggle := false
var _crouch_latch := false
var _aim_latch := false
var _sprint_latch := false
var _edge_t := 0.0             # how long the look stick has been held at full tilt
var _ads_t := 0.0              # time since aiming down sights started
var _was_aiming := false
## Current aim-assist candidate (debug / tests): {"enemy", "err": Vector2(yaw, pitch), "friction": bool}
var assist := {}
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

## The two carried weapons (state dicts, see weapons.gd); `current` is the one in hand.
var weapons: Array = []
var _vm_nodes := {}            # weapon id -> {"node", "muzzle"} viewmodels, built on demand
## Nearest weapon on the ground / rack within reach, or null.
var interact_target: Node = null
var in_interact := false
var _x_hold := 0.0
var _x_used := false
var _interact_prev := false
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
## Intents are set from outside (gallery / showcase); no device input.
var scripted := false
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
	heat_mat = StandardMaterial3D.new()
	heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	heat_mat.albedo_color = Color(0.3, 2.0, 3.0)
	weapons = [Weapons.new_state(Weapons.START[0]), Weapons.new_state(Weapons.START[1])]
	_build_muzzle_flash()
	_refresh_viewmodels()
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


func _viewmodel_for(id: String) -> Dictionary:
	if _vm_nodes.has(id):
		return _vm_nodes[id]
	var n := Weapons.model(id)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mz := Node3D.new()
	mz.position = n.get_meta("muzzle")
	n.add_child(mz)
	if id == "arc_caster":
		# heat cells along the barrel: blue when cool, orange near overheat
		for s in [-1.0, 1.0]:
			_vm(n, _bm(Vector3(0.004, 0.012, 0.16)), heat_mat, Vector3(0.024 * s, -0.035, -0.2))
	n.visible = false
	viewmodel.add_child(n)
	_vm_nodes[id] = {"node": n, "muzzle": mz}
	return _vm_nodes[id]


## Rebuilds the slot -> viewmodel lists after picking up or dropping a weapon.
func _refresh_viewmodels() -> void:
	weapon_models.clear()
	muzzles.clear()
	for vm in _vm_nodes.values():
		(vm.node as Node3D).visible = false
	for st in weapons:
		var vm := _viewmodel_for(st.id)
		weapon_models.append(vm.node)
		muzzles.append(vm.muzzle)
	current = clampi(current, 0, weapons.size() - 1)
	(weapon_models[current] as Node3D).visible = true
	_attach_flash()


func _attach_flash() -> void:
	if flash_mesh == null or muzzles.is_empty():
		return
	var mz: Node3D = muzzles[current]
	if flash_mesh.get_parent() != mz:
		if flash_mesh.get_parent():
			flash_mesh.get_parent().remove_child(flash_mesh)
		mz.add_child(flash_mesh)


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


func set_flashlight(on: bool) -> void:
	flashlight.visible = on


func _select_weapon(i: int, instant := false) -> void:
	if i >= weapons.size() or (i == current and not instant):
		return
	if current >= 0 and current < weapons.size():
		weapons[current].charge = 0.0
		weapons[current].charging = false
	current = i
	reloading = 0.0
	for j in weapon_models.size():
		(weapon_models[j] as Node3D).visible = j == i
	_attach_flash()
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


func _process(delta: float) -> void:
	if alive and not autobot and not scripted and not get_tree().paused:
		_pad_look(delta)


## Right-stick look: dead zone + response curve, a turn boost when held at the
## edge, slower while aiming, plus aim assist (slowdown over enemies and a
## gentle pull while aiming down sights).
func _pad_look(delta: float) -> void:
	var raw := Vector2(
		Input.get_action_raw_strength("look_right") - Input.get_action_raw_strength("look_left"),
		Input.get_action_raw_strength("look_down") - Input.get_action_raw_strength("look_up"))
	var stick := Gamepad.shape_stick(raw, pad_deadzone)
	var tilt := stick.length()
	_edge_t = _edge_t + delta if tilt > 0.92 else 0.0
	var boost := 1.0 + 0.6 * clampf((_edge_t - 0.2) / 0.4, 0.0, 1.0)
	var rate := deg_to_rad(pad_look_speed * 40.0) * boost
	if aiming:
		rate *= 0.5
	_ads_t = _ads_t + delta if aiming else 0.0
	assist = {}
	if aim_assist and Gamepad.active:
		assist = _assist_target()
		if not assist.is_empty() and assist.friction:
			rate *= 0.5
	if tilt > 0.0:
		rotate_y(-stick.x * rate * delta)
		var pitch_sign := -1.0 if pad_invert_y else 1.0
		head.rotation.x = clampf(head.rotation.x - stick.y * rate * 0.7 * pitch_sign * delta, deg_to_rad(-88), deg_to_rad(88))
		sway += stick * 0.01
	# magnetism: ease onto the target when aiming down sights, then track gently
	if not assist.is_empty() and (aiming or in_fire):
		var err: Vector2 = assist.err
		var k := 9.0 if (aiming and _ads_t < 0.25) else 2.5
		var f := clampf(k * delta, 0.0, 1.0)
		rotate_y(err.x * f)
		head.rotation.x = clampf(head.rotation.x + err.y * f, deg_to_rad(-88), deg_to_rad(88))


func _assist_target() -> Dictionary:
	var cam := camera.global_transform
	var best := {}
	var best_score := INF
	var space := get_world_3d().direct_space_state
	for e in get_tree().get_nodes_in_group("enemy"):
		var en := e as Node3D
		var p: Vector3 = en.global_position + Vector3.UP * float(e.head_y) * 0.8
		var to := p - cam.origin
		var dist := to.length()
		if dist < 1.0 or dist > 70.0:
			continue
		var local := cam.basis.inverse() * (to / dist)
		if local.z > 0.0:
			continue
		var yaw_err := atan2(-local.x, -local.z)
		var pitch_err := atan2(local.y, sqrt(local.x * local.x + local.z * local.z))
		var ang := Vector2(yaw_err, pitch_err).length()
		var cone := clampf(atan(2.2 / dist), deg_to_rad(2.5), deg_to_rad(9.0))
		if ang > cone:
			continue
		var score := ang / cone
		if score >= best_score:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.origin, p, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		best_score = score
		best = {"enemy": e, "err": Vector2(yaw_err, pitch_err),
			"friction": ang < atan((float(e.radius) + 0.5) / dist)}
	return best


func _read_input() -> void:
	in_move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	in_fire = Input.is_action_pressed("fire")
	in_fire_just = Input.is_action_just_pressed("fire")
	in_jump = Input.is_action_just_pressed("jump")
	# sprint: hold Shift, or click the left stick (stays on until you stop moving forward)
	if Input.is_action_just_pressed("sprint_toggle"):
		_sprint_latch = not _sprint_latch
	if in_move.y > -0.3:
		_sprint_latch = false
	in_sprint = Input.is_action_pressed("sprint") or _sprint_latch
	if crouch_toggle:
		if Input.is_action_just_pressed("crouch"):
			_crouch_latch = not _crouch_latch
		if in_sprint or in_jump:
			_crouch_latch = false
		in_crouch = _crouch_latch
	else:
		in_crouch = Input.is_action_pressed("crouch")
	if aim_toggle:
		if Input.is_action_just_pressed("aim"):
			_aim_latch = not _aim_latch
		if in_sprint or reloading > 0.0 or switching > 0.0:
			_aim_latch = false
		in_aim = _aim_latch
	else:
		in_aim = Input.is_action_pressed("aim")
	in_reload = Input.is_action_just_pressed("reload")
	# edge-detect by hand: a press between physics frames still counts once
	var e_down := Input.is_action_pressed("interact")
	in_interact = e_down and not _interact_prev
	_interact_prev = e_down
	# controller X: tap = reload, hold = pick up the weapon you're standing at
	if Input.is_action_pressed("pad_x"):
		if Input.is_action_just_pressed("pad_x") and interact_target == null:
			in_reload = true
			_x_used = true
		_x_hold += get_physics_process_delta_time()
		if _x_hold >= 0.35 and not _x_used and interact_target != null:
			in_interact = true
			_x_used = true
	elif _x_hold > 0.0:
		if not _x_used:
			in_reload = true
		_x_hold = 0.0
		_x_used = false
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
	elif not scripted:
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
	_update_interact()
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
	fire_cd -= delta
	grenade_cd -= delta
	melee_cd -= delta
	for i in weapons.size():
		_cool(weapons[i], delta, i == current)
	var w: Dictionary = weapons[current]
	if w.id == "arc_caster":
		heat_mat.albedo_color = Color(0.3, 2.0, 3.0).lerp(Color(3.5, 0.6, 0.1), w.heat)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0 and Weapons.uses_mag(w):
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
	elif in_switch and weapons.size() > 1:
		_select_weapon(1 - current)
	if in_interact and interact_target != null and is_instance_valid(interact_target):
		_take(interact_target)
	w = weapons[current]
	if in_reload and Weapons.uses_mag(w) and reloading <= 0.0 and w.ammo < w.mag and w.reserve > 0:
		_start_reload()
	if in_grenade and grenades > 0 and grenade_cd <= 0.0 and switching <= 0.0:
		_throw_grenade()
	if in_melee and melee_cd <= 0.0:
		_melee()
	var ready := fire_cd <= 0.0 and reloading <= 0.0 and switching <= 0.0 and melee_cd < 0.35
	match w.mode:
		"charge_bolt":
			# tap: quick bolt; keep holding: charge a heavy shot, fired on release
			if in_fire_just and ready and _has_shot(w):
				_fire(w)
				w.charging = true
				w.charge = 0.0
			elif in_fire and w.get("charging", false):
				var before: float = w.charge
				w.charge += delta
				if before < 0.2 and w.charge >= 0.2:
					Sfx.play_ui(self, "shield_charge", -8.0, 1.6)
			elif w.get("charging", false):
				if w.charge >= w.charge_time and w.overheated <= 0.0 and _has_shot(w):
					_fire(w, true)
				w.charging = false
				w.charge = 0.0
			elif in_fire_just and not _has_shot(w):
				_dry_fire(w)
		"beam":
			# hold to charge, release to fire; releasing early cancels
			if in_fire and ready and _has_shot(w):
				if w.charge <= 0.0:
					Sfx.play_ui(self, "lancer_charge", -6.0, 1.4)
				w.charge += delta
			elif w.charge > 0.0:
				if w.charge >= w.charge_time:
					_fire(w)
				w.charge = 0.0
			elif in_fire_just and not _has_shot(w):
				_dry_fire(w)
		_:
			var want: bool = in_fire if w.auto else in_fire_just
			if want and ready:
				if _has_shot(w):
					_fire(w)
				elif in_fire_just or w.auto:
					_dry_fire(w)


func _cool(st: Dictionary, delta: float, in_hand: bool) -> void:
	if not st.has("heat_per_shot"):
		return
	if st.overheated > 0.0:
		st.overheated -= delta
		st.heat = maxf(st.heat - delta * 0.45, 0.0)
		if st.overheated <= 0.0:
			st.heat = 0.0
	elif fire_cd < -0.1 or not in_hand:
		st.heat = maxf(st.heat - float(st.cool_rate) * delta, 0.0)


func _has_shot(w: Dictionary) -> bool:
	if w.overheated > 0.0:
		return false
	if Weapons.uses_mag(w):
		return w.ammo > 0
	return w.battery > 0.0005


func _dry_fire(w: Dictionary) -> void:
	fire_cd = 0.25
	if w.overheated > 0.0:
		return
	Sfx.play_ui(self, "empty", -2.0)
	if Weapons.uses_mag(w):
		if w.reserve > 0:
			_start_reload()
	elif w.family == "alien":
		notify("%s IS SPENT - swap it for another weapon" % w.short)
	else:
		notify("%s BATTERY EMPTY - recharge at a human cache" % w.short)


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


## Fires one shot of the weapon in hand. `charged` = the Spitter's held shot.
func _fire(w: Dictionary, charged := false) -> void:
	fire_cd = w.rate
	# spend ammo / charge / heat
	if Weapons.uses_mag(w):
		w.ammo -= 1
	else:
		var cost: float = float(w.get("charge_drain", w.drain)) if charged else float(w.drain)
		w.battery = maxf(w.battery - cost, 0.0)
	if w.has("heat_per_shot"):
		w.heat += float(w.get("charge_heat", w.heat_per_shot)) if charged else float(w.heat_per_shot)
		if w.heat >= 1.0:
			w.heat = 1.0
			w.overheated = w.overheat_time
			Sfx.play_ui(self, "overheat", -2.0)
			notify("%s OVERHEATED" % w.short)
	var mz: Vector3 = (muzzles[current] as Node3D).global_position
	match w.mode:
		"hitscan":
			var pellets := int(w.get("pellets", 1))
			for i in pellets:
				var hit := _aim_ray(_current_spread(w))
				var end: Vector3 = hit.end
				if hit.has("collider"):
					var dmg: float = w.damage
					if w.has("falloff"):
						var d: float = (hit.from as Vector3).distance_to(end)
						dmg *= clampf(1.0 - (d - w.falloff.x) / (w.falloff.y - w.falloff.x), 0.15, 1.0)
					var c: Object = hit.collider
					if c != null and c.has_method("take_damage"):
						register_hit(c.take_damage(dmg, "ballistic", global_position, end))
					if not (c is Node and (c as Node).is_in_group("enemy")):
						Decals.bullet_hole(self, end, hit.normal)
					if i < 4:
						Effects.impact(self, end, hit.normal, Color(1.0, 0.7, 0.3))
				if randf() < float(w.get("tracer", 0.5)):
					Effects.tracer(self, mz, end)
			flash_t = 0.04
			flash_mesh.visible = true
			flash_mesh.rotation.z = randf() * TAU
			Gamepad.rumble(0.18 + 0.1 * pellets / 9.0, 0.25 if pellets > 1 else 0.0, 0.06)
		"bolt", "charge_bolt":
			var hit := _aim_ray(_current_spread(w) * (0.3 if charged else 1.0))
			var end: Vector3 = hit.end
			var dir := (end - mz).normalized()
			if mz.distance_to(end) < 1.0:
				dir = -camera.global_transform.basis.z
			var p := ProjectileScript.new()
			p.vel = dir * float(w.speed) * (0.8 if charged else 1.0)
			p.damage = float(w.charge_damage) if charged else float(w.damage)
			p.kind = w.kind
			p.color = w.color
			p.size = 0.16 if charged else 0.08
			p.with_light = charged
			p.from_player = true
			p.shooter = self
			p.source_pos = global_position
			if charged:
				# the seed curves onto whatever you're aiming near
				var t := _assist_target()
				if t.is_empty() and aim_enemy and hit.has("collider"):
					t = {"enemy": hit.collider}
				if not t.is_empty():
					p.homing_target = t.enemy
					p.homing = 3.0
			get_parent().add_child(p)
			p.global_position = mz
			Gamepad.rumble(0.25, 0.3 if charged else 0.05, 0.12 if charged else 0.07)
		"lob":
			var b := camera.global_transform.basis
			var dir := (-b.z + b.y * 0.12).normalized()
			var p := ProjectileScript.new()
			p.vel = dir * float(w.speed) + velocity * 0.3
			p.grav = w.grav
			p.damage = w.damage
			p.kind = "explosive"
			p.blast_radius = w.blast
			p.color = w.color
			p.size = 0.2
			p.stretch = 1.3
			p.with_light = true
			p.life = 6.0
			p.from_player = true
			p.shooter = self
			p.source_pos = global_position
			get_parent().add_child(p)
			p.global_position = mz
			Gamepad.rumble(0.3, 0.5, 0.15)
		"beam":
			var hit := _aim_ray(_current_spread(w))
			var end: Vector3 = hit.end
			if hit.has("collider"):
				var c: Object = hit.collider
				if c != null and c.has_method("take_damage"):
					register_hit(c.take_damage(w.damage, w.kind, global_position, end))
				Effects.impact(self, end, hit.normal, w.color)
			Effects.tracer(self, mz, end, w.color, 0.12)
			Effects.flash(self, mz, w.color, 3.0, 4.0, 0.15)
			Gamepad.rumble(0.4, 0.6, 0.2)
	_kick(float(w.recoil) * (2.5 if charged else 1.0))
	muzzle_light.light_color = w.flash
	muzzle_light.light_energy = 3.0 if w.mode == "hitscan" else 2.5
	Sfx.play_ui(self, w.sfx, float(w.get("sfx_vol", 0.0)) - 5.0 + (3.0 if charged else 0.0),
		float(w.get("sfx_pitch", 1.0)) * (0.7 if charged else 1.0))
	if Weapons.uses_mag(w) and w.ammo == 0 and w.reserve > 0:
		_start_reload()


func _kick(amount: float) -> void:
	recoil_pitch += amount * (0.5 if aiming else 1.0)
	rotate_y(randf_range(-amount, amount) * 0.25)
	vm_kick = 0.04
	shots_fired_tick()


func shots_fired_tick() -> void:
	pass


# ---------------------------------------------------------------- weapon pickups

## Finds the weapon you can pick up, and quietly takes ammo from dropped copies
## of the guns you already carry.
func _update_interact() -> void:
	interact_target = null
	var best := 1e9
	var fwd := -global_transform.basis.z
	for p in get_tree().get_nodes_in_group("weapon_pickup"):
		var n := p as Node3D
		var d := n.global_position - global_position
		var flat := Vector2(d.x, d.z).length()
		if flat > 2.0 or d.y < -1.0 or d.y > 2.4:
			continue
		var carried := _slot_of(p.state.id)
		if carried >= 0:
			if flat < 1.4 and Weapons.scavenge(weapons[carried], p.state):
				Sfx.play_ui(self, "pickup", -6.0)
				notify("+AMMO  %s" % weapons[carried].short)
				p.touched()
				if Weapons.is_empty(p.state) and not p.rack:
					p.queue_free()
			continue
		# prefer what you're looking at
		var score := flat - fwd.dot(Vector3(d.x, 0, d.z).normalized()) * 0.8
		if score < best:
			best = score
			interact_target = p


func _slot_of(id: String) -> int:
	for i in weapons.size():
		if weapons[i].id == id:
			return i
	return -1


func _take(p: Node) -> void:
	var st: Dictionary = p.take()
	var slot := current
	if weapons.size() < 2:
		weapons.append(st)
		slot = weapons.size() - 1
	else:
		_drop(weapons[current])
		weapons[current] = st
	interact_target = null
	_refresh_viewmodels()
	current = -1
	_select_weapon(slot)
	notify("PICKED UP %s" % st.name)
	Sfx.play_ui(self, "pickup", -3.0)


func _drop(st: Dictionary) -> void:
	st.charge = 0.0
	st.charging = false
	var p := WeaponPickup.new()
	p.state = st
	get_parent().add_child(p)
	var fwd := -global_transform.basis.z
	p.global_position = global_position + fwd * 0.9 + Vector3.UP * 0.6
	p.drop_velocity = fwd * 2.0 + Vector3.UP * 1.5


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
			Gamepad.rumble(0.5, 0.7, 0.3)
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
	Gamepad.rumble(a * 0.6, a, 0.12 + a * 0.3)


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
	match kind:
		"ammo":
			var got := false
			for st in weapons:
				if st.family != "human":
					continue
				if Weapons.uses_mag(st) and st.reserve < st.max_reserve:
					st.reserve = mini(st.reserve + int(ceil(st.max_reserve * 0.3)), st.max_reserve)
					got = true
				elif Weapons.uses_battery(st) and st.battery < 1.0:
					st.battery = minf(st.battery + 0.25, 1.0)
					got = true
			if got:
				notify("+AMMO")
			return got
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
	return false


## Ammo caches: tops up every carried weapon of that family (and frags at a
## human cache). Returns false if there was nothing to refill.
func refill(family: String) -> bool:
	var changed := false
	for st in weapons:
		if st.family != family:
			continue
		if Weapons.uses_mag(st):
			if st.reserve < st.max_reserve or st.ammo < st.mag:
				st.reserve = st.max_reserve
				changed = true
		elif st.battery < 0.995:
			st.battery = 1.0
			changed = true
	if family == "human" and grenades < 3:
		grenades = 3
		changed = true
	return changed


func on_wave_cleared() -> void:
	health = minf(max_health, health + 30.0)
	grenades = mini(grenades + 1, max_grenades)
	for st in weapons:
		if Weapons.uses_mag(st):
			st.reserve = mini(st.reserve + int(ceil(st.max_reserve * 0.2)), st.max_reserve)
	notify("WAVE CLEARED  +30 HEALTH  +1 FRAG  +AMMO")


func _die() -> void:
	alive = false
	Gamepad.rumble(0.8, 1.0, 0.6)
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
	in_fire_just = in_fire
	var w: Dictionary = weapons[current]
	var other := 1 - current
	if w.overheated > 0.0 or Weapons.is_empty(w):
		if weapons.size() > 1 and not Weapons.is_empty(weapons[other]) and weapons[other].overheated <= 0.0:
			in_switch = true
	elif Weapons.uses_mag(w) and w.ammo == 0:
		in_reload = true
	if w.mode == "beam" and w.charge >= w.charge_time:
		in_fire = false
