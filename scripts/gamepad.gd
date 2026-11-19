extends Node
## Controller support shared by the player, HUD and menus:
## - tracks whether the last input came from a gamepad (switches prompts,
##   hides the menu cursor, enables aim assist)
## - rumble, respecting the setting
## - button labels for prompts (Xbox layout names)
## - stick dead zone + response curve
## Lives under main.gd with PROCESS_MODE_ALWAYS so it works in menus.

signal device_changed(using_pad: bool)
## The controller in use was unplugged / switched off.
signal lost

## True when the most recent input was from a controller.
static var active := false
static var rumble_enabled := true

## Prompt names for the default bindings (Xbox layout).
const PAD_LABELS := {
	"move": "Left stick", "look": "Right stick", "fire": "RT", "aim": "LT",
	"jump": "A", "sprint": "LS click", "crouch": "B", "reload": "X", "interact": "Hold X",
	"switch_weapon": "Y / LB", "grenade": "RB", "melee": "RS click",
	"flashlight": "D-pad up", "pause": "Menu", "accept": "A", "back": "B",
	"tabs": "LB / RB",
}
const KEY_LABELS := {
	"move": "WASD", "look": "Mouse", "fire": "Left click", "aim": "Right click",
	"jump": "Space", "sprint": "Shift", "crouch": "C", "reload": "R", "interact": "E",
	"switch_weapon": "Q", "grenade": "G", "melee": "F", "flashlight": "T",
	"pause": "Esc", "accept": "Enter", "back": "Esc", "tabs": "click",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection)


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or \
		(event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.35)
	var kbm := event is InputEventKey or event is InputEventMouseButton or \
		(event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0)
	if pad and not active:
		_set_active(true)
	elif kbm and active:
		_set_active(false)


func _set_active(v: bool) -> void:
	active = v
	device_changed.emit(v)


func _on_joy_connection(device: int, connected: bool) -> void:
	print("Controller %s: %s" % ["connected" if connected else "disconnected", Input.get_joy_name(device)])
	if not connected and Input.get_connected_joypads().is_empty() and active:
		lost.emit()
		_set_active(false)


static func label(action: String) -> String:
	return PAD_LABELS.get(action, action) if active else KEY_LABELS.get(action, action)


## weak = high-frequency motor, strong = low-frequency motor (0..1).
static func rumble(weak: float, strong: float, duration: float) -> void:
	if not rumble_enabled or not active:
		return
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


## Radial dead zone and response curve for a stick. Returns a vector whose
## length runs 0..1 from the dead-zone edge to full tilt, curved so small
## tilts give fine control.
static func shape_stick(raw: Vector2, deadzone: float, exponent := 1.8) -> Vector2:
	var m := raw.length()
	if m <= deadzone:
		return Vector2.ZERO
	var n := clampf((m - deadzone) / maxf(1.0 - deadzone, 0.01), 0.0, 1.0)
	return raw / m * pow(n, exponent)
