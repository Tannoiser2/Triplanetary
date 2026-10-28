class_name SolarMap
extends RefCounted
## Dati statici della plancia (data/map.json, generato da tools/build_map.py).
## Le parti modificabili durante la partita (asteroidi distrutti, lati devastati)
## vivono nello stato di gioco, non qui.

const MAP_PATH := "res://data/map.json"

static var _cache: Dictionary = {}

static func get_map(sol_classic := false) -> Dictionary:
	var key := "classic" if sol_classic else "map"
	if _cache.has(key): return _cache[key]
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	var cells := {}
	for c in raw.cells: cells[Vector2i(int(c[0]), int(c[1]))] = true
	var bodies: Array = []
	var body_at := {}
	for b in raw.bodies:
		var body := {
			"id": b.id, "name": b.name, "hex": Vector2i(int(b.hex[0]), int(b.hex[1])),
			"gravity": b.gravity, "radius": float(b.radius) * Hex.SQRT3 * 0.5,
			"color": Color(b.color), "base_sides": b.base_sides.map(func(s): return int(s)),
			"asteroid_base": bool(b.asteroid_base)
		}
		bodies.append(body)
		body_at[body.hex] = body
	var gravity := {}
	for key_str in raw.gravity:
		var parts: PackedStringArray = key_str.split(",")
		var h := Vector2i(int(parts[0]), int(parts[1]))
		var list: Array = []
		for g in raw.gravity[key_str]:
			if sol_classic and (g.get("inner_extra", false) or g.get("outer_pair", false) or g.get("outer_corner", false)): continue
			list.append({"acc": Vector2i(int(g.acc[0]), int(g.acc[1])), "weak": bool(g.weak), "body": g.body})
		if not list.is_empty(): gravity[h] = list
	var asteroids: Array = raw.asteroids.map(func(a): return Vector2i(int(a[0]), int(a[1])))
	var special: Array = raw.special_asteroids.map(func(a): return Vector2i(int(a[0]), int(a[1])))
	var data := {
		"cells": cells, "bodies": bodies, "body_at": body_at, "gravity": gravity,
		"asteroids": asteroids, "special_asteroids": special, "rows": int(raw.rows),
		"sol_classic": sol_classic, "edge_y": 0
	}
	_cache[key] = data
	return data

# ---------------------------------------------------------------- mappa ampliata (pianeti in moto)

## Varianti: "xmap" (sistema interno, 76 x 53) e "xmap_full" (fino a Plutone, 152 x 53).
static var _xraw: Dictionary = {}
static var _xcache: Dictionary = {}

static func xraw(variant := "xmap") -> Dictionary:
	if not _xraw.has(variant):
		_xraw[variant] = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % variant))
	return _xraw[variant]

## Mappa ampliata con i corpi nelle posizioni date ({id: indice lungo l'orbita}).
static func get_xmap(planets: Dictionary, variant := "xmap") -> Dictionary:
	var key := variant + JSON.stringify(planets)
	if _xcache.has(key): return _xcache[key]
	if _xcache.size() > 40: _xcache.clear()
	var raw := xraw(variant)
	var cells := {}
	for c in raw.cells: cells[Vector2i(int(c[0]), int(c[1]))] = true
	var bodies: Array = []
	var gravity := {}
	var sol := Vector2i(int(raw.sol[0]), int(raw.sol[1]))
	bodies.append({"id": "sol", "name": "Sol", "hex": sol, "gravity": "sol", "radius": 0.74 * Hex.SQRT3 * 0.5, "color": Color("#ffb347"), "base_sides": [], "asteroid_base": false})
	# Sole: anello interno a gravità tripla, anello esterno normale
	for d in Hex.DIRS:
		_add_grav(gravity, sol + d, -d * int(raw.sol_gravity.inner_mult), false, "sol")
	for h in Hex.ring(sol, 2):
		var best := Vector2i.ZERO
		var best_dot := -INF
		var to_sun := Hex.to_point(sol) - Hex.to_point(h)
		for d2 in Hex.DIRS:
			if Hex.distance(h + d2, sol) != 1: continue
			var dot := Hex.to_point(d2).normalized().dot(to_sun.normalized())
			if dot > best_dot: best_dot = dot; best = d2
		_add_grav(gravity, h, best * int(raw.sol_gravity.outer_mult), false, "sol")
	for o in raw.orbits:
		var idx := int(planets.get(o.id, 0))
		var p: Array = Planets.path(o.id)
		var h0: Vector2i = p[idx % p.size()]
		_add_body(bodies, gravity, o, h0)
		for m in o.get("moons", []):
			_add_body(bodies, gravity, m, h0 + Vector2i(int(m.offset[0]), int(m.offset[1])))
	var body_at := {}
	for b in bodies: body_at[b.hex] = b
	for c in raw.get("fixed", []):
		bodies.append({"id": c.id, "name": c.name, "hex": Vector2i(int(c.hex[0]), int(c.hex[1])), "gravity": "none", "radius": 0.0,
			"color": Color(c.color), "base_sides": [], "asteroid_base": true})
	var asteroids: Array = []
	for a in raw.asteroids:
		var ah := Vector2i(int(a[0]), int(a[1]))
		if not body_at.has(ah): asteroids.append(ah)
	var special: Array = raw.get("special", []).map(func(a): return Vector2i(int(a[0]), int(a[1])))
	var miny := 0
	for c in cells: miny = mini(miny, c.y)
	var data := {"cells": cells, "bodies": bodies, "body_at": body_at, "gravity": gravity,
		"asteroids": asteroids, "special_asteroids": special, "rows": 0, "sol_classic": false, "xmap": true, "variant": variant, "edge_y": miny}
	_xcache[key] = data
	return data

static func _add_body(bodies: Array, gravity: Dictionary, o: Dictionary, h: Vector2i) -> void:
	var g: String = o.gravity
	bodies.append({"id": o.id, "name": o.name, "hex": h, "gravity": g, "radius": float(o.get("size", 0.0)) * Hex.SQRT3 * 0.5,
		"color": Color(o.color), "base_sides": o.get("base_sides", []).map(func(x): return int(x)), "asteroid_base": bool(o.get("asteroid_base", false))})
	if g == "none": return
	var mult := int(o.get("mult", 1))
	for d in Hex.DIRS: _add_grav(gravity, h + d, -d * mult, g == "weak", o.id)

static func _add_grav(gravity: Dictionary, h: Vector2i, acc: Vector2i, weak: bool, body_id: String) -> void:
	if not gravity.has(h): gravity[h] = []
	gravity[h].append({"acc": acc, "weak": weak, "body": body_id})

static func body(map: Dictionary, id: String) -> Dictionary:
	for b in map.bodies:
		if b.id == id: return b
	return {}

static func on_map(map: Dictionary, h: Vector2i) -> bool:
	return map.cells.has(h)

## Esagoni di gravità di un corpo (tutti quelli che contengono una sua freccia).
static func gravity_hexes(map: Dictionary, body_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in map.gravity:
		for g in map.gravity[h]:
			if g.body == body_id and not out.has(h): out.append(h)
	return out

## Corpi con gravità piena (obiettivi del Grand Tour).
static func full_gravity_bodies(map: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for b in map.bodies:
		if b.gravity in ["full", "sol"]: out.append(b.id)
	return out
