extends Node
## Player-configurable options, quality presets and persistence.
## Add a new option by adding a default to DEFAULTS and a row to OPTIONS;
## the settings screen builds itself from OPTIONS.

signal changed(key: String)

const PATH := "user://settings.cfg"

## Set before reloading the scene to skip the home screen (used by "Redeploy").
static var quick_start := false

const DEFAULTS := {
	"preset": "high",
	"time_of_day": "day",
	# graphics
	"shadows": 3,
	"ssao": true,
	"ssil": false,
	"sdfgi": false,
	"volumetric_fog": true,
	"vol_fog_quality": 0,
	"glow": true,
	"grass_density": 1.0,
	"wind": true,
	"decals": true,
	"render_scale": 0.85,
	"upscaler": 1,
	"aa": 2,
	# display
	"fullscreen": false,
	"vsync": true,
	"max_fps": 0,
	"show_fps": false,
	# gameplay
	"fov": 78.0,
	"sensitivity": 0.0025,
	"invert_y": false,
	"flashlight_auto": true,
	# audio
	"master_volume": 0.8,
}

## Keys that presets control. Changing one of these switches the preset to "custom".
const PRESET_KEYS := ["shadows", "ssao", "ssil", "sdfgi", "volumetric_fog", "vol_fog_quality",
	"glow", "grass_density", "wind", "decals", "render_scale", "upscaler", "aa"]

const PRESETS := {
	"low": {"shadows": 1, "ssao": false, "ssil": false, "sdfgi": false, "volumetric_fog": false,
		"vol_fog_quality": 0, "glow": true, "grass_density": 0.35, "wind": true, "decals": true,
		"render_scale": 0.67, "upscaler": 1, "aa": 1},
	"medium": {"shadows": 2, "ssao": true, "ssil": false, "sdfgi": false, "volumetric_fog": false,
		"vol_fog_quality": 0, "glow": true, "grass_density": 0.7, "wind": true, "decals": true,
		"render_scale": 0.8, "upscaler": 1, "aa": 2},
	"high": {"shadows": 3, "ssao": true, "ssil": false, "sdfgi": false, "volumetric_fog": true,
		"vol_fog_quality": 0, "glow": true, "grass_density": 1.0, "wind": true, "decals": true,
		"render_scale": 0.85, "upscaler": 1, "aa": 2},
	"ultra": {"shadows": 4, "ssao": true, "ssil": true, "sdfgi": true, "volumetric_fog": true,
		"vol_fog_quality": 1, "glow": true, "grass_density": 1.6, "wind": true, "decals": true,
		"render_scale": 1.0, "upscaler": 0, "aa": 3},
}

