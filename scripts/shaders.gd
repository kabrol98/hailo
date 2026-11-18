extends RefCounted
## Shaders, procedural textures and procedural meshes shared by the world.

static var _cache: Dictionary = {}
static var _wind_mats: Array = []
static var wind_strength := 1.0


static func set_wind(v: float) -> void:
	wind_strength = v
	for m in _wind_mats:
		if is_instance_valid(m):
			(m as ShaderMaterial).set_shader_parameter("wind_strength", v)


static func _shader(key: String, code: String) -> Shader:
	if _cache.has(key):
		return _cache[key]
	var s := Shader.new()
	s.code = code
	_cache[key] = s
	return s


# ============================================================== shader code

const SKY := """
shader_type sky;
uniform vec3 top_color : source_color = vec3(0.25, 0.45, 0.7);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.78, 0.7);
uniform vec3 ground_color : source_color = vec3(0.1, 0.12, 0.08);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float cloud_cover = 0.45;
uniform float sun_size = 0.035;
uniform float sun_glow = 1.0;
uniform float disk_energy = 12.0;
uniform float stars = 0.0;
uniform float moon = 0.0;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		float halo = pow(max(sd, 0.0), 6.0) * 0.25 + pow(max(sd, 0.0), 80.0) * 0.6;
		col += LIGHT0_COLOR * halo * sun_glow;
		if (!AT_CUBEMAP_PASS) {
			float disk = smoothstep(cos(sun_size), cos(sun_size * 0.8), sd);
			vec3 disk_col = LIGHT0_COLOR * disk_energy;
			if (moon > 0.5) {
				// cratered moon
				vec2 mp = (d - LIGHT0_DIRECTION * sd).xz * 60.0;
				disk_col *= 0.75 + 0.25 * vnoise(mp * 1.5);
			}
			col += disk_col * disk;
		}
	}
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12);
		float n = fbm(uv * 1.2 + vec2(TIME * 0.004, TIME * 0.002));
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, n);
		float shade = 0.75 + 0.25 * fbm(uv * 2.4 + 3.0);
		col = mix(col, cloud_color * shade, c * smoothstep(0.0, 0.18, h) * 0.85);
		if (stars > 0.0 && !AT_CUBEMAP_PASS) {
			vec3 p = d * 240.0;
			vec3 i = floor(p);
			vec3 f = fract(p);
			float r = hash3(i);
			vec3 o = vec3(hash3(i + 1.3), hash3(i + 7.1), hash3(i + 3.7));
			float s = step(0.986, r) * smoothstep(0.12, 0.0, length(f - o));
			float tw = 0.6 + 0.4 * sin(TIME * (2.0 + r * 5.0) + r * 40.0);
			col += vec3(0.9, 0.95, 1.0) * s * tw * stars * (1.0 - c) * 3.0;
		}
	}
	COLOR = col;
}
"""

const GRASS := """
shader_type spatial;
render_mode cull_disabled;
uniform float wind_strength = 1.0;
uniform vec3 tip_tint : source_color = vec3(1.25, 1.2, 0.85);
varying float hgt;
void vertex() {
	float h = clamp((VERTEX.y + 0.275) / 0.55, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.25) * 0.6 + sin(TIME * 3.3 + wp.x * 0.9 - wp.z * 0.4) * 0.25;
	vec3 disp = vec3(w, 0.0, w * 0.6) * wind_strength * h * h * 0.22;
	float s2 = max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += (disp * mat3(MODEL_MATRIX)) / s2;
	hgt = h;
}
void fragment() {
	ALBEDO = COLOR.rgb * mix(vec3(0.5), tip_tint, hgt);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.25, 0.35, 0.1) * hgt;
}
"""

