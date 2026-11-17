extends Node3D
## Entry point: input map, environment, world assembly, game states.

const ArenaScript = preload("res://scripts/arena.gd")
const PlayerScript = preload("res://scripts/player.gd")
const WavesScript = preload("res://scripts/waves.gd")
const HudScript = preload("res://scripts/hud.gd")
const Sfx = preload("res://scripts/sfx.gd")

const SAVE_PATH := "user://verdant_hold.cfg"

var world: Node3D
var arena: Node3D
var player: CharacterBody3D
var waves: Node
var hud: Control
var state := "title"
var sensitivity := 0.0025
var best_wave := 0
var best_score := 0
var new_best := false

var autotest := false
var autotest_time := 0.0
var autotest_limit := 90.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	autotest = args.has("--autotest")
	for a in args:
		if a.begins_with("--seconds="):
			autotest_limit = float(a.get_slice("=", 1))
	_setup_input()
	_load()
	Sfx.preload_all()
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_to_group("world")
	add_child(world)
	_setup_environment()
	var t0 := Time.get_ticks_msec()
	arena = ArenaScript.new()
	arena.name = "Arena"
	world.add_child(arena)
	arena.build()
	print("Arena built in %d ms" % (Time.get_ticks_msec() - t0))
	player = PlayerScript.new()
	player.name = "Player"
	world.add_child(player)
	player.global_position = arena.player_spawn
	player.mouse_sens = sensitivity
	player.autobot = autotest
	player.godmode = args.has("--godmode")
	player.died.connect(_on_player_died)
	waves = WavesScript.new()
	waves.name = "Waves"
	waves.spawn_points = arena.spawn_points
	waves.player = player
	world.add_child(waves)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.player = player
	hud.waves = waves
	hud.main = self
	layer.add_child(hud)
	waves.wave_started.connect(func(n): hud.show_banner("WAVE %d" % n, "%d hostiles inbound" % waves.remaining(), 3.0))
	waves.wave_cleared.connect(func(n): hud.show_banner("WAVE %d CLEARED" % n, "Resupply at the bunker cache", 3.5))
	waves.announce.connect(func(t): hud.show_banner("WARNING", t, 4.0))
	if autotest:
		start_game()
	else:
		state = "title"
		get_tree().paused = true


func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("jump", [KEY_SPACE])
	_bind("sprint", [KEY_SHIFT])
	_bind("crouch", [KEY_C, KEY_CTRL])
	_bind("reload", [KEY_R])
	_bind("switch_weapon", [KEY_Q])
	_bind("weapon_1", [KEY_1])
	_bind("weapon_2", [KEY_2])
	_bind("grenade", [KEY_G])
	_bind("melee", [KEY_F, KEY_V])
	_bind("fire", [], [MOUSE_BUTTON_LEFT])
	_bind("aim", [KEY_E], [MOUSE_BUTTON_RIGHT])


func _bind(action: String, keys: Array, buttons: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.45, 0.62)
	sm.sky_horizon_color = Color(0.78, 0.76, 0.62)
	sm.ground_horizon_color = Color(0.5, 0.52, 0.4)
	sm.ground_bottom_color = Color(0.12, 0.15, 0.08)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.62, 0.48)
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-35), 0)
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	world.add_child(sun)


# ---------------------------------------------------------------- states

func start_game() -> void:
	state = "playing"
	get_tree().paused = false
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_game() -> void:
	if state != "playing":
		return
	state = "paused"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_game() -> void:
	state = "playing"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	state = "dead"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	new_best = false
	if waves.wave > best_wave or (waves.wave == best_wave and player.score > best_score):
		best_wave = waves.wave
		best_score = player.score
		new_best = true
	_save()
	if autotest:
		print("AUTOTEST: player died at wave %d, kills %d, score %d, t=%.1f" % [waves.wave, player.kills, player.score, autotest_time])


func _input(event: InputEvent) -> void:
	if autotest:
		return
	match state:
		"title":
			if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ENTER, KEY_SPACE]):
				start_game()
				get_viewport().set_input_as_handled()
		"playing":
			if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
				pause_game()
				get_viewport().set_input_as_handled()
			elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		"paused":
			if event is InputEventMouseButton and event.pressed:
				resume_game()
				get_viewport().set_input_as_handled()
			elif event is InputEventKey and event.pressed:
				match event.physical_keycode:
					KEY_ESCAPE:
						resume_game()
					KEY_Q:
						get_tree().quit()
		"dead":
			if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_R):
				restart()
	if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
		var f := 1.12 if event.physical_keycode == KEY_BRACKETRIGHT else 1.0 / 1.12
		sensitivity = clampf(sensitivity * f, 0.0004, 0.012)
		player.mouse_sens = sensitivity
		player.notify("Mouse sensitivity: %.2f" % (sensitivity * 400.0))
		_save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and not autotest:
		pause_game()


var _shot_i := 0


func _take_shots() -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.get_slice("=", 1)
	if dir == "":
		return
	var times := [6.0, 14.0, 24.0, 34.0, 44.0]
	if _shot_i < times.size() and autotest_time >= times[_shot_i]:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [dir, _shot_i])
		print("saved shot %d" % _shot_i)
		_shot_i += 1
		if _shot_i == 4:
			var cam := Camera3D.new()
			cam.fov = 60
			world.add_child(cam)
			cam.global_position = Vector3(38, 34, 52)
			cam.look_at(Vector3(0, 0, -2), Vector3.UP)
			cam.current = true
			hud.visible = false


func _process(delta: float) -> void:
	if not autotest:
		return
	autotest_time += delta
	_take_shots()
	if Engine.get_process_frames() % 300 == 0:
		print("AUTOTEST t=%.1f wave=%d alive_enemies=%d remaining=%d kills=%d hp=%.0f sh=%.0f fps=%d" % [
			autotest_time, waves.wave, get_tree().get_nodes_in_group("enemy").size(), waves.remaining(),
			player.kills, player.health, player.shield, Engine.get_frames_per_second()])
	if autotest_time >= autotest_limit or (state == "dead" and autotest_time > 3.0 and not player.godmode):
		print("AUTOTEST DONE: wave=%d kills=%d score=%d alive=%s nodes=%d" % [waves.wave, player.kills, player.score, player.alive, get_tree().get_node_count()])
		get_tree().quit()


# ---------------------------------------------------------------- save

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_wave = cf.get_value("stats", "best_wave", 0)
		best_score = cf.get_value("stats", "best_score", 0)
		sensitivity = cf.get_value("settings", "sensitivity", sensitivity)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("stats", "best_wave", best_wave)
	cf.set_value("stats", "best_score", best_score)
	cf.set_value("settings", "sensitivity", sensitivity)
	cf.save(SAVE_PATH)
