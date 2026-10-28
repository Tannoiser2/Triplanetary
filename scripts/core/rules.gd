class_name Rules
extends RefCounted
## Regole di Triplanetary (Updated Second Edition) come funzioni pure sullo stato.
## Lo stato è un Dictionary serializzabile; i comandi lo modificano sul posto e
## restituiscono "" in caso di successo o un messaggio d'errore leggibile.

const PHASES := ["astrogation", "ordnance", "movement", "combat", "resupply"]
const PHASE_NAMES := {
	"setup": "Schieramento", "astrogation": "Astrogazione", "ordnance": "Ordigni",
	"movement": "Movimento", "combat": "Combattimento", "resupply": "Rifornimento", "over": "Fine partita"
}

const GUN_TABLE := [
	["-", "-", "-", "-", "D2", "D3"],   # 1:2
	["-", "-", "-", "D2", "D3", "D4"],  # 1:1
	["-", "-", "D2", "D3", "D4", "D5"], # 2:1
	["-", "D2", "D3", "D4", "D5", "E"], # 3:1
	["D2", "D3", "D4", "D5", "E", "E"]  # 4:1
]
const ODDS_LABELS := ["1:2", "1:1", "2:1", "3:1", "4:1"]
const ITEM_TABLE := {
	"torpedo": ["-", "D5", "E", "E", "E", "E"],
	"mine": ["-", "-", "-", "D1", "D2", "D3"],
	"ram": ["-", "-", "-", "-", "D2", "D2"],
	"asteroid": ["-", "-", "-", "-", "D1", "D2"],
}
const ORDNANCE_LIFE := 5

# ---------------------------------------------------------------- utilità di base

static func map_of(state: Dictionary) -> Dictionary:
	if state.has("planets"): return SolarMap.get_xmap(state.planets, Planets.variant(state))
	return SolarMap.get_map(state.options.get("sol_classic", false))

static func player_ids(state: Dictionary) -> Array:
	return state.players.map(func(p): return p.id)

static func current_player(state: Dictionary) -> String:
	return state.players[state.seg].id

static func player(state: Dictionary, id: String) -> Dictionary:
	for p in state.players:
		if p.id == id: return p
	return {}

static func ticks_per_turn(state: Dictionary) -> int:
	return state.players.size() * PHASES.size()

static func tick(state: Dictionary) -> int:
	var phase_index := maxi(0, PHASES.find(state.phase))
	return ((int(state.turn) - 1) * state.players.size() + int(state.seg)) * PHASES.size() + phase_index

## Identificatore del segmento corrente (giorno + giocatore in fase).
static func seg_key(state: Dictionary) -> int:
	return (int(state.turn) - 1) * state.players.size() + int(state.seg)

static func ship(state: Dictionary, id: String) -> Dictionary:
	for s in state.ships:
		if s.id == id: return s
	return {}

static func alive(s: Dictionary) -> bool:
	return not s.destroyed and not s.escaped and not s.get("captured", false)

static func on_board(s: Dictionary) -> bool:
	return alive(s)

static func is_disabled(state: Dictionary, s: Dictionary) -> bool:
	return int(s.disabled_until) > tick(state)

static func disabled_turns(state: Dictionary, s: Dictionary) -> int:
	var left := int(s.disabled_until) - tick(state)
	if left <= 0: return 0
	return ceili(float(left) / ticks_per_turn(state))

static func roll(state: Dictionary) -> int:
	state.rng = int((int(state.rng) * 1103515245 + 12345) & 0x7fffffff)
	return int((state.rng >> 16) % 6) + 1

static func log_event(state: Dictionary, text: String, kind := "info") -> void:
	state.log.append({"turn": state.turn, "player": current_player(state) if state.has("players") and not state.players.is_empty() else "", "text": text, "kind": kind})

static func fx(state: Dictionary, kind: String, hex: Vector2i, extra := {}) -> void:
	var e := {"kind": kind, "hex": hex}
	e.merge(extra)
	state.fx.append(e)

# ---------------------------------------------------------------- fisica del movimento

## Simula un movimento senza effetti collaterali. Usata da regole, anteprima e IA.
static func simulate(map: Dictionary, pos: Vector2i, vel: Vector2i, pending: Array, burn: Vector2i,
		use_weak: bool, asteroids: Array, special: Array, access_special: bool) -> Dictionary:
	var new_vel := vel + burn
	for g in pending: new_vel += g
	var dest := pos + new_vel
	var path := Hex.supercover(pos, dest)
	var result := {"dest": dest, "vel": new_vel, "path": path, "crash": "", "offmap": not map.cells.has(dest),
		"grav": [], "visits": [], "asteroids": [], "special": false}
	# Collisione con i dischi dei corpi: conta la geometria, non l'intero esagono.
	for i in range(1, path.size()):
		var h: Vector2i = path[i]
		if map.body_at.has(h):
			var b: Dictionary = map.body_at[h]
			if float(b.radius) > 0.0 and Hex.segment_distance(pos, dest, h) < float(b.radius):
				result.crash = b.id
				result.path = path.slice(0, i + 1)
				return result
	# Gravità acquisita, da applicare al prossimo movimento (cumulativa e obbligatoria).
	var hexes: Array = path.slice(1)
	if new_vel == Vector2i.ZERO and map.gravity.has(pos): hexes = [pos]
	var previous_weak := false
	for h in hexes:
		if not map.gravity.has(h):
			previous_weak = false
			continue
		var weak_here := false
		for g in map.gravity[h]:
			if g.weak:
				weak_here = true
				if previous_weak or use_weak: result.grav.append(g.acc)
			else:
				result.grav.append(g.acc)
				if not result.visits.has(g.body): result.visits.append(g.body)
		previous_weak = weak_here
	# Asteroidi: solo sopra velocità 1; correre lungo un lato fra due esagoni ne conta uno.
	if Hex.length(new_vel) > 1:
		for h in Hex.line(pos, dest, 1.0).slice(1):
			if asteroids.has(h): result.asteroids.append(h)
	for h in hexes:
		if special.has(h) and not access_special: result.special = true
	return result

static func pending_sum(s: Dictionary) -> Vector2i:
	var t := Vector2i.ZERO
	for g in s.grav: t += g
	return t