const FOLIAGE := """
shader_type spatial;
render_mode cull_disabled;
uniform float wind_strength = 1.0;
uniform float sway = 1.0;
uniform float sway_height = 0.0;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float translucency = 0.6;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.3 + wp.x * 0.2 + wp.y * 0.3) * 0.5 + sin(TIME * 2.9 + wp.z * 0.5 + wp.x * 0.2) * 0.2;
	vec3 disp = vec3(w, w * 0.25, w * 0.7) * wind_strength * sway * 0.12;
	if (sway_height > 0.0) {
		disp *= clamp(VERTEX.y / sway_height, 0.0, 1.5);
	}
	float s2 = max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += (disp * mat3(MODEL_MATRIX)) / s2;
}
void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALBEDO = t.rgb * tint * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL; // keep the soft spherical normals on both sides
	}
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
	BACKLIGHT = t.rgb * tint * translucency;
}
"""

const TERRAIN := """
shader_type spatial;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : filter_linear, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.22;
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv = wpos.xz * tile;
	vec3 g = texture(grass_tex, uv).rgb;
	vec3 g2 = texture(grass_tex, uv * 0.27 + 0.5).rgb;
	g = mix(g, g2, 0.4);
	vec3 d = texture(dirt_tex, uv * 0.8).rgb;
	vec3 m = texture(mud_tex, uv * 1.3).rgb;
	float n = texture(mask_tex, wpos.xz * 0.011).r;
	float dirt = smoothstep(0.55, 0.72, n) * 0.8;
	dirt = max(dirt, COLOR.r);
	dirt = max(dirt, smoothstep(0.1, 0.25, 1.0 - wnorm.y));
	float mud = COLOR.g;
	vec3 col = mix(g, d, clamp(dirt, 0.0, 1.0));
	col = mix(col, m, mud);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.3, mud);
	SPECULAR = mix(0.3, 0.6, mud);
	NORMAL_MAP = texture(normal_tex, uv * 1.7).rgb;
	NORMAL_MAP_DEPTH = mix(1.2, 0.4, mud);
}
"""

const STRUCTURE := """
shader_type spatial;
uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 moss_color : source_color = vec3(0.13, 0.21, 0.07);
uniform float moss_amount = 0.5;
uniform float grime = 0.35;
uniform float tex_scale = 0.3;
uniform float rough = 0.85;
uniform float metal = 0.0;
varying vec3 wpos;
varying vec3 wn;
vec4 tri(sampler2D t, vec3 p, vec3 n) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= dot(b, vec3(1.0));
	return texture(t, p.zy) * b.x + texture(t, p.xz) * b.y + texture(t, p.xy) * b.z;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 p = wpos * tex_scale;
	vec3 col = tri(base_tex, p, wn).rgb * tint;
	float mn = tri(moss_noise, wpos * 0.17, wn).r;
	float up = smoothstep(0.35, 0.95, wn.y);
	float low = 1.0 - smoothstep(0.0, 1.4, wpos.y);
	float moss = (up * 0.9 + low * 0.75) * moss_amount + (mn - 0.5) * 0.9;
	moss = smoothstep(0.3, 0.75, moss);
	// rain streaks / grime darken toward the ground
	float streak = tri(moss_noise, vec3(wpos.x * 2.0, wpos.y * 0.15, wpos.z * 2.0), wn).r;
	col *= 1.0 - grime * (low * 0.6 + streak * 0.4);
	ALBEDO = mix(col, moss_color * (0.8 + mn * 0.4), moss);
	ROUGHNESS = mix(rough, 0.95, moss);
	METALLIC = metal * (1.0 - moss);
	NORMAL_MAP = tri(normal_tex, p, wn).rgb;
	NORMAL_MAP_DEPTH = 1.0;
}
"""

const WATER := """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
uniform vec3 deep : source_color = vec3(0.04, 0.12, 0.1);
uniform vec3 shallow : source_color = vec3(0.16, 0.3, 0.2);
uniform sampler2D n1 : hint_normal, filter_linear_mipmap, repeat_enable;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wp.xz;
	vec3 a = texture(n1, uv * 0.11 + TIME * vec2(0.035, 0.012)).rgb;
	vec3 b = texture(n1, uv * 0.19 - TIME * vec2(0.012, 0.03)).rgb;
	NORMAL_MAP = mix(a, b, 0.5);
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep, shallow, 0.35);
	ALPHA = mix(0.7, 0.96, fres);
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
}
"""

