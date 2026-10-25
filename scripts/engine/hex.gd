class_name HexMath
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (abs(d.x) + abs(d.y) + abs(d.x + d.y)) / 2

static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var count := distance(a, b)
	if count == 0:
		return [a]
	var result: Array[Vector2i] = []
	var ac := Vector3(a.x, -a.x - a.y, a.y)
	var bc := Vector3(b.x, -b.x - b.y, b.y)
	for i in range(count + 1):
		var c := ac.lerp(bc, float(i) / count)
		var rx := roundi(c.x)
		var ry := roundi(c.y)
		var rz := roundi(c.z)
		var dx: float = absf(rx - c.x)
		var dy: float = absf(ry - c.y)
		var dz: float = absf(rz - c.z)
		if dx > dy and dx > dz:
			rx = -ry - rz
		elif dy > dz:
			ry = -rx - rz
		else:
			rz = -rx - ry
		result.append(Vector2i(rx, rz))
	return result

# Restituisce anche entrambi gli esagoni quando una traiettoria corre
# esattamente lungo un bordo. È necessario per gravità e asteroidi.
static func supercover_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var primary := line(a, b)
	var result: Array[Vector2i] = []
	for hex in primary:
		if hex not in result: result.append(hex)
	if a == b: return result
	var ac := Vector3(a.x, -a.x - a.y, a.y)
	var bc := Vector3(b.x, -b.x - b.y, b.y)
	var count := distance(a, b)
	for sign_value in [-1.0, 1.0]:
		var nudge := Vector3(0.000001 * sign_value, -0.000002 * sign_value, 0.000001 * sign_value)
		for i in range(count + 1):
			var c := (ac + nudge).lerp(bc + nudge, float(i) / count)
			var rounded := _cube_round(c)
			var hex := Vector2i(int(rounded.x), int(rounded.z))
			if hex not in result: result.append(hex)
	result.sort_custom(func(left: Vector2i, right: Vector2i): return distance(a, left) < distance(a, right))
	return result

static func _cube_round(c: Vector3) -> Vector3:
	var rx := roundi(c.x)
	var ry := roundi(c.y)
	var rz := roundi(c.z)
	var dx: float = absf(rx - c.x)
	var dy: float = absf(ry - c.y)
	var dz: float = absf(rz - c.z)
	if dx > dy and dx > dz: rx = -ry - rz
	elif dy > dz: ry = -rx - rz
	else: rz = -rx - ry
	return Vector3(rx, ry, rz)

static func axial_to_odd_q(hex: Vector2i) -> Vector2i:
	return Vector2i(hex.x, hex.y + (hex.x - (hex.x & 1)) / 2)