static func burn_vector(burns: Array) -> Vector2i:
	var v := Vector2i.ZERO
	for d in burns: v += Hex.DIRS[int(d)]
	return v

## Anteprima del movimento di una nave secondo il suo ordine attuale.
static func predict(state: Dictionary, s: Dictionary, plot: Dictionary = {}) -> Dictionary:
	var map := map_of(state)
	if s.landed != "":
		if plot.get("takeoff", false):
			var b := SolarMap.body(map, s.landed)
			var h: Vector2i = b.hex + Hex.DIRS[int(s.side)]
			return {"dest": h, "vel": Vector2i.ZERO, "path": [b.hex, h], "crash": "", "offmap": false, "grav": [], "visits": [], "asteroids": [], "special": false, "takeoff": true}
		return {"dest": s.pos, "vel": Vector2i.ZERO, "path": [s.pos], "crash": "", "offmap": false, "grav": [], "visits": [], "asteroids": [], "special": false, "landed": true}
	if int(plot.get("land", -1)) >= 0:
		var b2 := SolarMap.body(map, plot.land_body)
		return {"dest": b2.hex, "vel": Vector2i.ZERO, "path": [s.pos, b2.hex], "crash": "", "offmap": false, "grav": [], "visits": [], "asteroids": [], "special": false, "land": true}
	var burns: Array = plot.get("burns", []) if not is_disabled(state, s) else []
	return simulate(map, s.pos, s.vel, s.grav, burn_vector(burns), plot.get("weak", false), hazard_rocks(state, s), state.special, s.access_special)

## Esagoni di asteroidi pericolosi per questa nave.
static func hazard_rocks(state: Dictionary, s: Dictionary) -> Array:
	if s.access_special and state.rules.get("special_as_asteroids", false): return state.asteroids + state.special
	return state.asteroids

## Nave in orbita: ultimo movimento a velocità 1, senza spinta, fra due esagoni di gravità
## adiacenti dello stesso corpo. Restituisce l'id del corpo o "".
static func orbit_body(state: Dictionary, s: Dictionary) -> String:
	if s.history.is_empty() or s.landed != "": return ""
	var last: Dictionary = s.history[-1]
	if int(last.turn) < int(state.turn) - 1: return ""
	if not last.burns.is_empty() or Hex.length(s.vel) != 1: return ""
	var map := map_of(state)
	var from: Vector2i = last.from
	var to: Vector2i = last.to
	if Hex.distance(from, to) != 1 or not map.gravity.has(from) or not map.gravity.has(to): return ""
	for g in map.gravity[to]:
		for g2 in map.gravity[from]:
			if g.body == g2.body: return g.body
	return ""

# ---------------------------------------------------------------- basi

static func base_at(state: Dictionary, body_id: String, side: int) -> Dictionary:
	for b in state.bases:
		if b.body == body_id and int(b.side) == side and b.active: return b
	return {}

static func friendly_base(state: Dictionary, b: Dictionary, owner: String) -> bool:
	if b.is_empty() or not b.active: return false
	return b.owner == owner or b.owner == "all" or b.get("friends", []).has(owner)

## Lati di atterraggio utilizzabili da una nave in orbita attorno a un corpo.
static func landing_sides(state: Dictionary, s: Dictionary) -> Array:
	var body_id := orbit_body(state, s)
	if body_id == "": return []
	var map := map_of(state)
	var body := SolarMap.body(map, body_id)
	if float(body.radius) <= 0.0: return []
	var sides := []
	for b in state.bases:
		if b.body != body_id or int(b.side) < 0 or not b.active: continue
		if friendly_base(state, b, s.owner) or state.rules.get("capture_bases", false): sides.append(int(b.side))
	# preferisce il lato sotto la nave
	var facing := Hex.dir_index(s.pos - body.hex)
	sides.sort_custom(func(x, y): return _side_gap(x, facing) < _side_gap(y, facing))
	return sides

static func _side_gap(a: int, b: int) -> int:
	if b < 0: return 0
	var d := absi(a - b) % 6
	return mini(d, 6 - d)

static func can_take_off(state: Dictionary, s: Dictionary) -> bool:
	if s.landed == "" or is_disabled(state, s) or not alive(s): return false
	if s.get("free_takeoff", false): return true
	return friendly_base(state, base_at(state, s.landed, int(s.side)), s.owner)

## Base (planetaria, asteroidale) con cui la nave ha accoppiato la rotta in questo momento.
static func docked_base(state: Dictionary, s: Dictionary) -> Dictionary:
	if not alive(s): return {}
	if s.landed != "": return base_at(state, s.landed, int(s.side))
	var map := map_of(state)
	for b in state.bases:
		if not b.active: continue
		var body := SolarMap.body(map, b.body)
		if int(b.side) < 0:
			if s.pos == body.hex and s.vel == Vector2i.ZERO: return b
		elif s.pos == body.hex + Hex.DIRS[int(b.side)] and orbit_body(state, s) == b.body:
			return b
	for ob in state.ships:
		if ob.get("is_base", false) and ob.id != s.id and alive(ob) and ob.pos == s.pos and ob.vel == s.vel and s.landed == "":
			return {"id": ob.id, "body": "", "side": -1, "owner": ob.owner, "active": true, "fuel": true, "ordnance": true, "orbital": true, "name": ob.name}
	return {}

static func base_name(state: Dictionary, b: Dictionary) -> String:
	if b.get("orbital", false): return b.get("name", "base orbitale")
	return SolarMap.body(map_of(state), b.body).name

# ---------------------------------------------------------------- astrogazione

static func can_plot(state: Dictionary, s: Dictionary) -> bool:
	return state.phase == "astrogation" and s.owner == current_player(state) and alive(s) and not s.get("dummy", false) and not s.get("is_base", false)

static func can_overload(state: Dictionary, s: Dictionary) -> bool:
	return not s.commercial and s.overload_ok and (s.infinite_fuel or int(s.fuel) >= 2)

