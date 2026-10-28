class_name Planets
extends RefCounted
## Mappa ampliata di Mike Rowles con i pianeti in moto.
## Ogni corpo segue la sua orbita circolare attorno al Sole, in senso antiorario, avanzando di un
## esagono ogni "period" turni (Map Notes: Mercurio 1/2, Venere 1/3, Terra 1/4, Marte 1/5, Vesta 1/11,
## Ceres e Pallade 1/12; Giove resta fermo). Lune, basi e navi in orbita o a terra si muovono con il pianeta.

const SAFE_TURNS := 160      # all'inizio ogni pianeta deve restare sulla plancia per tanti turni

static var _paths := {}

static func raw() -> Dictionary:
	return SolarMap.xraw()

## Orbita come sequenza di esagoni contigui, in senso antiorario sulla plancia (vista ruotata).
static func path(id: String) -> Array:
	if _paths.has(id): return _paths[id]
	var def := orbit_def(id)
	var R := float(def.radius) * Hex.SQRT3
	var out: Array = []
	# un campione per esagono di circonferenza: l'orbita non fa zig-zag (Map Notes, fig. 1)
	var steps := roundi(TAU * float(def.radius))
	for i in range(steps):
		var a := TAU * float(i) / steps
		# punto sulla plancia (x a destra, y in basso): antiorario = angolo che sale verso l'alto
		var d := Vector2(cos(a), -sin(a)) * R
		var h := Hex.from_point(Vector2(d.y, -d.x))
		if out.is_empty() or out[-1] != h:
			if not out.is_empty() and Hex.distance(out[-1], h) > 1:
				# niente salti: si passa per l'esagono intermedio
				var mid: Array = Hex.line(out[-1], h)
				for k in range(1, mid.size() - 1): out.append(mid[k])
			if out.is_empty() or out[-1] != h: out.append(h)
	if out.size() > 1 and out[0] == out[-1]: out.pop_back()
	_paths[id] = out
	return out

static func orbit_def(id: String) -> Dictionary:
	for o in raw().orbits:
		if o.id == id: return o
	return {}

## Posizioni iniziali: a caso, ma tali che pianeta e anello di gravità restino in plancia a lungo.
static func setup(state: Dictionary) -> void:
	var cells: Dictionary = SolarMap.get_xmap({}).cells
	var pos := {}
	for o in raw().orbits:
		var p := path(o.id)
		if o.has("behind"): continue
		var tries := 0
		var best := 0
		while tries < 400:
			tries += 1
			var idx := 0
			if int(o.period) == 0: idx = 0  # Giove: fermo nel punto della sua orbita visibile sulla plancia
			else: idx = (Rules.roll(state) * 997 + Rules.roll(state) * 131 + tries * 37) % p.size()
			if _stays(o, idx, cells): best = idx; break
		pos[o.id] = best
	for o in raw().orbits:
		if o.has("behind"):
			var lead: int = pos.get(o.behind, 0)
			pos[o.id] = (lead - int(path(o.id).size() * float(o.lag_deg) / 360.0) + path(o.id).size()) % path(o.id).size()
	state.planets = pos
	state.planet_clock = 0

static func _stays(o: Dictionary, idx: int, cells: Dictionary) -> bool:
	var p := path(o.id)
	var n := 1 if int(o.period) == 0 else SAFE_TURNS / int(o.period) + 1
	for k in range(n):
		var h: Vector2i = p[(idx + k) % p.size()]
		for c in [h] + Hex.neighbors(h):
			if not cells.has(c): return false
		for m in o.get("moons", []):
			var mh: Vector2i = h + Vector2i(int(m.offset[0]), int(m.offset[1]))
			for c2 in [mh] + Hex.neighbors(mh):
				if not cells.has(c2): return false
	return true

## Fine turno: i corpi avanzano; ciò che è a terra o nei loro campi di gravità si sposta con loro.
static func advance(state: Dictionary) -> void:
	if not state.has("planets"): return
	state.planet_clock = int(state.get("planet_clock", 0)) + 1
	var before := Rules.map_of(state)
	var moved := {}
	for o in raw().orbits:
		if int(o.period) <= 0 or int(state.planet_clock) % int(o.period) != 0: continue
		var p := path(o.id)
		state.planets[o.id] = (int(state.planets[o.id]) + 1) % p.size()
		moved[o.id] = true
	if moved.is_empty(): return
	var after := Rules.map_of(state)
	for o in raw().orbits:
		if not moved.has(o.id): continue
		var old_h: Vector2i = SolarMap.body(before, o.id).hex
		var d: Vector2i = SolarMap.body(after, o.id).hex - old_h
		var system: Array = [o.id]
		for m in o.get("moons", []): system.append(m.id)
		var near: Array = []
		for b in system: near.append(SolarMap.body(before, b).hex)
		for s in state.ships:
			if not Rules.alive(s): continue
			var carry: bool = system.has(s.landed)
			if not carry and s.landed == "":
				for h in near:
					if Hex.distance(s.pos, h) <= 1: carry = true; break
			if carry:
				s.pos = s.pos + d
				if not s.get("last_path", []).is_empty(): s.last_path = s.last_path.map(func(x): return x + d)
		for od in state.ordnance:
			for h in near:
				if Hex.distance(od.pos, h) <= 1: od.pos = od.pos + d; break

## Posizioni dei corpi dopo t avanzamenti di turno (per la pianificazione dell'IA).
static func future(state: Dictionary, t: int) -> Dictionary:
	if t <= 0: return state.planets
	var clock := int(state.get("planet_clock", 0))
	var out := {}
	for o in raw().orbits:
		var idx := int(state.planets.get(o.id, 0))
		if int(o.period) > 0:
			var per := int(o.period)
			idx = (idx + (clock + t) / per - clock / per) % path(o.id).size()
		out[o.id] = idx
	return out

## Esagono di un corpo fra t turni (lune comprese); per i corpi fissi la posizione attuale.
static func body_hex_at(state: Dictionary, id: String, t: int) -> Vector2i:
	var pl := future(state, t)
	for o in raw().orbits:
		var p := path(o.id)
		var h: Vector2i = p[int(pl.get(o.id, 0)) % p.size()]
		if o.id == id: return h
		for m in o.get("moons", []):
			if m.id == id: return h + Vector2i(int(m.offset[0]), int(m.offset[1]))
	return SolarMap.body(Rules.map_of(state), id).hex

## Esagoni dell'orbita per il disegno (una sola volta per corpo).
static func orbit_paths() -> Dictionary:
	var out := {}
	for o in raw().orbits:
		if int(o.period) > 0 and not o.has("behind"): out[o.id] = path(o.id)
	return out
