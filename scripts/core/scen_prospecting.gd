class_name ScenProspecting
extends RefCounted
## PROSPECTING — corsa alle risorse della Fascia per 2–6 cercatori.
## 25 MCr a testa per navi, carburante ed equipaggiamento. Si prospetta attraversando
## un esagono di asteroidi a velocità 1; minerale e schegge CT si vendono a Ceres e Luna.

const ITEMS := ["transport", "tanker", "corvette", "fuel", "automated_mine", "robot_guards", "pm_grapples", "mine", "torpedo"]
const EQUIP := ["automated_mine", "robot_guards", "pm_grapples", "mine", "torpedo"]
const MARKETS := ["ceres", "luna"]

static func setup(state: Dictionary) -> void:
	var map := Rules.map_of(state)
	state.bases = []
	for b in map.bodies:
		if b.asteroid_base:
			state.bases.append({"id": "base-%s" % b.id, "body": b.id, "side": -1, "owner": "all", "active": true, "defense": false, "fuel": false, "ordnance": false, "kind": "asteroid"})
		else:
			for side in b.base_sides:
				state.bases.append({"id": "base-%s-%d" % [b.id, side], "body": b.id, "side": side, "owner": "all", "active": true, "defense": false, "fuel": false, "ordnance": false, "kind": "planetary"})
	state.sd = {"mcr": {}, "prospected": {}, "claims": {}, "length": int(state.options.get("length", 120)), "queue_pids": []}
	for p in state.players: state.sd.mcr[p.id] = 25.0
	state.sd.queue_pids = state.players.map(func(p): return p.id)
	_next_shop(state)
	Rules.log_event(state, "Prospecting: %d giorni di corsa al minerale. Vince chi ha più MegaCrediti." % state.sd.length, "info")

static func _next_shop(state: Dictionary) -> void:
	if state.sd.queue_pids.is_empty():
		state.phase = "astrogation"; state.seg = 0; state.turn = 1; state.setup = {}
		return
	var pid: String = state.sd.queue_pids.pop_front()
	Fleet.open_shop(state, pid, float(state.sd.mcr[pid]), "mcr", ITEMS, {"title": "Equipaggiamento di %s" % Rules.player(state, pid).name,
		"note": "Anche il carburante si compra (1 MCr per punto). L'equipaggiamento va nelle stive delle navi acquistate."})

static func key(h: Vector2i) -> String:
	return "%d,%d" % [h.x, h.y]

## Distribuisce carburante ed equipaggiamento nelle navi del carrello.
static func _pack(cart: Dictionary) -> Dictionary:
	var ships := []
	for t in ["transport", "tanker", "corvette"]:
		for i in range(int(cart.get(t, 0))):
			ships.append({"type": t, "inv": {}, "fuel": 0, "room": float(ShipTypes.TYPES[t].cargo), "tank": int(ShipTypes.TYPES[t].fuel)})
	if ships.is_empty(): return {"error": "Serve almeno una nave."}
	var fuel := int(cart.get("fuel", 0))
	for s in ships:
		var f := mini(fuel, int(s.tank))
		s.fuel = f
		fuel -= f
	if fuel > 0: return {"error": "Il carburante comprato non entra nei serbatoi."}
	for item in EQUIP:
		for i in range(int(cart.get(item, 0))):
			var placed := false
			for s in ships:
				if item == "torpedo" and s.type != "corvette": continue
				if float(s.room) >= float(ShipTypes.ITEM_MASS[item]):
					s.room = float(s.room) - float(ShipTypes.ITEM_MASS[item])
					s.inv[item] = int(s.inv.get(item, 0)) + 1
					placed = true
					break
			if not placed: return {"error": "%s non entra nelle stive." % ShipTypes.ITEM_NAME[item]}
	return {"ships": ships}

static func shop_confirm_check(_state: Dictionary, st: Dictionary) -> String:
	if state_mid(st): return ""
	var r := _pack(st.cart)
	return r.get("error", "")

static func state_mid(st: Dictionary) -> bool:
	return st.get("mid", false)

static func shop_done(state: Dictionary, pid: String, cart: Dictionary, _queue: Array, spent: float) -> void:
	state.sd.mcr[pid] = float(state.sd.mcr[pid]) - spent
	var packed: Array = _pack(cart).ships
	var q := []
	for p in packed:
		q.append({"type": p.type, "inv": p.inv, "fuel": p.fuel})
	Fleet.open_deploy(state, pid, q, {"landed": ["luna"], "stop_at": ["ceres"]}, "Partenza: Luna (a terra) oppure Ceres (fermi nell'esagono)")

