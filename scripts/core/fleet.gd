class_name Fleet
extends RefCounted
## Acquisto delle flotte (punti di forza o MegaCrediti) e schieramento sulla plancia.
## Lo stato del passo corrente vive in state.setup: {step:"shop"|"deploy", player, ...}.

const EQUIP_COST := {"fuel": 1, "mine": 10, "torpedo": 20, "nuke": 300, "automated_mine": 5, "robot_guards": 50, "pm_grapples": 40}

## Prezzo di un oggetto: a punti di forza (le commerciali costano metà) o in MCr.
static func price(currency: String, item: String) -> float:
	if ShipTypes.TYPES.has(item):
		var t: Dictionary = ShipTypes.TYPES[item]
		if currency == "pts": return float(t.combat) * (0.5 if t.commercial else 1.0)
		return float(t.cost)
	return float(EQUIP_COST.get(item, 0))

static func is_ship(item: String) -> bool:
	return ShipTypes.TYPES.has(item)

static func item_name(item: String) -> String:
	if is_ship(item): return ShipTypes.TYPES[item].name
	return ShipTypes.ITEM_NAME.get(item, item)

# ---------------------------------------------------------------- negozio

static func open_shop(state: Dictionary, pid: String, budget: float, currency: String, items: Array, opts: Dictionary = {}) -> void:
	state.phase = "setup"
	state.setup = {"step": "shop", "player": pid, "budget": budget, "currency": currency, "items": items.duplicate(),
		"cart": {}, "max_ships": int(opts.get("max_ships", 0)), "title": opts.get("title", "Acquisto della flotta"),
		"note": opts.get("note", "")}

static func cart_cost(setup: Dictionary) -> float:
	var total := 0.0
	for k in setup.cart: total += price(setup.currency, k) * int(setup.cart[k])
	return total

static func cart_ships(setup: Dictionary) -> int:
	var n := 0
	for k in setup.cart:
		if is_ship(k) and k != "orbital_base": n += int(setup.cart[k])
	return n

static func can_add(state: Dictionary, item: String) -> String:
	var st: Dictionary = state.setup
	if st.get("step", "") != "shop" or not st.items.has(item): return "Oggetto non disponibile."
	if cart_cost(st) + price(st.currency, item) > float(st.budget) + 0.001: return "Budget insufficiente."
	if int(st.max_ships) > 0 and is_ship(item) and item != "orbital_base" and cart_ships(st) >= int(st.max_ships): return "Numero massimo di navi raggiunto."
	return Scenarios.shop_check(state, item)

static func add(state: Dictionary, item: String) -> String:
	var err := can_add(state, item)
	if err != "": return err
	state.setup.cart[item] = int(state.setup.cart.get(item, 0)) + 1
	return ""

static func remove(state: Dictionary, item: String) -> void:
	var c := int(state.setup.cart.get(item, 0))
	if c <= 1: state.setup.cart.erase(item)
	else: state.setup.cart[item] = c - 1

static func confirm_shop(state: Dictionary) -> String:
	var st: Dictionary = state.setup
	if st.get("step", "") != "shop": return "Nessun acquisto in corso."
	var err := Scenarios.shop_confirm_check(state, st)
	if err != "": return err
	var queue: Array = []
	var counters := {}
	for item in st.items:
		if not is_ship(item): continue
		for i in range(int(st.cart.get(item, 0))):
			counters[item] = int(counters.get(item, 0)) + 1
			queue.append({"type": item})
	var spent := cart_cost(st)
	Rules.log_event(state, "%s acquista: %s (%s)" % [Rules.player(state, st.player).name, cart_text(st), money_text(spent, st.currency)], "supply")
	Scenarios.shop_done(state, st.player, st.cart.duplicate(), queue, spent)
	return ""

