extends Node3D
## Entry point: input map, world assembly, settings application and game states.
## States: home, settings, controls, playing, paused, dead

const ModelKit = preload("res://scripts/model_kit.gd")
const ArenaScript = preload("res://scripts/arena.gd")
const PlayerScript = preload("res://scripts/player.gd")
const WavesScript = preload("res://scripts/waves.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/hud.gd")
const UiScript = preload("res://scripts/ui.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const AtmosphereScript = preload("res://scripts/atmosphere.gd")
const Shaders = preload("res://scripts/shaders.gd")
const Decals = preload("res://scripts/decals.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Showcase = preload("res://scripts/showcase.gd")
const Gamepad = preload("res://scripts/gamepad.gd")

const STATS_PATH := "user://verdant_hold.cfg"

var settings: Node
var gamepad: Node
var world: Node3D
var atmosphere: Node3D
var arena: Node3D
var player: CharacterBody3D
var waves: Node
var hud: Control
var ui: Control
var menu_cam: Camera3D
var state := "home"
var game_started := false
var best_wave := 0
var best_score := 0
var new_best := false
var _orbit_t := 0.0

var autotest := false
var autotest_time := 0.0
var autotest_limit := 90.0
var _shot_i := 0
var _shot_dir := ""
var showcase: Array = []
var _sc_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	for a in args:
		if a.begins_with("--seconds="):
			autotest_limit = float(a.get_slice("=", 1))
		elif a.begins_with("--shots="):
			_shot_dir = a.get_slice("=", 1)
		elif a.begins_with("--showcase="):
			showcase = Array(a.get_slice("=", 1).split(","))
	settings = SettingsScript.new()
	settings.name = "Settings"
	add_child(settings)
	gamepad = Gamepad.new()
	gamepad.name = "Gamepad"
	add_child(gamepad)
	gamepad.device_changed.connect(_on_device_changed)
	gamepad.lost.connect(func():
		if state == "playing":
			pause_game())
	for a in args:
		if a.begins_with("--tod="):
			settings.values["time_of_day"] = a.get_slice("=", 1)
		elif a.begins_with("--veg="):
			settings.values["vegetation"] = a.get_slice("=", 1)
		elif a.begins_with("--models="):
			settings.values["models"] = a.get_slice("=", 1)
		elif a.begins_with("--preset="):
			var pn := a.get_slice("=", 1)
			settings.values["preset"] = pn
			for k in SettingsScript.PRESETS[pn].keys():
				settings.values[k] = SettingsScript.PRESETS[pn][k]
	_setup_input()
	_load_stats()
	Sfx.preload_all()
	Decals.clear()
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_to_group("world")
	add_child(world)
	atmosphere = AtmosphereScript.new()
	atmosphere.name = "Atmosphere"
	world.add_child(atmosphere)
	var t0 := Time.get_ticks_msec()
	arena = ArenaScript.new()
	arena.name = "Arena"
	arena.vegetation_style = settings.get_v("vegetation")
	ModelKit.enabled = settings.get_v("models") == "kit" and ModelKit.available()
	world.add_child(arena)
	arena.build()
	print("Arena built in %d ms" % (Time.get_ticks_msec() - t0))
	player = PlayerScript.new()
	player.name = "Player"
	world.add_child(player)
	player.global_position = arena.player_spawn + Vector3.UP * arena.height_at(arena.player_spawn.x, arena.player_spawn.z)
	player.autobot = autotest
	player.godmode = args.has("--godmode")
	player.died.connect(_on_player_died)
	waves = WavesScript.new()
	waves.name = "Waves"
	waves.spawn_points = arena.spawn_points
	waves.player = player
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wave="):
			# debug: start later in the escalation so every enemy type appears
			waves.wave = maxi(int(a.get_slice("=", 1)) - 1, 0)
	world.add_child(waves)
	menu_cam = Camera3D.new()
	menu_cam.fov = 60.0
	menu_cam.far = 450.0
	menu_cam.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(menu_cam)
	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	hud = HudScript.new()
	hud.player = player
	hud.waves = waves
	hud.main = self
	hud_layer.add_child(hud)
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	ui = UiScript.new()
	ui.main = self
	ui.settings = settings
	ui_layer.add_child(ui)
	waves.wave_started.connect(func(n): hud.show_banner("WAVE %d" % n, "%d hostiles inbound" % waves.remaining(), 3.0))
	waves.wave_cleared.connect(func(n): hud.show_banner("WAVE %d CLEARED" % n, "Resupply at the bunker cache", 3.5))
	waves.announce.connect(func(t): hud.show_banner("WARNING", t, 4.0))
	settings.changed.connect(apply_settings)
	apply_settings("*")
	if OS.get_cmdline_user_args().has("--padtest"):
		var t: Node = load("res://tests/padtest.gd").new()
		t.main = self
		add_child(t)
	if not showcase.is_empty():
		autotest_limit = 0.0
		for c in showcase:
			autotest_limit += float(Showcase.clip(c).dur)
		waves.intermission = 2.0
	if autotest or SettingsScript.quick_start:
		SettingsScript.quick_start = false
		start_game()
	else:
		go_home_screen()


func _setup_input() -> void:
	# keyboard / mouse, then the controller (Xbox layout; Godot maps other
	# controllers onto the same buttons)
	_bind("move_forward", [KEY_W, KEY_UP], [], [], [[JOY_AXIS_LEFT_Y, -1.0]], 0.2)
	_bind("move_back", [KEY_S, KEY_DOWN], [], [], [[JOY_AXIS_LEFT_Y, 1.0]], 0.2)
	_bind("move_left", [KEY_A, KEY_LEFT], [], [], [[JOY_AXIS_LEFT_X, -1.0]], 0.2)
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [], [[JOY_AXIS_LEFT_X, 1.0]], 0.2)
	# look is read raw and shaped in player.gd (dead zone, curve, aim assist)
	_bind("look_left", [], [], [], [[JOY_AXIS_RIGHT_X, -1.0]], 0.0)
	_bind("look_right", [], [], [], [[JOY_AXIS_RIGHT_X, 1.0]], 0.0)
	_bind("look_up", [], [], [], [[JOY_AXIS_RIGHT_Y, -1.0]], 0.0)
	_bind("look_down", [], [], [], [[JOY_AXIS_RIGHT_Y, 1.0]], 0.0)
	_bind("jump", [KEY_SPACE], [], [JOY_BUTTON_A])
	_bind("sprint", [KEY_SHIFT])
	_bind("sprint_toggle", [], [], [JOY_BUTTON_LEFT_STICK])
	_bind("crouch", [KEY_C, KEY_CTRL], [], [JOY_BUTTON_B])
	_bind("reload", [KEY_R], [], [JOY_BUTTON_X])
	_bind("switch_weapon", [KEY_Q], [], [JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER])
	_bind("weapon_1", [KEY_1])
	_bind("weapon_2", [KEY_2])
	_bind("grenade", [KEY_G], [], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("melee", [KEY_F, KEY_V], [], [JOY_BUTTON_RIGHT_STICK])
	_bind("flashlight", [KEY_T], [], [JOY_BUTTON_DPAD_UP])
	_bind("fire", [], [MOUSE_BUTTON_LEFT], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], 0.3)
	_bind("aim", [KEY_E], [MOUSE_BUTTON_RIGHT], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], 0.3)
	_bind("pause", [KEY_ESCAPE], [], [JOY_BUTTON_START])
	# menus
	_bind("ui_accept", [], [], [JOY_BUTTON_A])
	_bind("ui_cancel", [], [], [JOY_BUTTON_B])
	_bind("ui_up", [], [], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("ui_down", [], [], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("ui_left", [], [], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("ui_right", [], [], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("tab_prev", [], [], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("tab_next", [], [], [JOY_BUTTON_RIGHT_SHOULDER])


## Adds keys, mouse buttons, joypad buttons and joypad axes ([axis, direction])
## to an action. `deadzone` < 0 keeps an existing action's dead zone.
func _bind(action: String, keys: Array, buttons: Array = [], joy_buttons: Array = [],
		joy_axes: Array = [], deadzone := -1.0) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5 if deadzone < 0.0 else deadzone)
	elif deadzone >= 0.0:
		InputMap.action_set_deadzone(action, deadzone)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)
	for jb in joy_buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = jb
		e.device = -1
		InputMap.action_add_event(action, e)
	for ja in joy_axes:
		var m := InputEventJoypadMotion.new()
		m.axis = ja[0]
		m.axis_value = ja[1]
		m.device = -1
		InputMap.action_add_event(action, m)


func _on_device_changed(using_pad: bool) -> void:
	# controllers drive the menus by focus, so hide the pointer
	if state != "playing":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if using_pad else Input.MOUSE_MODE_VISIBLE
	ui.on_device_changed(using_pad)


func _menu_mouse_mode() -> int:
	return Input.MOUSE_MODE_HIDDEN if Gamepad.active else Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- settings

func apply_settings(key: String = "*") -> void:
	var s := settings
	if key == "vegetation" or key == "models":
		# the level is built once at load, so rebuild it
		SettingsScript.quick_start = false
		get_tree().paused = false
		get_tree().call_deferred("reload_current_scene")
		return
	atmosphere.apply_quality(s)
	if key == "*" or key == "time_of_day":
		var tod: String = s.get_v("time_of_day")
		atmosphere.apply_time_of_day(tod)
		if s.get_v("flashlight_auto"):
			player.set_flashlight(tod == "night")
	if key == "flashlight_auto" and s.get_v("flashlight_auto"):
		player.set_flashlight(s.get_v("time_of_day") == "night")
	arena.set_grass_density(s.get_v("grass_density"))
	Shaders.set_wind(1.0 if s.get_v("wind") else 0.0)
	Decals.enabled = s.get_v("decals")
	# viewport / upscaling / anti-aliasing
	var vp := get_viewport()
	var up: int = s.get_v("upscaler")
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][up]
	vp.scaling_3d_scale = s.get_v("render_scale")
	var aa: int = s.get_v("aa")
	var fsr2 := up == 2
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_DISABLED][aa] if not fsr2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 and not fsr2 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == 4 and not fsr2
	vp.positional_shadow_atlas_size = 4096 if int(s.get_v("shadows")) >= 3 else 2048
	# display
	if not autotest:
		var want_fs: bool = s.get_v("fullscreen")
		var is_fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if s.get_v("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(s.get_v("max_fps"))
	# gameplay
	player.base_fov = s.get_v("fov")
	player.mouse_sens = s.get_v("sensitivity")
	player.invert_y = s.get_v("invert_y")
	player.pad_look_speed = s.get_v("pad_look_speed")
	player.pad_invert_y = s.get_v("pad_invert_y")
	player.pad_deadzone = s.get_v("pad_deadzone")
	player.aim_assist = s.get_v("aim_assist")
	player.crouch_toggle = s.get_v("crouch_mode") == "toggle"
	player.aim_toggle = s.get_v("aim_mode") == "toggle"
	Gamepad.rumble_enabled = s.get_v("rumble")
	# audio
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(s.get_v("master_volume")), 0.0001)))


