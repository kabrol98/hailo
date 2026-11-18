extends RefCounted
## Scripted camera paths for recording trailers / comparison footage:
##   godot -- --autotest --godmode --showcase=overview,trail,fps --write-movie out.avi
## Each clip is a list of [position, look_target] keys spread evenly over `dur`.

static func clip(name: String) -> Dictionary:
	match name:
		"overview":
			var keys := []
			for i in 6:
				var a := lerpf(0.55, 1.45, i / 5.0)
				keys.append([Vector3(sin(a) * 52.0, 27.0 - i * 1.2, cos(a) * 52.0), Vector3(0, 2, -2)])
			return {"dur": 8.0, "keys": keys}
		"trail":
			return {"dur": 8.0, "keys": [
				[Vector3(-56, 1.8, 13), Vector3(-40, 2.5, 11)],
				[Vector3(-47, 1.9, 12), Vector3(-30, 2.5, 9)],
				[Vector3(-37, 2.0, 10.5), Vector3(-15, 2.5, 7)],
				[Vector3(-27, 2.2, 9), Vector3(0, 3, 2)]]}
		"ruins":
			return {"dur": 7.0, "keys": [
				[Vector3(-46, 1.3, -14), Vector3(-31, 2.5, -29)],
				[Vector3(-43, 3.0, -21), Vector3(-31, 2.5, -29)],
				[Vector3(-41, 6.0, -31), Vector3(-30, 2.0, -29)]]}
		"creek":
			return {"dur": 7.0, "keys": [
				[Vector3(-34, 1.0, 39), Vector3(-20, 0.5, 46)],
				[Vector3(-22, 1.1, 40), Vector3(-5, 0.6, 45)],
				[Vector3(-10, 1.3, 39), Vector3(8, 0.8, 47)]]}
		"crash":
			return {"dur": 7.0, "keys": [
				[Vector3(14, 1.7, 14), Vector3(29, 2.5, 27)],
				[Vector3(18, 2.0, 22), Vector3(30, 2.5, 27)],
				[Vector3(19, 2.6, 32), Vector3(30, 2.0, 25)]]}
		"fps":
			return {"dur": 12.0, "keys": []}
	return {"dur": 0.0, "keys": []}


static func sample(c: Dictionary, t: float) -> Array:
	var keys: Array = c.keys
	var n := keys.size()
	if n == 0:
		return []
	if n == 1:
		return keys[0]
	var u := clampf(t / float(c.dur), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65  # gentle ease in/out
	var f := u * (n - 1)
	var i := mini(int(f), n - 2)
	var w := f - i
	var out := []
	for k in 2:
		var a: Vector3 = keys[i][k]
		var b: Vector3 = keys[i + 1][k]
		var pa: Vector3 = keys[maxi(i - 1, 0)][k]
		var pb: Vector3 = keys[mini(i + 2, n - 1)][k]
		out.append(a.cubic_interpolate(b, pa, pb, w))
	return out