static func cart_text(st: Dictionary) -> String:
	var parts := []
	for item in st.items:
		var n := int(st.cart.get(item, 0))
		if n > 0: parts.append("%d× %s" % [n, item_name(item).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "nulla"

static func money_text(v: float, currency: String) -> String:
	if currency == "pts": return ("%.1f punti" % v).replace(".0 ", " ")
	return "%s MCr" % fmt_mcr(v)

static func fmt_mcr(v: float) -> String:
	if absf(v - roundf(v)) < 0.05: return "%d" % roundi(v)
	return "%.1f" % v

# ---------------------------------------------------------------- schieramento

## zone: {landed:[corpi], orbit:[corpi], space_near:[corpi], space_radius:int, space_any:bool,
##        edge:"jupiter", min_sep:int, distinct_orbit:bool, stop_at:[corpi asteroide]}
static func open_deploy(state: Dictionary, pid: String, queue: Array, zone: Dictionary, title := "Schieramento") -> void:
	state.phase = "setup"
	state.setup = {"step": "deploy", "player": pid, "queue": queue.duplicate(true), "zone": zone.duplicate(true), "ccw": true, "title": title, "used_orbits": []}

static func current_unit(state: Dictionary) -> Dictionary:
	if state.setup.get("step", "") != "deploy" or state.setup.queue.is_empty(): return {}
	return state.setup.queue[0]

## Tutte le caselle valide per l'unità corrente: {hex: {mode, body, side}}.
static func spots(state: Dictionary) -> Dictionary:
	var out := {}
	var unit := current_unit(state)
	if unit.is_empty(): return out
	var st: Dictionary = state.setup
	var z: Dictionary = st.zone
	var map := Rules.map_of(state)
	var pid: String = st.player
	var is_base: bool = unit.type == "orbital_base"
	if not is_base:
		for bid in z.get("landed", []):
			var b := SolarMap.body(map, bid)
			if b.asteroid_base:
				if _sep_ok(state, b.hex, z): out[b.hex] = {"mode": "stop", "body": bid, "side": -1}
				continue
			var sides := []
			for base in state.bases:
				if base.body == bid and int(base.side) >= 0 and Rules.friendly_base(state, base, pid): sides.append(int(base.side))
			if not sides.is_empty() and _sep_ok(state, b.hex, z): out[b.hex] = {"mode": "landed", "body": bid, "side": sides}
	for bid in z.get("orbit", []):
		if z.get("distinct_orbit", false) and st.used_orbits.has(bid): continue
		var b2 := SolarMap.body(map, bid)
		for i in range(6):
			var h: Vector2i = b2.hex + Hex.DIRS[i]
			if map.cells.has(h) and not map.body_at.has(h) and _sep_ok(state, h, z):
				out[h] = {"mode": "orbit", "body": bid, "side": i}
	if not is_base:
		var near: Array = z.get("space_near", [])
		var radius := int(z.get("space_radius", 5))
		var any: bool = z.get("space_any", false)
		if any or not near.is_empty():
			for h in map.cells:
				if out.has(h) or map.body_at.has(h) or state.special.has(h): continue
				var ok := any
				if not ok:
					for bid in near:
						if Hex.distance(h, SolarMap.body(map, bid).hex) <= radius: ok = true; break
				if ok and _sep_ok(state, h, z): out[h] = {"mode": "space", "body": "", "side": -1}
		if z.get("edge", "") == "jupiter":
			var ey := int(map.get("edge_y", 0))
			for h in map.cells:
				if h.y == ey: out[h] = {"mode": "edge", "body": "", "side": -1}
		for bid in z.get("stop_at", []):
			var b3 := SolarMap.body(map, bid)
			out[b3.hex] = {"mode": "stop", "body": bid, "side": -1}
	return out

static func _sep_ok(state: Dictionary, h: Vector2i, z: Dictionary) -> bool:
	var sep := int(z.get("min_sep", 0))
	if sep <= 0: return true
	for s in state.ships:
		if Rules.alive(s) and Hex.distance(s.pos, h) < sep: return false
	return true

static func place(state: Dictionary, hex: Vector2i) -> String:
	var all := spots(state)
	if not all.has(hex): return "Posizione non valida per questa unità."
	var unit := current_unit(state)
	var st: Dictionary = state.setup
	var spot: Dictionary = all[hex]
	var map := Rules.map_of(state)
	state.next_id = int(state.next_id) + 1
	var count := 1
	for s in state.ships:
		if s.owner == st.player and s.type == unit.type: count += 1
	var name: String = unit.get("name", "%s %d" % [ShipTypes.TYPES[unit.type].name, count])
	var s := ShipTypes.make("u%d" % state.next_id, st.player, unit.type, name)
	for k in unit.get("inv", {}): s.inv[k] = int(unit.inv[k])
	if unit.has("fuel") and not s.infinite_fuel: s.fuel = mini(int(unit.fuel), int(s.max_fuel))
	for k in unit.get("flags", {}): s[k] = unit.flags[k]
	match spot.mode:
		"landed":
			var sides: Array = spot.side
			var best: int = sides[0]
			var fewest := 999
			for sd in sides:
				var n = state.ships.filter(func(x): return x.landed == spot.body and int(x.side) == int(sd)).size()
				if n < fewest: fewest = n; best = int(sd)
			Scenarios._land(s, map, spot.body, best)
		"orbit":
			Scenarios._orbit(s, map, spot.body, int(spot.side), st.get("ccw", true))
			st.used_orbits.append(spot.body)
		"space", "stop":
			s.pos = hex; s.vel = Vector2i.ZERO
		"edge":
			s.pos = hex
			s.vel = Vector2i(0, 1) if st.get("ccw", true) else Vector2i(-1, 1)
			s.history = [{"turn": 0, "from": hex - s.vel, "to": hex, "burns": [], "note": "ingresso"}]
	Scenarios.adapt_ship(state, s)
	state.ships.append(s)
	for p in state.players:
		if state.knowledge.has(p.id) and p.id != s.owner and not state.rules.get("hidden", false): state.knowledge[p.id][s.id] = true
	st.queue.pop_front()
	if st.queue.is_empty(): Scenarios.setup_step_done(state)
	return ""

## Schieramento automatico (IA o pulsante): sceglie le caselle con un punteggio dello scenario.
static func auto_deploy(state: Dictionary) -> void:
	var guard := 0
	var pid: String = state.setup.get("player", "")
	while state.phase == "setup" and state.setup.get("step", "") == "deploy" and state.setup.get("player", "") == pid and guard < 80:
		guard += 1
		var all := spots(state)
		if all.is_empty():
			# nessuna casella valida: l'unità viene scartata
			state.setup.queue.pop_front()
			if state.setup.queue.is_empty(): Scenarios.setup_step_done(state)
			continue
		var keys: Array = all.keys()
		var best: Vector2i = keys[0]
		var best_score := -INF
		for h in keys:
			var sc := Scenarios.deploy_score(state, current_unit(state), h, all[h]) + float(Rules.roll(state)) * 0.01
			if sc > best_score: best_score = sc; best = h
		place(state, best)