# ---------------------------------------------------------------- states

func go_home_screen() -> void:
	state = "home"
	get_tree().paused = true
	menu_cam.current = true
	Input.mouse_mode = _menu_mouse_mode()
	ui.show_screen("home")


func set_menu_state(s: String) -> void:
	state = s


func start_game() -> void:
	state = "playing"
	game_started = true
	player.camera.current = true
	get_tree().paused = false
	ui.show_screen("")
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_game() -> void:
	if state != "playing":
		return
	state = "pause"
	get_tree().paused = true
	Input.mouse_mode = _menu_mouse_mode()
	ui.show_screen("pause")


func resume_game() -> void:
	state = "playing"
	get_tree().paused = false
	ui.show_screen("")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func restart() -> void:
	SettingsScript.quick_start = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func go_home() -> void:
	SettingsScript.quick_start = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	state = "dead"
	Input.mouse_mode = _menu_mouse_mode()
	new_best = false
	if waves.wave > best_wave or (waves.wave == best_wave and player.score > best_score):
		best_wave = waves.wave
		best_score = player.score
		new_best = true
	_save_stats()
	if autotest:
		print("AUTOTEST: player died at wave %d, kills %d, score %d, t=%.1f" % [waves.wave, player.kills, player.score, autotest_time])
	else:
		var t := get_tree().create_timer(1.2)
		t.timeout.connect(_show_dead_screen)


