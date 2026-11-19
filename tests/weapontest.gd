extends Node
## Weapon-system test: armory rack, swapping and dropping, ammo scavenging,
## enemy weapon drops, alien weapons (battery, overheat, charged shot),
## ground-weapon expiry, rack restock, ammo caches and difficulty scaling.
## Run headless:  godot --headless -- --weapontest
## Prints PASS / FAIL per check and exits with the number of failures.

const EnemyScript = preload("res://scripts/enemy.gd")
const Weapons = preload("res://scripts/weapons.gd")
const WeaponPickup = preload("res://scripts/weapon_pickup.gd")
const Difficulty = preload("res://scripts/difficulty.gd")
const WavesScript = preload("res://scripts/waves.gd")

var main: Node
var p: Node
var fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""])
	if not ok:
		fails += 1


func _key(k: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await _frames(2)


func _mouse(pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	Input.parse_input_event(e)


func _click() -> void:
	_mouse(true)
	await _frames(2)
	_mouse(false)
	await _frames(2)


## Stand 1 m from a node, facing it.
func _stand_at(n: Node3D, dist := 1.0) -> void:
	var to: Vector3 = n.global_position - p.global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	var at: Vector3 = n.global_position - dir * dist
	at.y = main.arena.height_at(at.x, at.z) + 0.15
	if absf(n.global_position.y - at.y) > 2.5:
		at.y = n.global_position.y - 1.4
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-dir.x, -dir.z)
	p.head.rotation.x = 0.0
	await _frames(4)


func _ground(id: String) -> Array:
	return get_tree().get_nodes_in_group("weapon_pickup").filter(func(x): return not x.rack and x.state.get("id", "") == id)


func _rack(id: String) -> Node:
	for r in get_tree().get_nodes_in_group("weapon_rack"):
		if r.rack_id == id:
			return r
	return null


func _ids() -> Array:
	return p.weapons.map(func(w): return w.id)


func _run() -> void:
	await _frames(5)
	main.start_game()
	main.waves.set_physics_process(false)   # no waves: the test drives wave numbers itself
	p = main.player
	await _secs(0.5)
	# ---- loadout and rack
	_check("starts with carbine + sidearm", _ids() == ["carbine", "sidearm"], str(_ids()))
	var racks := get_tree().get_nodes_in_group("weapon_rack")
	_check("armory rack has 5 weapons", racks.size() == 5 and racks.all(func(r): return r.is_in_group("weapon_pickup")), str(racks.size()))
	# ---- take the shotgun from the rack (E), carbine drops
	var rb: Node = _rack("breacher")
	await _stand_at(rb, 1.0)
	_check("rack weapon is the pickup target", p.interact_target == rb, str(p.interact_target))
	# headless: the first synthetic key event of a session is dropped, so
	# prime the input queue with a key the game doesn't use
	await _key(KEY_F12)
	await _key(KEY_E)
	await _frames(3)
	_check("E swaps the weapon in hand for the Breacher", p.weapons[p.current].id == "breacher", str(_ids()))
	_check("carbine dropped on the ground", _ground("carbine").size() == 1)
	_check("rack slot now empty", not rb.is_in_group("weapon_pickup"))
	await _secs(0.6)
	# ---- shotgun fires 1 shell, 9 pellets
	var a0: int = p.weapons[p.current].ammo
	await _click()
	_check("Breacher uses one shell per shot", p.weapons[p.current].ammo == a0 - 1, "%d -> %d" % [a0, p.weapons[p.current].ammo])
	# ---- scavenge sidearm ammo by walking over a dropped sidearm
	var si: int = p._slot_of("sidearm")
	p.weapons[si].reserve = 0
	var gp := WeaponPickup.new()
	gp.state = Weapons.new_state("sidearm")
	main.world.add_child(gp)
	gp.global_position = p.global_position + Vector3(0.3, 0.4, 0)
	await _secs(0.4)
	_check("walking over a carried gun takes its ammo", p.weapons[si].reserve > 0, "reserve %d" % p.weapons[si].reserve)
	# ---- enemy drops its weapon
	var e: Node = EnemyScript.new()
	e.setup("stalker", 1)
	main.world.add_child(e)
	var ep: Vector3 = p.global_position + Vector3(4, 0, 4)
	e.global_position = Vector3(ep.x, main.arena.height_at(ep.x, ep.z) + 0.3, ep.z)
	await _frames(3)
	_check("stalker carries a Spitter", e.weapon_id == "spitter" and e.gun != null)
	var before := _ground("spitter").size()
	e.take_damage(9999.0, "melee", p.global_position)
	await _secs(1.2)
	var drops := _ground("spitter")
	_check("killed stalker drops its Spitter", drops.size() == before + 1)
	if drops.is_empty():
		return _finish()
	var sp: Node = drops[-1]
	var bat: float = sp.state.battery
	_check("dropped alien weapon is partly charged", bat >= 0.35 and bat <= 0.85, "%.2f" % bat)
	# ---- pick up the Spitter (alien), fire it
	await _stand_at(sp, 0.8)
	await _key(KEY_E)
	var w: Dictionary = p.weapons[p.current]
	_check("picked up the Spitter", w.id == "spitter", str(_ids()))
	await _secs(0.6)
	var b0: float = w.battery
	await _click()
	_check("Spitter shot drains battery", w.battery < b0, "%.3f -> %.3f" % [b0, w.battery])
	# charged shot: hold, release
	await _secs(0.3)
	var b1: float = w.battery
	_mouse(true)
	await _secs(0.9)
	_mouse(false)
	await _frames(3)
	_check("held Spitter fires a charged shot", b1 - w.battery >= w.charge_drain * 0.9, "%.3f -> %.3f" % [b1, w.battery])
	# overheat
	w.heat = 0.0
	w.overheated = 0.0
	for i in 20:
		await _click()
		await _secs(0.15)
		if w.overheated > 0.0:
			break
	_check("Spitter overheats under sustained fire", w.overheated > 0.0, "heat %.2f" % w.heat)
	# ---- expiry: untouched ground weapons vanish 5 waves later, rack restocks
	var carbine_drop: Array = _ground("carbine")
	var w0 := WeaponPickup.current_wave
	WeaponPickup.on_wave_started(get_tree(), w0 + 4)
	await _frames(2)
	_check("ground weapon survives 4 waves", _ground("carbine").size() == carbine_drop.size() and carbine_drop.size() > 0)
	main._on_wave_started(6)
	await _secs(0.8)
	_check("ground weapon expires after 5 untouched waves", _ground("carbine").is_empty())
	_check("armory restocks (wave 6)", rb.is_in_group("weapon_pickup") and rb.state.get("id", "") == "breacher")
	# ---- human ammo cache: limited refills, only spent when needed, reset every 5 waves
	var hc: Node = null
	var ac: Node = null
	for c in get_tree().get_nodes_in_group("ammo_cache"):
		if c.family == "human":
			hc = c
		else:
			ac = c
	_check("human + alien caches exist", hc != null and ac != null)
	if hc == null or ac == null:
		return _finish()
	var bi: int = p._slot_of("breacher")
	p.weapons[bi].reserve = 0
	var r0: int = hc.refills
	await _stand_at(hc, 0.3)
	await _secs(0.3)
	_check("human cache refills human weapons", p.weapons[bi].reserve == p.weapons[bi].max_reserve)
	_check("one refill spent", hc.refills == r0 - 1, "%d -> %d" % [r0, hc.refills])
	await _secs(1.2)
	_check("nothing to refill: no refill spent", hc.refills == r0 - 1)
	hc.refills = 0
	p.weapons[bi].reserve = 0
	await _secs(1.2)
	_check("empty cache gives nothing", p.weapons[bi].reserve == 0)
	main._on_wave_started(11)
	_check("caches refill every 5 waves", hc.refills == hc.max_refills)
	# ---- alien cache recharges alien weapons
	var spi: int = p._slot_of("spitter")
	p.weapons[spi].battery = 0.1
	await _stand_at(ac, 0.3)
	await _secs(0.4)
	_check("alien cache recharges alien weapons", p.weapons[spi].battery > 0.99, "%.2f" % p.weapons[spi].battery)
	# ---- difficulty
	Difficulty.level = "easy"
	var easy: Node = EnemyScript.new()
	easy.setup("trooper", 1)
	Difficulty.level = "hard"
	var hard: Node = EnemyScript.new()
	hard.setup("trooper", 1)
	_check("hard enemies are tougher than easy", hard.max_health > easy.max_health and hard.max_shield > easy.max_shield,
		"%.0f vs %.0f hp" % [hard.max_health, easy.max_health])
	_check("hard enemies hit harder", hard.dmg_mult > easy.dmg_mult)
	var wv := WavesScript.new()
	var n_hard: int = wv._composition(6).size()
	Difficulty.level = "easy"
	var n_easy: int = wv._composition(6).size()
	_check("hard waves are bigger", n_hard > n_easy, "%d vs %d" % [n_hard, n_easy])
	_check("fewer cache refills on hard", Difficulty.LEVELS.hard.refills < Difficulty.LEVELS.easy.refills)
	easy.free()
	hard.free()
	wv.free()
	Difficulty.level = "normal"
	_finish()


func _finish() -> void:
	print("WEAPONTEST DONE: %d failure(s)" % fails)
	get_tree().quit(fails)
