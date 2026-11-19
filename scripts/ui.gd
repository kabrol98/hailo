extends Control
## Menus: home, settings, controls, pause and death screens.
## The settings screen is generated from Settings.OPTIONS.

const SettingsScript = preload("res://scripts/settings.gd")
const Gamepad = preload("res://scripts/gamepad.gd")

const ACCENT := Color(1.0, 0.75, 0.25)
const TEXT := Color(0.9, 0.97, 0.88)
const DIM := Color(0.72, 0.82, 0.7, 0.8)
const PANEL := Color(0.03, 0.07, 0.04, 0.88)

## [action, keyboard / mouse, controller]
const CONTROLS := [
	["Move", "WASD / arrows", "Left stick"], ["Look", "Mouse", "Right stick"],
	["Fire", "Left click", "RT"], ["Aim / zoom", "Right click", "LT"],
	["Jump", "Space", "A"], ["Sprint", "Shift (hold)", "Click left stick"],
	["Crouch", "C / Ctrl", "B"], ["Reload", "R", "X (tap)"], ["Pick up weapon", "E", "X (hold)"],
	["Switch weapon", "Q / wheel / 1-2", "Y or LB"], ["Throw frag", "G", "RB"],
	["Melee", "F / V", "Click right stick"], ["Flashlight", "T", "D-pad up"],
	["Pause menu", "Esc", "Menu"], ["Mouse sensitivity", "[  ]", "Settings → Controller"],
]

var main: Node
var settings: Node
var screens := {}
var current := ""
var back_target := "home"
var rows := {}
var _syncing := false
var best_label: Label
var gfx_label: Label
var dead_stats: Label
var dead_best: Label
var tabs: TabContainer
var redeploy_btn: Button
var hint_labels: Array = []   # [Label, keyboard text, controller text]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	screens["home"] = _build_home()
	screens["settings"] = _build_settings()
	screens["controls"] = _build_controls()
	screens["pause"] = _build_pause()
	screens["dead"] = _build_dead()
	for k in screens:
		add_child(screens[k])
		screens[k].visible = false
	settings.changed.connect(_on_settings_changed)
	_sync_controls()
	on_device_changed(Gamepad.active)


func _process(_d: float) -> void:
	size = get_viewport_rect().size


func _input(event: InputEvent) -> void:
	if current != "settings" or tabs == null or event.is_echo():
		return
	# LB / RB flip settings tabs
	var step := 0
	if event.is_action_pressed("tab_prev"):
		step = -1
	elif event.is_action_pressed("tab_next"):
		step = 1
	if step != 0:
		tabs.current_tab = wrapi(tabs.current_tab + step, 0, tabs.get_tab_count())
		# the new tab only becomes visible this frame, so focus it afterwards
		_focus_first.call_deferred(tabs.get_current_tab_control())
		get_viewport().set_input_as_handled()


## Switches button prompts between keyboard and controller.
func on_device_changed(using_pad: bool) -> void:
	for h in hint_labels:
		(h[0] as Label).text = h[2] if using_pad else h[1]
	if redeploy_btn:
		redeploy_btn.text = "REDEPLOY" if using_pad else "REDEPLOY  (R)"
	if using_pad and current != "" and get_viewport().gui_get_focus_owner() == null:
		_focus_first(screens[current])


## Gives keyboard / controller focus to the first focusable control under `n`.
func _focus_first(n: Node) -> bool:
	if n == null:
		return false
	if n is Control and (n as Control).focus_mode == Control.FOCUS_ALL and (n as Control).is_visible_in_tree():
		(n as Control).grab_focus()
		return true
	for c in n.get_children():
		if _focus_first(c):
			return true
	return false


func _hint(kbm: String, pad: String, sz := 15) -> Label:
	var l := _label(kbm, sz, DIM)
	hint_labels.append([l, kbm, pad])
	return l


