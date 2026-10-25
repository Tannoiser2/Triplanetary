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
