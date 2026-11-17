extends Node3D
## Builds the "Verdant Hold" jungle outpost arena procedurally and bakes
## a navigation mesh for the enemies.

const BarrelScript = preload("res://scripts/barrel.gd")
const PickupScript = preload("res://scripts/pickup.gd")
const Shaders = preload("res://scripts/shaders.gd")

const HALF := 60.0
const GRID_HALF := 120
const GRASS_MAX_DENSITY := 2.0
const GRASS_BASE_COUNT := 20000

var nav_region: NavigationRegion3D
var deco: Node3D
var spawn_points: Array = []
var player_spawn := Vector3(0, 0.5, 10)
var rng := RandomNumberGenerator.new()
var occupied: Array = []
var mats := {}
var tree_spots: Array = []
var grass_mm: MultiMesh
var grass_total := 0

# terrain
var flat_zones: Array = []
var creek_pts: Array = []
var heights := PackedFloat32Array()
var path_mask := PackedFloat32Array()
var wet_mask := PackedFloat32Array()
var hnoise := FastNoiseLite.new()
var hnoise2 := FastNoiseLite.new()

# shared unit meshes
var m_box := BoxMesh.new()
var m_sph: SphereMesh
var m_rock: SphereMesh
var m_trunk: CylinderMesh
var m_cyl: CylinderMesh
var canopies: Array = []
var leaf_mats: Array = []
var frond_mat: ShaderMaterial
var fern_mat: ShaderMaterial


func build() -> void:
	rng.seed = 7741
	m_sph = SphereMesh.new()
	m_sph.radius = 1.0
	m_sph.height = 2.0
	m_sph.radial_segments = 14
	m_sph.rings = 7
	m_rock = SphereMesh.new()
	m_rock.radius = 1.0
	m_rock.height = 2.0
	m_rock.radial_segments = 7
	m_rock.rings = 4
	m_trunk = CylinderMesh.new()
	m_trunk.top_radius = 0.55
	m_trunk.bottom_radius = 1.0
	m_trunk.height = 1.0
	m_trunk.radial_segments = 10
	m_cyl = CylinderMesh.new()
	m_cyl.top_radius = 1.0
	m_cyl.bottom_radius = 1.0
	m_cyl.height = 1.0
	m_cyl.radial_segments = 12
	for i in 3:
		canopies.append(Shaders.canopy_mesh(100 + i, 14))
	_make_materials()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	add_child(nav_region)
	deco = Node3D.new()
	deco.name = "Deco"
	add_child(deco)
	_define_zones()
	_terrain()
	_bounds()
	_spawn_trails()
	_bunker()
	_towers()
	_ruins()
	_crash_site()
	_courtyard_cover()
	_barrels()
	_creek()
	_interior_trees()
	_rocks()
	_border_jungle()
	_grass()
	_ferns()
	_bake_nav()


# ---------------------------------------------------------------- helpers

func _std(key: String, color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	mats[key] = m
	return m


func _make_materials() -> void:
	mats["concrete"] = Shaders.structure_material(Color(0.42, 0.42, 0.38), Color(0.53, 0.53, 0.48), 0.5, 0.12, 0.88, 0.0, 0.05, 3.0)
	mats["stone"] = Shaders.structure_material(Color(0.3, 0.32, 0.26), Color(0.45, 0.45, 0.39), 0.85, 0.25, 0.95, 0.0, 0.06, 6.0)
	mats["wood"] = Shaders.structure_material(Color(0.24, 0.15, 0.08), Color(0.42, 0.3, 0.17), 0.3, 0.7, 0.9, 0.0, 0.12, 6.0)
	mats["metal"] = Shaders.structure_material(Color(0.24, 0.27, 0.24), Color(0.38, 0.41, 0.37), 0.2, 0.4, 0.5, 0.6, 0.1, 2.0)
	mats["metal_dark"] = Shaders.structure_material(Color(0.1, 0.11, 0.1), Color(0.2, 0.21, 0.19), 0.2, 0.4, 0.55, 0.6, 0.1, 2.0)
	mats["olive"] = Shaders.structure_material(Color(0.2, 0.23, 0.13), Color(0.32, 0.35, 0.2), 0.3, 0.5, 0.7, 0.3, 0.08, 2.5)
	mats["sandbag"] = Shaders.structure_material(Color(0.36, 0.31, 0.2), Color(0.52, 0.46, 0.32), 0.4, 1.4, 1.0, 0.0, 0.1, 9.0)
	mats["crate"] = Shaders.structure_material(Color(0.27, 0.31, 0.17), Color(0.34, 0.38, 0.21), 0.15, 0.5, 0.85, 0.0, 0.08, 4.0)
	mats["rock"] = Shaders.structure_material(Color(0.24, 0.25, 0.22), Color(0.45, 0.45, 0.4), 0.9, 0.45, 1.0, 0.0, 0.07, 8.0)
	mats["bark"] = Shaders.bark_material(Color(0.16, 0.12, 0.08), Color(0.34, 0.26, 0.18))
	mats["bark2"] = Shaders.bark_material(Color(0.3, 0.26, 0.19), Color(0.46, 0.41, 0.32))
	_std("leaf_dark", Color(0.05, 0.13, 0.04), 0.9)
	_std("moss", Color(0.16, 0.28, 0.08), 1.0)
	_std("scorch", Color(0.04, 0.04, 0.035), 1.0)
	var vine := _std("vine", Color(0.1, 0.22, 0.05), 0.9)
	vine.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glyph := StandardMaterial3D.new()
	glyph.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glyph.albedo_color = Color(0.3, 2.2, 1.6)
	mats["glyph"] = glyph
	var lamp := StandardMaterial3D.new()
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.albedo_color = Color(3.0, 2.2, 1.2)
	mats["lamp"] = lamp
	mats["water"] = Shaders.water_material()
	mats["grass"] = Shaders.grass_material()
	var leaf_cols := [[Color(0.1, 0.27, 0.06), Color(0.3, 0.5, 0.12)], [Color(0.13, 0.3, 0.05), Color(0.38, 0.52, 0.12)],
		[Color(0.06, 0.2, 0.07), Color(0.2, 0.4, 0.14)]]
	var tints := [Color(1, 1, 1), Color(1.05, 1.0, 0.85), Color(0.85, 0.95, 0.9)]
	for i in 3:
		var tex := Shaders.leaf_cluster_texture(31 + i, leaf_cols[i][0], leaf_cols[i][1])
		leaf_mats.append(Shaders.foliage_material(tex, tints[i], 1.0, 0.55))
	frond_mat = Shaders.foliage_material(Shaders.frond_texture(Color(0.12, 0.3, 0.07), Color(0.32, 0.5, 0.14)), Color(1, 1, 1), 1.6, 0.6)
	fern_mat = Shaders.foliage_material(Shaders.frond_texture(Color(0.08, 0.24, 0.06), Color(0.24, 0.42, 0.1)), Color(1, 1, 1), 0.7, 0.5)


func _occupy(center: Vector2, half: Vector2) -> void:
	occupied.append(Rect2(center - half, half * 2.0))


func _is_free(p: Vector2, margin := 0.0) -> bool:
	for r in occupied:
		if (r as Rect2).grow(margin).has_point(p):
			return false
	return true


func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, collide := true, parent: Node = null) -> Node3D:
	if parent == null:
		parent = nav_region if collide else deco
	var root: Node3D
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		root = body
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = m_box
	mi.scale = size
	mi.material_override = mat
	root.add_child(mi)
	root.position = pos
	root.rotation = rot
	parent.add_child(root)
	return root


