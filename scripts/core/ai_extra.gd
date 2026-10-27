class_name AIX
extends RefCounted
## IA per gli scenari con acquisti e schieramenti: Nova, Retribution, The Fleet Mutiny,
## Interplanetary War e Prospecting. Riusa la ricerca vettoriale di AI.

# ---------------------------------------------------------------- preparazione

static func setup_step(state: Dictionary) -> void:
	var st: Dictionary = state.setup
	match st.get("step", ""):
		"shop": _shop(state)
		"deploy": Fleet.auto_deploy(state)
		"choose": _choose(state)
		"designate":
			var units: Array = state.ships.filter(func(s): return s.owner == "P1" and Rules.alive(s))
			units.sort_custom(func(a, b): return int(a.combat) > int(b.combat))
			for u in units.slice(0, 5): ScenMutiny.toggle_pick(state, u.id)
			ScenMutiny.confirm_picks(state)

static func _choose(state: Dictionary) -> void:
	var st: Dictionary = state.setup
	var opts: Array = st.options
	if opts.is_empty(): return
	var pick: Variant = opts[0].value
	if st.kind == "spawn":
		var map := Rules.map_of(state)
		var cl: Vector2i = SolarMap.body(map, "clandestine").hex
		var best := 999
		for o in opts:
			var d := Hex.distance(SolarMap.body(map, str(o.value)).hex, cl)
			if d < best: best = d; pick = o.value
	elif st.kind == "terra3":
		pick = Rules.roll(state) - 1
	Scenarios.choose(state, pick)

static func _shop(state: Dictionary) -> void:
	var st: Dictionary = state.setup
	var pid: String = st.player
	var wish: Array = []
	match state.scenario:
		"nova": wish = ["dreadnought", "frigate", "frigate", "frigate", "frigate", "corvette", "packet"]
		"retribution":
			var pts := float(st.budget)
			while pts >= 2.0:
				if pts >= 8.0: wish.append("torch"); pts -= 8.0
				elif pts >= 4.0: wish.append("corsair"); pts -= 4.0
				else: wish.append("corvette"); pts -= 2.0
		"fleet-mutiny": wish = ["frigate", "frigate", "frigate", "frigate", "frigate", "corsair", "corsair", "corsair", "corsair", "corsair", "corvette", "corvette"]
		"interplanetary-war":
			if state.sd.get("mid", false):
				var money := float(st.budget)
				var carrier: bool = state.ships.any(func(x): return x.owner == pid and Rules.alive(x) and not x.commercial and int(x.cargo) >= 20 and not x.get("is_base", false))
				var stocked: bool = int(state.sd.stock[ScenWar.home(pid)].nuke) > 0
				if pid == "P2":
					if money >= 450.0 and not carrier: wish = ["frigate", "nuke"]
					elif money >= 300.0 and carrier and not stocked: wish = ["nuke"]
					elif money >= 150.0 and not carrier: wish = ["frigate"]
				else:
					if rebels_hiding(state) and money >= 300.0 and not stocked: wish = ["nuke"]
					elif not rebels_hiding(state) and money >= 150.0: wish = ["frigate"]
					elif not rebels_hiding(state) and money >= 80.0: wish = ["corsair"]
			elif pid == "P1":
				wish = ["dreadnought", "frigate", "frigate", "frigate", "frigate", "corsair", "corsair", "transport"]
				for i in range(11): wish.append("torpedo")
			else:
				wish = ["frigate", "frigate", "nuke", "nuke", "corsair", "torpedo"]
		"prospecting":
			wish = ["transport", "automated_mine"]
			for i in range(10): wish.append("fuel")
	for item in wish: Fleet.add(state, item)
	if state.scenario == "prospecting":
		while Fleet.add(state, "fuel") == "": pass
	var err := Fleet.confirm_shop(state)
	if err != "":
		if Scenarios.can_cancel_shop(state): Scenarios.cancel_shop(state)
		else:
			state.setup.cart = {}
			Fleet.confirm_shop(state)

# ---------------------------------------------------------------- comando delle navi