## Imposta l'ordine di una nave. plot = {burns:[dir], weak:bool, takeoff:bool, land:side, ram:id}
static func set_plot(state: Dictionary, ship_id: String, plot: Dictionary) -> String:
	var s := ship(state, ship_id)
	if s.is_empty() or not can_plot(state, s): return "Non puoi dare ordini a questa nave ora."
	var burns: Array = plot.get("burns", [])
	if s.landed != "":
		if plot.get("takeoff", false) and not can_take_off(state, s): return "Il decollo richiede una base amica con booster."
		if not burns.is_empty(): return "Una nave a terra può solo decollare."
	if is_disabled(state, s) and (not burns.is_empty() or plot.get("takeoff", false) or int(plot.get("land", -1)) >= 0):
		return "Nave disabilitata: può solo andare alla deriva."
	if s.get("locked", false) and not burns.is_empty(): return "Il dreadnought non può muovere finché non viene rilevato un pirata."
	if s.get("is_base", false) and (not burns.is_empty() or plot.get("takeoff", false)): return "Una base orbitale non ha motori."
	if burns.size() > 2: return "Al massimo due accelerazioni."
	if burns.size() == 2 and not can_overload(state, s): return "Sovraccarico non disponibile per questa nave."
	if not s.infinite_fuel and burns.size() > int(s.fuel): return "Carburante insufficiente."
	if int(plot.get("land", -1)) >= 0:
		var sides := landing_sides(state, s)
		if not sides.has(int(plot.land)): return "Per atterrare serve un'orbita stabile sopra una base utilizzabile."
		if not s.infinite_fuel and int(s.fuel) < 1: return "Serve 1 punto carburante per atterrare."
		plot.land_body = orbit_body(state, s)
	var extra := Scenarios.plot_check(state, s, plot)
	if extra != "": return extra
	state.plots[ship_id] = plot.duplicate(true)
	return ""

static func clear_plot(state: Dictionary, ship_id: String) -> void:
	state.plots.erase(ship_id)

# ---------------------------------------------------------------- ordigni

static func can_launch(state: Dictionary, s: Dictionary, kind: String) -> String:
	if state.phase != "ordnance" or s.owner != current_player(state) or not alive(s): return "Non è la fase ordigni."
	if not state.rules.get("ordnance", true): return "In questo scenario gli ordigni non sono disponibili."
	if int(s.inv.get(kind, 0)) <= 0: return "Nessun ordigno di questo tipo a bordo."
	if s.landed != "": return "Una nave a terra non può lanciare."
	if is_disabled(state, s): return "Nave disabilitata."
	if int(s.launched_seg) == seg_key(state): return "Un solo ordigno per nave per turno."
	if kind == "torpedo" and s.commercial: return "Solo le navi da guerra lanciano siluri."
	if s.get("is_base", false):
		if kind != "torpedo": return "Una base orbitale lancia solo siluri."
		if int(s.resupplied_seg) == seg_key(state): return "La base ha rifornito navi in questo turno."
		return ""
	var plot: Dictionary = state.plots.get(s.id, {})
	if kind in ["mine", "nuke"] and plot.get("burns", []).is_empty():
		return "Dopo il lancio la nave deve cambiare rotta: pianifica una spinta in astrogazione."
	if int(plot.get("land", -1)) >= 0 or plot.get("takeoff", false): return "Non si lancia durante decollo o atterraggio."
	return ""

static func launch(state: Dictionary, ship_id: String, kind: String, torpedo_burns: Array = []) -> String:
	var s := ship(state, ship_id)
	if s.is_empty(): return "Nave inesistente."
	var err := can_launch(state, s, kind)
	if err != "": return err
	if kind == "torpedo" and (torpedo_burns.size() < 1 or torpedo_burns.size() > 2): return "Il siluro accelera di 1 o 2 esagoni al lancio."
	if kind != "torpedo": torpedo_burns = []
	s.inv[kind] = int(s.inv[kind]) - 1
	s.launched_seg = seg_key(state)
	state.next_id = int(state.next_id) + 1
	var item := {"id": "o%d" % state.next_id, "kind": kind, "owner": s.owner, "pos": s.pos, "vel": s.vel,
		"grav": s.grav.duplicate(), "launch_burn": burn_vector(torpedo_burns), "age": 0, "from": s.id, "history": []}
	state.ordnance.append(item)
	if not state.has("replay_ord"): state.replay_ord = {}
	state.replay_ord[item.id] = [kind, s.owner]
	log_event(state, "%s lancia: %s" % [s.name, ShipTypes.ORDNANCE_NAME[kind].to_lower()], "ordnance")
	return ""

# ---------------------------------------------------------------- avanzamento delle fasi

static func end_phase(state: Dictionary) -> void:
	state.fx = []
	match state.phase:
		"astrogation":
			state.phase = "ordnance"
		"ordnance":
			state.phase = "movement"
			_do_movement(state)
		"movement":
			state.phase = "combat"
			_announce_hazards(state)
		"combat":
			if not state.pending_attack.is_empty(): return
			_planetary_defense(state)
			state.phase = "resupply"
		"resupply":
			_do_resupply(state)
			_next_segment(state)
	Scenarios.check_victory(state)

static func _next_segment(state: Dictionary) -> void:
	state.plots = {}
	state.phase = "astrogation"
	for _guard in range(state.players.size() + 1):
		state.seg = int(state.seg) + 1
		if int(state.seg) >= state.players.size():
			state.seg = 0
			Scenarios.end_of_turn(state)
			if state.over: return
			Scenarios.check_stalemate(state)
			if state.over: return
			state.turn = int(state.turn) + 1
			Planets.advance(state)
		if _player_active(state, current_player(state)):
			Scenarios.start_of_segment(state)
			return
	# nessun giocatore ha più navi in gioco
	Scenarios.check_victory(state)

static func _player_active(state: Dictionary, pid: String) -> bool:
	for s in state.ships:
		if s.owner == pid and alive(s) and not s.get("dummy", false): return true
	for o in state.ordnance:
		if o.owner == pid: return true
	return Scenarios.player_has_reinforcements(state, pid)

# ---------------------------------------------------------------- movimento

static func _do_movement(state: Dictionary) -> void:
	var map := map_of(state)
	var me := current_player(state)
	state.moves = []
	for s in state.ships:
		if s.owner != me or not alive(s) or s.get("dummy", false): continue
		var plot: Dictionary = state.plots.get(s.id, {})
		if s.get("locked", false): plot = {}
		_move_ship(state, map, s, plot)
	_move_ordnance(state, map)
	_replay_frame(state)
	_update_detection(state)
	Scenarios.after_movement(state)