func _cyl(radius: float, h: float, pos: Vector3, mat: Material, collide := true, rot := Vector3.ZERO) -> Node3D:
	var root: Node3D
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = h
		cs.shape = sh
		body.add_child(cs)
		root = body
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = m_cyl
	mi.scale = Vector3(radius, h, radius)
	mi.material_override = mat
	root.add_child(mi)
	root.position = pos
	root.rotation = rot
	(nav_region if collide else deco).add_child(root)
	return root


func _deco_mesh(mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3, rot := Vector3.ZERO, parent: Node = null, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else deco).add_child(mi)
	return mi


## A ramp from `bottom` rising `rise` metres over `run` metres along `dir`.
func _ramp(bottom: Vector3, dir: Vector3, run: float, rise: float, width: float, mat: Material) -> void:
	var length := sqrt(run * run + rise * rise)
	var angle := atan2(rise, run)
	var yaw := atan2(-dir.x, -dir.z)
	var thick := 0.4
	var mid := bottom + dir * run * 0.5 + Vector3.UP * (rise * 0.5 - thick * 0.5 / cos(angle))
	var b := _box(Vector3(width, thick, length), mid, mat)
	b.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, angle)


func _light(pos: Vector3, color: Color, energy: float, rng_m: float, can_shadow := false) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.4
	l.position = pos
	l.add_to_group("lamp")
	l.set_meta("base_energy", energy)
	l.set_meta("can_shadow", can_shadow)
	deco.add_child(l)
	_deco_mesh(m_sph, mats.lamp, pos + Vector3.UP * 0.1, Vector3.ONE * 0.12, Vector3.ZERO, null, false)


# ---------------------------------------------------------------- terrain

func _define_zones() -> void:
	flat_zones = [
		[Vector2(0, -2), 24.0], [Vector2(-27, 22), 11.0], [Vector2(27, -22), 11.0],
		[Vector2(-31, -29), 14.0], [Vector2(29, 27), 14.0],
	]
	var pts := [Vector3(55, 0, -12), Vector3(55, 0, 28), Vector3(-55, 0, 12), Vector3(-55, 0, -36),
		Vector3(8, 0, -55), Vector3(-34, 0, 55), Vector3(36, 0, 56), Vector3(42, 0, -52)]
	for p in pts:
		spawn_points.append(p)
		flat_zones.append([Vector2(p.x, p.z), 6.0])
	creek_pts = [Vector2(-75, 49), Vector2(-40, 43), Vector2(-20, 47), Vector2(0, 44), Vector2(18, 48), Vector2(40, 45), Vector2(75, 50)]
	hnoise.seed = 99
	hnoise.frequency = 0.03
	hnoise.fractal_octaves = 3
	hnoise2.seed = 7
	hnoise2.frequency = 0.12


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _creek_dist(p: Vector2) -> float:
	var d := 1e9
	for i in creek_pts.size() - 1:
		d = minf(d, _seg_dist(p, creek_pts[i], creek_pts[i + 1]))
	return d