static func decide(state: Dictionary, s: Dictionary) -> Dictionary:
	if s.get("is_base", false): return {}
	clear_refuel(state, s)
	match state.scenario:
		"nova": return _nova(state, s)
		"retribution": return _retribution(state, s)
		"fleet-mutiny": return _mutiny(state, s)
		"interplanetary-war": return _war(state, s)
		"prospecting": return _prospect(state, s)
	return {}

static func enemies(state: Dictionary, s: Dictionary) -> Array:
	var map := Rules.map_of(state)
	var cl: Vector2i = SolarMap.body(map, "clandestine").hex
	return state.ships.filter(func(t): return t.owner != s.owner and Rules.alive(t) and not t.get("dummy", false) and t.landed == "" and Rules.is_known(state, s.owner, t) and target_ok(state, s.owner, t) and (s.access_special or Hex.distance(t.pos, cl) > 1))

## Nova: i blocchi non si combattono fra loro.
static func target_ok(state: Dictionary, me: String, t: Dictionary) -> bool:
	if state.scenario == "nova" and me != "P3": return t.owner == "P3"
	if state.scenario == "nova" and me == "P3": return false
	if state.scenario == "prospecting": return false
	return true

static func nearest(list: Array, h: Vector2i) -> Dictionary:
	var best := {}
	var bd := 9999
	for t in list:
		var d := Hex.distance(t.pos, h)
		if d < bd: bd = d; best = t
	return best

static func hunt(state: Dictionary, s: Dictionary, t: Dictionary, max_turns := 8) -> Dictionary:
	if t.is_empty(): return {}
	var plan := AI.search_intercept(state, s, t, 1, 1400 if max_turns <= 8 else 2600, 0 if s.infinite_fuel else 4)
	if plan.is_empty() or plan.burns.is_empty(): return {}
	# per le cacce lunghe basta un piano parziale che avvicini; per quelle brevi serve il piano completo
	if plan.get("partial", false) and max_turns <= 20: return {}
	if int(plan.turns) > max_turns: return {}
	return {"burns": plan.burns[0]}