const ENEMY_SKIN := """
shader_type spatial;
uniform vec3 albedo : source_color = vec3(0.2);
uniform vec3 glow : source_color = vec3(1.0, 0.2, 0.8);
uniform float glow_amount = 1.0;
uniform float flash = 0.0;
uniform float pulse_speed = 2.2;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD * 0.85;
}
void fragment() {
	vec3 p = wp * 3.0;
	float v = abs(sin(p.x * 2.1 + 1.6 * sin(p.y * 1.7)) * cos(p.z * 2.3 + 1.4 * sin(p.y * 1.3 + p.x)));
	float vein = 1.0 - smoothstep(0.0, 0.09, v);
	float pulse = 0.55 + 0.45 * sin(TIME * pulse_speed - wp.y * 5.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float bands = 0.82 + 0.18 * sin(wp.y * 26.0 + sin(wp.x * 9.0));
	ALBEDO = albedo * bands;
	ROUGHNESS = 0.32;
	METALLIC = 0.25;
	SPECULAR = 0.6;
	EMISSION = glow * (vein * pulse * 1.6 + fres * 0.5) * glow_amount + vec3(flash * 2.5);
}
"""


# ============================================================== materials

static func sky_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("sky", SKY)
	return m


static func grass_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("grass", GRASS)
	m.set_shader_parameter("wind_strength", wind_strength)
	_wind_mats.append(m)
	return m