func _raw_height(x: float, z: float) -> Array:
	var p := Vector2(x, z)
	var h := (hnoise.get_noise_2d(x, z) * 0.5 + 0.5) * 1.9 + hnoise2.get_noise_2d(x, z) * 0.18
	var mask := 1.0
	for fz in flat_zones:
		var d: float = p.distance_to(fz[0])
		mask = minf(mask, smoothstep(fz[1], fz[1] + 10.0, d))
	h *= mask
	var edge := maxf(absf(x), absf(z))
	if edge > HALF + 2.0:
		h += pow((edge - HALF - 2.0) / 18.0, 1.5) * 5.0
	var dc := _creek_dist(p)
	var bed := 1.0 - smoothstep(1.5, 4.5, dc)
	h = lerpf(h, -0.9, bed)
	var wet := 1.0 - smoothstep(2.5, 5.5, dc)
	# trodden trails from each jungle trail to the outpost, plus the courtyard clearing
	var path := 0.0
	if edge < HALF + 4.0:
		for sp in spawn_points:
			var d2 := _seg_dist(p, Vector2(sp.x, sp.z), Vector2(0, 6))
			path = maxf(path, (1.0 - smoothstep(1.0, 2.8, d2)) * 0.9)
		path = maxf(path, (1.0 - smoothstep(10.0, 19.0, p.distance_to(Vector2(0, 4)))) * 0.7)
		path = maxf(path, (1.0 - smoothstep(6.0, 11.0, p.distance_to(Vector2(-31, -29)))) * 0.6)
		path = maxf(path, (1.0 - smoothstep(7.0, 12.0, p.distance_to(Vector2(29, 27)))) * 0.75)
		path *= 0.75 + 0.5 * (hnoise2.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5)
	return [h, clampf(path, 0.0, 1.0), wet]


func height_at(x: float, z: float) -> float:
	var n := GRID_HALF * 2 + 1
	var fx := clampf(x + GRID_HALF, 0.0, n - 1.001)
	var fz := clampf(z + GRID_HALF, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := heights[iz * n + ix]
	var h10 := heights[iz * n + ix + 1]
	var h01 := heights[(iz + 1) * n + ix]
	var h11 := heights[(iz + 1) * n + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _mask_at(arr: PackedFloat32Array, x: float, z: float) -> float:
	var n := GRID_HALF * 2 + 1
	var ix := clampi(int(round(x + GRID_HALF)), 0, n - 1)
	var iz := clampi(int(round(z + GRID_HALF)), 0, n - 1)
	return arr[iz * n + ix]


func _terrain() -> void:
	var n := GRID_HALF * 2 + 1
	heights.resize(n * n)
	path_mask.resize(n * n)
	wet_mask.resize(n * n)
	for iz in n:
		for ix in n:
			var r := _raw_height(ix - GRID_HALF, iz - GRID_HALF)
			var i := iz * n + ix
			heights[i] = r[0]
			path_mask[i] = r[1]
			wet_mask[i] = r[2]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			verts[i] = Vector3(ix - GRID_HALF, heights[i], iz - GRID_HALF)
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, n - 1)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, n - 1) * n + ix]
			norms[i] = Vector3(hl - hr, 2.0, hd - hu).normalized()
			cols[i] = Color(path_mask[i], wet_mask[i], 0.0)
	idx.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[k] = a
			idx[k + 1] = b
			idx[k + 2] = c
			idx[k + 3] = b
			idx[k + 4] = d
			idx[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Shaders.terrain_material()
	deco.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = heights
	cs.shape = hm
	body.add_child(cs)
	nav_region.add_child(body)


func _bounds() -> void:
	for s in [-1.0, 1.0]:
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(2, 40, HALF * 2 + 4)
		cs.shape = sh
		wall.add_child(cs)
		wall.position = Vector3(s * (HALF + 1.0), 20, 0)
		nav_region.add_child(wall)
		var wall2 := StaticBody3D.new()
		var cs2 := CollisionShape3D.new()
		var sh2 := BoxShape3D.new()
		sh2.size = Vector3(HALF * 2 + 4, 40, 2)
		cs2.shape = sh2
		wall2.add_child(cs2)
		wall2.position = Vector3(0, 20, s * (HALF + 1.0))
		nav_region.add_child(wall2)


func _spawn_trails() -> void:
	for p in spawn_points:
		_occupy(Vector2(p.x, p.z), Vector2(5, 5))
		var inward: Vector3 = (-p).normalized()
		var side := Vector3(-inward.z, 0, inward.x)
		for s in [-1.0, 1.0]:
			var post_pos: Vector3 = p + side * 3.2 * s + inward * 2.0
			_box(Vector3(0.6, 2.6, 0.6), post_pos + Vector3.UP * 1.3, mats.stone)
			_deco_mesh(m_box, mats.glyph, post_pos + Vector3.UP * 2.0 + inward * 0.31, Vector3(0.25, 0.3, 0.02),
				Vector3(0, atan2(-inward.x, -inward.z), 0), null, false)


# ---------------------------------------------------------------- outpost

func _bunker() -> void:
	var c: Material = mats.concrete
	var h := 3.6
	var t := 0.6
	var cz := -2.0
	_occupy(Vector2(0, -7), Vector2(13, 13))
	_box(Vector3(16.6, h, t), Vector3(0, h / 2, cz - 6), c)
	for s in [-1.0, 1.0]:
		_box(Vector3(6.5, h, t), Vector3(4.75 * s, h / 2, cz + 6), c)
		_box(Vector3(t, h, 4.5), Vector3(8 * s, h / 2, cz - 3.75), c)
		_box(Vector3(t, h, 4.5), Vector3(8 * s, h / 2, cz + 3.75), c)
		_box(Vector3(t, 0.9, 3.0), Vector3(8 * s, h - 0.45, cz), c)
	_box(Vector3(3.0, 0.9, t), Vector3(0, h - 0.45, cz + 6), c)
	# floor slab and roof
	_box(Vector3(16.0, 0.12, 12.0), Vector3(0, 0.06, cz), mats.concrete, Vector3.ZERO, false)
	_box(Vector3(16.6, 0.4, 12.6), Vector3(0, h + 0.2, cz), c)
	var top := h + 0.4
	_box(Vector3(16.6, 0.9, 0.4), Vector3(0, top + 0.45, cz + 6.1), c)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.4, 0.9, 12.6), Vector3(8.1 * s, top + 0.45, cz), c)
	_box(Vector3(11.0, 0.9, 0.4), Vector3(-2.8, top + 0.45, cz - 6.1), c)
	_box(Vector3(1.6, 0.9, 0.4), Vector3(7.5, top + 0.45, cz - 6.1), c)
	_ramp(Vector3(5.0, 0, cz - 6.3 - 10.0), Vector3(0, 0, 1), 10.0, top, 3.0, mats.metal)
	_occupy(Vector2(5, cz - 11.5), Vector2(2.5, 6))
	_box(Vector3(1.3, 1.3, 1.3), Vector3(-6.2, 0.65, cz - 4.2), mats.crate)
	_box(Vector3(1.3, 1.3, 1.3), Vector3(-6.2, 1.95, cz - 4.2), mats.crate, Vector3(0, 0.3, 0))
	_box(Vector3(1.3, 1.3, 1.3), Vector3(-4.8, 0.65, cz - 4.4), mats.crate)
	_box(Vector3(2.5, 1.1, 1.0), Vector3(5.5, 0.55, cz - 4.8), mats.metal_dark)
	_box(Vector3(1.0, 1.1, 2.5), Vector3(-3.0, 0.55, cz + 2.5), mats.olive)
	var cache := PickupScript.new()
	cache.kind = "supply"
	cache.persistent = true
	nav_region.add_child(cache)
	cache.position = Vector3(0, 0.0, cz - 3.5)
	_light(Vector3(0, h - 0.3, cz), Color(1.0, 0.85, 0.6), 1.6, 11.0, true)
	_light(Vector3(0, h - 0.2, cz + 6.6), Color(1.0, 0.7, 0.4), 1.2, 9.0)
	for s in [-1.0, 1.0]:
		_light(Vector3(8.6 * s, h - 0.2, cz), Color(1.0, 0.7, 0.4), 1.0, 8.0)
	_cyl(0.08, 6.0, Vector3(-6.5, top + 3.0, cz - 4.5), mats.metal, false)
	_deco_mesh(m_sph, Shaders.enemy_skin(Color(0.3, 0.05, 0.05), Color(1.0, 0.1, 0.05), 3.0), Vector3(-6.5, top + 6.1, cz - 4.5), Vector3.ONE * 0.12, Vector3.ZERO, null, false)
	_deco_mesh(m_cyl, mats.metal, Vector3(5.5, top + 1.0, cz + 3.5), Vector3(1.0, 0.1, 1.0), Vector3(0.6, 0.4, 0))
	_box(Vector3(1.2, 0.8, 1.2), Vector3(-3.5, top + 0.4, cz + 2.0), mats.metal_dark)