static func step_done(state: Dictionary) -> void:
	_next_shop(state)

static func deploy_score(state: Dictionary, _unit: Dictionary, _h: Vector2i, spot: Dictionary) -> float:
	return 2.0 if spot.body == "ceres" else 1.0

# ---------------------------------------------------------------- prospezione e miniere

static func ore_at(state: Dictionary, h: Vector2i) -> bool:
	return state.sd.prospected.get(key(h), "") == "ore"

static func after_ship_move(state: Dictionary, s: Dictionary) -> void:
	if not Rules.alive(s) or Hex.length(s.vel) != 1: return
	for i in range(1, s.last_path.size()):
		var h: Vector2i = s.last_path[i]
		if not state.asteroids.has(h) or state.sd.prospected.has(key(h)): continue
		var d1 := Rules.roll(state)
		var d2 := Rules.roll(state)
		state.sd.prospected[key(h)] = "ore" if d1 == 6 else "none"
		Rules.log_event(state, "%s prospetta un asteroide: %s" % [s.name, "MINERALE! (dado 6)" if d1 == 6 else "niente (dado %d)" % d1], "supply")
		Rules.fx(state, "rock", h)
		if d2 == 1:
			if int(s.inv.get("pm_grapples", 0)) > 0 and ShipTypes.free_cargo(s) >= 10.0:
				s.inv.ct_shard = int(s.inv.get("ct_shard", 0)) + 1
				Rules.log_event(state, "%s raccoglie una scheggia di antimateria con i ganci PM!" % s.name, "victory")
			else:
				Rules.log_event(state, "Una scheggia CT esplode contro %s!" % s.name, "loss")
				Rules._apply_damage(state, s, "D4", "scheggia CT")
				if not Rules.alive(s): return

static func end_of_turn(state: Dictionary) -> void:
	# estrazione manuale: 0,1 t per turno a una nave ferma su un asteroide con minerale
	for s in state.ships:
		if Rules.alive(s) and s.landed == "" and s.vel == Vector2i.ZERO and ore_at(state, s.pos) and not Rules.is_disabled(state, s):
			if ShipTypes.free_cargo(s) >= 0.1: s.ore10 = int(s.ore10) + 1
	for k in state.sd.claims:
		state.sd.claims[k].stock10 = int(state.sd.claims[k].stock10) + 10
	if int(state.turn) >= int(state.sd.length):
		var best := -1.0
		var winners := []
		for p in state.players:
			var m := float(state.sd.mcr[p.id])
			if m > best + 0.001: best = m; winners = [p.id]
			elif absf(m - best) <= 0.001: winners.append(p.id)
		var names := " e ".join(winners.map(func(id): return Rules.player(state, id).name))
		Scenarios._finish(state, winners[0] if winners.size() == 1 else "pari", "Dopo %d giorni %s %s con %s MCr." % [state.sd.length, names, "vince" if winners.size() == 1 else "vincono ex aequo", Fleet.fmt_mcr(best)])

## Mercato in cui la nave si trova ora (Ceres: ferma nell'esagono; Luna: a terra).
static func market(state: Dictionary, s: Dictionary) -> String:
	if not Rules.alive(s): return ""
	if s.landed == "luna": return "luna"
	var map := Rules.map_of(state)
	if s.landed == "" and s.vel == Vector2i.ZERO and s.pos == SolarMap.body(map, "ceres").hex: return "ceres"
	return ""

static func at_base(state: Dictionary, s: Dictionary) -> bool:
	return not Rules.docked_base(state, s).is_empty()

static func can_sell(state: Dictionary, s: Dictionary) -> String:
	if state.phase != "resupply" or s.owner != Rules.current_player(state): return "Solo nella tua fase di rifornimento."
	if market(state, s) == "": return "Si vende a Ceres (fermi nell'esagono) o sulla Luna (a terra)."
	if int(s.ore10) < 10 and int(s.inv.get("ct_shard", 0)) == 0: return "Niente da vendere (almeno 1 t di minerale)."
	return ""

