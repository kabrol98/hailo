extends Node3D
## Sky, sun/moon, environment post-processing, time of day and ambient particles.
## All visual quality settings that live on the Environment / lights are applied here.

const Shaders = preload("res://scripts/shaders.gd")

var env: Environment
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var pollen: CPUParticles3D
var fireflies: CPUParticles3D
var tod := "day"
var vol_fog_on := false

const TOD := {
	"day": {
		"sun_rot": Vector3(-50, -35, 0), "sun_color": Color(1.0, 0.94, 0.82), "sun_energy": 1.3,
		"top": Color(0.22, 0.42, 0.68), "horizon": Color(0.72, 0.77, 0.68), "ground": Color(0.12, 0.15, 0.08),
		"cloud": Color(1.0, 1.0, 0.98), "cloud_cover": 0.42, "sun_size": 0.035, "disk": 14.0, "stars": 0.0, "moon": 0.0,
		"ambient": Color(0.6, 0.7, 0.55), "ambient_energy": 0.85, "sky_contrib": 0.75,
		"fog": Color(0.58, 0.66, 0.52), "fog_density": 0.0045, "fog_height_density": 0.08,
		"vfog_density": 0.012, "vfog_albedo": Color(0.85, 0.92, 0.8), "vfog_emission": Color(0, 0, 0),
		"exposure": 1.0, "lamps": 0.35, "flood": 0.0, "pollen": true, "fireflies": false, "glow_threshold": 1.0,
	},
	"dusk": {
		"sun_rot": Vector3(-9, -62, 0), "sun_color": Color(1.0, 0.58, 0.32), "sun_energy": 1.15,
		"top": Color(0.18, 0.22, 0.42), "horizon": Color(0.98, 0.56, 0.32), "ground": Color(0.1, 0.08, 0.06),
		"cloud": Color(1.0, 0.62, 0.45), "cloud_cover": 0.5, "sun_size": 0.045, "disk": 10.0, "stars": 0.15, "moon": 0.0,
		"ambient": Color(0.55, 0.45, 0.5), "ambient_energy": 0.6, "sky_contrib": 0.7,
		"fog": Color(0.72, 0.5, 0.38), "fog_density": 0.0065, "fog_height_density": 0.12,
		"vfog_density": 0.018, "vfog_albedo": Color(1.0, 0.8, 0.65), "vfog_emission": Color(0, 0, 0),
		"exposure": 1.1, "lamps": 1.0, "flood": 0.7, "pollen": true, "fireflies": true, "glow_threshold": 0.9,
	},
	"night": {
		"sun_rot": Vector3(-42, 28, 0), "sun_color": Color(0.55, 0.66, 1.0), "sun_energy": 0.28,
		"top": Color(0.008, 0.012, 0.035), "horizon": Color(0.04, 0.06, 0.09), "ground": Color(0.01, 0.012, 0.01),
		"cloud": Color(0.06, 0.07, 0.1), "cloud_cover": 0.35, "sun_size": 0.03, "disk": 6.0, "stars": 1.0, "moon": 1.0,
		"ambient": Color(0.18, 0.24, 0.38), "ambient_energy": 0.35, "sky_contrib": 0.3,
		"fog": Color(0.04, 0.06, 0.09), "fog_density": 0.012, "fog_height_density": 0.2,
		"vfog_density": 0.025, "vfog_albedo": Color(0.6, 0.7, 0.9), "vfog_emission": Color(0.002, 0.003, 0.006),
		"exposure": 1.35, "lamps": 2.4, "flood": 3.2, "pollen": false, "fireflies": true, "glow_threshold": 0.75,
	},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = Shaders.sky_material()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.3
	env.fog_height = 1.5
	env.glow_intensity = 0.75
	env.glow_bloom = 0.04
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(2, 1.0)
	env.set_glow_level(4, 0.6)
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_light_affect = 0.15
	env.ssil_radius = 6.0
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_energy = 1.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.5
	add_child(sun)
	pollen = _motes(Color(1.6, 1.5, 1.1, 0.5), 160, 0.03, 9.0, Vector3(0.15, 0.05, 0.1))
	fireflies = _motes(Color(2.8, 3.2, 0.9, 1.0), 120, 0.045, 6.0, Vector3(0.0, 0.0, 0.0))


func _motes(col: Color, amount: int, size: float, life: float, drift: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 3, 22)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.gravity = drift
	p.damping_min = 0.0
	p.damping_max = 0.2
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.25, col)
	g.add_point(0.45, Color(col.r, col.g, col.b, col.a * 0.2))
	g.add_point(0.65, col)
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0, 2.5, 0)
	add_child(p)
	return p


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var p := cam.global_position
		pollen.global_position = Vector3(p.x, p.y + 0.5, p.z)
		fireflies.global_position = Vector3(p.x, maxf(p.y - 0.5, 1.2), p.z)