func _tower(base: Vector3, ramp_dir: Vector3) -> void:
	var ph := 5.0
	var s := 2.6
	_occupy(Vector2(base.x, base.z), Vector2(4, 4))
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_cyl(0.22, 8.4, base + Vector3(cx * (s - 0.3), 4.2, cz * (s - 0.3)), mats.wood)
	_box(Vector3(s * 2, 0.35, s * 2), base + Vector3(0, ph, 0), mats.wood)
	var top := ph + 0.175
	var ramp_side := Vector3(signf(ramp_dir.x) if absf(ramp_dir.x) > 0.5 else 0.0, 0, signf(ramp_dir.z) if absf(ramp_dir.z) > 0.5 else 0.0)
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		if d == -ramp_side:
			continue
		var size := Vector3(0.2, 1.0, s * 2) if d.x != 0.0 else Vector3(s * 2, 1.0, 0.2)
		_box(size, base + d * (s - 0.1) + Vector3.UP * (top + 0.5), mats.wood)
	_box(Vector3(s * 2 + 0.8, 0.25, s * 2 + 0.8), base + Vector3(0, 8.5, 0), mats.metal_dark)
	var run := 11.0
	var start: Vector3 = base - ramp_side * (s + run)
	_ramp(Vector3(start.x, 0, start.z), ramp_side, run, top, 2.4, mats.wood)
	var mid: Vector3 = base - ramp_side * (s + run * 0.5)
	_occupy(Vector2(mid.x, mid.z), Vector2(2.5 + absf(ramp_side.x) * run * 0.5, 2.5 + absf(ramp_side.z) * run * 0.5))
	# floodlight (only lit at dusk/night)
	var sl := SpotLight3D.new()
	sl.light_color = Color(1.0, 0.92, 0.75)
	sl.light_energy = 3.0
	sl.set_meta("base_energy", 3.0)
	sl.spot_range = 45.0
	sl.spot_angle = 32.0
	sl.spot_attenuation = 0.8
	sl.light_volumetric_fog_energy = 2.0
	sl.position = base + Vector3(0, 8.2, 0)
	sl.add_to_group("flood")
	deco.add_child(sl)
	sl.look_at(Vector3(0, 0, 0), Vector3.UP)
	_deco_mesh(m_sph, mats.lamp, sl.position, Vector3.ONE * 0.18, Vector3.ZERO, null, false)
	_light(base + Vector3(0, top + 1.8, 0), Color(1.0, 0.75, 0.45), 0.8, 6.0)
	_sandbag_arc(base, 5.0, 0.0, TAU * 0.35, 6)


