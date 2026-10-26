class_name Scenarios
extends RefCounted
## Allestimento degli scenari e regole speciali/vittoria (capitolo 9 del manuale).

const PLAYER_COLORS := ["#ff8a3d", "#3fb6ff", "#43e08f", "#f2d94e", "#e46bff", "#e8e8e8"]

const CATALOG := [
	{"id": "grand-tour", "title": "Grand Tour", "year": "2037 AD", "players": "2–6", "min": 2, "max": 6, "length": "Corsa",
		"playable": true, "ai": true,
		"blurb": "Gara attorno al Sistema Solare: attraversa un campo di gravità piena di ogni corpo e torna ad atterrare sulla Terra. Carburante gratuito solo su Terra, Venere, Marte e Callisto.",
		"sides": ["Pilota", "Pilota", "Pilota", "Pilota", "Pilota", "Pilota"]},
	{"id": "escape", "title": "Escape", "year": "", "players": "2", "min": 2, "max": 2, "length": "Breve",
		"playable": true, "ai": true,
		"blurb": "Tre trasporti dei Pellegrini lasciano la Terra: uno solo porta i fuggitivi. Devono uscire oltre Giove prima che gli Enforcers li catturino.",
		"sides": ["Pellegrini", "Enforcers"]},
	{"id": "lateral-7", "title": "Lateral 7", "year": "", "players": "2", "min": 2, "max": 2, "length": "Breve",
		"playable": true, "ai": true,
		"blurb": "Pirati nascosti fra gli asteroidi, falsi bersagli e un dreadnought di guardia: riusciranno a rapire i passeggeri della nave di linea diretta a Ganimede?",
		"sides": ["Pirati", "Marina"]},
	{"id": "nova", "title": "Nova", "year": "", "players": "3", "min": 3, "max": 3, "length": "Breve", "playable": false, "ai": false,
		"blurb": "EastBloc e WestBloc contro quattro corsari alieni armati di bombe Nova diretti verso il Sole.", "sides": []},
	{"id": "retribution", "title": "Retribution", "year": "", "players": "2", "min": 2, "max": 2, "length": "Breve", "playable": false, "ai": false,
		"blurb": "Dieci corvette dei Figli della Libertà, una alla volta, contro gli Enforcers.", "sides": []},
	{"id": "fleet-mutiny", "title": "The Fleet Mutiny", "year": "", "players": "2", "min": 2, "max": 2, "length": "Breve", "playable": false, "ai": false,
		"blurb": "Una flotta imperiale di dodici navi: cinque potrebbero ammutinarsi e colpire la Terra.", "sides": []},
	{"id": "interplanetary-war", "title": "Interplanetary War", "year": "", "players": "2", "min": 2, "max": 2, "length": "Lunga", "playable": false, "ai": false,
		"blurb": "Guerra economica e militare fra la Terra e le colonie ribelli, in MegaCrediti.", "sides": []},
	{"id": "prospecting", "title": "Prospecting", "year": "", "players": "2+", "min": 2, "max": 6, "length": "Lunga", "playable": false, "ai": false,
		"blurb": "Corsa all'oro nella Fascia: minerale, schegge di antimateria e mercati di Ceres e Luna.", "sides": []},
]

static func info(id: String) -> Dictionary:
	for c in CATALOG:
		if c.id == id: return c
	return {}

## seats: [{name, type:"human"|"ai"}]  options: {sol_classic, liner_terra, seed}
static func create(id: String, seats: Array, options: Dictionary = {}) -> Dictionary:
	var state := _base_state(id, seats, options)
	match id:
		"grand-tour": _setup_grand_tour(state)
		"escape": _setup_escape(state)
		"lateral-7": _setup_lateral7(state)
	Rules._update_detection(state)
	return state