## Registro compatto per il replay di fine partita: per ogni movimento
## [id, da.x, da.y, a.x, a.y, spinta.x, spinta.y] (gli ordigni hanno l'id "o…").
static func _replay_frame(state: Dictionary) -> void:
	if not state.has("replay"): state.replay = []
	var mv := []
	for m in state.moves:
		var b: Vector2i = m.get("burn", Vector2i.ZERO)
		mv.append([m.id, m.from.x, m.from.y, m.to.x, m.to.y, b.x, b.y])
	if mv.is_empty(): return
	state.replay.append({"t": int(state.turn), "m": mv})

static func _record(state: Dictionary, s: Dictionary, from: Vector2i, to: Vector2i, burns: Array, path: Array, note := "") -> void:
	s.history.append({"turn": state.turn, "from": from, "to": to, "burns": burns.duplicate(), "note": note})
	if s.history.size() > 40: s.history.pop_front()
	s.last_path = path.duplicate()
	state.moves.append({"id": s.id, "from": from, "to": to, "path": path.duplicate(), "result": note, "burn": burn_vector(burns)})

static func _move_ship(state: Dictionary, map: Dictionary, s: Dictionary, plot: Dictionary) -> void:
	var disabled := is_disabled(state, s)
	# --- a terra
	if s.landed != "":
		if plot.get("takeoff", false) and can_take_off(state, s):
			var body := SolarMap.body(map, s.landed)
			var h: Vector2i = body.hex + Hex.DIRS[int(s.side)]
			var acc: Array = []
			if map.gravity.has(h):
				for g in map.gravity[h]:
					if not g.weak or plot.get("weak", false): acc.append(g.acc)
					if not g.weak and not s.visited.has(g.body): s.visited.append(g.body)
					if not g.weak: Scenarios.on_visits(state, s, [g.body])
			s.pos = h; s.vel = Vector2i.ZERO; s.grav = acc
			log_event(state, "%s decolla da %s con il booster" % [s.name, body.name], "move")
			s.landed = ""; s.side = -1
			_record(state, s, body.hex, h, [], [body.hex, h], "decollo")
		else:
			s.last_path = [s.pos]
		return
	# --- atterraggio da orbita
	if int(plot.get("land", -1)) >= 0 and not disabled:
		var body2 := SolarMap.body(map, plot.land_body)
		var from: Vector2i = s.pos
		if not s.infinite_fuel: s.fuel = int(s.fuel) - 1
		s.fuel_spent = int(s.fuel_spent) + 1
		s.pos = body2.hex; s.vel = Vector2i.ZERO; s.grav = []
		s.landed = body2.id; s.side = int(plot.land)
		log_event(state, "%s atterra su %s" % [s.name, body2.name], "move")
		var lb := base_at(state, body2.id, s.side)
		if not lb.is_empty() and lb.owner != s.owner and lb.owner != "all" and state.rules.get("capture_bases", false):
			lb.owner = s.owner
			log_event(state, "%s conquista la base di %s (lato %d)" % [player(state, s.owner).name, body2.name, s.side + 1], "combat")
		_record(state, s, from, body2.hex, [], [from, body2.hex], "atterraggio")
		Scenarios.on_landed(state, s)
		return
	# --- volo
	var burns: Array = [] if disabled or s.get("locked", false) else plot.get("burns", [])
	var cost := burns.size()
	if not s.infinite_fuel:
		cost = mini(cost, int(s.fuel))
		burns = burns.slice(0, cost)
		s.fuel = int(s.fuel) - cost
	s.fuel_spent = int(s.fuel_spent) + burns.size()
	if burns.size() == 2: s.overload_ok = false
	if not burns.is_empty() and s.get("first_burn_pending", false):
		s.first_burn_pending = false
		Scenarios.on_first_burn(state, s)
	var r := simulate(map, s.pos, s.vel, s.grav, burn_vector(burns), plot.get("weak", false), hazard_rocks(state, s), state.special, s.access_special)
	var from2: Vector2i = s.pos
	s.pos = r.dest; s.vel = r.vel; s.grav = r.grav
	for v in r.visits:
		if not s.visited.has(v): s.visited.append(v)
	if not r.visits.is_empty(): Scenarios.on_visits(state, s, r.visits)
	var note := ""
	if r.crash != "":
		var b3 := SolarMap.body(map, r.crash)
		s.pos = r.path[-1]
		s.crashed_on = r.crash
		s.crash_disabled = disabled
		_destroy(state, s, "si schianta su " + b3.name)
		note = "schianto"
	elif r.offmap:
		if Scenarios.on_exit_map(state, s, r):
			note = "fuga"
		else:
			_destroy(state, s, "esce dalla mappa")
			note = "uscita"
	elif r.special:
		_destroy(state, s, "entra negli asteroidi speciali di Clandestine")
		note = "asteroidi"
	_record(state, s, from2, s.pos, burns, r.path, note)
	if not alive(s): return
	if s.must_change_course: s.must_change_course = false
	# pericoli: asteroidi (tirati ora, mostrati nella fase di combattimento)
	for h in r.asteroids:
		var die := roll(state)
		var res: String = ITEM_TABLE.asteroid[die - 1]
		state.hazards.append({"ship": s.id, "hex": h, "die": die, "result": res})
		_apply_damage(state, s, res, "asteroidi")
		if not alive(s): return
	# mine nemiche e amiche sulla rotta
	_mines_on_course(state, s, r.path)
	if not alive(s): return
	# speronamento
	var ram_id: String = plot.get("ram", "")
	if ram_id != "" and not disabled:
		_try_ram(state, s, ram_id, from2)
	# ordigni speronati lungo il centro della rotta
	Scenarios.after_ship_move(state, s)

static func _mines_on_course(state: Dictionary, s: Dictionary, path: Array) -> void:
	var crossed: Array = path.slice(1)
	for o in state.ordnance.duplicate():
		if o.kind != "mine" or not state.ordnance.has(o): continue
		if crossed.has(o.pos):
			state.blame = o.owner
			_detonate_mine(state, o, o.pos)
			state.blame = ""
			if not alive(s): return

