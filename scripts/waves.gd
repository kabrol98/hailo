extends Node
## Endless escalating waves of Thorn attackers emerging from jungle trails.

signal wave_started(n: int)
signal wave_cleared(n: int)
signal announce(text: String)

const EnemyScript = preload("res://scripts/enemy.gd")
const Sfx = preload("res://scripts/sfx.gd")

var spawn_points: Array = []
var player: Node3D
var wave := 0
var to_spawn: Array = []
var alive_count := 0
var spawn_cd := 0.0
var intermission := 5.0
var in_wave := false
var kills := 0
var max_alive := 10
var _announced := {}


func remaining() -> int:
	return alive_count + to_spawn.size()


func _physics_process(delta: float) -> void:
	if player == null or not player.is_alive():
		return
	if not in_wave:
		intermission -= delta
		if intermission <= 0.0:
			_start_wave()
		return
	if not to_spawn.is_empty() and alive_count < max_alive:
		spawn_cd -= delta
		if spawn_cd <= 0.0:
			_spawn(to_spawn.pop_front())
			spawn_cd = randf_range(0.4, 1.2)
	# stragglers stop sniping from the treeline and close in
	if to_spawn.is_empty() and alive_count <= 2:
		for e in get_tree().get_nodes_in_group("enemy"):
			e.min_range = minf(e.min_range, 5.0)
			e.max_range = minf(e.max_range, 14.0)
	if to_spawn.is_empty() and alive_count <= 0:
		in_wave = false
		intermission = 12.0
		player.on_wave_cleared()
		wave_cleared.emit(wave)


func _start_wave() -> void:
	wave += 1
	in_wave = true
	max_alive = mini(8 + wave, 18)
	to_spawn = _composition(wave)
	spawn_cd = 0.5
	Sfx.play_ui(self, "wave", 0.0)
	wave_started.emit(wave)


func _composition(n: int) -> Array:
	var list: Array = []
	var stalkers := 2 + n
	var troopers := 1 + int(n * 1.2)
	var bulwarks := 0 if n < 3 else 1 + int((n - 3) / 3)
	var lancers := 0 if n < 4 else 1 + int((n - 4) / 2)
	if n % 5 == 0:
		stalkers *= 2
	for i in stalkers:
		list.append("stalker")
	for i in troopers:
		list.append("trooper")
	list.shuffle()
	# heavies arrive mid-wave
	var mid := list.size() / 2
	for i in bulwarks:
		list.insert(mini(mid + i * 2, list.size()), "bulwark")
	for i in lancers:
		list.insert(mini(2 + i * 3, list.size()), "lancer")
	return list


func _spawn(type: String) -> void:
	var candidates: Array = []
	for sp in spawn_points:
		if (sp as Vector3).distance_to(player.global_position) > 28.0:
			candidates.append(sp)
	if candidates.is_empty():
		candidates = spawn_points.duplicate()
	var sp: Vector3 = candidates[randi() % candidates.size()]
	var e := EnemyScript.new()
	e.setup(type, wave)
	e.player = player
	get_parent().add_child(e)
	e.global_position = sp + Vector3(randf_range(-2.5, 2.5), 0.3, randf_range(-2.5, 2.5))
	e.died.connect(_on_enemy_died)
	alive_count += 1
	if (type == "bulwark" or type == "lancer") and not _announced.has(type):
		_announced[type] = true
		announce.emit("BULWARK INBOUND — strip its shield with plasma" if type == "bulwark" else "LANCER SPOTTED — watch for the red targeting beam")


func _on_enemy_died(e: Node) -> void:
	alive_count -= 1
	kills += 1
	if player != null and is_instance_valid(player):
		player.add_score(e.score_value)