func _towers() -> void:
	_tower(Vector3(-27, 0, 16), Vector3(0, 0, -1))
	_tower(Vector3(27, 0, -16), Vector3(0, 0, 1))


func _sandbag_arc(center: Vector3, radius: float, a0: float, a1: float, count: int) -> void:
	for i in count:
		var a := lerpf(a0, a1, (float(i) + 0.5) / count)
		var p := center + Vector3(sin(a), 0, cos(a)) * radius
		_box(Vector3(1.5, 1.05, 0.7), p + Vector3.UP * 0.52, mats.sandbag, Vector3(0, a, 0))
	var mid := (a0 + a1) * 0.5
	var mp := center + Vector3(sin(mid), 0, cos(mid)) * radius
	_occupy(Vector2(mp.x, mp.z), Vector2(radius * 0.7, radius * 0.7))


func _courtyard_cover() -> void:
	_occupy(Vector2(0, 12), Vector2(14, 9))
	_sandbag_arc(Vector3(0, 0, 13), 6.5, -0.9, 0.9, 7)
	_sandbag_arc(Vector3(-14, 0, 2), 4.0, -PI * 0.75, -PI * 0.25, 4)
	_sandbag_arc(Vector3(14, 0, 2), 4.0, PI * 0.25, PI * 0.75, 4)
	for p in [Vector3(-9, 0, 10), Vector3(9.5, 0, 9), Vector3(-12, 0, -14), Vector3(13, 0, -12), Vector3(3, 0, 20), Vector3(-5, 0, 19)]:
		_box(Vector3(1.3, 1.3, 1.3), p + Vector3.UP * 0.65, mats.crate, Vector3(0, rng.randf() * 1.5, 0))
		if rng.randf() < 0.6:
			_box(Vector3(1.3, 1.3, 1.3), p + Vector3(0.7, 0.65, 0.9), mats.crate, Vector3(0, rng.randf() * 1.5, 0))
		if rng.randf() < 0.4:
			_box(Vector3(1.2, 1.2, 1.2), p + Vector3(0.2, 1.9, 0.2), mats.crate, Vector3(0, rng.randf() * 1.5, 0))
		_occupy(Vector2(p.x, p.z), Vector2(2.5, 2.5))
	for i in 2:
		var tp := Vector3(16, 1.3, -4 + i * 3.2)
		_cyl(1.2, 4.0, tp, mats.olive, true, Vector3(PI / 2, 0, 0))
	_box(Vector3(2.0, 1.6, 1.4), Vector3(18.5, 0.8, 4.5), mats.metal_dark)
	_light(Vector3(18.5, 1.9, 4.5), Color(0.6, 1.0, 0.6), 0.6, 4.0)
	_occupy(Vector2(17, 0), Vector2(3.5, 6))
	for i in 3:
		_box(Vector3(3.0, 1.1, 0.6), Vector3(-17, 0.55, -6 + i * 5), mats.concrete, Vector3(0, PI / 2 + rng.randf_range(-0.2, 0.2), 0))
	_occupy(Vector2(-17, -1), Vector2(2, 8))
	# lamp posts around the courtyard
	for lp in [Vector3(-11, 0, 15), Vector3(11, 0, 15), Vector3(-12, 0, -11), Vector3(12, 0, -10)]:
		_cyl(0.08, 4.0, lp + Vector3.UP * 2.0, mats.metal_dark, true)
		_light(lp + Vector3(0, 4.05, 0), Color(1.0, 0.78, 0.5), 1.4, 12.0, true)


func _barrels() -> void:
	for p in [Vector3(-10, 0, 6), Vector3(10.5, 0, 6.5), Vector3(14.5, 0, -8), Vector3(-24, 0, 12),
			Vector3(24, 0, -12), Vector3(26, 0, 22), Vector3(-26, 0, -20), Vector3(2, 0, -22)]:
		var b := BarrelScript.new()
		nav_region.add_child(b)
		b.position = Vector3(p.x, height_at(p.x, p.z), p.z)


