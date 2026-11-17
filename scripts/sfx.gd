extends RefCounted
## Procedurally generated sound effects (no audio files needed).

const RATE := 22050
static var _cache: Dictionary = {}

const ALL := ["rifle", "plasma", "enemy_bolt", "mortar", "lancer_charge", "lancer_fire",
	"explosion", "hit", "kill", "shield_hit", "shield_break", "shield_charge", "reload",
	"empty", "switch", "pickup", "wave", "throw", "bounce", "screech", "enemy_die",
	"melee", "overheat", "hurt", "beep", "roar"]


static func preload_all() -> void:
	for n in ALL:
		get_stream(n)


static func get_stream(sname: String) -> AudioStreamWAV:
	if _cache.has(sname):
		return _cache[sname]
	var samples := _generate(sname)
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	_cache[sname] = s
	return s


static func play_at(node: Node, sname: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(sname)
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.unit_size = 10.0
	p.max_distance = 150.0
	p.finished.connect(p.queue_free)
	node.get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.play()


static func play_ui(node: Node, sname: String, vol_db := 0.0, pitch := 1.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(sname)
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.finished.connect(p.queue_free)
	node.get_tree().current_scene.add_child(p)
	p.play()


static func _click(x: float, noise: float) -> float:
	if x < 0.0:
		return 0.0
	return noise * exp(-x * 300.0) * 0.6 + sin(TAU * 1800.0 * x) * exp(-x * 200.0) * 0.4


static func _generate(sname: String) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sname)
	var dur := 0.2
	match sname:
		"rifle": dur = 0.22
		"plasma": dur = 0.3
		"enemy_bolt": dur = 0.28
		"mortar": dur = 0.5
		"lancer_charge": dur = 1.35
		"lancer_fire": dur = 0.45
		"explosion": dur = 1.6
		"hit": dur = 0.06
		"kill": dur = 0.2
		"shield_hit": dur = 0.14
		"shield_break": dur = 0.5
		"shield_charge": dur = 0.9
		"reload": dur = 0.65
		"empty": dur = 0.06
		"switch": dur = 0.25
		"pickup": dur = 0.36
		"wave": dur = 1.4
		"throw": dur = 0.3
		"bounce": dur = 0.08
		"screech": dur = 0.45
		"enemy_die": dur = 0.6
		"melee": dur = 0.22
		"overheat": dur = 0.9
		"hurt": dur = 0.25
		"beep": dur = 0.1
		"roar": dur = 1.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	var phase2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var noise := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match sname:
			"rifle":
				lp += (noise - lp) * 0.35
				phase += TAU * lerpf(170.0, 55.0, minf(t * 12.0, 1.0)) / RATE
				v = lp * exp(-t * 26.0) * 0.9 + sin(phase) * exp(-t * 20.0) * 0.7 + noise * exp(-t * 120.0) * 0.5
			"plasma":
				phase += TAU * lerpf(1600.0, 260.0, sqrt(u)) / RATE
				v = (sin(phase) + 0.35 * signf(sin(phase * 0.5))) * exp(-t * 9.0) * 0.45 + noise * exp(-t * 40.0) * 0.15
			"enemy_bolt":
				phase += TAU * (700.0 - 400.0 * u + 60.0 * sin(t * 90.0)) / RATE
				v = (2.0 * absf(2.0 * fposmod(phase / TAU, 1.0) - 1.0) - 1.0) * exp(-t * 8.0) * 0.45
			"mortar":
				lp += (noise - lp) * 0.08
				phase += TAU * (120.0 - 60.0 * t) / RATE
				v = sin(phase) * exp(-t * 6.0) * 0.8 + lp * 0.8 * exp(-t * 5.0)
			"lancer_charge":
				phase += TAU * (220.0 + 1100.0 * u * u) / RATE
				v = sin(phase) * 0.3 * (0.6 + 0.4 * sin(t * 60.0)) * minf(t * 4.0, 1.0)
			"lancer_fire":
				phase += TAU * maxf(2400.0 - 4000.0 * t, 200.0) / RATE
				v = noise * exp(-t * 14.0) * 0.6 + sin(phase) * exp(-t * 10.0) * 0.4
			"explosion":
				lp += (noise - lp) * 0.05
				lp2 += (lp - lp2) * 0.1
				phase += TAU * (55.0 - 20.0 * t) / RATE
				v = (lp * 2.6 + lp2 * 3.0) * exp(-t * 2.6) + sin(phase) * exp(-t * 4.0) * 0.8 + noise * exp(-t * 30.0) * 0.4
			"hit":
				v = sin(TAU * 2600.0 * t) * exp(-t * 60.0) * 0.5
			"kill":
				var f := 1800.0 if t < 0.08 else 2700.0
				phase += TAU * f / RATE
				v = sin(phase) * 0.45 * exp(-fmod(t, 0.08) * 25.0)
			"shield_hit":
				var hp := noise - lp
				lp += (noise - lp) * 0.5
				v = hp * 0.4 * exp(-t * 20.0) + sin(TAU * 3200.0 * t) * 0.2 * exp(-t * 25.0)
			"shield_break":
				phase += TAU * maxf(2200.0 - 3000.0 * t, 150.0) / RATE
				var hp2 := noise - lp
				lp += (noise - lp) * 0.4
				v = sin(phase) * 0.35 * exp(-t * 5.0) + hp2 * 0.3 * exp(-t * 9.0)
			"shield_charge":
				phase += TAU * (300.0 + 700.0 * u) / RATE
				v = sin(phase) * 0.22 * sin(PI * u)
			"reload":
				v = _click(t - 0.02, noise) + _click(t - 0.5, noise)
			"empty":
				v = _click(t, noise) * 0.6
			"switch":
				v = _click(t, noise) * 0.7 + _click(t - 0.15, noise) * 0.7
			"pickup":
				var notes := [880.0, 1175.0, 1568.0]
				var idx := mini(int(t / 0.12), 2)
				phase += TAU * float(notes[idx]) / RATE
				v = sin(phase) * 0.3 * exp(-fmod(t, 0.12) * 15.0)
			"wave":
				var env := minf(t * 3.0, 1.0) * clampf((dur - t) * 3.0, 0.0, 1.0)
				phase = fposmod(phase + 110.0 / RATE, 1.0)
				phase2 = fposmod(phase2 + 164.8 / RATE, 1.0)
				var raw := ((phase * 2.0 - 1.0) + (phase2 * 2.0 - 1.0)) * 0.25 * env
				lp += (raw - lp) * 0.15
				v = lp * 1.6
			"throw":
				lp += (noise - lp) * 0.12
				v = lp * sin(PI * u) * 0.8
			"bounce":
				v = sin(TAU * 1400.0 * t) * exp(-t * 70.0) * 0.4 + noise * exp(-t * 200.0) * 0.2
			"screech":
				phase += TAU * (900.0 + 500.0 * sin(t * 40.0)) / RATE
				lp += (noise - lp) * 0.3
				v = (sin(phase) * 0.4 + lp * 0.5) * sin(PI * u) * 0.6
			"enemy_die":
				phase += TAU * maxf(400.0 - 600.0 * t, 60.0) / RATE
				var raw2 := signf(sin(phase)) * 0.3 + noise * 0.3
				lp += (raw2 - lp) * 0.12
				v = lp * exp(-t * 4.0) * 1.5
			"melee":
				lp += (noise - lp) * 0.2
				v = lp * exp(-t * 25.0) * 1.2 + sin(TAU * 80.0 * t) * exp(-t * 20.0) * 0.8
			"overheat":
				var hp3 := noise - lp
				lp += (noise - lp) * 0.3
				v = hp3 * 0.35 * exp(-t * 3.0)
			"hurt":
				phase += TAU * maxf(110.0 - 120.0 * t, 40.0) / RATE
				lp += (noise - lp) * 0.1
				v = sin(phase) * exp(-t * 12.0) * 0.8 + lp * exp(-t * 15.0)
			"beep":
				v = sin(TAU * 1000.0 * t) * 0.3 * (1.0 if t < 0.08 else 0.0)
			"roar":
				phase = fposmod(phase + (70.0 + 15.0 * sin(t * 25.0)) / RATE, 1.0)
				lp += (noise - lp) * 0.06
				var raw3 := (phase * 2.0 - 1.0) * 0.5 + lp * 1.5
				lp2 += (raw3 - lp2) * 0.2
				v = lp2 * sin(PI * u) * 0.9
		# short fade-out to avoid clicks
		var tail := float(n - i) / (RATE * 0.005)
		if tail < 1.0:
			v *= tail
		out[i] = v
	return out