static func _try_ram(state: Dictionary, s: Dictionary, target_id: String, from: Vector2i) -> void:
	if not can_ram(state, s): return
	var t := ship(state, target_id)
	if t.is_empty() or not alive(t) or t.owner == s.owner or t.landed != "": return
	if not Hex.passes_center(from, s.pos, t.pos): return
	if t.get("dummy", false):
		t.destroyed = true; t.reason = "smascherato"
		log_event(state, "%s tenta lo speronamento: era un falso bersaglio" % s.name, "detect")
		return
	var die := roll(state)
	var res: String = ITEM_TABLE.ram[die - 1]
	log_event(state, "%s sperona %s: dado %d → %s" % [s.name, t.name, die, _res_text(res)], "combat")
	fx(state, "ram", t.pos)
	state.blame = t.owner
	_apply_damage(state, s, res, "speronamento")
	state.blame = s.owner
	_apply_damage(state, t, res, "speronamento")
	state.blame = ""

static func can_ram(state: Dictionary, s: Dictionary) -> bool:
	if not state.rules.get("ram", true): return false
	var allowed: Array = state.rules.get("ram_players", [])
	return allowed.is_empty() or allowed.has(s.owner)

## Navi nemiche il cui esagono è attraversato al centro dalla rotta prevista.
static func ram_candidates(state: Dictionary, s: Dictionary, prediction: Dictionary) -> Array:
	var out: Array = []
	if not can_ram(state, s) or prediction.get("crash", "") != "": return out
	for t in state.ships:
		if not alive(t) or t.owner == s.owner or t.landed != "": continue
		if t.pos != s.pos and Hex.passes_center(s.pos, prediction.dest, t.pos): out.append(t.id)
	return out

static func _move_ordnance(state: Dictionary, map: Dictionary) -> void:
	var me := current_player(state)
	for o in state.ordnance.duplicate():
		if o.owner != me or not state.ordnance.has(o): continue
		var burn: Vector2i = o.get("launch_burn", Vector2i.ZERO)
		o.launch_burn = Vector2i.ZERO
		var r := simulate(map, o.pos, o.vel, o.grav, burn, false, [], [], true)
		var from: Vector2i = o.pos
		o.vel = r.vel; o.grav = r.grav; o.age = int(o.age) + 1
		o.history.append({"turn": state.turn, "from": from, "to": r.dest})
		state.moves.append({"id": o.id, "from": from, "to": r.dest, "path": r.path.duplicate(), "result": ""})
		var path: Array = r.path
		var detonated := false
		for i in range(1, path.size()):
			var h: Vector2i = path[i]
			o.pos = h
			if _ordnance_contact(state, map, o, h, r):
				detonated = true
				break
		if detonated: continue
		o.pos = r.dest
		if r.offmap:
			state.ordnance.erase(o)
			continue
		if int(o.age) >= ORDNANCE_LIFE:
			state.ordnance.erase(o)
			log_event(state, "%s si disperde dopo cinque turni" % ShipTypes.ORDNANCE_NAME[o.kind], "ordnance")

## Contatto di un ordigno mentre entra nell'esagono h. Restituisce true se detona.
static func _ordnance_contact(state: Dictionary, map: Dictionary, o: Dictionary, h: Vector2i, r: Dictionary) -> bool:
	state.blame = o.owner
	var hit := _ordnance_contact_inner(state, map, o, h, r)
	state.blame = ""
	return hit

static func _ordnance_contact_inner(state: Dictionary, map: Dictionary, o: Dictionary, h: Vector2i, r: Dictionary) -> bool:
	if r.crash != "" and h == r.path[-1]:
		var body := SolarMap.body(map, r.crash)
		if o.kind == "nuke": _nuke_planet(state, map, o, body)
		else: log_event(state, "%s impatta su %s" % [ShipTypes.ORDNANCE_NAME[o.kind], body.name], "ordnance")
		fx(state, "blast", h)
		state.ordnance.erase(o)
		return true
	if state.special.has(h):
		if o.kind == "nuke":
			state.special.erase(h)
			log_event(state, "Una testata nucleare apre un varco negli asteroidi speciali", "ordnance")
		fx(state, "blast", h)
		state.ordnance.erase(o)
		return true
	var targets: Array = state.ships.filter(func(x): return alive(x) and x.pos == h and x.landed == "" and not x.get("dummy", false))
	if o.kind == "nuke":
		var asteroid: bool = state.asteroids.has(h)
		var base_here := false
		for b in state.bases:
			if b.active and int(b.side) < 0 and SolarMap.body(map, b.body).hex == h: base_here = true
		if targets.is_empty() and not asteroid and not base_here: return false
		for t in targets: _destroy(state, t, "annientata da una testata nucleare")
		if asteroid:
			state.asteroids.erase(h)
			log_event(state, "Una testata nucleare polverizza un campo di asteroidi", "ordnance")
		for b in state.bases:
			if b.active and int(b.side) < 0 and SolarMap.body(map, b.body).hex == h:
				b.active = false
				log_event(state, "Base di %s distrutta da una testata nucleare" % SolarMap.body(map, b.body).name, "ordnance")
		fx(state, "nuke", h)
		state.ordnance.erase(o)
		for other in state.ordnance.duplicate():
			if other.pos == h: state.ordnance.erase(other)
		return true
	# mine e siluri: navi, poi altri ordigni (le testate contano come navi)
	if not targets.is_empty():
		if o.kind == "mine":
			_detonate_mine(state, o, h)
		else:
			fx(state, "blast", h)
			state.ordnance.erase(o)
			for t in targets:
				var die := roll(state)
				var res: String = ITEM_TABLE.torpedo[die - 1]
				log_event(state, "Siluro contro %s: dado %d → %s" % [t.name, die, _res_text(res)], "combat")
				_apply_damage(state, t, res, "siluro")
				if res != "-": break
		return true
	for other in state.ordnance:
		if other == o or other.pos != h: continue
		fx(state, "blast", h)
		state.ordnance.erase(o)
		if other.kind == "nuke":
			var die2 := roll(state)
			var table: Array = ITEM_TABLE[o.kind]
			if table[die2 - 1] != "-":
				state.ordnance.erase(other)
				log_event(state, "%s neutralizza una testata nucleare" % ShipTypes.ORDNANCE_NAME[o.kind], "ordnance")
		else:
			state.ordnance.erase(other)
			log_event(state, "Due ordigni si annullano a vicenda", "ordnance")
		return true
	return false

