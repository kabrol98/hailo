extends Area3D
## Ammo caches. A human cache (in the bunker) tops up magazine reserves, the
## Arc Caster's battery and frags; an alien cache (a Thorn pod at the crash
## site) recharges alien weapons. Each has a few refills (by difficulty) that
## come back every RESET_EVERY waves. Walk into it to use it; a refill is only
## spent if something actually needed topping up.

const Sfx = preload("res://scripts/sfx.gd")
const Shaders = preload("res://scripts/shaders.gd")
const Difficulty = preload("res://scripts/difficulty.gd")

const RESET_EVERY := 5

var family := "human"
var max_refills := 3
var refills := 3
var _cd := 0.0
var _label: Label3D
var _glow: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	add_to_group("ammo_cache")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.3
	cs.shape = sh
	cs.position.y = 0.6
	add_child(cs)
	max_refills = Difficulty.refills()
	refills = max_refills
	var col := Color(0.3, 0.9, 1.0) if family == "human" else Color(1.0, 0.3, 0.85)
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.albedo_color = Color(col.r * 2.5, col.g * 2.5, col.b * 2.5)
	if family == "human":
		_build_crate()
	else:
		_build_pod(col)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 1.2
	_light.omni_range = 4.0
	_light.position.y = 1.0
	add_child(_light)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.9
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.outline_size = 8
	_label.modulate = col.lightened(0.3)
	_label.no_depth_test = false
	add_child(_label)
	_update_label()


func _build_crate() -> void:
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.18, 0.2, 0.17)
	base.metallic = 0.5
	base.roughness = 0.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.9, 1.0)
	body.mesh = bm
	body.material_override = base
	body.position.y = 0.45
	add_child(body)
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.62, 0.08, 1.02)
	strip.mesh = sm
	strip.material_override = _glow
	strip.position.y = 0.75
	add_child(strip)


func _build_pod(col: Color) -> void:
	var skin := Shaders.enemy_skin(Color(0.22, 0.12, 0.2), col, 1.2)
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	var body := MeshInstance3D.new()
	body.mesh = sph
	body.material_override = skin
	body.scale = Vector3(1.5, 1.1, 1.3)
	body.position.y = 0.5
	add_child(body)
	var core := MeshInstance3D.new()
	core.mesh = sph
	core.material_override = _glow
	core.scale = Vector3.ONE * 0.55
	core.position = Vector3(0, 0.75, 0.42)
	add_child(core)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.08
	cone.height = 0.6
	for i in 7:
		var a := TAU * i / 7.0
		var sp := MeshInstance3D.new()
		sp.mesh = cone
		sp.material_override = skin
		sp.position = Vector3(cos(a) * 0.55, 0.9, sin(a) * 0.5)
		sp.rotation = Vector3(sin(a) * 0.6, 0, -cos(a) * 0.6)
		add_child(sp)


func _update_label() -> void:
	var pips := ""
	for i in max_refills:
		pips += "●" if i < refills else "○"
	_label.text = "%s AMMO\n%s" % ["HUMAN" if family == "human" else "ALIEN", pips]
	var on := refills > 0
	_glow.albedo_color.a = 1.0 if on else 0.25
	_glow.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if on else BaseMaterial3D.TRANSPARENCY_ALPHA
	if _light:
		_light.light_energy = 1.2 if on else 0.2


func _process(delta: float) -> void:
	_t += delta
	_cd = maxf(_cd - delta, 0.0)
	if refills > 0:
		_light.light_energy = 1.0 + 0.3 * sin(_t * 3.0)
	if _cd > 0.0:
		return
	for b in get_overlapping_bodies():
		if b.has_method("refill"):
			_use(b)


func _use(player: Node) -> void:
	_cd = 1.0
	if refills <= 0:
		player.notify("%s CACHE EMPTY - restocks every %d waves" % [family.to_upper(), RESET_EVERY])
		return
	if not player.refill(family):
		return
	refills -= 1
	Sfx.play_ui(self, "pickup", -3.0, 0.8 if family == "alien" else 1.0)
	player.notify("%s WEAPONS REFILLED  (%d left)" % [family.to_upper(), refills])
	_update_label()


func on_wave_started(wave: int) -> void:
	max_refills = Difficulty.refills()
	if wave > 1 and (wave - 1) % RESET_EVERY == 0:
		refills = max_refills
	refills = mini(refills, max_refills)
	_update_label()
