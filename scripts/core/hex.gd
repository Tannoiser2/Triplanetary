class_name Hex
extends RefCounted
## Geometria esagonale assiale (esagoni "a punta", come nel reticolo della mappa sorgente).
## La rotazione di 90° per la vista orizzontale è compito esclusivo del renderer.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]
const SQRT3 := 1.7320508075688772

static func distance(a: Vector2i, b: Vector2i) -> int:
	return length(a - b)

static func length(v: Vector2i) -> int:
	return (absi(v.x) + absi(v.y) + absi(v.x + v.y)) / 2

static func dir_index(v: Vector2i) -> int:
	return DIRS.find(v)

## Centro dell'esagono in unità di raggio esterno = 1 (orientamento sorgente).
static func to_point(h: Vector2i) -> Vector2:
	return Vector2(SQRT3 * (h.x + h.y * 0.5), 1.5 * h.y)

static func from_point(p: Vector2) -> Vector2i:
	var r := p.y / 1.5
	var q := p.x / SQRT3 - r * 0.5
	return cube_round(q, r)

static func cube_round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q); var rr := roundf(r); var rs := roundf(s)
	var dq := absf(rq - q); var dr := absf(rr - r); var ds := absf(rs - s)
	if dq > dr and dq > ds: rq = -rr - rs
	elif dr > ds: rr = -rq - rs
	return Vector2i(int(rq), int(rr))

## Esagoni attraversati da un segmento centro-centro. Con `nudge` positivo o negativo
## si sceglie un lato quando la rotta corre esattamente lungo un bordo.
static func line(a: Vector2i, b: Vector2i, nudge := 1.0) -> Array[Vector2i]:
	var n := distance(a, b)
	var out: Array[Vector2i] = [a]
	if n == 0: return out
	var eq := 1e-6 * nudge; var er := 2e-6 * nudge
	for i in range(1, n + 1):
		var t := float(i) / n
		var h := cube_round(lerpf(a.x + eq, b.x + eq, t), lerpf(a.y + er, b.y + er, t))
		if h != out[-1]: out.append(h)
	return out

## Unione dei due lati: se la rotta corre lungo un bordo restituisce entrambi gli esagoni,
## in ordine di avanzamento lungo la rotta.
static func supercover(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var first := line(a, b, 1.0)
	var second := line(a, b, -1.0)
	var out: Array[Vector2i] = []
	var i := 0; var j := 0
	while i < first.size() or j < second.size():
		var pick: Vector2i
		if j >= second.size(): pick = first[i]; i += 1
		elif i >= first.size(): pick = second[j]; j += 1
		else:
			var da := _progress(a, b, first[i]); var db := _progress(a, b, second[j])
			if da <= db: pick = first[i]; i += 1
			else: pick = second[j]; j += 1
		if not out.has(pick): out.append(pick)
	return out

static func _progress(a: Vector2i, b: Vector2i, h: Vector2i) -> float:
	var pa := to_point(a); var pb := to_point(b); var ph := to_point(h)
	var ab := pb - pa
	if ab.length_squared() == 0.0: return 0.0
	return (ph - pa).dot(ab) / ab.length_squared()

## Distanza minima tra il segmento centro(a)→centro(b) e il centro di `c`, in raggi esterni.
static func segment_distance(a: Vector2i, b: Vector2i, c: Vector2i) -> float:
	var pa := to_point(a); var pb := to_point(b); var pc := to_point(c)
	var ab := pb - pa
	var t := 0.0
	if ab.length_squared() > 0.0: t = clampf((pc - pa).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (pa + ab * t).distance_to(pc)

## Vero se la rotta passa esattamente per il centro dell'esagono `c` (regola dello speronamento).
static func passes_center(a: Vector2i, b: Vector2i, c: Vector2i) -> bool:
	return segment_distance(a, b, c) < 0.01

static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS: out.append(h + d)
	return out

static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius == 0: return [center]
	var h := center + DIRS[4] * radius
	for side in range(6):
		for _i in range(radius):
			out.append(h)
			h += DIRS[side]
	return out