static func sell(state: Dictionary, ship_id: String) -> String:
	var s := Rules.ship(state, ship_id)
	var err := can_sell(state, s)
	if err != "": return err
	var where := market(state, s)
	var total := 0.0
	var parts := []
	var tons := int(s.ore10) / 10
	if tons > 0:
		var die := Rules.roll(state)
		var price := maxi(1, die - 2) if where == "ceres" else die
		total += tons * price
		s.ore10 = int(s.ore10) - tons * 10
		parts.append("%d t di minerale a %d MCr/t (dado %d)" % [tons, price, die])
	var shards := int(s.inv.get("ct_shard", 0))
	if shards > 0:
		var each := 100 if where == "ceres" else 300
		total += shards * each
		s.inv.ct_shard = 0
		parts.append("%d schegge CT a %d" % [shards, each])
	state.sd.mcr[s.owner] = float(state.sd.mcr[s.owner]) + total
	Rules.log_event(state, "%s vende a %s: %s → %s MCr." % [s.name, "Ceres" if where == "ceres" else "Luna", ", ".join(parts), Fleet.fmt_mcr(total)], "supply")
	return ""

static func can_buy(state: Dictionary, s: Dictionary, item: String) -> String:
	if state.phase != "resupply" or s.owner != Rules.current_player(state): return "Solo nella tua fase di rifornimento."
	if not at_base(state, s): return "Bisogna essere in una base."
	var cost := Fleet.price("mcr", item)
	if float(state.sd.mcr[s.owner]) < cost - 0.001: return "Crediti insufficienti."
	if item == "fuel":
		if s.infinite_fuel or int(s.fuel) >= int(s.max_fuel): return "Serbatoio pieno."
		return ""
	if item == "torpedo" and s.commercial: return "I siluri vanno solo su navi da guerra."
	if not ShipTypes.can_carry(s, item): return "Stiva insufficiente."
	return ""

static func buy(state: Dictionary, ship_id: String, item: String, n := 1) -> String:
	var s := Rules.ship(state, ship_id)
	var done := 0
	for i in range(n):
		if can_buy(state, s, item) != "": break
		state.sd.mcr[s.owner] = float(state.sd.mcr[s.owner]) - Fleet.price("mcr", item)
		if item == "fuel": s.fuel = int(s.fuel) + 1
		else: s.inv[item] = int(s.inv.get(item, 0)) + 1
		done += 1
	if done == 0: return can_buy(state, s, item)
	Rules.log_event(state, "%s compra %d× %s." % [s.name, done, ShipTypes.ITEM_NAME.get(item, item).to_lower()], "supply")
	return ""

## Azioni sulla concessione: piazzare miniera/guardie, ritirare il minerale accumulato.
static func claim_actions(state: Dictionary, s: Dictionary) -> Array:
	var out := []
	if state.phase != "resupply" or s.owner != Rules.current_player(state) or not Rules.alive(s): return out
	if s.landed != "" or s.vel != Vector2i.ZERO or not ore_at(state, s.pos): return out
	var k := key(s.pos)
	var claim: Dictionary = state.sd.claims.get(k, {})
	if claim.is_empty():
		if int(s.inv.get("automated_mine", 0)) > 0: out.append("place_mine")
	else:
		if claim.owner == s.owner and not claim.guards and int(s.inv.get("robot_guards", 0)) > 0: out.append("place_guards")
		if int(claim.stock10) > 0 and (claim.owner == s.owner or not claim.guards) and ShipTypes.free_cargo(s) >= 0.1: out.append("collect")
	return out

static func claim_action(state: Dictionary, ship_id: String, action: String) -> String:
	var s := Rules.ship(state, ship_id)
	if not claim_actions(state, s).has(action): return "Azione non disponibile."
	var k := key(s.pos)
	match action:
		"place_mine":
			s.inv.automated_mine = int(s.inv.automated_mine) - 1
			state.sd.claims[k] = {"owner": s.owner, "stock10": 0, "guards": false, "hex": s.pos}
			Rules.log_event(state, "%s installa una miniera automatica: 1 t di minerale al giorno." % s.name, "supply")
		"place_guards":
			s.inv.robot_guards = int(s.inv.robot_guards) - 1
			state.sd.claims[k].guards = true
			Rules.log_event(state, "%s mette guardie robot sulla concessione." % s.name, "supply")
		"collect":
			var claim: Dictionary = state.sd.claims[k]
			var room := int(floorf(ShipTypes.free_cargo(s) * 10.0))
			var take := mini(room, int(claim.stock10))
			claim.stock10 = int(claim.stock10) - take
			s.ore10 = int(s.ore10) + take
			Rules.log_event(state, "%s carica %.1f t di minerale%s." % [s.name, take / 10.0, "" if claim.owner == s.owner else " (salto di concessione!)"], "supply")
	return ""

static func net_worth(state: Dictionary, pid: String) -> float:
	return float(state.sd.mcr.get(pid, 0.0))