## UI description of every option. type: choice | toggle | slider
const OPTIONS := [
	{"tab": "Graphics", "key": "preset", "label": "Quality preset", "type": "choice",
		"choices": [["Low", "low"], ["Medium", "medium"], ["High", "high"], ["Ultra", "ultra"], ["Custom", "custom"]],
		"hint": "Sets everything below. Changing any graphics option switches to Custom."},
	{"tab": "Graphics", "key": "shadows", "label": "Shadows", "type": "choice",
		"choices": [["Off", 0], ["Low", 1], ["Medium", 2], ["High", 3], ["Ultra", 4]],
		"hint": "Sun/moon shadow resolution, softness and distance. High+ also gives lamps shadows."},
	{"tab": "Graphics", "key": "ssao", "label": "Ambient occlusion (SSAO)", "type": "toggle",
		"hint": "Contact shadows in corners and under foliage."},
	{"tab": "Graphics", "key": "ssil", "label": "Indirect light (SSIL)", "type": "toggle",
		"hint": "Screen-space light bounce. Moderate cost."},
	{"tab": "Graphics", "key": "sdfgi", "label": "Global illumination (SDFGI)", "type": "toggle",
		"hint": "Real-time bounced light from the sun, moon and lamps. Expensive: Ultra / M4 Pro."},
	{"tab": "Graphics", "key": "volumetric_fog", "label": "Volumetric fog", "type": "toggle",
		"hint": "Light shafts through the canopy and glowing halos around lamps at night."},
	{"tab": "Graphics", "key": "vol_fog_quality", "label": "Volumetric fog quality", "type": "choice",
		"choices": [["Standard", 0], ["High", 1]]},
	{"tab": "Graphics", "key": "glow", "label": "Glow / bloom", "type": "toggle"},
	{"tab": "Graphics", "key": "grass_density", "label": "Grass density", "type": "slider",
		"min": 0.0, "max": 2.0, "step": 0.05, "fmt": "%d%%", "fmt_mul": 100.0},
	{"tab": "Graphics", "key": "wind", "label": "Wind animation", "type": "toggle",
		"hint": "Grass and leaves sway."},
	{"tab": "Graphics", "key": "decals", "label": "Bullet holes & scorch marks", "type": "toggle"},
	{"tab": "Graphics", "key": "render_scale", "label": "Render scale", "type": "slider",
		"min": 0.5, "max": 1.0, "step": 0.01, "fmt": "%d%%", "fmt_mul": 100.0,
		"hint": "Renders 3D below screen resolution and upscales. The biggest performance lever on Retina screens."},
	{"tab": "Graphics", "key": "upscaler", "label": "Upscaler", "type": "choice",
		"choices": [["Bilinear", 0], ["AMD FSR 1", 1], ["AMD FSR 2", 2]],
		"hint": "FSR 2 looks best below 100% scale and replaces anti-aliasing."},
	{"tab": "Graphics", "key": "aa", "label": "Anti-aliasing", "type": "choice",
		"choices": [["Off", 0], ["FXAA", 1], ["MSAA 2x", 2], ["MSAA 4x", 3], ["TAA", 4]]},
	{"tab": "World", "key": "time_of_day", "label": "Time of day", "type": "choice",
		"choices": [["Day", "day"], ["Dusk", "dusk"], ["Night", "night"]],
		"hint": "Night: the outpost floodlights come on, the Thorn glow, and you carry a flashlight (T)."},
	{"tab": "Gameplay", "key": "fov", "label": "Field of view", "type": "slider",
		"min": 65.0, "max": 100.0, "step": 1.0, "fmt": "%d°", "fmt_mul": 1.0},
	{"tab": "Gameplay", "key": "sensitivity", "label": "Mouse sensitivity", "type": "slider",
		"min": 0.0005, "max": 0.008, "step": 0.0001, "fmt": "%.2f", "fmt_mul": 400.0},
	{"tab": "Gameplay", "key": "invert_y", "label": "Invert mouse Y", "type": "toggle"},
	{"tab": "Gameplay", "key": "flashlight_auto", "label": "Flashlight on automatically at night", "type": "toggle"},
	{"tab": "Display & Audio", "key": "fullscreen", "label": "Fullscreen", "type": "toggle"},
	{"tab": "Display & Audio", "key": "vsync", "label": "V-Sync", "type": "toggle"},
	{"tab": "Display & Audio", "key": "max_fps", "label": "Frame rate cap", "type": "choice",
		"choices": [["Unlimited", 0], ["30", 30], ["60", 60], ["120", 120]]},
	{"tab": "Display & Audio", "key": "show_fps", "label": "Show FPS counter", "type": "toggle"},
	{"tab": "Display & Audio", "key": "master_volume", "label": "Master volume", "type": "slider",
		"min": 0.0, "max": 1.0, "step": 0.01, "fmt": "%d%%", "fmt_mul": 100.0},
]

var values: Dictionary = {}
var first_run := false


func _init() -> void:
	values = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in DEFAULTS.keys():
			values[k] = cf.get_value("settings", k, DEFAULTS[k])
	else:
		first_run = true
		var rec := recommended_preset()
		values["preset"] = rec
		for k in PRESETS[rec].keys():
			values[k] = PRESETS[rec][k]


func get_v(key: String):
	return values.get(key, DEFAULTS.get(key))


func set_v(key: String, v, save_now := true) -> void:
	if values.get(key) == v:
		return
	if key == "preset":
		apply_preset(str(v))
		return
	values[key] = v
	if key in PRESET_KEYS and values.preset != "custom":
		values.preset = "custom"
		changed.emit("preset")
	if save_now:
		save()
	changed.emit(key)


func apply_preset(name: String) -> void:
	values.preset = name
	if PRESETS.has(name):
		for k in PRESETS[name].keys():
			values[k] = PRESETS[name][k]
	save()
	changed.emit("*")


func save() -> void:
	var cf := ConfigFile.new()
	for k in values.keys():
		cf.set_value("settings", k, values[k])
	cf.save(PATH)


static func chip_name() -> String:
	var n := OS.get_processor_name()
	return n if n != "" else "unknown CPU"


static func recommended_preset() -> String:
	var cpu := OS.get_processor_name().to_lower()
	if not cpu.contains("apple"):
		return "medium"
	for strong in ["m4 pro", "m4 max", "m3 max", "m2 max", "m2 ultra", "m1 ultra", "m3 ultra", "m5"]:
		if cpu.contains(strong):
			return "ultra"
	for good in ["m1 pro", "m1 max", "m2 pro", "m3 pro", "m4"]:
		if cpu.contains(good):
			return "high"
	return "medium"
