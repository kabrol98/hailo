extends Node
## Controller test: feeds synthetic Xbox-controller events into the real game
## (Input.parse_input_event) and checks menus, look, movement, firing, weapon
## switch, aim assist and pause. Run headless:
##   godot --headless -- --padtest
## Prints PASS / FAIL per check and exits with the number of failures.

const EnemyScript = preload("res://scripts/enemy.gd")

var main: Node
var fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _button(b: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func _tap(b: int) -> void:
	_button(b, true)
	await _frames(3)
	_button(b, false)
	await _frames(3)


func _axis(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = a
	e.axis_value = v
	Input.parse_input_event(e)


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""])
	if not ok:
		fails += 1


func _focus_text() -> String:
	var f := get_viewport().gui_get_focus_owner()
	return (f as Button).text if f is Button else (str(f) if f else "none")


func _run() -> void:
	await _frames(10)
	var p: Node = main.player
	# ---- home menu
	_check("home screen focuses DEPLOY", _focus_text() == "DEPLOY", _focus_text())
	await _tap(JOY_BUTTON_DPAD_DOWN)
	_check("d-pad down moves focus", _focus_text() == "SETTINGS", _focus_text())
	await _tap(JOY_BUTTON_DPAD_UP)
	await _tap(JOY_BUTTON_A)
	await _frames(5)
	_check("A on DEPLOY starts the game", main.state == "playing", main.state)
	_check("controller marked active", main.Gamepad.active)
	await _secs(0.3)
	# ---- look
	var yaw0: float = p.rotation.y
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _secs(0.5)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	var turned: float = p.rotation.y - yaw0
	_check("right stick turns right", turned < -0.8, "%.2f rad" % turned)
	var pitch0: float = p.head.rotation.x
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _secs(0.25)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_check("right stick up looks up", p.head.rotation.x > pitch0 + 0.2, "%.2f" % (p.head.rotation.x - pitch0))
	var yaw1: float = p.rotation.y
	_axis(JOY_AXIS_RIGHT_X, 0.1)   # inside the dead zone
	await _secs(0.3)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_check("dead zone ignores small drift", absf(p.rotation.y - yaw1) < 0.001)
	# ---- move
	var pos0: Vector3 = p.global_position
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _secs(0.5)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_check("left stick moves", p.global_position.distance_to(pos0) > 1.5, "%.2f m" % p.global_position.distance_to(pos0))
	_axis(JOY_AXIS_LEFT_Y, -0.35)
	await _secs(0.3)
	var slow: float = Vector2(p.velocity.x, p.velocity.z).length()
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_check("partial tilt walks slower", slow > 0.5 and slow < 4.0, "%.2f m/s" % slow)
	# ---- sprint latch
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _tap(JOY_BUTTON_LEFT_STICK)
	await _secs(0.3)
	_check("left-stick click sprints", p.sprinting)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _secs(0.2)
	_check("sprint ends when you stop", not p._sprint_latch)
	# ---- fire / switch
	var ammo0: int = p.weapons[0].ammo
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _secs(0.4)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_check("RT fires", p.weapons[0].ammo < ammo0, "%d -> %d" % [ammo0, p.weapons[0].ammo])
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	_check("LB switches weapon", p.current == 1)
	await _secs(0.5)
	await _tap(JOY_BUTTON_Y)
	_check("Y switches back", p.current == 0)
	await _secs(0.5)
	# ---- aim assist: an idle enemy 4 degrees off the crosshair
	var cam: Camera3D = p.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized().rotated(Vector3.UP, deg_to_rad(4.0))
	var e: Node = EnemyScript.new()
	e.setup("trooper", 1)
	main.world.add_child(e)
	var at: Vector3 = p.global_position + fwd * 14.0
	at.y = main.arena.height_at(at.x, at.z) + 0.1
	e.global_position = at
	p.head.rotation.x = 0.0
	await _secs(0.3)
	var err0 := _err_to(cam, e)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _secs(0.5)
	var err1 := _err_to(cam, e)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_check("aim assist pulls onto target when aiming", err1 < err0 * 0.4, "%.1f° -> %.1f°" % [rad_to_deg(err0), rad_to_deg(err1)])
	main.player.aim_assist = false
	p.rotate_y(deg_to_rad(-5.0))
	await _secs(0.1)
	var err2 := _err_to(cam, e)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _secs(0.5)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_check("no pull with aim assist off", absf(_err_to(cam, e) - err2) < deg_to_rad(0.5))
	main.player.aim_assist = true
	e.queue_free()
	await _secs(0.3)
	# ---- pause / menus
	await _tap(JOY_BUTTON_START)
	_check("Menu pauses", main.state == "pause" and get_tree().paused, main.state)
	await _frames(3)
	_check("pause menu focuses RESUME", _focus_text() == "RESUME", _focus_text())
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_A)
	await _frames(3)
	_check("open settings from pause", main.state == "settings", main.state)
	var tab0: int = main.ui.tabs.current_tab
	await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	_check("RB next settings tab", main.ui.tabs.current_tab == wrapi(tab0 + 1, 0, main.ui.tabs.get_tab_count()))
	_check("tab content focused", get_viewport().gui_get_focus_owner() != null)
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	await _tap(JOY_BUTTON_B)
	_check("B goes back to pause", main.state == "pause", main.state)
	await _tap(JOY_BUTTON_B)
	_check("B resumes", main.state == "playing" and not get_tree().paused, main.state)
	# ---- prompts switch back to keyboard
	var k := InputEventKey.new()
	k.physical_keycode = KEY_SHIFT
	k.pressed = true
	Input.parse_input_event(k)
	k = k.duplicate()
	k.pressed = false
	Input.parse_input_event(k)
	await _frames(2)
	_check("keyboard input switches prompts back", not main.Gamepad.active)
	print("PADTEST DONE: %d failure(s)" % fails)
	get_tree().quit(fails)


func _err_to(cam: Camera3D, e: Node3D) -> float:
	var target: Vector3 = e.global_position + Vector3.UP * float(e.head_y) * 0.8
	return (-cam.global_transform.basis.z).angle_to((target - cam.global_position).normalized())