func show_screen(name: String) -> void:
	current = name
	for k in screens:
		screens[k].visible = k == name
	mouse_filter = Control.MOUSE_FILTER_STOP if name != "" else Control.MOUSE_FILTER_IGNORE
	if name == "home":
		_refresh_home()
	elif name == "settings":
		_sync_controls()
	if name == "":
		get_viewport().gui_release_focus()
	elif screens.has(name):
		# focus the first button so a controller (or arrow keys) can drive the menu
		_focus_first.call_deferred(screens[name])


# ---------------------------------------------------------------- theme

func _flat(bg: Color, border: Color, bw := 1, radius := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, _flat(Color(0.08, 0.14, 0.08, 0.85), Color(0.5, 0.7, 0.4, 0.35)))
		t.set_stylebox("hover", cls, _flat(Color(0.16, 0.24, 0.12, 0.95), ACCENT))
		t.set_stylebox("pressed", cls, _flat(Color(0.25, 0.2, 0.08, 0.95), ACCENT))
		t.set_stylebox("focus", cls, _flat(Color(0, 0, 0, 0), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, ACCENT)
		t.set_color("font_pressed_color", cls, ACCENT)
	t.set_stylebox("panel", "PanelContainer", _flat(PANEL, Color(0.5, 0.7, 0.4, 0.3), 1, 4))
	t.set_stylebox("panel", "TabContainer", _flat(Color(0, 0, 0, 0.25), Color(0.5, 0.7, 0.4, 0.2)))
	t.set_stylebox("tab_selected", "TabContainer", _flat(Color(0.16, 0.24, 0.12, 0.95), ACCENT))
	t.set_stylebox("tab_unselected", "TabContainer", _flat(Color(0.06, 0.1, 0.06, 0.8), Color(0.5, 0.7, 0.4, 0.25)))
	t.set_stylebox("tab_hovered", "TabContainer", _flat(Color(0.12, 0.18, 0.1, 0.9), ACCENT))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_stylebox("slider", "HSlider", _flat(Color(0.15, 0.2, 0.14), Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_area", "HSlider", _flat(Color(0.6, 0.48, 0.15), Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(ACCENT, Color(0, 0, 0, 0), 0, 2))
	return t


func _label(text: String, sz := 18, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String, cb: Callable, sz := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", sz)
	b.custom_minimum_size = Vector2(300, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	return b


func _center_panel(min_size: Vector2) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = min_size
	cc.add_child(pc)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	pc.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)
	return [root, vb]


# ---------------------------------------------------------------- home

func _build_home() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.03, 0.02, 0.92))
	g.set_color(1, Color(0.01, 0.03, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 8
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.6
	root.add_child(shade)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 80)
	m.add_theme_constant_override("margin_top", 70)
	m.add_theme_constant_override("margin_bottom", 50)
	root.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	m.add_child(vb)
	vb.add_child(_label("VERDANT HOLD", 76, ACCENT))
	vb.add_child(_label("JUNGLE OUTPOST  //  WAVE DEFENSE", 20, DIM))
	vb.add_child(_label("The Thorn are coming out of the trees. Hold the outpost as long as you can.", 18, TEXT))
	var sp := Control.new()
	sp.custom_minimum_size.y = 30
	vb.add_child(sp)
	vb.add_child(_button("DEPLOY", func(): main.start_game()))
	vb.add_child(_button("SETTINGS", func(): open_settings("home")))
	vb.add_child(_button("CONTROLS", func(): open_controls("home")))
	vb.add_child(_button("QUIT", func(): get_tree().quit()))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(fill)
	best_label = _label("", 18, DIM)
	vb.add_child(best_label)
	vb.add_child(_hint("Controller supported: plug in or pair one any time.", "D-pad / left stick to choose  ·  A to select  ·  B back"))
	gfx_label = _label("", 16, DIM)
	vb.add_child(gfx_label)
	return root


func _refresh_home() -> void:
	var diff := str(settings.get_v("difficulty")).capitalize()
	best_label.text = ("%s  ·  best: wave %d  ·  %d pts" % [diff, main.best_wave, main.best_score]) if main.best_wave > 0 else "%s  ·  no runs yet." % diff
	gfx_label.text = "Graphics: %s   ·   Time of day: %s   ·   Recommended for %s: %s" % [
		str(settings.get_v("preset")).capitalize(), str(settings.get_v("time_of_day")).capitalize(),
		SettingsScript.chip_name(), SettingsScript.recommended_preset().capitalize()]


# ---------------------------------------------------------------- settings

func open_settings(from: String) -> void:
	back_target = from
	main.set_menu_state("settings")
	show_screen("settings")


func open_controls(from: String) -> void:
	back_target = from
	main.set_menu_state("controls")
	show_screen("controls")


func go_back() -> void:
	main.set_menu_state(back_target)
	show_screen(back_target)


func _build_settings() -> Control:
	var r := _center_panel(Vector2(980, 660))
	var root: Control = r[0]
	var vb: VBoxContainer = r[1]
	vb.add_child(_label("SETTINGS", 34, ACCENT))
	var info := _label("This Mac: %s  ·  recommended preset: %s." % [
		SettingsScript.chip_name(), SettingsScript.recommended_preset().capitalize()], 15, DIM)
	vb.add_child(info)
	vb.add_child(_hint("Hover an option's name for details.", "LB / RB switch tabs  ·  D-pad to move and change values  ·  A select  ·  B back"))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.y = 470
	vb.add_child(tabs)
	var tab_boxes := {}
	for opt in SettingsScript.OPTIONS:
		var tname: String = opt.tab
		if not tab_boxes.has(tname):
			var sc := ScrollContainer.new()
			sc.name = tname
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			sc.follow_focus = true
			tabs.add_child(sc)
			var m := MarginContainer.new()
			m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for side in ["left", "right", "top", "bottom"]:
				m.add_theme_constant_override("margin_" + side, 14)
			sc.add_child(m)
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 6)
			m.add_child(box)
			tab_boxes[tname] = box
		tab_boxes[tname].add_child(_row(opt))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	vb.add_child(foot)
	var back := _button("BACK", go_back, 20)
	back.custom_minimum_size = Vector2(180, 44)
	foot.add_child(back)
	var rec := _button("USE RECOMMENDED GRAPHICS", func(): settings.apply_preset(SettingsScript.recommended_preset()), 16)
	rec.custom_minimum_size = Vector2(300, 44)
	foot.add_child(rec)
	return root


func _row(opt: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var lbl := _label(opt.label, 18, TEXT)
	lbl.custom_minimum_size.x = 360
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	lbl.tooltip_text = opt.get("hint", "")
	row.add_child(lbl)
	var key: String = opt.key
	var entry := {"opt": opt}
	match opt.type:
		"choice":
			var ob := OptionButton.new()
			ob.custom_minimum_size.x = 300
			for i in opt.choices.size():
				ob.add_item(opt.choices[i][0], i)
			ob.item_selected.connect(func(i): _on_change(key, opt.choices[i][1]))
			row.add_child(ob)
			entry.ctrl = ob
		"toggle":
			var cb := CheckButton.new()
			cb.toggled.connect(func(v): _on_change(key, v))
			row.add_child(cb)
			entry.ctrl = cb
		"slider":
			var sl := HSlider.new()
			sl.min_value = opt.min
			sl.max_value = opt.max
			sl.step = opt.step
			sl.custom_minimum_size = Vector2(300, 28)
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var vl := _label("", 18, ACCENT)
			vl.custom_minimum_size.x = 80
			sl.value_changed.connect(func(v):
				vl.text = _fmt(opt, v)
				_on_change(key, v))
			row.add_child(sl)
			row.add_child(vl)
			entry.ctrl = sl
			entry.val = vl
	if opt.has("hint"):
		var h := _label("      " + opt.hint, 13, DIM)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.custom_minimum_size.x = 860
		box.add_child(h)
	rows[key] = entry
	return box


func _fmt(opt: Dictionary, v: float) -> String:
	var x: float = v * float(opt.get("fmt_mul", 1.0))
	var f: String = opt.get("fmt", "%.2f")
	if f.contains("%d"):
		return f % int(round(x))
	return f % x


func _on_change(key: String, v) -> void:
	if _syncing:
		return
	settings.set_v(key, v)


func _on_settings_changed(key: String) -> void:
	if key == "*" or key == "preset":
		_sync_controls()


func _sync_controls() -> void:
	_syncing = true
	for key in rows:
		var e: Dictionary = rows[key]
		var v = settings.get_v(key)
		match e.opt.type:
			"choice":
				var ob: OptionButton = e.ctrl
				for i in e.opt.choices.size():
					if e.opt.choices[i][1] == v:
						ob.select(i)
			"toggle":
				(e.ctrl as CheckButton).set_pressed_no_signal(bool(v))
			"slider":
				(e.ctrl as HSlider).set_value_no_signal(float(v))
				(e.val as Label).text = _fmt(e.opt, float(v))
	_syncing = false


# ---------------------------------------------------------------- controls / pause / dead

func _build_controls() -> Control:
	var r := _center_panel(Vector2(780, 0))
	var vb: VBoxContainer = r[1]
	vb.add_child(_label("CONTROLS", 34, ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["", "KEYBOARD / MOUSE", "CONTROLLER"]:
		grid.add_child(_label(h, 14, DIM))
	for c in CONTROLS:
		var a := _label(c[0], 18, TEXT)
		a.custom_minimum_size.x = 200
		grid.add_child(a)
		var k := _label(c[1], 18, ACCENT)
		k.custom_minimum_size.x = 220
		grid.add_child(k)
		grid.add_child(_label(c[2], 18, ACCENT))
	vb.add_child(grid)
	vb.add_child(_label("Shields recharge when you avoid damage; health doesn't, so grab red med-packs.\nCarbine: strong vs flesh, headshots once shields are down.\nArc Caster: shreds shields but overheats.\nThe glowing bunker cache refills ammo and frags every 30 s.", 15, DIM))
	vb.add_child(_button("BACK", go_back, 20))
	return r[0]


func _build_pause() -> Control:
	var r := _center_panel(Vector2(380, 0))
	var vb: VBoxContainer = r[1]
	vb.add_child(_label("PAUSED", 40, ACCENT))
	vb.add_child(_button("RESUME", func(): main.resume_game()))
	vb.add_child(_button("SETTINGS", func(): open_settings("pause")))
	vb.add_child(_button("CONTROLS", func(): open_controls("pause")))
	vb.add_child(_button("QUIT TO HOME", func(): main.go_home()))
	vb.add_child(_button("QUIT GAME", func(): get_tree().quit()))
	return r[0]


func _build_dead() -> Control:
	var r := _center_panel(Vector2(560, 0))
	var vb: VBoxContainer = r[1]
	var t := _label("THE OUTPOST HAS FALLEN", 38, Color(1.0, 0.35, 0.25))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	dead_stats = _label("", 22, TEXT)
	dead_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dead_stats)
	dead_best = _label("NEW BEST", 20, ACCENT)
	dead_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dead_best)
	redeploy_btn = _button("REDEPLOY  (R)", func(): main.restart())
	vb.add_child(redeploy_btn)
	vb.add_child(_button("HOME", func(): main.go_home()))
	return r[0]


func show_dead(wave: int, kills: int, score: int, new_best: bool) -> void:
	dead_stats.text = "Survived to wave %d  ·  %d kills  ·  %d pts" % [wave, kills, score]
	dead_best.visible = new_best
	show_screen("dead")
