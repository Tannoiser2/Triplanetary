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
		"sol_classic": sol_classic
	}
	_cache[key] = data
	return data

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