func _ruins() -> void:
	var base := Vector3(-31, 0, -29)
	_occupy(Vector2(base.x, base.z), Vector2(10, 10))
	var ph := 1.2
	_box(Vector3(12, ph, 12), base + Vector3(0, ph / 2, 0), mats.stone)
	_ramp(base + Vector3(6 + 4.5, 0, 2), Vector3(-1, 0, 0), 4.5, ph, 3.5, mats.stone)
	_ramp(base + Vector3(-2, 0, 6 + 4.5), Vector3(0, 0, -1), 4.5, ph, 3.5, mats.stone)
	_occupy(Vector2(base.x + 8, base.z + 2), Vector2(3, 2.5))
	_occupy(Vector2(base.x - 2, base.z + 8), Vector2(2.5, 3))
	var pillar_pos := [Vector3(-4.5, 0, -4.5), Vector3(0, 0, -4.8), Vector3(4.5, 0, -4.5), Vector3(-4.8, 0, 0),
		Vector3(-4.5, 0, 4.5), Vector3(4.5, 0, 4.5)]
	for i in pillar_pos.size():
		var h := rng.randf_range(2.0, 6.0)
		var pp: Vector3 = base + pillar_pos[i]
		_box(Vector3(1.1, h, 1.1), pp + Vector3.UP * (ph + h / 2), mats.stone)
		_box(Vector3(1.4, 0.3, 1.4), pp + Vector3.UP * (ph + h + 0.15), mats.stone)
		if rng.randf() < 0.6:
			_deco_mesh(m_box, mats.glyph, pp + Vector3(0, ph + 1.4, 0.56), Vector3(0.4, 0.5, 0.02), Vector3.ZERO, null, false)
		_deco_mesh(canopies[i % 3], fern_mat, pp + Vector3.UP * (ph + h + 0.35), Vector3(0.8, 0.35, 0.8))
		for v in rng.randi_range(1, 3):
			var vl := rng.randf_range(1.0, h * 0.8)
			_deco_mesh(m_cyl, mats.vine, pp + Vector3(rng.randf_range(-0.56, 0.56), ph + h - vl * 0.5, 0.57), Vector3(0.03, vl, 0.03), Vector3.ZERO, null, false)
	_box(Vector3(2.4, 1.0, 1.4), base + Vector3(0.5, ph + 0.5, 0.5), mats.stone)
	_deco_mesh(m_box, mats.glyph, base + Vector3(0.5, ph + 1.01, 0.5), Vector3(1.6, 0.02, 0.6), Vector3.ZERO, null, false)
	_light(base + Vector3(0.5, ph + 1.6, 0.5), Color(0.3, 1.0, 0.8), 1.2, 9.0)
	_box(Vector3(1.1, 1.1, 6.0), base + Vector3(9.5, 0.55, -6), mats.stone, Vector3(0, 0.5, 0.1))
	_box(Vector3(5.0, 2.6, 0.9), base + Vector3(-9, 1.3, 4), mats.stone, Vector3(0, 0.3, 0))
	_box(Vector3(3.5, 1.6, 0.9), base + Vector3(3, 0.8, -10), mats.stone, Vector3(0, -0.2, 0))
	_occupy(Vector2(base.x + 9.5, base.z - 6), Vector2(3, 3.5))
	_occupy(Vector2(base.x - 9, base.z + 4), Vector2(3, 2))
	_occupy(Vector2(base.x + 3, base.z - 10), Vector2(2.5, 1.5))


func _crash_site() -> void:
	var base := Vector3(29, 0, 27)
	_occupy(Vector2(base.x, base.z), Vector2(11, 9))
	var yaw := 0.55
	var b := Basis(Vector3.UP, yaw)
	_deco_mesh(m_cyl, mats.scorch, base + Vector3(0, 0.02, 0), Vector3(10, 0.02, 8), Vector3.ZERO, null, false)
	_box(Vector3(5.5, 4.0, 13.0), base + b * Vector3(0, 1.4, 0), mats.metal, Vector3(0, yaw, 0.12))
	_box(Vector3(4.5, 3.0, 4.5), base + b * Vector3(0.4, 0.9, -8.5), mats.metal_dark, Vector3(0.25, yaw, 0.2))
	_box(Vector3(9.0, 0.35, 3.2), base + b * Vector3(5.5, 1.6, 1.5), mats.metal_dark, Vector3(0, yaw, 0.35))
	_cyl(1.1, 3.6, base + b * Vector3(-4.0, 1.0, 3.0), mats.olive, true, Vector3(PI / 2, yaw, 0))
	for i in 8:
		var dp := base + Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-8, 8))
		var ds := Vector3(rng.randf_range(0.6, 2.0), rng.randf_range(0.3, 1.2), rng.randf_range(0.6, 2.4))
		if absf(dp.x - base.x) < 4 and absf(dp.z - base.z) < 7:
			continue
		_box(ds, dp + Vector3.UP * ds.y * 0.4, mats.metal_dark, Vector3(rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * 0.4))
	var fire_pos := base + b * Vector3(0.4, 2.8, -8.0)
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 5.0
	p.preprocess = 5.0
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 1.6
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.12, 0.12, 0.11, 0.35)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	p.mesh = sm
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0.4, 0.3, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.5
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = fire_pos
	deco.add_child(p)
	# flickering embers
	var em := CPUParticles3D.new()
	em.amount = 24
	em.lifetime = 1.4
	var emm := SphereMesh.new()
	emm.radius = 0.04
	emm.height = 0.08
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.albedo_color = Color(4.0, 1.6, 0.4)
	emm.material = emat
	em.mesh = emm
	em.direction = Vector3.UP
	em.spread = 25.0
	em.initial_velocity_min = 1.0
	em.initial_velocity_max = 3.0
	em.gravity = Vector3(0, 0.5, 0)
	em.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 0.6
	em.position = fire_pos
	deco.add_child(em)
	_light(fire_pos + Vector3.UP * 0.3, Color(1.0, 0.5, 0.15), 2.5, 10.0)