static func _base_state(id: String, seats: Array, options: Dictionary) -> Dictionary:
	var players := []
	for i in range(seats.size()):
		var info_c := info(id)
		var side_name: String = info_c.sides[i] if i < info_c.sides.size() else "Giocatore"
		players.append({"id": "P%d" % (i + 1), "name": seats[i].get("name", "Giocatore %d" % (i + 1)), "type": seats[i].get("type", "human"),
			"color": PLAYER_COLORS[i % PLAYER_COLORS.size()], "side": side_name})
	var map := SolarMap.get_map(options.get("sol_classic", false))
	var seed_value: int = int(options.get("seed", Time.get_ticks_usec() & 0x7fffffff))
	var knowledge := {}
	for p in players: knowledge[p.id] = {}
	return {
		"version": 2, "scenario": id, "options": options.duplicate(), "rng": seed_value, "seed": seed_value,
		"turn": 1, "seg": 0, "phase": "astrogation", "players": players,
		"ships": [], "ordnance": [], "bases": [], "plots": {}, "knowledge": knowledge,
		"asteroids": map.asteroids.duplicate(), "special": map.special_asteroids.duplicate(),
		"devastated": [], "pending_attack": {}, "last_combat": {}, "hazards": [], "fx": [], "moves": [],
		"log": [], "next_id": 0, "winner": "", "result": "", "over": false,
		"rules": {"combat": true, "ordnance": true, "ram": true, "hidden": false, "surrender": false, "nukes": false},
		"sd": {}, "setup": {},
	}

static func _add_bases(state: Dictionary, body_ids: Array, owner: String, extra: Dictionary = {}) -> void:
	var map := Rules.map_of(state)
	for bid in body_ids:
		var b := SolarMap.body(map, bid)
		if b.asteroid_base:
			var base := {"id": "base-%s" % bid, "body": bid, "side": -1, "owner": owner, "active": true, "defense": false, "fuel": true, "ordnance": true, "kind": "asteroid"}
			base.merge(extra, true)
			base.defense = false
			state.bases.append(base)
		else:
			for side in b.base_sides:
				var base2 := {"id": "base-%s-%d" % [bid, side], "body": bid, "side": side, "owner": owner, "active": true, "defense": true, "fuel": true, "ordnance": true, "kind": "planetary"}
				base2.merge(extra, true)
				state.bases.append(base2)

static func _land(s: Dictionary, map: Dictionary, body_id: String, side: int) -> void:
	var b := SolarMap.body(map, body_id)
	s.pos = b.hex; s.vel = Vector2i.ZERO; s.landed = body_id; s.side = side

static func _orbit(s: Dictionary, map: Dictionary, body_id: String, side: int) -> void:
	var b := SolarMap.body(map, body_id)
	var d: Vector2i = Hex.DIRS[side]
	s.pos = b.hex + d
	s.vel = Hex.DIRS[(side + 1) % 6]
	s.grav = [-d]
	s.history = [{"turn": 0, "from": b.hex + Hex.DIRS[(side + 5) % 6], "to": s.pos, "burns": [], "note": "orbita"}]
	s.last_path = [b.hex + Hex.DIRS[(side + 5) % 6], s.pos]
	if not s.visited.has(body_id) and b.gravity in ["full", "sol"]: s.visited.append(body_id)

# ---------------------------------------------------------------- Grand Tour