static func _detonate_mine(state: Dictionary, o: Dictionary, h: Vector2i) -> void:
	state.ordnance.erase(o)
	fx(state, "blast", h)
	for t in state.ships:
		if not alive(t) or t.pos != h or t.landed != "" or t.get("dummy", false): continue
		var die := roll(state)
		var res: String = ITEM_TABLE.mine[die - 1]
		log_event(state, "Mina contro %s: dado %d → %s" % [t.name, die, _res_text(res)], "combat")
		_apply_damage(state, t, res, "mina")

static func _nuke_planet(state: Dictionary, map: Dictionary, o: Dictionary, body: Dictionary) -> void:
	var from: Vector2i = o.history[-1].from if not o.history.is_empty() else o.pos
	var side := Hex.dir_index(_nearest_dir(from, body.hex))
	if side < 0: side = 0
	state.devastated.append({"body": body.id, "side": side})
	for b in state.bases:
		if b.body == body.id and int(b.side) == side: b.active = false
	for s in state.ships:
		if alive(s) and s.landed == body.id and int(s.side) == side: _destroy(state, s, "distrutta al suolo da una testata nucleare")
	log_event(state, "Testata nucleare su %s: lato %d devastato" % [body.name, side + 1], "combat")
	fx(state, "nuke", body.hex)

static func _nearest_dir(from: Vector2i, center: Vector2i) -> Vector2i:
	var best := Hex.DIRS[0]; var best_d := 1e9
	var p := Hex.to_point(from) - Hex.to_point(center)
	for d in Hex.DIRS:
		var dd := Hex.to_point(d).normalized().distance_to(p.normalized())
		if dd < best_d: best_d = dd; best = d
	return best

static func _announce_hazards(state: Dictionary) -> void:
	for hz in state.hazards:
		var s := ship(state, hz.ship)
		if s.is_empty(): continue
		log_event(state, "Asteroidi: %s, dado %d → %s" % [s.name, hz.die, _res_text(hz.result)], "hazard")
		fx(state, "rock", hz.hex)
	state.hazards = []

# ---------------------------------------------------------------- danni

static func _res_text(res: String) -> String:
	if res == "-": return "nessun effetto"
	if res == "E": return "eliminata"
	return "disabilitata %s turni" % res.substr(1)

static func _destroy(state: Dictionary, s: Dictionary, why: String) -> void:
	if s.destroyed: return
	s.killed_by = state.get("blame", "")
	s.destroyed = true
	s.reason = why
	s.lost_turn = int(state.turn)
	log_event(state, "%s %s" % [s.name, why], "loss")
	fx(state, "explosion", s.pos)
	Scenarios.on_destroyed(state, s)

static func _apply_damage(state: Dictionary, s: Dictionary, res: String, source: String) -> void:
	if res == "-" or not alive(s): return
	if res == "E":
		_destroy(state, s, "eliminata (%s)" % source)
		return
	var n := int(res.substr(1))
	var tpt := ticks_per_turn(state)
	var now := tick(state)
	var base_until := maxi(int(s.disabled_until), now)
	var until := base_until + n * tpt
	if until - now >= 6 * tpt:
		_destroy(state, s, "distrutta: danni cumulativi")
		return
	s.disabled_until = until
	s.disabled_by = state.get("blame", "")
	fx(state, "hit", s.pos)

# ---------------------------------------------------------------- combattimento

static func odds_column(att: int, def: int) -> int:
	if def <= 0: return 4
	if att * 2 < def: return -1
	if att < def: return 0
	if att < def * 2: return 1
	if att < def * 3: return 2
	if att < def * 4: return 3
	return 4

static func can_fire(state: Dictionary, s: Dictionary) -> bool:
	if not alive(s) or s.commercial or s.landed != "" or s.get("dummy", false) or s.surrendered: return false
	if is_disabled(state, s) and s.type != "dreadnought": return false
	if int(s.resupplied_seg) == seg_key(state): return false
	return true

static func can_be_attacked(state: Dictionary, attacker_owner: String, t: Dictionary) -> bool:
	if not alive(t) or t.owner == attacker_owner or t.landed != "" or t.get("dummy", false): return false
	if t.surrendered: return false
	return is_known(state, attacker_owner, t)

static func is_known(state: Dictionary, viewer: String, t: Dictionary) -> bool:
	if t.owner == viewer: return true
	if not state.rules.get("hidden", false): return true
	return state.knowledge.get(viewer, {}).get(t.id, false)

## Valori di distanza e velocità relativa per un gruppo (si usano i peggiori).
static func fire_modifiers(state: Dictionary, attackers: Array, targets: Array) -> Dictionary:
	var rng := 0; var rv := 0
	for a in attackers:
		var course: Array = a.last_path if not a.last_path.is_empty() else [a.pos]
		for t in targets:
			var best := 999
			for h in course: best = mini(best, Hex.distance(h, t.pos))
			rng = maxi(rng, best)
			rv = maxi(rv, Hex.distance(a.vel, t.vel))
	return {"range": rng, "rv": rv}

static func attack_preview(state: Dictionary, attackers: Array, targets: Array) -> Dictionary:
	var att := 0; var def := 0
	for a in attackers: att += int(a.combat)
	for t in targets: def += int(t.combat)
	var m := fire_modifiers(state, attackers, targets)
	var heroic := not attackers.is_empty() and attackers.all(func(a): return a.heroic)
	var mod := -int(m.range) - maxi(0, int(m.rv) - 2) + (1 if heroic else 0)
	var col := odds_column(att, def)
	var chances := {}
	if col >= 0:
		for die in range(1, 7):
			var md := die + mod
			var res: String = "-" if md < 1 else GUN_TABLE[col][mini(md, 6) - 1]
			chances[res] = chances.get(res, 0) + 1
	return {"att": att, "def": def, "column": col, "odds": ODDS_LABELS[col] if col >= 0 else "< 1:2",
		"range": m.range, "rv": m.rv, "mod": mod, "heroic": heroic, "chances": chances}