func _show_dead_screen() -> void:
	if state == "dead":
		ui.show_dead(waves.wave, player.kills, player.score, new_best)


func _input(event: InputEvent) -> void:
	if autotest:
		return
	var key := event as InputEventKey
	var pressed_key := key != null and key.pressed and not key.echo
	if state == "playing" and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if state != "playing" and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pressed_key and key.physical_keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT] and state == "playing":
		var f := 1.12 if key.physical_keycode == KEY_BRACKETRIGHT else 1.0 / 1.12
		settings.set_v("sensitivity", clampf(float(settings.get_v("sensitivity")) * f, 0.0005, 0.008))
		player.notify("Mouse sensitivity: %.2f" % (float(settings.get_v("sensitivity")) * 400.0))


## Menu / pause navigation. Unhandled, so an open dropdown gets B / Esc first.
func _unhandled_input(event: InputEvent) -> void:
	if autotest or event.is_echo():
		return
	var pause := event.is_action_pressed("pause")
	var back := event.is_action_pressed("ui_cancel")
	match state:
		"playing":
			if pause:
				pause_game()
				get_viewport().set_input_as_handled()
		"pause":
			if pause or back:
				resume_game()
				get_viewport().set_input_as_handled()
		"settings", "controls":
			if pause or back:
				ui.go_back()
				get_viewport().set_input_as_handled()
		"dead":
			if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_R:
				restart()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and not autotest:
		pause_game()