func apply_time_of_day(name: String) -> void:
	if not TOD.has(name):
		name = "day"
	tod = name
	var t: Dictionary = TOD[name]
	var r: Vector3 = t.sun_rot
	sun.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
	sun.light_color = t.sun_color
	sun.light_energy = t.sun_energy
	sky_mat.set_shader_parameter("top_color", t.top)
	sky_mat.set_shader_parameter("horizon_color", t.horizon)
	sky_mat.set_shader_parameter("ground_color", t.ground)
	sky_mat.set_shader_parameter("cloud_color", t.cloud)
	sky_mat.set_shader_parameter("cloud_cover", t.cloud_cover)
	sky_mat.set_shader_parameter("sun_size", t.sun_size)
	sky_mat.set_shader_parameter("disk_energy", t.disk)
	sky_mat.set_shader_parameter("stars", t.stars)
	sky_mat.set_shader_parameter("moon", t.moon)
	env.ambient_light_color = t.ambient
	env.ambient_light_energy = t.ambient_energy
	env.ambient_light_sky_contribution = t.sky_contrib
	env.fog_light_color = t.fog
	env.fog_height_density = t.fog_height_density
	env.volumetric_fog_density = t.vfog_density
	env.volumetric_fog_albedo = t.vfog_albedo
	env.volumetric_fog_emission = t.vfog_emission
	env.tonemap_exposure = t.exposure
	env.glow_hdr_threshold = t.glow_threshold
	_apply_fog_density()
	pollen.emitting = t.pollen
	pollen.visible = t.pollen
	fireflies.emitting = t.fireflies
	fireflies.visible = t.fireflies
	fireflies.amount = 120 if name == "night" else 40
	for l in get_tree().get_nodes_in_group("lamp"):
		var base: float = l.get_meta("base_energy", 1.0)
		(l as Light3D).light_energy = base * float(t.lamps)
	for l in get_tree().get_nodes_in_group("flood"):
		var base: float = l.get_meta("base_energy", 1.0)
		(l as Light3D).light_energy = base * float(t.flood)
		(l as Light3D).visible = float(t.flood) > 0.01
	for m in get_tree().get_nodes_in_group("lamp_bulb"):
		(m as Node3D).visible = name != "day"


func _apply_fog_density() -> void:
	var t: Dictionary = TOD[tod]
	# depth fog is lighter when volumetric fog provides the haze
	env.fog_density = float(t.fog_density) * (0.45 if vol_fog_on else 1.0)


func apply_quality(s) -> void:
	env.ssao_enabled = s.get_v("ssao")
	env.ssil_enabled = s.get_v("ssil")
	env.sdfgi_enabled = s.get_v("sdfgi")
	env.glow_enabled = s.get_v("glow")
	vol_fog_on = s.get_v("volumetric_fog")
	env.volumetric_fog_enabled = vol_fog_on
	var vq: int = s.get_v("vol_fog_quality")
	if vq >= 1:
		RenderingServer.environment_set_volumetric_fog_volume_size(128, 96)
	else:
		RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	_apply_fog_density()
	var q: int = s.get_v("shadows")
	sun.shadow_enabled = q > 0
	var atlas := [1024, 2048, 4096, 4096, 8192]
	RenderingServer.directional_shadow_atlas_set_size(atlas[q], true)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q <= 1 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [40.0, 55.0, 80.0, 110.0, 150.0][q]
	var soft := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft[q])
	RenderingServer.positional_soft_shadow_filter_set_quality(soft[q])
	for l in get_tree().get_nodes_in_group("lamp"):
		(l as Light3D).shadow_enabled = q >= 3 and l.get_meta("can_shadow", false)
	for l in get_tree().get_nodes_in_group("flood"):
		(l as Light3D).shadow_enabled = q >= 2
