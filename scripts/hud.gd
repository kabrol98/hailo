extends Control
## All HUD + menu drawing, done immediate-mode in _draw().

const Weapons = preload("res://scripts/weapons.gd")
const WeaponIcons = preload("res://scripts/weapon_icons.gd")
const Gamepad = preload("res://scripts/gamepad.gd")

var player: Node3D
var waves: Node
var main: Node
var font: Font
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var _last_shield := 100.0
var _shield_flash := 0.0

const C_TEXT := Color(0.9, 0.97, 0.88)
const C_DIM := Color(0.75, 0.85, 0.72, 0.75)
const C_SHIELD := Color(0.35, 0.85, 1.0)
const C_HEALTH := Color(0.55, 0.95, 0.4)
const C_WARN := Color(1.0, 0.3, 0.2)
const C_ACCENT := Color(1.0, 0.75, 0.25)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	add_child(WeaponIcons.new())


func show_banner(t: String, sub := "", dur := 3.0) -> void:
	banner = t
	banner_sub = sub
	banner_t = dur


func _process(delta: float) -> void:
	size = get_viewport_rect().size
	banner_t = maxf(banner_t - delta, 0.0)
	_shield_flash = maxf(_shield_flash - delta, 0.0)
	if player != null and player.shield < _last_shield - 0.5:
		_shield_flash = 0.25
	if player != null:
		_last_shield = player.shield
	queue_redraw()


func _text(pos: Vector2, t: String, sz := 18, col := C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos + Vector2(2, 2), t, align, width, sz, Color(0, 0, 0, col.a * 0.6))
	draw_string(font, pos, t, align, width, sz, col)


func _ctext(y: float, t: String, sz := 18, col := C_TEXT) -> void:
	_text(Vector2(0, y), t, sz, col, HORIZONTAL_ALIGNMENT_CENTER, size.x)


func _draw() -> void:
	if player == null or not main.game_started:
		return
	_draw_vignette()
	if player.alive:
		_draw_crosshair()
		_draw_damage_dirs()
	_draw_bars()
	_draw_weapon()
	_draw_pickup_prompt()
	_draw_wave_info()
	_draw_radar()
	if banner_t > 0.0:
		var a := clampf(banner_t, 0.0, 1.0)
		_ctext(size.y * 0.28, banner, 46, Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, a))
		if banner_sub != "":
			_ctext(size.y * 0.28 + 38, banner_sub, 20, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, a))
	if player.msg_t > 0.0:
		_ctext(size.y * 0.68, player.msg, 18, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, clampf(player.msg_t, 0.0, 1.0)))
	if main.settings.get_v("show_fps"):
		_text(Vector2(size.x - 120, 30), "%d FPS" % Engine.get_frames_per_second(), 16, C_DIM)


func _panel(r: Rect2, a := 0.55) -> void:
	draw_rect(r, Color(0.02, 0.05, 0.03, a))
	draw_rect(r, Color(0.6, 0.8, 0.5, 0.25), false, 1.0)


func _draw_vignette() -> void:
	var hp: float = player.health / player.max_health
	var a := 0.0
	if hp < 0.5:
		a = (0.5 - hp) * 1.2 * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006))
	if not player.alive:
		a = 0.5
	if a <= 0.01:
		return
	var c := Color(0.6, 0.0, 0.0, a)
	var t := 90.0
	for i in 6:
		var k := float(i) / 6.0
		var cc := Color(c.r, c.g, c.b, c.a * (1.0 - k))
		var w := t * (1.0 - k) / 6.0 + 4.0
		var off := t * k
		draw_rect(Rect2(off, off, size.x - off * 2, w), cc)
		draw_rect(Rect2(off, size.y - off - w, size.x - off * 2, w), cc)
		draw_rect(Rect2(off, off, w, size.y - off * 2), cc)
		draw_rect(Rect2(size.x - off - w, off, w, size.y - off * 2), cc)


func _draw_crosshair() -> void:
	var c := size * 0.5
	var w: Dictionary = player.weapons[player.current]
	var spread: float = player._current_spread(w)
	var gap := 6.0 + spread * 600.0
	var col := C_WARN if player.aim_enemy else Color(1, 1, 1, 0.85)
	if player.sprinting:
		col.a = 0.25
	var l := 9.0
	if w.family == "alien" or w.mode != "hitscan":
		draw_arc(c, gap + 4.0, 0, TAU, 28, col, 1.5, true)
		draw_circle(c, 1.8, col)
	else:
		draw_line(c + Vector2(gap, 0), c + Vector2(gap + l, 0), col, 2.0)
		draw_line(c - Vector2(gap, 0), c - Vector2(gap + l, 0), col, 2.0)
		draw_line(c + Vector2(0, gap), c + Vector2(0, gap + l), col, 2.0)
		draw_line(c - Vector2(0, gap), c - Vector2(0, gap + l), col, 2.0)
		draw_circle(c, 1.5, col)
	if player.hitmarker > 0.0:
		var hc := C_WARN if player.hit_kill else Color(1, 1, 1)
		hc.a = clampf(player.hitmarker * 6.0, 0.0, 1.0)
		var s := 7.0
		var o := 14.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * s, c + d * o, hc, 2.5)