func _process(delta: float) -> void:
	if not game_started and menu_cam.current:
		_orbit_t += delta * 0.04
		var p := Vector3(sin(_orbit_t) * 46.0, 20.0 + sin(_orbit_t * 0.7) * 3.0, cos(_orbit_t) * 46.0)
		menu_cam.global_position = p
		menu_cam.look_at(Vector3(0, 2.5, -2), Vector3.UP)
	if not autotest:
		return
	autotest_time += delta
	_take_shots()
	_run_showcase(delta)
	_run_gallery()
	if Engine.get_process_frames() % 300 == 0:
		print("AUTOTEST t=%.1f wave=%d alive_enemies=%d remaining=%d kills=%d hp=%.0f sh=%.0f fps=%d" % [
			autotest_time, waves.wave, get_tree().get_nodes_in_group("enemy").size(), waves.remaining(),
			player.kills, player.health, player.shield, Engine.get_frames_per_second()])
		if OS.get_cmdline_user_args().has("--debug") and waves.remaining() <= 2:
			for e in get_tree().get_nodes_in_group("enemy"):
				print("   %s pos=%s vel=%s state=%s los=%s navfin=%s goal=%s next=%s floor=%s" % [e.type, e.global_position.snapped(Vector3.ONE * 0.1), e.velocity.snapped(Vector3.ONE * 0.1), e.state, e.los, e.agent.is_navigation_finished(), e.goal.snapped(Vector3.ONE * 0.1), e.agent.get_next_path_position().snapped(Vector3.ONE * 0.1), e.is_on_floor()])
			print("   player=%s" % player.global_position.snapped(Vector3.ONE * 0.1))
	if autotest_time >= autotest_limit or (state == "dead" and autotest_time > 3.0 and not player.godmode):
		print("AUTOTEST DONE: wave=%d kills=%d score=%d alive=%s nodes=%d" % [waves.wave, player.kills, player.score, player.alive, get_tree().get_node_count()])
		get_tree().quit()