static func _setup_grand_tour(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	state.rules.ordnance = false
	_add_bases(state, ["terra", "venus", "mars", "callisto"], "all", {"defense": false})
	_add_bases(state, ["mercury", "luna", "io", "ganymede", "ceres", "clandestine"], "all", {"defense": false, "fuel": false})
	var sides := [0, 3, 1, 4, 2, 5]
	for i in range(state.players.size()):
		var p: Dictionary = state.players[i]
		var s := ShipTypes.make("gt-%d" % (i + 1), p.id, "corvette", "Corvetta di %s" % p.name)
		_land(s, map, "terra", sides[i])
		s.visited = ["terra"]
		state.ships.append(s)
	state.sd = {"required": SolarMap.full_gravity_bodies(map), "finishers": []}
	Rules.log_event(state, "Grand Tour 2037: si parte dalla Terra. Visita un campo di gravità piena di ogni corpo e rientra.", "info")

static func grand_tour_progress(state: Dictionary, s: Dictionary) -> Array:
	var out := []
	for b in state.sd.get("required", []): out.append({"id": b, "done": s.visited.has(b)})
	return out

# ---------------------------------------------------------------- Escape

static func _setup_escape(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	state.rules.ordnance = false
	state.rules.ram_players = ["P1"]
	_add_bases(state, ["terra", "venus", "io"], "P2", {"defense": false})
	var letters := ["A", "B", "C"]
	var sides := [0, 2, 4]
	for i in range(3):
		var s := ShipTypes.make("pilgrim-%s" % letters[i].to_lower(), "P1", "transport", "Trasporto %s" % letters[i])
		_land(s, map, "terra", sides[i])
		s.free_takeoff = true
		state.ships.append(s)
	var c := ShipTypes.make("enf-corvette", "P2", "corvette", "Corvetta Enforcer")
	_orbit(c, map, "terra", 3)
	c.patrol = true
	state.ships.append(c)
	var k := ShipTypes.make("enf-corsair", "P2", "corsair", "Corsaro Enforcer")
	_orbit(k, map, "venus", 0)
	k.patrol = true
	state.ships.append(k)
	state.sd = {"fugitive": "", "captured_by": "", "inspected": []}
	state.phase = "setup"
	state.setup = {"step": "fugitive", "player": "P1"}
	Rules.log_event(state, "Escape: i Pellegrini scelgono in segreto il trasporto dei fuggitivi.", "info")

static func choose_fugitive(state: Dictionary, ship_id: String) -> String:
	if state.scenario != "escape" or state.phase != "setup": return "Non ora."
	var s := Rules.ship(state, ship_id)
	if s.is_empty() or s.owner != "P1": return "Scegli uno dei tre trasporti."
	state.sd.fugitive = ship_id
	state.phase = "astrogation"
	state.setup = {}
	Rules.log_event(state, "I fuggitivi sono a bordo. Giorno 1: i Pellegrini possono decollare.", "info")
	return ""

static func inspect(state: Dictionary, inspector_id: String, target_id: String) -> String:
	if state.scenario != "escape" or state.phase != "resupply": return "Ispezione solo nella fase di rifornimento."
	var a := Rules.ship(state, inspector_id); var t := Rules.ship(state, target_id)
	if a.is_empty() or t.is_empty() or a.owner != "P2" or t.owner != "P1" or a.owner != Rules.current_player(state): return "Ispezione non valida."
	if not Rules.matched(a, t): return "Per ispezionare serve la stessa posizione e lo stesso vettore."
	if not state.sd.inspected.has(t.id): state.sd.inspected.append(t.id)
	var is_fugitive: bool = state.sd.fugitive == t.id
	Rules.log_event(state, "%s ispeziona %s: %s" % [a.name, t.name, "A BORDO CI SONO I FUGGITIVI!" if is_fugitive else "è un'esca"], "detect")
	if is_fugitive and (Rules.is_disabled(state, t) or t.surrendered):
		t.captured = true
		state.sd.captured_by = a.id
		Rules.log_event(state, "I Pellegrini sono catturati: %s deve riportarli a una base." % a.name, "combat")
	check_victory(state)
	return ""

# ---------------------------------------------------------------- Lateral 7

const L7_NAVY := [["l7-dread", "dreadnought", "Tycho Brahe 101"], ["l7-nd1", "dummy", ""], ["l7-nd2", "dummy", ""], ["l7-nd3", "dummy", ""]]
const L7_PIRATES := [["l7-cor1", "corsair", "Corsaro pirata Ombra"], ["l7-cor2", "corsair", "Corsaro pirata Vespa"], ["l7-crv", "corvette", "Corvetta pirata Gazza"],
	["l7-pd1", "dummy", ""], ["l7-pd2", "dummy", ""], ["l7-pd3", "dummy", ""], ["l7-pd4", "dummy", ""], ["l7-pd5", "dummy", ""],
	["l7-pd6", "dummy", ""], ["l7-pd7", "dummy", ""], ["l7-pd8", "dummy", ""], ["l7-pd9", "dummy", ""]]

static func _setup_lateral7(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	state.rules.hidden = true
	state.rules.surrender = true
	_add_bases(state, ["mars", "terra", "callisto"], "P2")
	# porto civile di Venere: solo il booster per la nave di linea, niente rifornimenti
	_add_bases(state, ["venus"], "P2", {"defense": false, "fuel": false, "ordnance": false})
	# Clandestine: carburante, manutenzione e solo mine per i pirati
	_add_bases(state, ["clandestine"], "P1", {"ordnance_kinds": ["mine"]})
	var liner := ShipTypes.make("l7-liner", "P2", "liner", "Nave di linea Lateral 7")
	_land(liner, map, "terra" if state.options.get("liner_terra", false) else "venus", 0)
	liner.passengers = true
	state.ships.append(liner)
	for p in state.players:
		state.knowledge[p.id][liner.id] = true
	state.sd = {"passengers": liner.id, "queue": {"P2": L7_NAVY.duplicate(true), "P1": L7_PIRATES.duplicate(true)}}
	state.phase = "setup"
	state.seg = 1
	state.setup = {"step": "place", "player": "P2"}
	Rules.log_event(state, "Lateral 7: la Marina colloca il dreadnought e tre falsi bersagli negli asteroidi.", "info")

static func next_placement(state: Dictionary) -> Array:
	if state.phase != "setup" or state.setup.get("step", "") != "place": return []
	var q: Array = state.sd.queue.get(state.setup.player, [])
	return q[0] if not q.is_empty() else []

static func can_place(state: Dictionary, hex: Vector2i) -> bool:
	if not state.asteroids.has(hex): return false
	for s in state.ships:
		if Rules.alive(s) and s.pos == hex and s.landed == "": return false
	return true

static func place(state: Dictionary, hex: Vector2i) -> String:
	var unit := next_placement(state)
	if unit.is_empty(): return "Nessuna pedina da collocare."
	if not can_place(state, hex): return "Colloca in un esagono di asteroidi libero."
	var owner: String = state.setup.player
	var s: Dictionary
	if unit[1] == "dummy":
		s = ShipTypes.make(unit[0], owner, "corvette", "Falso bersaglio")
		s.dummy = true
		s.combat = 0
	else:
		s = ShipTypes.make(unit[0], owner, unit[1], unit[2])
		s.first_burn_pending = true
		if unit[1] == "corsair": s.inv.mine = 1
		if unit[1] == "dreadnought":
			s.inv.mine = 1; s.inv.torpedo = 1; s.locked = true; s.first_burn_pending = true
		if owner == "P1": s.access_special = true
	s.pos = hex
	s.concealed = true
	state.ships.append(s)
	state.sd.queue[owner].pop_front()
	if state.sd.queue[owner].is_empty():
		if owner == "P2":
			state.setup.player = "P1"
			state.seg = 0
			Rules.log_event(state, "La Marina ha schierato. Ora i Pirati collocano tre navi e nove falsi bersagli.", "info")
		else:
			state.setup = {}
			state.phase = "astrogation"
			state.seg = 0
			Rules.log_event(state, "Schieramento completo. Giorno 1: muovono i Pirati.", "info")
	return ""

static func auto_place(state: Dictionary) -> void:
	var owner: String = state.setup.get("player", "")
	var free: Array = state.asteroids.filter(func(h): return can_place(state, h))
	var map := Rules.map_of(state)
	# la Marina preferisce la Fascia vicina alle rotte interne, i pirati vicino a Clandestine
	var anchor: Vector2i = SolarMap.body(map, "clandestine" if owner == "P1" else "ceres").hex
	free.sort_custom(func(a, b): return Hex.distance(a, anchor) < Hex.distance(b, anchor))
	var rng_pick := func(n: int) -> int: return Rules.roll(state) % n
	while state.phase == "setup" and state.setup.get("player", "") == owner and not free.is_empty():
		var window: int = mini(free.size(), 14)
		var idx: int = rng_pick.call(window)
		var h: Vector2i = free[idx]
		free.remove_at(idx)
		place(state, h)

static func remove_dummies(state: Dictionary, owner: String, chosen: Array) -> void:
	var mine: Array = state.ships.filter(func(s): return s.owner == owner and s.get("dummy", false) and Rules.alive(s))
	var picked: Array = []
	for id in chosen:
		for d in mine:
			if d.id == id and not picked.has(d): picked.append(d)
	for d in mine:
		if picked.size() >= 3: break
		if not picked.has(d): picked.append(d)
	for d in picked.slice(0, 3):
		d.destroyed = true
		d.reason = "rimosso"
	if not picked.is_empty():
		Rules.log_event(state, "%s ritira tre falsi bersagli" % Rules.player(state, owner).name, "detect")

static func transfer_passengers(state: Dictionary, from_id: String, to_id: String) -> String:
	if state.scenario != "lateral-7" or state.phase != "resupply": return "Solo durante il rifornimento."
	var a := Rules.ship(state, from_id); var b := Rules.ship(state, to_id)
	if a.is_empty() or b.is_empty() or state.sd.passengers != a.id: return "Quella nave non ha i passeggeri."
	if b.owner != Rules.current_player(state): return "Solo il giocatore in fase può prendere i passeggeri."
	if not Rules.matched(a, b): return "Serve stessa posizione e stesso vettore."
	if a.owner != b.owner and not (Rules.is_disabled(state, a) or a.surrendered): return "La nave di linea va prima disabilitata o deve arrendersi."
	a.passengers = false; b.passengers = true
	state.sd.passengers = b.id
	Rules.log_event(state, "I passeggeri passano da %s a %s" % [a.name, b.name], "combat")
	check_victory(state)
	return ""

# ---------------------------------------------------------------- ganci chiamati dalle regole

static func player_has_reinforcements(_state: Dictionary, _pid: String) -> bool:
	return false

static func after_movement(state: Dictionary) -> void:
	if state.scenario == "lateral-7":
		# i falsi bersagli entro la portata dei rilevatori nemici vengono smascherati
		var map := Rules.map_of(state)
		for d in state.ships:
			if not d.get("dummy", false) or not Rules.alive(d): continue
			var exposed := false
			for o in state.ships:
				if o.owner != d.owner and Rules.alive(o) and not o.get("dummy", false) and Hex.distance(o.pos, d.pos) <= 3: exposed = true
			for b in state.bases:
				if b.active and b.owner != d.owner and b.owner != "all" and Hex.distance(SolarMap.body(map, b.body).hex, d.pos) <= 5: exposed = true
			if exposed:
				d.destroyed = true; d.reason = "smascherato"
				Rules.log_event(state, "Un falso bersaglio è stato smascherato e rimosso", "detect")

static func after_ship_move(_state: Dictionary, _s: Dictionary) -> void:
	pass

static func on_first_burn(state: Dictionary, s: Dictionary) -> void:
	if state.scenario != "lateral-7": return
	var plot: Dictionary = state.plots.get(s.id, {})
	remove_dummies(state, s.owner, plot.get("dummies", []))

static func on_detected(state: Dictionary, viewer: String, t: Dictionary) -> void:
	if state.scenario == "lateral-7" and viewer == "P2" and t.owner == "P1":
		for s in state.ships:
			if s.get("locked", false):
				s.locked = false
				Rules.log_event(state, "Pirata rilevato! Il Tycho Brahe può finalmente muovere.", "detect")

static func on_landed(state: Dictionary, s: Dictionary) -> void:
	if state.scenario == "grand-tour" and s.landed == "terra":
		var done := true
		for b in state.sd.required:
			if not s.visited.has(b): done = false
		if done and not state.sd.finishers.has(s.id):
			state.sd.finishers.append(s.id)
			s.finished_turn = state.turn
			Rules.log_event(state, "%s completa il Grand Tour il giorno %d con %d punti carburante consumati!" % [s.name, state.turn, s.fuel_spent], "victory")
	if state.scenario == "escape" and state.sd.captured_by == s.id:
		var b := Rules.base_at(state, s.landed, int(s.side))
		if Rules.friendly_base(state, b, s.owner): state.sd.returned = true
	check_victory(state)

static func on_exit_map(state: Dictionary, s: Dictionary, r: Dictionary) -> bool:
	if state.scenario == "escape" and s.owner == "P1" and r.dest.y < 0:
		s.escaped = true
		s.exit_speed = Hex.length(r.vel)
		Rules.log_event(state, "%s supera il bordo oltre Giove con %d carburante a velocità %d" % [s.name, s.fuel, s.exit_speed], "victory")
		return true
	return false

static func on_destroyed(state: Dictionary, s: Dictionary) -> void:
	if state.scenario == "lateral-7" and state.sd.get("passengers", "") == s.id:
		state.sd.passengers_lost = true
	if state.scenario == "escape" and state.sd.get("captured_by", "") == s.id:
		state.sd.fugitives_lost = true

static func on_resupply(_state: Dictionary, _s: Dictionary, _b: Dictionary) -> void:
	pass

static func end_of_turn(state: Dictionary) -> void:
	if state.scenario == "grand-tour" and not state.over:
		var fin: Array = state.sd.finishers.map(func(id): return Rules.ship(state, id))
		if not fin.is_empty():
			fin.sort_custom(func(a, b): return int(a.fuel_spent) < int(b.fuel_spent))
			var best := int(fin[0].fuel_spent)
			var winners: Array = fin.filter(func(x): return int(x.fuel_spent) == best)
			var names := " e ".join(winners.map(func(x): return Rules.player(state, x.owner).name))
			_finish(state, winners[0].owner if winners.size() == 1 else "pari", "%s %s il Grand Tour in %d giorni consumando %d carburante." % [names, "vince" if winners.size() == 1 else "vincono ex aequo", state.turn, best])

static func _finish(state: Dictionary, winner: String, text: String) -> void:
	if state.over: return
	state.over = true
	state.winner = winner
	state.result = text
	state.phase = "over"
	Rules.log_event(state, text, "victory")

static func check_victory(state: Dictionary) -> void:
	if state.over: return
	match state.scenario:
		"grand-tour":
			var any_alive: bool = state.ships.any(func(s): return Rules.alive(s))
			if not any_alive: _finish(state, "", "Tutte le corvette sono andate perdute: nessun vincitore.")
		"escape": _escape_victory(state)
		"lateral-7": _l7_victory(state)

static func _escape_victory(state: Dictionary) -> void:
	var fid: String = state.sd.get("fugitive", "")
	if fid == "": return
	var f := Rules.ship(state, fid)
	var enforcer_lost: bool = state.ships.any(func(s): return s.owner == "P2" and s.destroyed)
	var pilgrims: String = Rules.player(state, "P1").name
	var enforcers: String = Rules.player(state, "P2").name
	if f.escaped:
		if int(f.fuel) >= int(f.get("exit_speed", 0)) + 1:
			_finish(state, "P1", "Vittoria decisiva dei Pellegrini (%s): i fuggitivi lasciano il Sistema Solare con carburante per fermarsi." % pilgrims)
		else:
			_finish(state, "P1", "Vittoria marginale dei Pellegrini (%s): fuggitivi in salvo, ma senza carburante per fermarsi." % pilgrims)
	elif f.destroyed or state.sd.get("fugitives_lost", false):
		if enforcer_lost: _finish(state, "P1", "Vittoria morale dei Pellegrini (%s): perduti, ma hanno distrutto una nave Enforcer." % pilgrims)
		else: _finish(state, "P2", "Vittoria marginale degli Enforcers (%s): il trasporto dei fuggitivi è distrutto." % enforcers)
	elif f.captured and state.sd.get("returned", false):
		if enforcer_lost: _finish(state, "P1", "Vittoria morale dei Pellegrini (%s): catturati, ma un Enforcer è caduto." % pilgrims)
		else: _finish(state, "P2", "Vittoria decisiva degli Enforcers (%s): i Pellegrini sono catturati e riportati in base." % enforcers)
	elif not state.ships.any(func(s): return s.owner == "P2" and Rules.alive(s)) and not f.captured:
		pass

static func _l7_victory(state: Dictionary) -> void:
	if state.phase == "setup": return
	var holder := Rules.ship(state, state.sd.get("passengers", ""))
	var map := Rules.map_of(state)
	if state.sd.get("passengers_lost", false) or holder.is_empty() or holder.destroyed:
		_finish(state, "", "I passeggeri sono morti: entrambi i giocatori perdono.")
		return
	var dread_lost: bool = state.ships.any(func(s): return s.type == "dreadnought" and s.destroyed and not s.get("dummy", false))
	var pirate_lost: bool = state.ships.any(func(s): return s.owner == "P1" and s.destroyed and not s.get("dummy", false))
	if holder.owner == "P1":
		var cl := SolarMap.body(map, "clandestine")
		if holder.pos == cl.hex and holder.vel == Vector2i.ZERO:
			_finish(state, "P1", "%s dei Pirati: i passeggeri sono a Clandestine." % ("Vittoria decisiva" if dread_lost else "Vittoria"))
	elif holder.type == "liner" and holder.visited.has("ganymede"):
		_finish(state, "P2", "%s della Marina: la nave di linea raggiunge Ganimede." % ("Vittoria decisiva" if pirate_lost else "Vittoria"))