func _local_dir(world_pos: Vector3) -> Vector2:
	var rel: Vector3 = world_pos - player.global_position
	var local: Vector3 = player.global_transform.basis.inverse() * rel
	return Vector2(local.x, local.z)


func _draw_damage_dirs() -> void:
	var c := size * 0.5
	for d in player.damage_dirs:
		var v := _local_dir(d.pos)
		if v.length() < 0.5:
			continue
		var ang := v.angle()
		var a: float = clampf(d.t, 0.0, 1.0)
		draw_arc(c, 110.0, ang - 0.32, ang + 0.32, 16, Color(1.0, 0.15, 0.1, a * 0.85), 7.0, true)


func _draw_bars() -> void:
	var w := 460.0
	var x := size.x * 0.5 - w * 0.5
	var y := 26.0
	_panel(Rect2(x - 10, y - 10, w + 20, 52))
	# shield: segmented
	var segs := 20
	var sf: float = player.shield / player.max_shield
	var sw := (w - (segs - 1) * 3.0) / segs
	for i in segs:
		var fill := clampf(sf * segs - i, 0.0, 1.0)
		var r := Rect2(x + i * (sw + 3.0), y, sw, 16)
		draw_rect(r, Color(0.2, 0.3, 0.35, 0.5))
		if fill > 0.0:
			var col := C_SHIELD
			if _shield_flash > 0.0:
				col = Color(1, 1, 1)
			elif player.shield_charging:
				col = C_SHIELD.lerp(Color(1, 1, 1), 0.3 + 0.3 * sin(Time.get_ticks_msec() * 0.02))
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), col)
	if player.shield <= 0.0 and player.alive and fmod(Time.get_ticks_msec() * 0.001, 0.6) < 0.35:
		draw_rect(Rect2(x, y, w, 16), Color(1, 0.2, 0.15, 0.5), false, 2.0)
		_text(Vector2(x, y + 13), "SHIELDS DOWN", 14, C_WARN, HORIZONTAL_ALIGNMENT_CENTER, w)
	# health: blocks
	var hf: float = player.health / player.max_health
	var blocks := 10
	var bw := (w - (blocks - 1) * 4.0) / blocks
	for i in blocks:
		var fill := clampf(hf * blocks - i, 0.0, 1.0)
		var r := Rect2(x + i * (bw + 4.0), y + 22, bw, 8)
		draw_rect(r, Color(0.2, 0.3, 0.2, 0.5))
		if fill > 0.0:
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), C_HEALTH if hf > 0.35 else C_WARN)


func _draw_icon(id: String, r: Rect2, col: Color) -> bool:
	var tex: Texture2D = WeaponIcons.icon(id)
	if tex == null:
		return false
	draw_texture_rect(tex, r, false, col)
	return true


## Ammo readout for a weapon state: magazine "12 / 60" or battery %, plus heat.
func _ammo_text(w: Dictionary) -> String:
	if Weapons.uses_mag(w):
		return "%d / %d" % [w.ammo, w.reserve]
	return "%d%%" % int(round(w.battery * 100.0))


func _draw_weapon() -> void:
	var w: Dictionary = player.weapons[player.current]
	var fam_col := C_ACCENT if w.family == "human" else Color(1.0, 0.45, 0.85)
	var r := Rect2(size.x - 380, size.y - 168, 350, 138)
	_panel(r)
	# current weapon: big icon, name, ammo
	var icon_r := Rect2(r.position + Vector2(10, 8), Vector2(176, 66))
	if not _draw_icon(w.id, icon_r, Color(1, 1, 1, 0.95)):
		_text(icon_r.position + Vector2(0, 40), w.short, 22, C_TEXT)
	_text(r.position + Vector2(12, 92), w.name, 15, fam_col)
	if Weapons.uses_mag(w):
		var col := C_TEXT if w.ammo > int(w.mag) / 4 else C_WARN
		_text(r.position + Vector2(196, 50), str(w.ammo), 40, col)
		_text(r.position + Vector2(196 + 26 * str(w.ammo).length(), 50), "/ %d" % w.reserve, 20, C_DIM)
		if player.reloading > 0.0:
			_text(r.position + Vector2(196, 74), "RELOADING", 13, C_DIM)
		elif w.ammo == 0 and w.reserve == 0:
			_text(r.position + Vector2(196, 74), "NO AMMO", 13, C_WARN)
	else:
		# battery bar
		var bar := Rect2(r.position + Vector2(196, 24), Vector2(140, 12))
		draw_rect(bar, Color(0.2, 0.25, 0.3, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * w.battery, bar.size.y)), fam_col if w.battery > 0.2 else C_WARN)
		_text(bar.position + Vector2(0, 30), "CHARGE %d%%" % int(round(w.battery * 100.0)), 15, C_TEXT if w.battery > 0.0 else C_WARN)
	if w.has("heat_per_shot"):
		var hb := Rect2(r.position + Vector2(196, 64), Vector2(140, 8))
		draw_rect(hb, Color(0.2, 0.25, 0.3, 0.6))
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * w.heat, hb.size.y)), C_SHIELD.lerp(C_WARN, w.heat))
		if w.overheated > 0.0:
			_text(hb.position + Vector2(0, 22), "OVERHEATED", 13, C_WARN)
	if w.get("charge", 0.0) > 0.0 and w.has("charge_time"):
		var cf: float = clampf(w.charge / w.charge_time, 0.0, 1.0)
		var c := size * 0.5
		draw_arc(c, 22.0, -PI / 2, -PI / 2 + TAU * cf, 32, fam_col if cf < 1.0 else Color(1, 1, 1), 3.0, true)
	# grenades
	for i in player.max_grenades:
		var gc := C_HEALTH if i < player.grenades else Color(0.3, 0.35, 0.3, 0.6)
		draw_circle(r.position + Vector2(240 + i * 20, 118), 6, gc)
	_text(r.position + Vector2(196, 123), "FRAG", 11, C_DIM)
	# carried weapon: smaller, above
	if player.weapons.size() > 1:
		var o: Dictionary = player.weapons[1 - player.current]
		var r2 := Rect2(size.x - 380, size.y - 228, 350, 54)
		_panel(r2, 0.4)
		if not _draw_icon(o.id, Rect2(r2.position + Vector2(10, 4), Vector2(122, 46)), Color(1, 1, 1, 0.55)):
			_text(r2.position + Vector2(10, 32), o.short, 16, C_DIM)
		_text(r2.position + Vector2(142, 22), o.name, 13, C_DIM)
		_text(r2.position + Vector2(142, 42), _ammo_text(o), 15, C_DIM if not Weapons.is_empty(o) else C_WARN)
		var sw := "Y" if Gamepad.active else "Q"
		_text(r2.position + Vector2(312, 34), sw, 18, C_ACCENT)


