class_name ScenRetribution
extends RefCounted
## RETRIBUTION — Figli della Libertà (P1) contro Enforcers (P2).
## Dieci corvette ribelli, una alla volta: a Clandestine per formare la Flotta della Libertà
## o in picchiata suicida sulla Terra. Gli Enforcers hanno tutte le basi tranne Clandestine.

const PLANETS := ["mercury", "venus", "terra", "mars", "jupiter"]
const NO_SPAWN := ["luna", "ceres", "terra", "clandestine"]
const TOTAL := 10

static func setup(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	state.rules.special_as_asteroids = true
	state.rules.ram_players = []
	state.bases = []
	for b in map.bodies:
		if b.id == "clandestine":
			state.bases.append({"id": "base-clandestine", "body": "clandestine", "side": -1, "owner": "P1", "active": true, "defense": false, "fuel": true, "ordnance": false, "kind": "asteroid"})
		elif b.asteroid_base:
			state.bases.append({"id": "base-%s" % b.id, "body": b.id, "side": -1, "owner": "P2", "active": true, "defense": false, "fuel": true, "ordnance": false, "kind": "asteroid"})
		else:
			for side in b.base_sides:
				state.bases.append({"id": "base-%s-%d" % [b.id, side], "body": b.id, "side": side, "owner": "P2", "active": true,
					"defense": b.id in ["terra", "luna"], "fuel": true, "ordnance": b.id == "terra", "kind": "planetary"})
	var fr := ShipTypes.make("enf-frigate", "P2", "frigate", "Fregata Enforcer Inquisitore")
	Scenarios._land(fr, map, "luna", int(SolarMap.body(map, "luna").base_sides[0]))
	state.ships.append(fr)
	state.sd = {"spawned": 0, "formed": false, "terra_hits": 0, "patrol": [], "enf_grounded": 0, "reb_grounded": 0, "parked": []}
	var q := [{"type": "corsair", "name": "Corsaro Enforcer Vindice"}, {"type": "corsair", "name": "Corsaro Enforcer Castigo"}]
	Fleet.open_deploy(state, "P2", q, {"orbit": PLANETS, "distinct_orbit": true}, "Enforcers: metti i due corsari in orbita attorno a pianeti diversi")
	Rules.log_event(state, "Retribution: la Fregata Enforcer è sulla Luna; i corsari prendono posizione in orbita.", "info")

static func step_done(state: Dictionary) -> void:
	var st: Dictionary = state.setup
	if st.step == "deploy" and st.player == "P2":
		state.phase = "astrogation"; state.seg = 0; state.turn = 1; state.setup = {}
		start_of_segment(state)
	elif st.step == "deploy" and st.player == "P1":
		# flotta della libertà schierata
		state.phase = "astrogation"; state.setup = {}
		state.sd.formed = true
		Rules.log_event(state, "La Flotta della Libertà è pronta a Clandestine: la Terran Security Patrol è sciolta.", "victory")

## Corvetta in volo (missione in corso).
static func active_corvette(state: Dictionary) -> Dictionary:
	for s in state.ships:
		if s.owner == "P1" and Rules.alive(s) and s.get("mission", false): return s
	return {}

static func start_of_segment(state: Dictionary) -> void:
	if Rules.current_player(state) != "P1" or state.sd.formed or state.over: return
	if not active_corvette(state).is_empty(): return
	if int(state.sd.spawned) < TOTAL:
		var opts := spawn_options(state)
		if opts.is_empty(): return
		state.phase = "setup"
		state.setup = {"step": "choose", "player": "P1", "kind": "spawn", "title": "Corvetta %d di %d" % [int(state.sd.spawned) + 1, TOTAL],
			"prompt": "Da quale base parte la prossima corvetta? Missione: fermarsi a Clandestine oppure schiantarsi sulla Terra.", "options": opts}
	else:
		form_fleet(state)

static func spawn_options(state: Dictionary) -> Array:
	var map := Rules.map_of(state)
	var seen := {}
	var out := []
	for b in state.bases:
		if not b.active or NO_SPAWN.has(b.body) or seen.has(b.body): continue
		seen[b.body] = true
		out.append({"value": b.body, "label": SolarMap.body(map, b.body).name})
	return out

static func choose(state: Dictionary, value: Variant) -> String:
	if state.setup.get("kind", "") != "spawn": return "Scelta non valida."
	var map := Rules.map_of(state)
	var body := SolarMap.body(map, str(value))
	state.sd.spawned = int(state.sd.spawned) + 1
	var s := ShipTypes.make("sol-%d" % state.sd.spawned, "P1", "corvette", "Corvetta della Libertà %d" % state.sd.spawned)
	var side := -1
	for b in state.bases:
		if b.body == body.id and b.active: side = int(b.side); break
	if side >= 0: Scenarios._land(s, map, body.id, side)
	else: s.pos = body.hex
	s.free_takeoff = true
	s.access_special = true
	s.mission = true
	state.ships.append(s)
	state.phase = "astrogation"
	state.setup = {}
	Rules.log_event(state, "%s si leva in segreto da %s." % [s.name, body.name], "info")
	return ""

## I Figli della Libertà convertono le corvette giunte a Clandestine nella Flotta della Libertà.
static func can_form(state: Dictionary) -> bool:
	return not state.sd.formed and not parked(state).is_empty()

static func parked(state: Dictionary) -> Array:
	return state.ships.filter(func(s): return s.owner == "P1" and Rules.alive(s) and s.get("parked", false))

static func form_fleet(state: Dictionary) -> void:
	if state.sd.formed: return
	var p := parked(state)
	var points := 0.0
	for s in p: points += float(s.combat)
	points *= 2.0
	if points <= 0.0:
		state.sd.formed = true
		Scenarios._finish(state, "P2", "Nessuna corvetta è giunta a Clandestine: la ribellione è soffocata. Vincono gli Enforcers.")
		return
	for s in p:
		s.destroyed = true; s.reason = "convertita nella Flotta della Libertà"; s.retired = true
	var cur := active_corvette(state)
	if not cur.is_empty(): cur.mission = false
	state.sd.spawned = TOTAL
	Rules.log_event(state, "Le %d corvette di Clandestine diventano la Flotta della Libertà: %d punti di forza." % [p.size(), int(points)], "victory")
	Fleet.open_shop(state, "P1", points, "pts", ["torch", "dreadnought", "frigate", "corsair", "corvette", "packet"],
		{"title": "Flotta della Libertà", "note": "Il doppio della forza delle corvette giunte a Clandestine. Ammesse le navi torcia."})

static func shop_done(state: Dictionary, _pid: String, _cart: Dictionary, queue: Array, _spent: float) -> void:
	if queue.is_empty():
		state.sd.formed = true
		state.phase = "astrogation"; state.setup = {}
		check_victory(state)
		return
	for u in queue:
		u.flags = {"access_special": true}
	Fleet.open_deploy(state, "P1", queue, {"stop_at": ["clandestine"]}, "La Flotta della Libertà si raduna a Clandestine")

static func deploy_score(state: Dictionary, _unit: Dictionary, _h: Vector2i, spot: Dictionary) -> float:
	match spot.body:
		"terra": return 3.0
		"mars": return 2.5
		"venus": return 2.0
	return 1.0

static func after_movement(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	var cl := SolarMap.body(map, "clandestine")
	for s in state.ships:
		if s.owner == "P1" and Rules.alive(s) and s.get("mission", false) and s.pos == cl.hex and s.vel == Vector2i.ZERO:
			s.mission = false
			s.parked = true
			Rules.log_event(state, "%s raggiunge Clandestine: missione compiuta." % s.name, "victory")

static func on_destroyed(state: Dictionary, s: Dictionary) -> void:
	if s.owner != "P1" or not s.get("mission", false): return
	s.mission = false
	if s.get("crashed_on", "") == "terra" and not s.get("crash_disabled", false):
		state.sd.terra_hits = int(state.sd.terra_hits) + 1
		Rules.log_event(state, "%s si abbatte sulla Terra! Il Primo Cittadino è terrorizzato." % s.name, "victory")
		_assign_patrol(state)

static func _assign_patrol(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	var terra: Vector2i = SolarMap.body(map, "terra").hex
	var free: Array = state.ships.filter(func(x): return x.owner == "P2" and Rules.alive(x) and not state.sd.patrol.has(x.id))
	if free.is_empty(): return
	var n := 3 if int(state.sd.terra_hits) >= 3 else 1
	free.sort_custom(func(a, b): return Hex.distance(a.pos, terra) < Hex.distance(b.pos, terra))
	for x in free.slice(0, n):
		state.sd.patrol.append(x.id)
		Rules.log_event(state, "%s assegnata alla Terran Security Patrol: non può allontanarsi da Terra e Luna." % x.name, "info")

static func on_patrol(state: Dictionary, s: Dictionary) -> bool:
	return not state.sd.formed and state.sd.patrol.has(s.id)

static func patrol_distance(state: Dictionary, h: Vector2i) -> int:
	var map := Rules.map_of(state)
	return mini(Hex.distance(h, SolarMap.body(map, "terra").hex), Hex.distance(h, SolarMap.body(map, "luna").hex))

static func plot_check(state: Dictionary, s: Dictionary, plot: Dictionary) -> String:
	if not on_patrol(state, s) or s.landed != "" and not plot.get("takeoff", false): return ""
	var pr := Rules.predict(state, s, plot)
	var d := patrol_distance(state, pr.dest)
	if d <= 5 or d < patrol_distance(state, s.pos): return ""
	return "La Terran Security Patrol non può uscire dalla portata dei rilevatori di Terra e Luna."

static func end_of_turn(state: Dictionary) -> void:
	var enf: Array = state.ships.filter(func(x): return x.owner == "P2" and Rules.alive(x))
	if not enf.is_empty() and enf.all(func(x): return x.landed != ""): state.sd.enf_grounded = int(state.sd.enf_grounded) + 1
	else: state.sd.enf_grounded = 0
	if state.sd.formed:
		var map := Rules.map_of(state)
		var reb: Array = state.ships.filter(func(x): return x.owner == "P1" and Rules.alive(x))
		var grounded := not reb.is_empty() and reb.all(func(x): return x.landed != "" or (x.vel == Vector2i.ZERO and map.body_at.has(x.pos)))
		state.sd.reb_grounded = int(state.sd.reb_grounded) + 1 if grounded else 0
	check_victory(state)

static func check_victory(state: Dictionary) -> void:
	if state.over or state.phase == "setup" and state.setup.get("step", "") != "choose": return
	var enf_alive: bool = state.ships.any(func(x): return x.owner == "P2" and Rules.alive(x))
	if not enf_alive:
		Scenarios._finish(state, "P1", "La flotta Enforcer è distrutta: la Terra è libera! Vincono i Figli della Libertà.")
	elif int(state.sd.enf_grounded) >= 12:
		Scenarios._finish(state, "P1", "Gli Enforcers si nascondono a terra da dodici turni: vincono i Figli della Libertà.")
	elif state.sd.formed and not state.ships.any(func(x): return x.owner == "P1" and Rules.alive(x)):
		Scenarios._finish(state, "P2", "La Flotta della Libertà è annientata: gli Enforcers schiacciano la ribellione.")
	elif int(state.sd.reb_grounded) >= 12:
		Scenarios._finish(state, "P2", "La ribellione resta a terra per dodici turni e si spegne: vincono gli Enforcers.")

static func player_has_reinforcements(state: Dictionary, pid: String) -> bool:
	return pid == "P1" and not state.sd.formed