## Rifornimento: in orbita sopra una base amica con carburante, o fermi in una base asteroidale.
static func refuel(state: Dictionary, s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	if not state.ai.has(s.id): state.ai[s.id] = {}
	var memo: Dictionary = state.ai[s.id]
	# resta fedele alla base scelta finché il piano regge
	var kept: String = memo.get("refuel_goal", "")
	if kept != "":
		var kb := SolarMap.body(map, kept.split(":")[1])
		var kp := AI._cached_or_plan(state, s, kept, func(): return AI.search_stop(state, s, kb.hex, 2000) if kb.asteroid_base else AI.search_orbit(state, s, kb.id, 0, 2000))
		if not kp.is_empty() and not kp.get("partial", false): return AI._follow(state, s, kp)
	var best := {}
	var best_goal := ""
	var best_t := 999
	var seen := {}
	for b in state.bases:
		if not b.active or not b.get("fuel", true) or not Rules.friendly_base(state, b, s.owner) or seen.has(b.body): continue
		seen[b.body] = true
		var body := SolarMap.body(map, b.body)
		if Hex.distance(body.hex, s.pos) > 40: continue
		var plan := AI._cached_or_plan(state, s, ("stop:" if body.asteroid_base else "orbit:") + b.body,
			func(): return AI.search_stop(state, s, body.hex, 2000) if body.asteroid_base else AI.search_orbit(state, s, b.body, 0, 2000))
		if plan.is_empty() or plan.get("partial", false): continue
		if int(plan.turns) < best_t: best_t = int(plan.turns); best = plan; best_goal = ("stop:" if body.asteroid_base else "orbit:") + b.body
	state.ai[s.id].refuel_goal = best_goal
	return AI._follow(state, s, best) if not best.is_empty() else AI._drift_safe(state, s)

static func hold_orbit(state: Dictionary, s: Dictionary, body: String) -> Dictionary:
	if Rules.orbit_body(state, s) == body: return {"burns": []}
	var plan := AI._cached_or_plan(state, s, "orbit:" + body, func(): return AI.search_orbit(state, s, body, 0, 1500))
	return AI._follow(state, s, plan)

static func low_fuel(s: Dictionary, limit := 6) -> bool:
	return not s.infinite_fuel and int(s.fuel) <= limit

static func clear_refuel(state: Dictionary, s: Dictionary) -> void:
	if state.ai.has(s.id) and not low_fuel(s, 8): state.ai[s.id].erase("refuel_goal")

static func land_at(state: Dictionary, s: Dictionary, body: String) -> Dictionary:
	if s.landed == body: return {}
	if s.landed != "": return {"takeoff": true} if Rules.can_take_off(state, s) else {}
	if Rules.orbit_body(state, s) == body:
		var sides := Rules.landing_sides(state, s)
		if not sides.is_empty() and (s.infinite_fuel or int(s.fuel) >= 1): return {"land": sides[0]}
	return hold_orbit(state, s, body)

# ---- Nova

static func _nova(state: Dictionary, s: Dictionary) -> Dictionary:
	if s.owner == "P3":
		var plan := AI._cached_or_plan(state, s, "orbit:sol", func(): return AI.search_orbit(state, s, "sol", 0, 3000))
		return AI._follow(state, s, plan)
	var foes := enemies(state, s)
	var t := nearest(foes, s.pos)
	if s.landed != "":
		if t.is_empty() or Hex.distance(t.pos, s.pos) > 28: return {}
		return {"takeoff": true}
	if low_fuel(s):
		var rf := refuel(state, s)
		if not rf.is_empty(): return rf
	var h := hunt(state, s, t)
	if not h.is_empty(): return h
	return hold_orbit(state, s, "terra")

# ---- Retribution

static func _retribution(state: Dictionary, s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	if s.owner == "P1":
		if s.get("parked", false): return {}
		if s.get("mission", false):
			if s.landed != "": return {"takeoff": true}
			var cl: Vector2i = SolarMap.body(map, "clandestine").hex
			var plan := AI._cached_or_plan(state, s, "stop:clandestine", func(): return AI.search_stop(state, s, cl, 3000))
			return AI._follow(state, s, plan)
		# Flotta della Libertà
		if low_fuel(s, 7):
			var rf := refuel(state, s)
			if not rf.is_empty(): return rf
		if s.landed != "" or s.vel == Vector2i.ZERO and s.pos == SolarMap.body(map, "clandestine").hex:
			if s.landed != "": return {"takeoff": true}
		var prey := nearest(enemies(state, s), s.pos)
		var hh := hunt(state, s, prey)
		# nessuna preda vicina: la flotta va a cercarla, anche lontano (altrimenti la partita si arena)
		if hh.is_empty() and not prey.is_empty(): hh = hunt(state, s, prey, 40)
		return hh if not hh.is_empty() else AI._drift_safe(state, s)
	# Enforcers
	var foes := enemies(state, s)
	var on_patrol := ScenRetribution.on_patrol(state, s)
	if on_patrol:
		foes = foes.filter(func(t): return ScenRetribution.patrol_distance(state, t.pos) <= 6)
	var t := nearest(foes, s.pos)
	if s.landed != "":
		if t.is_empty() or Hex.distance(t.pos, s.pos) > 25: return {}
		return {"takeoff": true}
	if low_fuel(s, 7):
		var rf2 := refuel(state, s)
		if not rf2.is_empty(): return rf2
	if not t.is_empty():
		var h := hunt(state, s, t)
		if not h.is_empty(): return h
	return hold_orbit(state, s, "terra")

# ---- The Fleet Mutiny

static func _mutiny(state: Dictionary, s: Dictionary) -> Dictionary:
	if s.owner == "P2":
		if s.landed != "": return {"takeoff": true}
		return hold_orbit(state, s, "terra")
	var foes := enemies(state, s)
	foes.sort_custom(func(a, b): return int(a.get("is_base", false)) < int(b.get("is_base", false)))
	var map := Rules.map_of(state)
	var terra: Vector2i = SolarMap.body(map, "terra").hex
	var near_terra := foes.filter(func(t): return Hex.distance(t.pos, terra) <= 3)
	var t := nearest(near_terra if not near_terra.is_empty() else foes, s.pos)
	if s.landed != "":
		if t.is_empty(): return {}
		return {"takeoff": true}
	if low_fuel(s, 7):
		var rf := refuel(state, s)
		if not rf.is_empty(): return rf
	var h := hunt(state, s, t)
	if not h.is_empty(): return h
	return hold_orbit(state, s, "terra")

# ---- Interplanetary War

static func _war(state: Dictionary, s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	if not state.ai.has(s.id): state.ai[s.id] = {}
	state.ai[s.id].nuke_now = false
	if int(s.inv.get("nuke", 0)) > 0:
		if s.landed != "": return {"takeoff": true}
		var target := _nuke_target(state, s.owner)
		var inertial := Rules.simulate(map, s.pos, s.vel, s.grav, Vector2i.ZERO, false, state.asteroids, state.special, false)
		if inertial.crash == target and (s.infinite_fuel or int(s.fuel) >= 1):
			var dodge := _dodge(state, s)
			if not dodge.is_empty():
				state.ai[s.id].nuke_now = true
				return dodge
		var plan := AI._cached_or_plan(state, s, "nuke:" + target, func(): return search_nuke(state, s, target, 2500))
		if not plan.is_empty(): return AI._follow(state, s, plan)
		return hold_orbit(state, s, "mars")
	if s.owner == "P1" and s.commercial:
		if float(s.mcr) >= 1.0: return land_at(state, s, "terra") if s.landed != "terra" else {}
		for w in ["luna", "venus"]:
			if float(state.sd.pool[w]) >= 5.0:
				if s.landed == w: return {}
				if s.landed != "": return {"takeoff": true}
				return land_at(state, s, w)
		if s.landed != "": return {}
		return land_at(state, s, "terra")
	var foes := enemies(state, s)
	var homes: Array = ScenWar.worlds(s.owner)
	var threats := foes.filter(func(t):
		for w in homes:
			if Hex.distance(t.pos, SolarMap.body(map, w).hex) <= 14: return true
		return false)
	# con forza doppia si passa all'offensiva ovunque
	var mine_str := 0
	var their_str := 0
	for x in state.ships:
		if not Rules.alive(x) or x.commercial: continue
		if x.owner == s.owner: mine_str += int(x.combat)
		else: their_str += int(x.combat)
	var offensive := mine_str >= 2 * maxi(1, their_str)
	if offensive: threats = foes
	var t2 := nearest(threats, s.pos)
	if s.landed != "":
		if t2.is_empty() and not (s.owner == "P2" and not foes.is_empty()): return {}
		return {"takeoff": true}
	if low_fuel(s, 7):
		var rf := refuel(state, s)
		if not rf.is_empty(): return rf
	if t2.is_empty() and s.owner == "P2": t2 = nearest(foes.filter(func(x): return not x.commercial), s.pos)
	var h := hunt(state, s, t2, 20 if offensive else 8)
	if not h.is_empty(): return h
	return hold_orbit(state, s, ScenWar.home(s.owner))

static func _nuke_target(state: Dictionary, pid: String) -> String:
	if pid == "P2": return "terra" if ScenWar.devastated(state, "terra") < 3 else "luna"
	var count := {}
	for x in state.ships:
		if x.owner == "P2" and Rules.alive(x) and x.landed != "": count[x.landed] = int(count.get(x.landed, 0)) + 1
	var best := "callisto"
	var n := 0
	for k in count:
		if int(count[k]) > n: n = int(count[k]); best = k
	return best

## La Terra arma testate solo quando i ribelli si nascondono a terra.
static func rebels_hiding(state: Dictionary) -> bool:
	var reb: Array = state.ships.filter(func(x): return x.owner == "P2" and Rules.alive(x))
	return not reb.is_empty() and reb.all(func(x): return x.landed != "")

## Spinta che evita lo schianto mantenendo la nave sicura (la testata prosegue da sola).
static func _dodge(state: Dictionary, s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	var best := []
	var best_v := 999
	for d in range(6):
		var r := Rules.simulate(map, s.pos, s.vel, s.grav, Hex.DIRS[d], false, state.asteroids, state.special, false)
		if r.crash != "" or r.offmap: continue
		var g := Vector2i.ZERO
		for a in r.grav: g += a
		var nxt := Rules.simulate(map, r.dest, r.vel, [g], Vector2i.ZERO, false, [], [], false)
		var v := Hex.length(r.vel) + (50 if nxt.crash != "" else 0)
		if v < best_v: best_v = v; best = [d]
	if best.is_empty() or best_v >= 50: return {}
	return {"burns": best}

## Rotta che porta la nave su una traiettoria d'impatto (per la testata) con carburante per scansarsi.
static func search_nuke(state: Dictionary, s: Dictionary, body_id: String, budget: int) -> Dictionary:
	var map := Rules.map_of(state)
	var b := SolarMap.body(map, body_id)
	var goal := func(n: Dictionary, r: Dictionary) -> bool:
		if r.offmap or (not s.infinite_fuel and int(n.fuel) < 1): return false
		var nx := Rules.simulate(map, n.pos, n.vel, [n.g], Vector2i.ZERO, false, [], [], false)
		return nx.crash == body_id
	var h := func(n: Dictionary) -> float: return float(AI.reach_bound(n.pos, n.vel + n.g, b.hex, 2))
	return AI._search(state, s, goal, h, budget, 0, false, 1.5)

# ---- Prospecting

static func _prospect(state: Dictionary, s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	var ceres: Vector2i = SolarMap.body(map, "ceres").hex
	var money := float(state.sd.mcr[s.owner])
	var stopped = s.landed == "" and s.vel == Vector2i.ZERO
	if s.landed != "": return {"takeoff": true}
	var fuel := int(s.fuel)
	var here_claim: Dictionary = state.sd.claims.get(ScenProspecting.key(s.pos), {})
	# vendere quando la stiva è ricca
	if int(s.ore10) >= 150 or int(s.inv.get("ct_shard", 0)) > 0 or (ShipTypes.free_cargo(s) < 1.0 and int(s.ore10) >= 10):
		if stopped and s.pos == ceres: return {}
		return _goto_stop(state, s, ceres)
	# fermi sulla propria concessione: si raccoglie finché la stiva si riempie
	if stopped and not here_claim.is_empty() and here_claim.owner == s.owner and ShipTypes.free_cargo(s) >= 1.0:
		return {}
	# a Ceres per il carburante
	if stopped and s.pos == ceres and fuel < int(s.max_fuel) and money >= 1.0: return {}
	if fuel <= 4 and money >= 4.0:
		if stopped and s.pos == ceres: return {}
		return _goto_stop(state, s, ceres)
	# piazzare una miniera automatica su un filone noto
	if int(s.inv.get("automated_mine", 0)) > 0:
		var ore := _known_ore(state, s, true)
		if not ore.is_empty():
			if stopped and s.pos == ore[0]: return {}
			return _goto_stop(state, s, ore[0])
	# tornare alla propria concessione quando ha accumulato minerale
	for k in state.sd.claims:
		var c: Dictionary = state.sd.claims[k]
		if c.owner == s.owner and int(c.stock10) >= 60 and ShipTypes.free_cargo(s) >= 5.0:
			return _goto_stop(state, s, c.hex)
	if fuel <= 3:
		# poco carburante e niente soldi: estrazione manuale sul filone più vicino
		if stopped and ScenProspecting.ore_at(state, s.pos): return {}
		var ore2 := _known_ore(state, s, false)
		if not ore2.is_empty() and fuel > 0: return _goto_stop(state, s, ore2[0])
		return AI._drift_safe(state, s)
	# prospettare l'asteroide inesplorato più vicino
	var targets: Array = state.asteroids.filter(func(h): return not state.sd.prospected.has(ScenProspecting.key(h)))
	targets.sort_custom(func(a, b): return Hex.distance(a, s.pos) < Hex.distance(b, s.pos))
	for h in targets.slice(0, 3):
		var plan := AI._cached_or_plan(state, s, "pass:%d,%d" % [h.x, h.y], func(): return search_pass(state, s, h, 900))
		if not plan.is_empty() and not plan.get("partial", false): return AI._follow(state, s, plan)
	if stopped and ScenProspecting.ore_at(state, s.pos): return {}
	return AI._drift_safe(state, s)

## Carburante stimato per fermarsi e tornare a Ceres a bassa velocità.
static func _home_cost(s: Dictionary, ceres: Vector2i) -> int:
	var d := Hex.distance(s.pos, ceres)
	if d == 0: return Hex.length(s.vel)
	return Hex.length(s.vel) + 2 + d / 6

## Frena verso la velocità zero senza uscire dalla plancia.
static func _brake(state: Dictionary, s: Dictionary) -> Dictionary:
	if s.vel == Vector2i.ZERO or int(s.fuel) <= 0: return AI._drift_safe(state, s)
	var map := Rules.map_of(state)
	var best := []
	var best_v := 999
	for d in range(6):
		var r := Rules.simulate(map, s.pos, s.vel, s.grav, Hex.DIRS[d], false, state.asteroids, state.special, s.access_special)
		if r.crash != "" or r.offmap or r.special: continue
		var v = Hex.length(r.vel) * 10 + r.asteroids.size() * 3
		if v < best_v: best_v = v; best = [d]
	if best.is_empty(): return AI._drift_safe(state, s)
	return {"burns": best}

## Passeggiata di prospezione: a velocità 1 si entra in un esagono nuovo per turno e si prosegue
## gratis in linea retta; ogni svolta di 60° costa 1 carburante. Ricerca in profondità su 8 turni
## del percorso con più asteroidi inesplorati (da fermi si parte in una delle sei direzioni).
static func _prospect_walk(state: Dictionary, s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	var near := false
	for h in state.asteroids:
		if Hex.distance(h, s.pos) <= 9 and not state.sd.prospected.has(ScenProspecting.key(h)): near = true; break
	if not near: return {}
	if Hex.length(s.vel) > 1 or not Rules.pending_sum(s) == Vector2i.ZERO: return {}
	var best := {"score": 0.0, "first": null}
	_walk(state, map, s.pos, s.vel, int(s.fuel), 0, [], {}, 0.0, best, s)
	if best.first == null or float(best.score) < 0.9: return {}
	return {"burns": best.first}

static func _walk(state: Dictionary, map: Dictionary, pos: Vector2i, vel: Vector2i, fuel: int, depth: int, first, seen: Dictionary, score: float, best: Dictionary, s: Dictionary) -> void:
	if score > float(best.score): best.score = score; best.first = first
	if depth == 8: return
	var options: Array = []
	if vel == Vector2i.ZERO:
		if fuel > 1:
			for d in range(6): options.append([d])
	else:
		options.append([])
		if fuel > 2:
			for d in range(6):
				var nv: Vector2i = vel + Hex.DIRS[d]
				if Hex.length(nv) == 1: options.append([d])
	for burns in options:
		var nv2: Vector2i = vel + Rules.burn_vector(burns)
		var dest: Vector2i = pos + nv2
		if not map.cells.has(dest) or state.special.has(dest) or map.gravity.has(dest): continue
		var sc = score - 0.45 * burns.size()
		var seen2 := seen
		if state.asteroids.has(dest) and not state.sd.prospected.has(ScenProspecting.key(dest)) and not seen.has(dest):
			seen2 = seen.duplicate()
			seen2[dest] = true
			sc += pow(0.92, depth)
		# una scheggia CT può disabilitare la nave per 4 turni: meglio non puntare verso il bordo
		if not map.cells.has(dest + nv2 * 5): sc -= 0.3
		_walk(state, map, dest, nv2, fuel - burns.size(), depth + 1, burns if depth == 0 else first, seen2, sc, best, s)

static func _goto_stop(state: Dictionary, s: Dictionary, h: Vector2i) -> Dictionary:
	var budget := 4000 if state.scenario == "prospecting" else 1800
	var plan := AI._cached_or_plan(state, s, "stop:%d,%d" % [h.x, h.y], func(): return AI.search_stop(state, s, h, budget))
	# con poco carburante un piano incompleto è un rischio: meglio fermarsi e ripianificare da fermi
	if plan.get("partial", false) and not s.infinite_fuel and int(s.fuel) <= 5 and s.vel != Vector2i.ZERO: return _brake(state, s)
	return AI._follow(state, s, plan)

static func _known_ore(state: Dictionary, s: Dictionary, free_only: bool) -> Array:
	var out := []
	for k in state.sd.prospected:
		if state.sd.prospected[k] != "ore": continue
		if free_only and state.sd.claims.has(k): continue
		var parts: PackedStringArray = k.split(",")
		out.append(Vector2i(int(parts[0]), int(parts[1])))
	out.sort_custom(func(a, b): return Hex.distance(a, s.pos) < Hex.distance(b, s.pos))
	return out

## Attraversare un esagono a velocità 1 (prospezione).
static func search_pass(state: Dictionary, s: Dictionary, hex: Vector2i, budget: int) -> Dictionary:
	var goal := func(n: Dictionary, r: Dictionary) -> bool: return not r.offmap and Hex.length(n.vel) == 1 and r.path.slice(1).has(hex)
	var h := func(n: Dictionary) -> float: return float(AI.h_arrive(n.pos, n.vel + n.g, hex, Vector2i.ZERO, 1, 0))
	return AI._search(state, s, goal, h, budget, 0, false, 1.5)

# ---------------------------------------------------------------- fasi speciali

static func ordnance(state: Dictionary) -> void:
	if state.scenario != "interplanetary-war": return
	var me := Rules.current_player(state)
	for s in state.ships:
		if s.owner == me and Rules.alive(s) and state.ai.get(s.id, {}).get("nuke_now", false):
			if Rules.launch(state, s.id, "nuke") == "": state.ai[s.id].nuke_now = false

## Fleet Mutiny: i ribelli in orbita terrestre sopprimono i lati della Terra.
static func combat(state: Dictionary) -> void:
	if state.scenario != "fleet-mutiny": return
	var me := Rules.current_player(state)
	for s in state.ships:
		if s.owner != me or not Rules.alive(s): continue
		var tg := ScenMutiny.suppress_target(state, s)
		if not tg.is_empty() and tg.body == "terra" and me == "P2": ScenMutiny.suppress(state, s.id)

static func resupply(state: Dictionary) -> void:
	var me := Rules.current_player(state)
	match state.scenario:
		"interplanetary-war":
			for s in state.ships:
				if s.owner != me or not Rules.alive(s): continue
				if int(s.inv.get("nuke", 0)) == 0 and not s.commercial and (me == "P2" or rebels_hiding(state)):
					Rules.load_ordnance(state, s.id, "nuke")
				for k in ["torpedo", "mine"]:
					var guard := 0
					while Rules.can_load(state, s, k) == "" and guard < 3 and int(s.inv.get(k, 0)) < 2:
						Rules.load_ordnance(state, s.id, k); guard += 1
			if ScenWar.can_buy_now(state, me) == "":
				var money := ScenWar.spendable(state, me)
				if money >= 150.0:
					ScenWar.open_mid_shop(state, me)
					_shop(state)
		"prospecting":
			for s in state.ships:
				if s.owner != me or not Rules.alive(s): continue
				for a in ScenProspecting.claim_actions(state, s): ScenProspecting.claim_action(state, s.id, a)
				if ScenProspecting.can_sell(state, s) == "": ScenProspecting.sell(state, s.id)
				if ScenProspecting.at_base(state, s):
					var need := int(s.max_fuel) - int(s.fuel)
					var cash := int(float(state.sd.mcr[me]))
					ScenProspecting.buy(state, s.id, "fuel", mini(need, maxi(0, cash - 2)) if cash < 25 else need)
					if float(state.sd.mcr[me]) >= 30.0 and int(s.inv.get("automated_mine", 0)) == 0:
						ScenProspecting.buy(state, s.id, "automated_mine")
					if float(state.sd.mcr[me]) >= 120.0 and int(s.inv.get("pm_grapples", 0)) == 0 and ShipTypes.free_cargo(s) >= 40.0:
						ScenProspecting.buy(state, s.id, "pm_grapples")