## "Hold X to pick up ..." when standing at a weapon.
func _draw_pickup_prompt() -> void:
	var t = player.interact_target
	if t == null or not is_instance_valid(t) or t.state.is_empty():
		return
	var st: Dictionary = t.state
	var key := "Hold X" if Gamepad.active else "E"
	var verb := "Pick up" if player.weapons.size() < 2 else "Swap %s for" % player.weapons[player.current].short
	var line := "%s  ·  %s %s" % [key, verb, st.name]
	var y := size.y * 0.74
	var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var ir := Rect2(size.x * 0.5 - 60, y - 64, 120, 45)
	_panel(Rect2(size.x * 0.5 - tw * 0.5 - 18, y - 70, tw + 36, 104), 0.5)
	_draw_icon(st.id, ir, Color(1, 1, 1, 0.9))
	_ctext(y, line, 20, C_TEXT)
	_ctext(y + 22, _ammo_text(st) + ("" if st.family == "human" else "  ·  alien weapon, no reload"), 14, C_DIM)


func _draw_wave_info() -> void:
	var r := Rect2(24, 20, 260, 92)
	_panel(r)
	if waves.in_wave:
		_text(r.position + Vector2(14, 32), "WAVE %d" % waves.wave, 28, C_ACCENT)
		_text(r.position + Vector2(14, 58), "Hostiles remaining: %d" % waves.remaining(), 16, C_TEXT)
	else:
		_text(r.position + Vector2(14, 32), "WAVE %d" % (waves.wave + 1), 28, C_DIM)
		_text(r.position + Vector2(14, 58), "Incoming in %d s" % ceili(maxf(waves.intermission, 0.0)), 16, C_TEXT)
	_text(r.position + Vector2(14, 82), "Score %d   ·   Kills %d" % [player.score, player.kills], 15, C_DIM)


func _draw_radar() -> void:
	var rad := 82.0
	var c := Vector2(24 + rad, size.y - 24 - rad)
	draw_circle(c, rad, Color(0.02, 0.06, 0.03, 0.6))
	draw_arc(c, rad, 0, TAU, 48, Color(0.6, 0.8, 0.5, 0.35), 1.5, true)
	draw_arc(c, rad * 0.5, 0, TAU, 32, Color(0.6, 0.8, 0.5, 0.15), 1.0, true)
	draw_line(c - Vector2(rad, 0), c + Vector2(rad, 0), Color(0.6, 0.8, 0.5, 0.12))
	draw_line(c - Vector2(0, rad), c + Vector2(0, rad), Color(0.6, 0.8, 0.5, 0.12))
	var rng := 35.0
	for e in get_tree().get_nodes_in_group("enemy"):
		var v := _local_dir((e as Node3D).global_position)
		var dist := v.length()
		var p := c + v / rng * rad
		if dist > rng:
			if waves.remaining() > 3:
				continue
			p = c + v.normalized() * rad  # last stragglers pinned to the radar edge
		var big: bool = e.type == "bulwark"
		draw_circle(p, 6.0 if big else 4.0, Color(1.0, 0.25, 0.2, 0.9))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 5), c + Vector2(-5, 5)]), C_ACCENT)
	_text(Vector2(c.x - rad, c.y + rad + 18), "35 m", 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, rad * 2)
