class_name ScenMutiny
extends RefCounted
## THE FLEET MUTINY — Impero (P1) contro Ribelli (P2).
## L'Impero schiera 12 navi e 2 basi orbitali; il Ribelle designa cinque unità e tira:
## con 6 restano fedeli. Vince chi controlla i lati della Terra.

const ITEMS := ["dreadnought", "frigate", "corsair", "corvette", "packet", "torch", "liner", "transport", "tanker"]

static func setup(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	state.rules.capture_bases = true
	state.bases = []
	for b in map.bodies:
		if b.asteroid_base:
			state.bases.append({"id": "base-%s" % b.id, "body": b.id, "side": -1, "owner": "P1", "active": true, "defense": false, "fuel": true, "ordnance": true, "kind": "asteroid"})
		else:
			for side in b.base_sides:
				state.bases.append({"id": "base-%s-%d" % [b.id, side], "body": b.id, "side": side, "owner": "P1", "active": true, "defense": false, "fuel": true, "ordnance": true, "kind": "planetary"})
	state.sd = {"suppressed": [], "designated": []}
	Fleet.open_shop(state, "P1", 9999.0, "pts", ITEMS, {"max_ships": 12, "title": "Flotta imperiale",
		"note": "Scegli esattamente 12 navi. Le 2 basi orbitali sono già comprese."})
	Rules.log_event(state, "The Fleet Mutiny: l'Impero compone e schiera la sua flotta, poi i ribelli si rivelano.", "info")

static func shop_check(_state: Dictionary, _item: String) -> String:
	return ""

static func shop_confirm_check(_state: Dictionary, st: Dictionary) -> String:
	if Fleet.cart_ships(st) != 12: return "Servono esattamente 12 navi (ora %d)." % Fleet.cart_ships(st)
	return ""

static func shop_done(state: Dictionary, _pid: String, _cart: Dictionary, queue: Array, _spent: float) -> void:
	var q := [{"type": "orbital_base", "name": "Base orbitale Aquila"}, {"type": "orbital_base", "name": "Base orbitale Fenice"}]
	q.append_array(queue)
	var map := Rules.map_of(state)
	var landed := []
	var orbit := []
	for b in map.bodies:
		if b.gravity in ["full", "weak"]: orbit.append(b.id)
		if not b.base_sides.is_empty() or b.asteroid_base: landed.append(b.id)
	Fleet.open_deploy(state, "P1", q, {"landed": landed, "orbit": orbit, "space_any": true, "min_sep": 3},
		"Schieramento imperiale: ogni unità ad almeno 3 esagoni dalle altre")

static func step_done(state: Dictionary) -> void:
	if state.setup.step == "deploy":
		state.phase = "setup"
		state.setup = {"step": "designate", "player": "P2", "picks": [], "max": 5, "title": "Ammutinamento",
			"prompt": "Ribelle: designa fino a cinque navi o basi imperiali. Per ognuna si tira un dado: con 6 resta fedele."}

static func toggle_pick(state: Dictionary, ship_id: String) -> String:
	var st: Dictionary = state.setup
	var s := Rules.ship(state, ship_id)
	if s.is_empty() or s.owner != "P1": return "Scegli un'unità imperiale."
	if st.picks.has(ship_id): st.picks.erase(ship_id)
	elif st.picks.size() >= 5: return "Al massimo cinque unità."
	else: st.picks.append(ship_id)
	return ""

static func confirm_picks(state: Dictionary) -> String:
	var st: Dictionary = state.setup
	if st.picks.is_empty(): return "Designa almeno un'unità."
	var turned := 0
	for id in st.picks:
		var s := Rules.ship(state, id)
		var die := Rules.roll(state)
		if die == 6:
			Rules.log_event(state, "%s resta fedele all'Impero (dado 6)." % s.name, "info")
		else:
			s.owner = "P2"
			s.name = s.name + " (ribelle)"
			turned += 1
			Rules.log_event(state, "%s si ammutina! (dado %d)" % [s.name, die], "combat")
	state.sd.designated = st.picks.duplicate()
	state.setup = {}
	state.phase = "astrogation"
	state.turn = 1
	state.seg = 1
	if turned == 0:
		Scenarios._finish(state, "P1", "Nessuna unità si ammutina: l'Impero vince senza combattere.")
	return ""

static func deploy_score(state: Dictionary, unit: Dictionary, h: Vector2i, spot: Dictionary) -> float:
	var map := Rules.map_of(state)
	var terra: Vector2i = SolarMap.body(map, "terra").hex
	var d := float(Hex.distance(h, terra))
	if unit.type == "orbital_base": return 5.0 if spot.body in ["venus", "mars"] else (2.0 if spot.body != "terra" and spot.body != "luna" else -5.0)
	# vicino alla Terra ma sparpagliati, con preferenza per le orbite
	return -absf(d - 7.0) + (1.5 if spot.mode == "orbit" else 0.0) + (1.0 if spot.mode == "landed" else 0.0)

# ---------------------------------------------------------------- soppressione dei lati planetari

static func is_suppressed(state: Dictionary, body: String, side: int) -> bool:
	for x in state.sd.suppressed:
		if x.body == body and int(x.side) == side: return true
	return false

## Lato che la nave può sopprimere ora (orbita sopra quel lato), oppure {}.
static func suppress_target(state: Dictionary, s: Dictionary) -> Dictionary:
	if state.phase != "combat" or s.owner != Rules.current_player(state) or not Rules.can_fire(state, s): return {}
	if s.get("is_base", false): return {}
	if int(s.attacked_tick) == Rules.tick(state): return {}
	var body_id := Rules.orbit_body(state, s)
	if body_id == "": return {}
	var body := SolarMap.body(Rules.map_of(state), body_id)
	if float(body.radius) <= 0.0 or body.id == "sol": return {}
	var side := Hex.dir_index(s.pos - body.hex)
	if side < 0 or is_suppressed(state, body.id, side): return {}
	return {"body": body.id, "side": side, "name": body.name}

static func suppress(state: Dictionary, ship_id: String) -> String:
	var s := Rules.ship(state, ship_id)
	var tg := suppress_target(state, s)
	if tg.is_empty(): return "Questa nave non può sopprimere alcun lato ora."
	state.sd.suppressed.append({"body": tg.body, "side": tg.side, "by": s.owner})
	s.attacked_tick = Rules.tick(state)
	s.fired_seg = Rules.seg_key(state)
	for b in state.bases:
		if b.body == tg.body and int(b.side) == int(tg.side): b.active = false
	Rules.log_event(state, "%s sopprime il lato %d di %s." % [s.name, int(tg.side) + 1, tg.name], "combat")
	Rules.fx(state, "flak", SolarMap.body(Rules.map_of(state), tg.body).hex)
	check_victory(state)
	return ""

static func terra_suppressed(state: Dictionary) -> int:
	return state.sd.suppressed.filter(func(x): return x.body == "terra").size()

# ---------------------------------------------------------------- cattura delle basi

static func on_docked(state: Dictionary, s: Dictionary, _b: Dictionary) -> void:
	if state.phase != "resupply" or not Rules.alive(s) or s.get("is_base", false): return
	var map := Rules.map_of(state)
	# basi asteroidali: fermarsi nell'esagono
	for b in state.bases:
		if int(b.side) >= 0 or b.owner == s.owner or not b.active: continue
		var body := SolarMap.body(map, b.body)
		if s.pos == body.hex and s.vel == Vector2i.ZERO and not _defended(state, s, body.hex, Vector2i.ZERO, b.owner):
			b.owner = s.owner
			Rules.log_event(state, "%s conquista la base di %s." % [Rules.player(state, s.owner).name, body.name], "combat")
	# basi orbitali: accoppiare la rotta senza difensori
	for ob in state.ships:
		if not ob.get("is_base", false) or ob.owner == s.owner or not Rules.alive(ob): continue
		if ob.pos == s.pos and ob.vel == s.vel and not _defended(state, s, ob.pos, ob.vel, ob.owner, ob.id):
			ob.owner = s.owner
			Rules.log_event(state, "%s conquista %s." % [Rules.player(state, s.owner).name, ob.name], "combat")

static func _defended(state: Dictionary, _attacker: Dictionary, pos: Vector2i, vel: Vector2i, owner: String, exclude := "") -> bool:
	for x in state.ships:
		if x.id != exclude and x.owner == owner and Rules.alive(x) and x.pos == pos and x.vel == vel and not x.get("is_base", false): return true
	return false

static func check_victory(state: Dictionary) -> void:
	if state.over or state.phase == "setup": return
	var n := terra_suppressed(state)
	if n >= 4:
		Scenarios._finish(state, "P2", "I ribelli sopprimono %d lati della Terra: vittoria decisiva dell'ammutinamento." % n)
		return
	var rebels: bool = state.ships.any(func(x): return x.owner == "P2" and Rules.alive(x))
	if not rebels:
		if n == 3: Scenarios._finish(state, "P1", "Ammutinamento domato, ma con tre lati della Terra soppressi: vittoria marginale dell'Impero.")
		else: Scenarios._finish(state, "P1", "Ammutinamento domato con %d lati della Terra soppressi: vittoria decisiva dell'Impero." % n)