func _creek() -> void:
	for i in creek_pts.size() - 1:
		var a: Vector2 = creek_pts[i]
		var bpt: Vector2 = creek_pts[i + 1]
		var mid := (a + bpt) * 0.5
		var len := a.distance_to(bpt)
		var ang := atan2(bpt.y - a.y, bpt.x - a.x)
		_deco_mesh(m_box, mats.water, Vector3(mid.x, -0.35, mid.y), Vector3(len + 3.0, 0.02, 8.0), Vector3(0, -ang, 0), null, false)
		for k in 6:
			var t := rng.randf()
			var sp := a.lerp(bpt, t) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-2.5, 2.5))
			_deco_mesh(m_rock, mats.rock, Vector3(sp.x, height_at(sp.x, sp.y) + 0.05, sp.y), Vector3(rng.randf_range(0.3, 0.8), 0.3, rng.randf_range(0.3, 0.8)), Vector3(0, rng.randf() * TAU, 0))
	# reeds along the banks
	var reeds: Array = []
	var cols: Array = []
	for i in 900:
		var seg := rng.randi() % (creek_pts.size() - 1)
		var a: Vector2 = creek_pts[seg]
		var b: Vector2 = creek_pts[seg + 1]
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var dirv := (b - a).normalized()
		var p := a.lerp(b, rng.randf()) + Vector2(-dirv.y, dirv.x) * side * rng.randf_range(2.8, 4.5)
		var s := rng.randf_range(1.4, 2.6)
		reeds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.6, s, s * 0.6)), Vector3(p.x, height_at(p.x, p.y) + 0.27 * s, p.y)))
		cols.append(Color(0.25, 0.35, 0.12).lerp(Color(0.45, 0.45, 0.2), rng.randf()))
	var blade := PrismMesh.new()
	blade.size = Vector3(0.14, 0.55, 0.01)
	_multimesh(blade, mats.grass, reeds, cols, false, 2)


func _rocks() -> void:
	for i in 26:
		var p := Vector2(rng.randf_range(-56, 56), rng.randf_range(-56, 56))
		if not _is_free(p, 2.0) or p.length() < 22.0 or _mask_at(path_mask, p.x, p.y) > 0.5:
			continue
		var s := rng.randf_range(0.8, 2.4)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = s * 0.85
		cs.shape = sh
		body.add_child(cs)
		body.position = Vector3(p.x, height_at(p.x, p.y) + s * 0.2, p.y)
		nav_region.add_child(body)
		_deco_mesh(m_rock, mats.rock, Vector3.ZERO, Vector3(s * 1.2, s * 0.8, s), Vector3(rng.randf() * 0.3, rng.randf() * TAU, 0), body)
		_occupy(p, Vector2(s, s))


# ---------------------------------------------------------------- vegetation

func _canopy(parent: Node3D, pos: Vector3, cr: float) -> void:
	var v := rng.randi() % 3
	_deco_mesh(canopies[v], leaf_mats[v], pos, Vector3(cr, cr * 0.7, cr), Vector3(0, rng.randf() * TAU, 0), parent)
	_deco_mesh(m_sph, mats.leaf_dark, pos + Vector3.DOWN * cr * 0.05, Vector3(cr * 0.62, cr * 0.38, cr * 0.62), Vector3.ZERO, parent, false)


func _tree(pos: Vector3, scale_f: float) -> void:
	var palm := rng.randf() < 0.3
	var h := rng.randf_range(10.0, 17.0) * scale_f
	var r := rng.randf_range(0.45, 0.75) * scale_f
	if palm:
		h = rng.randf_range(8.0, 12.0)
		r = 0.3
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h + 2.0
	cs.shape = sh
	cs.position.y = h * 0.5 - 1.0
	body.add_child(cs)
	body.position = pos
	nav_region.add_child(body)
	var bark: Material = mats.bark2 if palm else mats.bark
	var lean := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
	_deco_mesh(m_trunk, bark, Vector3(0, h * 0.5 - 0.5, 0), Vector3(r, h + 1.0, r), lean, body)
	if palm:
		var crown := Vector3(-lean.z * h, h, lean.x * h)
		var fm := Shaders.frond_mesh(0.55)
		for i in 10:
			var a := TAU * i / 10.0 + rng.randf() * 0.3
			var pitch := rng.randf_range(-0.15, 0.35)
			_deco_mesh(fm, frond_mat, crown, Vector3(1.3, 4.0, 4.6) * rng.randf_range(0.85, 1.1), Vector3(pitch, a, 0), body)
		_deco_mesh(m_sph, mats.bark2, crown, Vector3.ONE * 0.45, Vector3.ZERO, body)
	else:
		for i in 4:
			var a := TAU * i / 4.0 + rng.randf() * 0.5
			_deco_mesh(m_box, bark, Vector3(sin(a) * r * 1.2, 0.6 * scale_f, cos(a) * r * 1.2), Vector3(0.18 * scale_f, 1.5 * scale_f, 1.6 * scale_f), Vector3(0, a, 0), body)
		var n := rng.randi_range(3, 5)
		for i in n:
			var cr := rng.randf_range(2.6, 4.4) * scale_f
			var off := Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(-1.2, 1.5), rng.randf_range(-2.5, 2.5)) * scale_f
			_canopy(body, Vector3(0, h, 0) + off, cr)
		for i in rng.randi_range(2, 5):
			var vl := rng.randf_range(3.0, 7.0)
			var vp := Vector3(rng.randf_range(-2.5, 2.5), h - 1.5 - vl * 0.5, rng.randf_range(-2.5, 2.5))
			_deco_mesh(m_cyl, mats.vine, vp, Vector3(0.04, vl, 0.04), Vector3.ZERO, body, false)
	tree_spots.append(Vector2(pos.x, pos.z))


