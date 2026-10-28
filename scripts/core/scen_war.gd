class_name ScenWar
extends RefCounted
## INTERPLANETARY WAR — Terra (P1, 1600 MCr) contro Ribelli (P2, 1000 MCr).
## Ogni base produce 0,1 MCr per turno. I ribelli spendono liberamente (a Callisto);
## la Terra deve portare con navi commerciali i crediti di Luna e Venere fino alla Terra.

const TERRAN := ["terra", "luna", "venus"]
const REBEL := ["callisto", "io", "ganymede", "mars"]
const ITEMS := ["dreadnought", "frigate", "corsair", "corvette", "torch", "liner", "transport", "tanker", "orbital_base", "mine", "torpedo", "nuke"]

static func setup(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	state.rules.nukes = true
	state.bases = []
	for bid in TERRAN + REBEL:
		var b := SolarMap.body(map, bid)
		for side in b.base_sides:
			state.bases.append({"id": "base-%s-%d" % [bid, side], "body": bid, "side": side, "owner": "P1" if TERRAN.has(bid) else "P2",
				"active": true, "defense": true, "fuel": true, "ordnance": true, "kind": "planetary"})
	state.sd = {"mcr": {"P1": 0.0, "P2": 0.0}, "pool": {"terra": 0.0, "luna": 0.0, "venus": 0.0},
		"stock": {}, "mid": false}
	for bid in TERRAN + REBEL: state.sd.stock[bid] = {"mine": 0, "torpedo": 0, "nuke": 0}
	Fleet.open_shop(state, "P1", 1600.0, "mcr", ITEMS, {"title": "Arsenale terrestre",
		"note": "1600 MCr. Gli ordigni restano in deposito sulla Terra; le navi si caricano in fase di rifornimento."})
	Rules.log_event(state, "Interplanetary War: la Terra arma la sua flotta contro le colonie ribelli.", "info")

static func home(pid: String) -> String:
	return "terra" if pid == "P1" else "callisto"

static func worlds(pid: String) -> Array:
	return TERRAN if pid == "P1" else REBEL

## Crediti spendibili ora.
static func spendable(state: Dictionary, pid: String) -> float:
	return float(state.sd.pool.terra) if pid == "P1" else float(state.sd.mcr.P2)

static func shop_done(state: Dictionary, pid: String, cart: Dictionary, queue: Array, spent: float) -> void:
	var h := home(pid)
	for k in ["mine", "torpedo", "nuke"]:
		state.sd.stock[h][k] = int(state.sd.stock[h][k]) + int(cart.get(k, 0))
	if state.sd.mid:
		# acquisto durante la partita: le navi compaiono sulla base di casa
		if pid == "P1": state.sd.pool.terra = float(state.sd.pool.terra) - spent
		else: state.sd.mcr.P2 = float(state.sd.mcr.P2) - spent
		state.sd.mid = false
		state.phase = state.sd.get("mid_phase", "resupply")
		state.setup = {}
		var map := Rules.map_of(state)
		for u in queue:
			state.next_id = int(state.next_id) + 1
			var s := ShipTypes.make("u%d" % state.next_id, pid, u.type, "%s %d" % [ShipTypes.TYPES[u.type].name, state.next_id])
			if u.type == "orbital_base":
				var side := Hex.dir_index(Vector2i(1, 0))
				Scenarios._orbit(s, map, h, side, true)
			else:
				var b := _home_base(state, pid)
				Scenarios._land(s, map, h, int(b.side))
			s.resupplied_seg = Rules.seg_key(state)
			Scenarios.adapt_ship(state, s)
			state.ships.append(s)
		return
	var left := (1600.0 if pid == "P1" else 1000.0) - spent
	if pid == "P1": state.sd.pool.terra = left
	else: state.sd.mcr.P2 = left
	var zone := {"landed": worlds(pid), "orbit": worlds(pid), "space_near": worlds(pid), "space_radius": 5}
	Fleet.open_deploy(state, pid, queue, zone, "Schieramento: su, in orbita o entro 5 esagoni dai tuoi mondi")

static func _home_base(state: Dictionary, pid: String) -> Dictionary:
	for b in state.bases:
		if b.body == home(pid) and b.active and b.owner == pid: return b
	return {}

static func can_buy_now(state: Dictionary, pid: String) -> String:
	if not (state.phase in ["astrogation", "resupply"]) or Rules.current_player(state) != pid: return "Si compra in astrogazione o rifornimento, nel proprio segmento."
	if _home_base(state, pid).is_empty(): return "Le basi di %s sono distrutte." % ("Terra" if pid == "P1" else "Callisto")
	if spendable(state, pid) < 10.0: return "Crediti insufficienti."
	return ""

static func open_mid_shop(state: Dictionary, pid: String) -> String:
	var err := can_buy_now(state, pid)
	if err != "": return err
	state.sd.mid = true
	state.sd.mid_phase = state.phase
	Fleet.open_shop(state, pid, spendable(state, pid), "mcr", ITEMS, {"title": "Cantiere di %s" % ("Terra" if pid == "P1" else "Callisto"),
		"note": "Le navi nuove compaiono a terra sulla base di casa."})
	return ""

static func step_done(state: Dictionary) -> void:
	if state.setup.step == "deploy" and state.setup.player == "P1":
		Fleet.open_shop(state, "P2", 1000.0, "mcr", ITEMS, {"title": "Arsenale ribelle",
			"note": "1000 MCr. Gli ordigni restano in deposito su Callisto."})
	else:
		state.phase = "astrogation"; state.seg = 0; state.turn = 1; state.setup = {}

static func deploy_score(state: Dictionary, unit: Dictionary, h: Vector2i, spot: Dictionary) -> float:
	var pid: String = state.setup.player
	var sc := 0.0
	if spot.body == home(pid): sc += 3.0
	if spot.mode == "landed": sc += 2.0
	if unit.type == "orbital_base" and spot.mode == "orbit": sc += 4.0
	return sc

# ---------------------------------------------------------------- depositi di ordigni

static func stock_check(state: Dictionary, s: Dictionary, b: Dictionary, kind: String) -> String:
	if b.get("orbital", false):
		var ob := Rules.ship(state, b.id)
		return "" if int(ob.inv.get(kind, 0)) > 0 else "La base orbitale ha esaurito questo ordigno."
	var st: Dictionary = state.sd.stock.get(b.body, {})
	return "" if int(st.get(kind, 0)) > 0 else "Deposito di %s vuoto: compra ordigni al cantiere." % SolarMap.body(Rules.map_of(state), b.body).name

static func stock_take(state: Dictionary, _s: Dictionary, b: Dictionary, kind: String, n: int) -> void:
	if b.is_empty(): return
	if b.get("orbital", false):
		var ob := Rules.ship(state, b.id)
		ob.inv[kind] = int(ob.inv.get(kind, 0)) - n
		return
	if state.sd.stock.has(b.body): state.sd.stock[b.body][kind] = int(state.sd.stock[b.body][kind]) - n

# ---------------------------------------------------------------- crediti

static func end_of_turn(state: Dictionary) -> void:
	for b in state.bases:
		if not b.active: continue
		if b.owner == "P1": state.sd.pool[b.body] = float(state.sd.pool[b.body]) + 0.1
		elif b.owner == "P2": state.sd.mcr.P2 = float(state.sd.mcr.P2) + 0.1
	# un mondo senza basi perde i crediti accumulati
	for w in TERRAN:
		if not state.bases.any(func(b): return b.body == w and b.active) and float(state.sd.pool[w]) > 0.0:
			Rules.log_event(state, "Le basi di %s sono distrutte: %s MCr perduti." % [SolarMap.body(Rules.map_of(state), w).name, Fleet.fmt_mcr(state.sd.pool[w])], "loss")
			state.sd.pool[w] = 0.0
	if not state.bases.any(func(b): return b.body == "callisto" and b.active) and float(state.sd.mcr.P2) > 0.0:
		Rules.log_event(state, "Callisto è devastata: i crediti ribelli sono perduti.", "loss")
		state.sd.mcr.P2 = 0.0
	check_victory(state)

## Corrieri terrestri: caricano i crediti a Luna/Venere e li scaricano sulla Terra.
static func on_docked(state: Dictionary, s: Dictionary, b: Dictionary) -> void:
	if s.owner != "P1" or not s.commercial or b.is_empty() or s.landed == "": return
	if s.landed == "terra" and float(s.mcr) > 0.0:
		state.sd.pool.terra = float(state.sd.pool.terra) + float(s.mcr)
		Rules.log_event(state, "%s consegna %s MCr alla Terra." % [s.name, Fleet.fmt_mcr(s.mcr)], "supply")
		s.mcr = 0.0
	elif s.landed in ["luna", "venus"] and float(state.sd.pool[s.landed]) >= 1.0:
		var room := floorf(ShipTypes.free_cargo(s))
		var take := minf(floorf(float(state.sd.pool[s.landed])), room)
		if take >= 1.0:
			s.mcr = float(s.mcr) + take
			state.sd.pool[s.landed] = float(state.sd.pool[s.landed]) - take
			Rules.log_event(state, "%s carica %s MCr a %s." % [s.name, Fleet.fmt_mcr(take), SolarMap.body(Rules.map_of(state), s.landed).name], "supply")

static func devastated(state: Dictionary, body: String) -> int:
	var seen := {}
	for d in state.devastated:
		if d.body == body: seen[int(d.side)] = true
	return seen.size()

static func check_victory(state: Dictionary) -> void:
	if state.over or state.phase == "setup": return
	if devastated(state, "terra") >= 3 and devastated(state, "luna") >= 1:
		Scenarios._finish(state, "P2", "Tre lati della Terra e uno della Luna sono devastati: le colonie ribelli vincono la guerra.")
		return
	var rebels: bool = state.ships.any(func(x): return x.owner == "P2" and Rules.alive(x))
	if not rebels:
		if devastated(state, "terra") > 0:
			Scenarios._finish(state, "P1", "La flotta ribelle è distrutta, ma la Terra porta le cicatrici delle testate: vittoria marginale terrestre.")
		else:
			Scenarios._finish(state, "P1", "La flotta ribelle è distrutta: vittoria decisiva della Terra.")

static func player_has_reinforcements(state: Dictionary, pid: String) -> bool:
	return spendable(state, pid) >= 10.0 and not _home_base(state, pid).is_empty()