static func declare_attack(state: Dictionary, attacker_ids: Array, target_ids: Array) -> String:
	if state.phase != "combat" or not state.pending_attack.is_empty(): return "Non è possibile attaccare ora."
	if not state.rules.get("combat", true): return "Combattimento non consentito in questo scenario."
	var me := current_player(state)
	var t_now := tick(state)
	var attackers: Array = []; var targets: Array = []
	for id in attacker_ids:
		var a := ship(state, id)
		if a.is_empty() or a.owner != me or not can_fire(state, a): return "%s non può aprire il fuoco." % (a.name if not a.is_empty() else "?")
		if int(a.attacked_tick) == t_now: return "%s ha già attaccato in questa fase." % a.name
		attackers.append(a)
	if attackers.is_empty(): return "Scegli almeno una nave attaccante."
	var hex := Vector2i(9999, 9999)
	for id in target_ids:
		var t := ship(state, id)
		if t.is_empty() or not can_be_attacked(state, me, t): return "Bersaglio non valido."
		if int(t.targeted_tick) == t_now: return "%s è già stata attaccata in questa fase." % t.name
		if hex.x != 9999 and t.pos != hex: return "I bersagli di un attacco devono stare nello stesso esagono."
		hex = t.pos
		targets.append(t)
	if targets.is_empty(): return "Scegli un bersaglio."
	state.pending_attack = {"attackers": attacker_ids.duplicate(), "targets": target_ids.duplicate(), "defender": targets[0].owner}
	return ""

## Navi del difensore che possono contrattaccare: i bersagli e chi condivide la loro rotta.
static func counter_candidates(state: Dictionary) -> Array:
	var pa: Dictionary = state.pending_attack
	if pa.is_empty(): return []
	var out: Array = []
	for tid in pa.targets:
		var t := ship(state, tid)
		for s in state.ships:
			if s.owner != pa.defender or out.has(s.id) or not alive(s) or s.commercial or s.landed != "" or s.get("dummy", false): continue
			if is_disabled(state, s) and s.type != "dreadnought": continue
			if s.id == tid or (s.pos == t.pos and s.vel == t.vel): out.append(s.id)
	return out

static func resolve_attack(state: Dictionary, counter_ids: Array, counter_target_ids: Array) -> String:
	var pa: Dictionary = state.pending_attack
	if pa.is_empty(): return "Nessun attacco in corso."
	var attackers: Array = pa.attackers.map(func(id): return ship(state, id))
	var targets: Array = pa.targets.map(func(id): return ship(state, id))
	var allowed := counter_candidates(state)
	var counters: Array = []
	for id in counter_ids:
		if allowed.has(id): counters.append(ship(state, id))
	var counter_targets: Array = []
	for id in counter_target_ids:
		if pa.attackers.has(id): counter_targets.append(ship(state, id))
	var t_now := tick(state)
	var main := _gun_roll(state, attackers, targets)
	var counter := {}
	if not counters.is_empty() and not counter_targets.is_empty():
		counter = _gun_roll(state, counters, counter_targets)
	for a in attackers: a.attacked_tick = t_now; a.fired_seg = seg_key(state)
	for t in targets: t.targeted_tick = t_now
	var names_a := ", ".join(attackers.map(func(x): return x.name))
	var names_t := ", ".join(targets.map(func(x): return x.name))
	log_event(state, "Fuoco: %s → %s a %s (dado %d, mod %+d): %s" % [names_a, names_t, main.odds, main.die, main.mod, _res_text(main.result)], "combat")
	if not counter.is_empty():
		log_event(state, "Contrattacco a %s (dado %d, mod %+d): %s" % [counter.odds, counter.die, counter.mod, _res_text(counter.result)], "combat")
	# i danni sono applicati dopo entrambi i tiri
	state.blame = attackers[0].owner
	for t in targets: _apply_damage(state, t, main.result, "fuoco")
	if not counter.is_empty():
		state.blame = pa.defender
		for a in counter_targets: _apply_damage(state, a, counter.result, "contrattacco")
	state.blame = ""
	if int(main.column) == 0 and main.result in ["D2", "D3", "D4", "D5", "E"]:
		for a in attackers:
			if not a.heroic and alive(a):
				a.heroic = true
				log_event(state, "%s diventa EROICA (+1 agli attacchi futuri)" % a.name, "combat")
	if not counter.is_empty() and int(counter.column) == 0 and counter.result in ["D2", "D3", "D4", "D5", "E"]:
		for c in counters:
			if not c.heroic and alive(c): c.heroic = true
	state.last_combat = {"attackers": pa.attackers.duplicate(), "targets": pa.targets.duplicate(), "main": main, "counter": counter, "counter_targets": counter_target_ids.duplicate()}
	state.pending_attack = {}
	Scenarios.check_victory(state)
	return ""

static func _gun_roll(state: Dictionary, attackers: Array, targets: Array) -> Dictionary:
	var p := attack_preview(state, attackers, targets)
	var die := roll(state)
	var res := "-"
	if int(p.column) >= 0:
		var md := die + int(p.mod)
		res = "-" if md < 1 else GUN_TABLE[int(p.column)][mini(md, 6) - 1]
	p.die = die; p.result = res
	return p

static func cancel_attack(state: Dictionary) -> void:
	state.pending_attack = {}

static func _planetary_defense(state: Dictionary) -> void:
	var map := map_of(state)
	var me := current_player(state)
	for b in state.bases:
		if not b.active or not b.get("defense", false) or b.owner != me or int(b.side) < 0: continue
		var body := SolarMap.body(map, b.body)
		var hex: Vector2i = body.hex + Hex.DIRS[int(b.side)]
		var enemies: Array = state.ships.filter(func(s): return alive(s) and s.owner != me and not b.get("friends", []).has(s.owner) and s.pos == hex and s.landed == "" and not s.get("dummy", false) and not s.surrendered)
		if enemies.is_empty(): continue
		var die := roll(state)
		var res: String = GUN_TABLE[2][die - 1]
		log_event(state, "Difesa planetaria di %s: dado %d → %s" % [body.name, die, _res_text(res)], "combat")
		fx(state, "flak", hex)
		state.blame = me
		for s in enemies: _apply_damage(state, s, res, "difesa planetaria")
		state.blame = ""
	Scenarios.check_victory(state)

# ---------------------------------------------------------------- rifornimento