func _interior_trees() -> void:
	var placed := 0
	var tries := 0
	while placed < 55 and tries < 2000:
		tries += 1
		var p := Vector2(rng.randf_range(-57, 57), rng.randf_range(-57, 57))
		if absf(p.x) < 20 and p.y > -24 and p.y < 24:
			continue
		if not _is_free(p, 2.5) or _mask_at(path_mask, p.x, p.y) > 0.45 or _creek_dist(p) < 4.5:
			continue
		var ok := true
		for t in tree_spots:
			if (t as Vector2).distance_to(p) < 6.0:
				ok = false
				break
		if not ok:
			continue
		_tree(Vector3(p.x, height_at(p.x, p.y), p.y), rng.randf_range(0.8, 1.25))
		_occupy(p, Vector2(1.2, 1.2))
		placed += 1


func _multimesh(mesh: Mesh, mat: Material, transforms: Array, colors: Array = [], shadows := true, layer := 1) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if not colors.is_empty():
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.layers = layer
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(mmi)
	return mm


func _border_jungle() -> void:
	var trunks: Array = []
	var cans: Array[Array] = [[], [], []]
	var cores: Array = []
	var bushes: Array[Array] = [[], [], []]
	for i in 560:
		var p := Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
		var edge := maxf(absf(p.x), absf(p.y))
		if edge < HALF + 1.5:
			continue
		var gy := height_at(p.x, p.y)
		var h := rng.randf_range(12, 24)
		var r := rng.randf_range(0.5, 1.0)
		trunks.append(Transform3D(Basis().scaled(Vector3(r, h, r)), Vector3(p.x, gy + h * 0.5, p.y)))
		for k in rng.randi_range(2, 4):
			var cr := rng.randf_range(3.5, 6.0)
			var off := Vector3(rng.randf_range(-3, 3), rng.randf_range(-2, 2), rng.randf_range(-3, 3))
			var pos := Vector3(p.x, gy + h, p.y) + off
			cans[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(cr, cr * 0.7, cr)), pos))
			cores.append(Transform3D(Basis().scaled(Vector3(cr * 0.6, cr * 0.36, cr * 0.6)), pos))
	var steps := 170
	for side in 4:
		for i in steps:
			var t := lerpf(-HALF - 3, HALF + 3, float(i) / steps)
			var d := HALF + rng.randf_range(0.5, 3.5)
			var p := Vector2(t, d)
			match side:
				1: p = Vector2(t, -d)
				2: p = Vector2(d, t)
				3: p = Vector2(-d, t)
			var near_spawn := false
			for sp in spawn_points:
				if Vector2(sp.x, sp.z).distance_to(p) < 6.0:
					near_spawn = true
			var br := rng.randf_range(1.8, 3.4) * (0.5 if near_spawn else 1.0)
			bushes[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(br, br * rng.randf_range(0.6, 1.0), br)), Vector3(p.x, height_at(p.x, p.y) + br * 0.35, p.y)))
	_multimesh(m_trunk, mats.bark, trunks)
	_multimesh(m_sph, mats.leaf_dark, cores, [], false)
	for k in 3:
		_multimesh(canopies[k], leaf_mats[k], cans[k])
		_multimesh(canopies[(k + 1) % 3], leaf_mats[k], bushes[k], [], true)


func _grass() -> void:
	var blade := PrismMesh.new()
	blade.size = Vector3(0.14, 0.55, 0.01)
	var tufts: Array = []
	var cols: Array = []
	var target := int(GRASS_BASE_COUNT * GRASS_MAX_DENSITY)
	var tries := 0
	while tufts.size() < target and tries < target * 3:
		tries += 1
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		if not _is_free(p, 0.3):
			continue
		var path := _mask_at(path_mask, p.x, p.y)
		if path > 0.55 and rng.randf() < 0.9:
			continue
		if _mask_at(wet_mask, p.x, p.y) > 0.75:
			continue
		var s := rng.randf_range(0.6, 1.6) * (1.0 - path * 0.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		tufts.append(Transform3D(basis.scaled(Vector3(s, s, s)), Vector3(p.x, height_at(p.x, p.y) + 0.25 * s, p.y)))
		cols.append(Color(0.14, 0.3, 0.07).lerp(Color(0.4, 0.43, 0.14), rng.randf()))
	grass_total = tufts.size()
	grass_mm = _multimesh(blade, mats.grass, tufts, cols, false, 2)


func set_grass_density(d: float) -> void:
	if grass_mm != null:
		grass_mm.visible_instance_count = clampi(int(grass_total * d / GRASS_MAX_DENSITY), 0, grass_total)


func _ferns() -> void:
	var ferns: Array = []
	var spots: Array = tree_spots.duplicate()
	for i in 140:
		spots.append(Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF)))
	for t in spots:
		for k in 3:
			var p: Vector2 = t + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
			if not _is_free(p, 0.5) or _mask_at(path_mask, p.x, p.y) > 0.4 or absf(p.x) > HALF or absf(p.y) > HALF:
				continue
			var s := rng.randf_range(0.7, 1.5)
			ferns.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, height_at(p.x, p.y) + 0.05, p.y)))
	_multimesh(Shaders.fern_mesh(), fern_mat, ferns, [], true, 2)


# ---------------------------------------------------------------- navigation

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 42.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.filter_baking_aabb = AABB(Vector3(-HALF, -2, -HALF), Vector3(HALF * 2, 14, HALF * 2))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