func _run_showcase(delta: float) -> void:
	if showcase.is_empty():
		return
	_sc_t += delta
	var t := _sc_t
	for name in showcase:
		var c := Showcase.clip(name)
		if t <= float(c.dur) or name == showcase[-1]:
			if name == "fps":
				player.camera.current = true
				hud.visible = true
			else:
				var s := Showcase.sample(c, t)
				menu_cam.current = true
				hud.visible = false
				menu_cam.fov = 62.0
				menu_cam.global_position = s[0]
				menu_cam.look_at(s[1], Vector3.UP)
			return
		t -= float(c.dur)


## Debug: --gallery lines up one of each enemy type in front of a frozen
## player and steps through hip fire / aim on both weapons (pair with --shots).
var _gallery_step := -1


func _run_gallery() -> void:
	if not OS.get_cmdline_user_args().has("--gallery"):
		return
	var live := OS.get_cmdline_user_args().has("--live")
	if _gallery_step < 0:
		_gallery_step = 0
		waves.set_physics_process(false)
		player.autobot = false
		player.scripted = true
		player.rotation.y += PI
		var p: Vector3 = arena.player_spawn
		var spots := [[-2.6, 5.5, "stalker"], [-0.6, 8.5, "trooper"], [1.6, 7.0, "trooper"], [-3.8, 12.0, "bulwark"], [3.8, 11.0, "lancer"], [0.8, 14.5, "trooper"]]
		var fwd := -player.global_transform.basis.z
		var right := player.global_transform.basis.x
		for sp in spots:
			var e := EnemyScript.new()
			e.setup(sp[2], 4)
			world.add_child(e)
			var q: Vector3 = p + right * float(sp[0]) + fwd * float(sp[1])
			q.y = arena.height_at(q.x, q.z) + 0.2
			e.global_position = q
			e.rotation.y = player.rotation.y
			if live:
				e.player = player
		return
	var t := autotest_time
	if live:
		# enemies close in on a frozen player for a few seconds, then the bot fights back
		if t >= 7.0 and not player.autobot:
			player.scripted = false
			player.autobot = true
		return
	var steps := [[3.0, false, 0], [5.0, true, 0], [7.0, false, 1], [9.0, true, 1]]
	for st in steps:
		if t >= st[0]:
			player.in_aim = st[1]
			player.in_select = st[2]


## Screenshot helper for automated visual checks: --shots=<dir>
func _take_shots() -> void:
	if _shot_dir == "":
		return
	var times := [3.0, 6.0, 9.0, 11.0, 13.0, 15.0]
	var menus := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-times="):
			times = Array(a.get_slice("=", 1).split(",")).map(func(x): return float(x))
			menus = false
	if _shot_i < times.size() and autotest_time >= times[_shot_i]:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [_shot_dir, _shot_i])
		print("saved shot %d" % _shot_i)
		_shot_i += 1
		if not menus:
			return
		if _shot_i == 3:
			menu_cam.current = true
			game_started = false
			hud.visible = false
			ui.show_screen("home")
		elif _shot_i == 4:
			ui.show_screen("settings")
			if OS.get_cmdline_user_args().has("--shot-controls"):
				ui.tabs.current_tab = 3   # Controller
		elif _shot_i == 5:
			ui.show_screen("controls")


# ---------------------------------------------------------------- stats

func _load_stats() -> void:
	var cf := ConfigFile.new()
	if cf.load(STATS_PATH) == OK:
		best_wave = cf.get_value("stats", "best_wave", 0)
		best_score = cf.get_value("stats", "best_score", 0)


func _save_stats() -> void:
	var cf := ConfigFile.new()
	cf.load(STATS_PATH)
	cf.set_value("stats", "best_wave", best_wave)
	cf.set_value("stats", "best_score", best_score)
	cf.save(STATS_PATH)
