extends Node3D
## A weapon lying on the ground (dropped by the Thorn or by you) or hanging on
## the bunker armory rack. The player picks it up (hold X / press E) or walks
## over a copy of a gun they carry to take its ammo (see player.gd).
##
## Ground weapons disappear after EXPIRE_WAVES waves without being touched,
## and only MAX_GROUND stay at once (the oldest untouched go first). Rack
## slots never expire; once taken they restock every RESTOCK_EVERY waves.

const Weapons = preload("res://scripts/weapons.gd")

const EXPIRE_WAVES := 5
const MAX_GROUND := 30
const RESTOCK_EVERY := 5

## Set by waves.gd so new pickups know when they were last touched.
static var current_wave := 0

var state: Dictionary = {}
var rack := false
var rack_id := ""
var drop_velocity := Vector3.ZERO
var last_touch := 0
var _model: Node3D
var _light: OmniLight3D
var _resting := false
var _t := 0.0


func _ready() -> void:
	add_to_group("weapon_pickup")
	last_touch = current_wave
	if rack:
		rack_id = state.id
		add_to_group("weapon_rack")
	_build()
	if not rack:
		_trim()


func _build() -> void:
	if _model:
		_model.queue_free()
	_model = Weapons.model(state.id)
	add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not _light:
		_light = OmniLight3D.new()
		_light.omni_range = 1.6
		_light.light_energy = 0.7
		_light.position = Vector3(0, 0.25, 0)
		add_child(_light)
	var d: Dictionary = Weapons.DEFS[state.id]
	_light.light_color = d.get("glow", Color(1.0, 0.85, 0.6))
	if rack:
		_resting = true
		# hang on the wall: barrel pointing sideways
		_model.rotation = Vector3(0, PI / 2, 0)
	else:
		_model.rotation = Vector3(0, randf() * TAU, PI / 2)


func _physics_process(delta: float) -> void:
	_t += delta
	if _resting:
		if not rack and _model:
			# a slow glint so weapons stand out in the grass
			_light.light_energy = 0.5 + 0.3 * sin(_t * 2.5)
		return
	drop_velocity.y -= 14.0 * delta
	var from := global_position
	var to := from + drop_velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to + Vector3.DOWN * 0.12, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = (hit.position as Vector3) + Vector3.UP * 0.08
		_resting = true
		return
	global_position = to
	if global_position.y < -30.0:
		queue_free()


## Called when the player walks over it and takes some ammo.
func touched() -> void:
	last_touch = current_wave


## Hands the weapon to the player. Rack slots empty until the next restock.
func take() -> Dictionary:
	var st := state
	if rack:
		state = {}
		remove_from_group("weapon_pickup")
		_model.visible = false
		_light.visible = false
	else:
		queue_free()
	return st


func restock() -> void:
	if not rack:
		return
	state = Weapons.new_state(rack_id)
	if not is_in_group("weapon_pickup"):
		add_to_group("weapon_pickup")
	_build()
	_model.visible = true
	_light.visible = true


## Every wave: expire forgotten ground weapons, restock the rack.
static func on_wave_started(tree: SceneTree, wave: int) -> void:
	current_wave = wave
	var restock := wave > 1 and (wave - 1) % RESTOCK_EVERY == 0
	if restock:
		for p in tree.get_nodes_in_group("weapon_rack"):
			p.restock()
	for p in tree.get_nodes_in_group("weapon_pickup"):
		if not p.rack and wave - int(p.last_touch) >= EXPIRE_WAVES:
			p.expire()


func expire() -> void:
	remove_from_group("weapon_pickup")
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.6)
	tw.tween_callback(queue_free)


## Too many on the ground: remove the oldest untouched ones.
func _trim() -> void:
	var ground: Array = get_tree().get_nodes_in_group("weapon_pickup").filter(func(p): return not p.rack and p != self)
	if ground.size() < MAX_GROUND:
		return
	ground.sort_custom(func(a, b): return a.last_touch < b.last_touch)
	for i in ground.size() - MAX_GROUND + 1:
		ground[i].expire()