static func _do_resupply(state: Dictionary) -> void:
	var me := current_player(state)
	for s in state.ships:
		if s.owner != me or not alive(s) or s.get("dummy", false): continue
		if s.get("is_base", false): continue
		var b := docked_base(state, s)
		Scenarios.on_docked(state, s, b)
		if b.is_empty() or not friendly_base(state, b, s.owner) or not b.get("fuel", true): continue
		if int(s.fired_seg) == seg_key(state) or int(s.launched_seg) == seg_key(state): continue
		if b.get("orbital", false):
			var ob := ship(state, b.id)
			if int(ob.fired_seg) == seg_key(state) or int(ob.launched_seg) == seg_key(state): continue
			ob.resupplied_seg = seg_key(state)
		var refuelled: bool = not s.infinite_fuel and int(s.fuel) < int(s.max_fuel)
		var maintained: bool = not s.overload_ok and not s.commercial
		s.fuel = s.max_fuel
		s.overload_ok = true
		s.resupplied_seg = seg_key(state)
		if refuelled or maintained:
			log_event(state, "%s fa rifornimento e manutenzione a %s" % [s.name, base_name(state, b)], "supply")
		Scenarios.on_resupply(state, s, b)

## Carico di ordigni in base durante la fase di rifornimento.
static func can_load(state: Dictionary, s: Dictionary, kind: String) -> String:
	if state.phase != "resupply" or s.owner != current_player(state) or not alive(s): return "Solo nella tua fase di rifornimento."
	if not state.rules.get("ordnance", true): return "Ordigni non disponibili in questo scenario."
	if kind == "nuke" and not state.rules.get("nukes", false): return "Testate nucleari non disponibili."
	var b := docked_base(state, s)
	if b.is_empty() or not friendly_base(state, b, s.owner) or not b.get("ordnance", true): return "Serve una base amica che fornisca ordigni."
	if b.has("ordnance_kinds") and not b.ordnance_kinds.has(kind): return "Questa base non fornisce questo ordigno."
	var stock_err := Scenarios.stock_check(state, s, b, kind)
	if stock_err != "": return stock_err
	if int(s.fired_seg) == seg_key(state) or int(s.launched_seg) == seg_key(state): return "Chi ha sparato o lanciato in questo turno non può rifornirsi."
	if not ShipTypes.can_carry(s, kind): return "Stiva insufficiente o carico non ammesso."
	return ""

static func load_ordnance(state: Dictionary, ship_id: String, kind: String) -> String:
	var s := ship(state, ship_id)
	var err := can_load(state, s, kind)
	if err != "": return err
	s.inv[kind] = int(s.inv[kind]) + 1
	Scenarios.stock_take(state, s, docked_base(state, s), kind, 1)
	log_event(state, "%s carica: %s" % [s.name, ShipTypes.ORDNANCE_NAME[kind].to_lower()], "supply")
	return ""

static func unload_ordnance(state: Dictionary, ship_id: String, kind: String) -> String:
	var s := ship(state, ship_id)
	if s.is_empty() or int(s.inv.get(kind, 0)) <= 0: return "Niente da scaricare."
	if docked_base(state, s).is_empty() or state.phase != "resupply": return "Solo in base durante il rifornimento."
	s.inv[kind] = int(s.inv[kind]) - 1
	Scenarios.stock_take(state, s, docked_base(state, s), kind, -1)
	return ""

static func matched(a: Dictionary, b: Dictionary) -> bool:
	return alive(a) and alive(b) and a.pos == b.pos and a.vel == b.vel and a.landed == "" and b.landed == ""

## Trasferimento di carburante fra navi con rotta accoppiata (soccorso).
static func transfer_fuel(state: Dictionary, from_id: String, to_id: String, amount: int) -> String:
	if state.phase != "resupply": return "Solo durante il rifornimento."
	var a := ship(state, from_id); var b := ship(state, to_id)
	if a.is_empty() or b.is_empty() or not matched(a, b): return "Le navi devono avere stessa posizione e stesso vettore."
	if a.owner != current_player(state): return "Puoi cedere solo il tuo carburante."
	if a.infinite_fuel: return "Le navi torcia non possono cedere carburante."
	if b.owner != a.owner and not (is_disabled(state, b) or b.surrendered): return "Si può saccheggiare solo una nave disabilitata o arresa."
	var n := mini(amount, mini(int(a.fuel), int(b.max_fuel) - int(b.fuel)))
	if n <= 0: return "Nessun carburante trasferibile."
	a.fuel = int(a.fuel) - n; b.fuel = int(b.fuel) + n
	log_event(state, "%s trasferisce %d carburante a %s" % [a.name, n, b.name], "supply")
	return ""

static func surrender(state: Dictionary, ship_id: String) -> String:
	var s := ship(state, ship_id)
	if s.is_empty() or s.owner != current_player(state): return "Nave non tua."
	if not state.rules.get("surrender", false): return "La resa non è prevista in questo scenario."
	if s.get("patrol", false): return "Il Terran Space Patrol non si arrende mai."
	s.surrendered = true
	log_event(state, "%s si arrende" % s.name, "combat")
	return ""

# ---------------------------------------------------------------- rilevamento

static func _update_detection(state: Dictionary) -> void:
	if not state.rules.get("hidden", false): return
	var map := map_of(state)
	for viewer in player_ids(state):
		var k: Dictionary = state.knowledge.get(viewer, {})
		for t in state.ships:
			if t.owner == viewer or not alive(t) or t.get("dummy", false): continue
			if k.get(t.id, false): continue
			var seen := false
			for o in state.ships:
				if o.owner == viewer and alive(o) and not o.get("dummy", false) and Hex.distance(o.pos, t.pos) <= 3: seen = true; break
			if not seen:
				for b in state.bases:
					if b.active and b.owner == viewer and Hex.distance(SolarMap.body(map, b.body).hex, t.pos) <= 5: seen = true; break
			if seen:
				k[t.id] = true
				log_event(state, "%s rileva %s" % [player(state, viewer).name, t.name], "detect")
				Scenarios.on_detected(state, viewer, t)
		state.knowledge[viewer] = k
	# una nave che raggiunge una base amica torna nascosta
	for t in state.ships:
		if not alive(t): continue
		var b := docked_base(state, t)
		if not b.is_empty() and b.owner == t.owner:
			for viewer in player_ids(state):
				if viewer != t.owner: state.knowledge[viewer].erase(t.id)