static func foliage_material(tex: Texture2D, tint: Color, sway := 1.0, translucency := 0.6, sway_height := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.set_shader_parameter("sway_height", sway_height)
	m.shader = _shader("foliage", FOLIAGE)
	m.set_shader_parameter("leaf_tex", tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("translucency", translucency)
	m.set_shader_parameter("wind_strength", wind_strength)
	_wind_mats.append(m)
	return m


static func terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("terrain", TERRAIN)
	m.set_shader_parameter("grass_tex", noise_tex(Color(0.12, 0.2, 0.06), Color(0.3, 0.36, 0.12), 0.05, 512, 3, true))
	m.set_shader_parameter("dirt_tex", noise_tex(Color(0.2, 0.15, 0.09), Color(0.38, 0.3, 0.19), 0.08, 256, 4, true))
	m.set_shader_parameter("mud_tex", noise_tex(Color(0.08, 0.07, 0.05), Color(0.2, 0.17, 0.11), 0.06, 256, 4, true))
	m.set_shader_parameter("mask_tex", noise_tex(Color.BLACK, Color.WHITE, 0.03, 256, 3, true))
	m.set_shader_parameter("normal_tex", normal_tex(0.09, 512, 6.0))
	return m


static func structure_material(c0: Color, c1: Color, moss := 0.5, scale_f := 0.3, rough := 0.85, metal := 0.0, freq := 0.06, bump := 4.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("structure", STRUCTURE)
	m.set_shader_parameter("base_tex", noise_tex(c0, c1, freq, 256, 4, true))
	m.set_shader_parameter("normal_tex", normal_tex(freq * 1.5, 256, bump))
	m.set_shader_parameter("moss_noise", noise_tex(Color.BLACK, Color.WHITE, 0.035, 256, 4, true))
	m.set_shader_parameter("moss_amount", moss)
	m.set_shader_parameter("tex_scale", scale_f)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	return m


static func water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("water", WATER)
	m.set_shader_parameter("n1", normal_tex(0.04, 256, 8.0))
	return m


static func enemy_skin(albedo: Color, glow: Color, glow_amount := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("enemy_skin", ENEMY_SKIN)
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("glow_amount", glow_amount)
	m.set_shader_parameter("pulse_speed", randf_range(1.8, 2.8))
	return m


# ============================================================== textures

static func noise_tex(c0: Color, c1: Color, freq := 0.05, sz := 256, octaves := 4, seamless := true) -> NoiseTexture2D:
	var key := "nt|%s|%s|%s|%s|%s" % [c0, c1, freq, sz, octaves]
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = hash(key) % 10000
	var t := NoiseTexture2D.new()
	t.width = sz
	t.height = sz
	t.seamless = seamless
	t.generate_mipmaps = true
	t.noise = n
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	t.color_ramp = g
	_cache[key] = t
	return t


static func normal_tex(freq := 0.08, sz := 256, bump := 5.0) -> NoiseTexture2D:
	var key := "nm|%s|%s|%s" % [freq, sz, bump]
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 5
	n.seed = hash(key) % 10000
	var t := NoiseTexture2D.new()
	t.width = sz
	t.height = sz
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = bump
	t.generate_mipmaps = true
	t.noise = n
	_cache[key] = t
	return t


## Bark: vertically elongated noise (wide texture squeezed into square UVs).
static func bark_material(c0: Color, c1: Color) -> StandardMaterial3D:
	var key := "bark|%s|%s" % [c0, c1]
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 64
	t.seamless = true
	t.noise = n
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	t.color_ramp = g
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 64
	nt.seamless = true
	nt.noise = n
	nt.as_normal_map = true
	nt.bump_strength = 10.0
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = 1.2
	m.roughness = 0.95
	m.uv1_scale = Vector3(2.0, 1.0, 1.0)
	_cache[key] = m
	return m


## A circular cluster of individually drawn leaves with alpha.
static func leaf_cluster_texture(seed_v: int, base: Color, light: Color) -> ImageTexture:
	var key := "leaf|%s" % seed_v
	if _cache.has(key):
		return _cache[key]
	var size := 160
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(base.r, base.g, base.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var half := size * 0.5
	for i in 85:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.42 * size
		var c := Vector2(half, half) + Vector2(cos(a), sin(a)) * r
		var ll := rng.randf_range(0.08, 0.14) * size
		var w := ll * rng.randf_range(0.32, 0.45)
		var ang := a + rng.randf_range(-0.9, 0.9)
		var dir := Vector2(cos(ang), sin(ang))
		var nrm := Vector2(-dir.y, dir.x)
		var col := base.lerp(light, rng.randf())
		col = col.darkened(0.25 * (1.0 - r / (0.42 * size)))  # inner leaves darker
		for y in range(maxi(0, int(c.y - ll)), mini(size, int(c.y + ll) + 1)):
			for x in range(maxi(0, int(c.x - ll)), mini(size, int(c.x + ll) + 1)):
				var p := Vector2(x, y) - c
				var u := p.dot(dir) / ll
				var v := p.dot(nrm) / w
				if absf(u) < 1.0 and absf(v) < 1.0 - u * u:
					var pc := col
					if absf(v) < 0.1:
						pc = pc.darkened(0.3)
					pc = pc.lightened((u + 1.0) * 0.06)
					img.set_pixel(x, y, Color(pc.r, pc.g, pc.b, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## A single fern / palm frond: stem with leaflets, tip at v=0.
static func frond_texture(base: Color, light: Color) -> ImageTexture:
	var key := "frond|%s" % base
	if _cache.has(key):
		return _cache[key]
	var wdt := 64
	var hgt := 256
	var img := Image.create(wdt, hgt, false, Image.FORMAT_RGBA8)
	img.fill(Color(base.r, base.g, base.b, 0.0))
	var cx := wdt / 2
	for y in hgt:
		for dx in [-1, 0, 1]:
			img.set_pixel(cx + dx, y, base.darkened(0.3))
	var y0 := 8
	while y0 < hgt - 4:
		var t := float(y0) / hgt
		var length := int(28.0 * sin(clampf(t * 1.15, 0.0, 1.0) * PI * 0.5 + 0.25) * (0.35 + 0.65 * t))
		for side in [-1, 1]:
			var col := base.lerp(light, randf())
			for k in length:
				var x: int = cx + side * (k + 2)
				var yy := y0 - int(k * 0.55)
				for th in range(-1, 2):
					var py := yy + th
					if x >= 0 and x < wdt and py >= 0 and py < hgt:
						img.set_pixel(x, py, Color(col.r, col.g, col.b, 1.0).lightened(float(k) / length * 0.12))
		y0 += 5
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func decal_texture(kind: String) -> ImageTexture:
	var key := "decal|" + kind
	if _cache.has(key):
		return _cache[key]
	var size := 64 if kind == "hole" else 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.08 if kind == "hole" else 0.05
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			var nv := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := 0.0
			var col := Color(0.03, 0.03, 0.025)
			if kind == "hole":
				a = 1.0 - smoothstep(0.18, 0.24, d)
				var ring := (1.0 - smoothstep(0.25, 0.9 + nv * 0.2, d)) * 0.55
				a = maxf(a, ring)
				col = Color(0.02, 0.02, 0.02) if d < 0.24 else Color(0.12, 0.11, 0.09)
			else:
				a = (1.0 - smoothstep(0.2, 1.0, d + (nv - 0.5) * 0.5)) * 0.85
				col = Color(0.03, 0.025, 0.02).lerp(Color(0.12, 0.08, 0.05), nv)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# ============================================================== meshes

## Cluster of crossed leaf cards with outward "spherical" normals.
static func canopy_mesh(seed_v: int, cards := 14) -> ArrayMesh:
	var key := "canopy|%s|%s" % [seed_v, cards]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in cards:
		var c := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1))
		if c.length() > 1.0:
			c = c.normalized() * rng.randf_range(0.3, 1.0)
		c.y *= 0.55
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.7, 0.7), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
		var s := rng.randf_range(0.9, 1.25)
		var right := b.x * s
		var up := b.z * s
		var ao := clampf(0.55 + 0.35 * (c.y + 0.4) + 0.2 * c.length(), 0.45, 1.0)
		var corners := [c - right - up, c + right - up, c + right + up, c - right + up]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			var v: Vector3 = corners[idx]
			st.set_color(Color(ao, ao, ao))
			st.set_uv(uvs[idx])
			st.set_normal((v * Vector3(1.0, 1.6, 1.0)).normalized())
			st.add_vertex(v)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## One drooping frond strip along -Z, length 1, width 1 (scale per use).
static func _frond_into(st: SurfaceTool, xf: Transform3D, droop: float, segs := 5) -> void:
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := Vector3(0, -droop * t0 * t0, -t0)
		var p1 := Vector3(0, -droop * t1 * t1, -t1)
		var hw0 := 0.5
		var hw1 := 0.5
		var quad := [p0 + Vector3(-hw0, 0, 0), p0 + Vector3(hw0, 0, 0), p1 + Vector3(hw1, 0, 0), p1 + Vector3(-hw1, 0, 0)]
		var uvq := [Vector2(0, 1.0 - t0), Vector2(1, 1.0 - t0), Vector2(1, 1.0 - t1), Vector2(0, 1.0 - t1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			var v: Vector3 = quad[idx]
			st.set_color(Color(1, 1, 1))
			st.set_uv(uvq[idx])
			st.set_normal((xf.basis * Vector3(0, 1, 0)).normalized())
			st.add_vertex(xf * v)


static func frond_mesh(droop := 0.6) -> ArrayMesh:
	var key := "frond_mesh|%s" % droop
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_frond_into(st, Transform3D.IDENTITY, droop)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## A fern clump: several fronds radiating from the centre, rising then drooping.
static func fern_mesh() -> ArrayMesh:
	if _cache.has("fern"):
		return _cache["fern"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 7
	for i in n:
		var a := TAU * i / n + 0.3 * sin(i * 3.7)
		var xf := Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.55) * Basis.from_scale(Vector3(0.35, 1.0, 1.0)), Vector3.ZERO)
		_frond_into(st, xf, 1.2)
	var mesh := st.commit()
	_cache["fern"] = mesh
	return mesh
