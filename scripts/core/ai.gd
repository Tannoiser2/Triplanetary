class_name AI
extends RefCounted
## Comandante automatico. Pianifica le rotte con una ricerca A* sugli stati vettoriali
## (posizione, velocità, gravità in sospeso) e usa le stesse regole del giocatore umano.
## Non legge informazioni nascoste: decide solo su ciò che il suo lato può vedere.

const MAX_SPEED := 6
const DEFAULT_BUDGET := 2600

# ---------------------------------------------------------------- ingresso principale

static func is_ai_turn(state: Dictionary) -> bool:
	if state.over: return false
	if not state.pending_attack.is_empty():
		return Rules.player(state, state.pending_attack.defender).type == "ai"
	if state.phase == "setup":
		return Rules.player(state, state.setup.get("player", "P1")).type == "ai"
	return Rules.player(state, Rules.current_player(state)).type == "ai"

## Esegue un passo decisionale (una fase) per il giocatore automatico di turno.
static func play_step(state: Dictionary) -> void:
	if state.over: return
	if not state.pending_attack.is_empty():
		if Rules.player(state, state.pending_attack.defender).type == "ai": respond_counter(state)
		return
	match state.phase:
		"setup": _setup(state)
		"astrogation":
			plan_astrogation(state)
			Rules.end_phase(state)
		"ordnance":
			plan_ordnance(state)
			Rules.end_phase(state)
		"movement":
			Rules.end_phase(state)
		"combat":
			if not plan_combat(state): Rules.end_phase(state)
		"resupply":
			plan_resupply(state)
			Rules.end_phase(state)

static func _setup(state: Dictionary) -> void:
	match state.scenario:
		"escape":
			var mine: Array = state.ships.filter(func(s): return s.owner == "P1")
			Scenarios.choose_fugitive(state, mine[Rules.roll(state) % mine.size()].id)
		"lateral-7":
			Scenarios.auto_place(state)

# ---------------------------------------------------------------- astrogazione

static func plan_astrogation(state: Dictionary) -> void:
	var me := Rules.current_player(state)
	if not state.has("ai"): state.ai = {}
	for s in state.ships:
		if s.owner != me or not Rules.alive(s) or s.get("dummy", false): continue
		var plot := _decide(state, s)
		if OS.has_feature("debug_ai") or state.get("ai_trace", false):
			var memo: Dictionary = state.ai.get(s.id, {})
			var tr: Array = memo.get("trace", [])
			tr.append("T%d pos%s vel%s g%s fuel%d -> %s [%s]" % [state.turn, s.pos, s.vel, Rules.pending_sum(s), s.fuel, plot, memo.get("goal", "")])
			if tr.size() > 14: tr.pop_front()
			memo.trace = tr
			state.ai[s.id] = memo
		if plot.is_empty(): continue
		if Rules.set_plot(state, s.id, plot) != "":
			Rules.set_plot(state, s.id, {"burns": []})

static func _decide(state: Dictionary, s: Dictionary) -> Dictionary:
	if Rules.is_disabled(state, s): return {}
	match state.scenario:
		"grand-tour": return _grand_tour(state, s)
		"escape": return _escape(state, s)
		"lateral-7": return _lateral7(state, s)
	return {}

# ---- Grand Tour

static func _grand_tour(state: Dictionary, s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	var missing: Array = state.sd.required.filter(func(b): return not s.visited.has(b))
	if s.landed != "":
		if missing.is_empty(): return {}
		return {"takeoff": true}
	var orbiting := Rules.orbit_body(state, s)
	var fuel_bodies := ["terra", "venus", "mars", "callisto"]
	var fuel: int = 99 if s.infinite_fuel else int(s.fuel)
	if missing.is_empty() and orbiting == "terra":
		var sides := Rules.landing_sides(state, s)
		if not sides.is_empty() and fuel >= 1: return {"land": sides[0]}
	var memo: Dictionary = state.ai.get(s.id, {})
	var chosen: String = memo.get("chosen", "")
	# l'obiettivo scelto resta valido finché ha senso e ha un piano completo
	if chosen != "" and _gt_goal_relevant(chosen, missing, orbiting, fuel):
		var keep := _gt_plan(state, s, chosen)
		if not keep.is_empty() and not keep.get("partial", false): return _follow(state, s, keep)
	var candidates: Array = []
	if missing.is_empty():
		candidates.append("orbit:terra")
	if fuel <= 10 and not (orbiting in fuel_bodies):
		for b in fuel_bodies: candidates.append("orbit:" + b)
	else:
		var order: Array = missing.duplicate()
		order.sort_custom(func(a, b): return _reach_bound_body(map, s, a) < _reach_bound_body(map, s, b))
		for b in order.slice(0, 3):
			candidates.append(("orbit:" if (b in fuel_bodies and fuel <= 15) else "visit:") + b)
	var best := {}
	var best_goal := ""
	var best_score := INF
	for g in candidates:
		var plan := _gt_plan(state, s, g)
		if plan.is_empty() or plan.get("partial", false): continue
		var body: String = g.split(":")[1]
		var score := float(plan.turns) - (3.0 if (g.begins_with("orbit:") and missing.has(body)) else 0.0)
		if score < best_score: best_score = score; best = plan; best_goal = g
	if best.is_empty() and not candidates.has("orbit:terra"):
		for b in fuel_bodies:
			var g2: String = "orbit:" + b
			var p := _gt_plan(state, s, g2)
			if not p.is_empty() and not p.get("partial", false) and float(p.turns) < best_score:
				best_score = float(p.turns); best = p; best_goal = g2
	memo = state.ai.get(s.id, {})
	memo.chosen = best_goal
	state.ai[s.id] = memo
	return _follow(state, s, best)

static func _gt_goal_relevant(goal: String, missing: Array, orbiting: String, fuel: int) -> bool:
	var parts := goal.split(":")
	if parts[0] == "visit": return missing.has(parts[1])
	if parts[1] == "terra" and missing.is_empty(): return true
	if orbiting == parts[1]: return false
	return missing.has(parts[1]) or fuel <= 10

static func _gt_plan(state: Dictionary, s: Dictionary, goal: String) -> Dictionary:
	var parts := goal.split(":")
	if parts[0] == "visit":
		return _cached_or_plan(state, s, goal, func(): return search_visit(state, s, parts[1], 8, 1500))
	var reserve := 1 if parts[1] == "terra" else 0
	return _cached_or_plan(state, s, goal, func(): return search_orbit(state, s, parts[1], reserve, 3500))

# ---- Escape

static func _escape(state: Dictionary, s: Dictionary) -> Dictionary:
	if s.owner == "P1":
		if s.landed != "":
			# i trasporti partono scaglionati per confondere l'inseguitore
			var idx := ["pilgrim-a", "pilgrim-b", "pilgrim-c"].find(s.id)
			if int(state.turn) >= 1 + maxi(0, idx): return {"takeoff": true}
			return {}
		var plan := _cached_or_plan(state, s, "exit", func(): return search_exit(state, s, 3000))
		if plan.is_empty(): return _drift_safe(state, s)
		return _follow(state, s, plan)
	# Enforcers: ispezione, cattura e rientro
	if state.sd.get("captured_by", "") == s.id:
		if s.landed != "": return {}
		var b := Rules.orbit_body(state, s)
		if b in ["terra", "venus", "io"]:
			var sides := Rules.landing_sides(state, s)
			if not sides.is_empty(): return {"land": sides[0]}
		var best := {}
		for body in ["terra", "venus", "io"]:
			var p := search_orbit(state, s, body, 1, 1500)
			if not p.is_empty() and (best.is_empty() or p.turns < best.turns): best = p
		return _follow(state, s, best)
	var targets: Array = state.ships.filter(func(t): return t.owner == "P1" and Rules.alive(t) and t.landed == "" and not state.sd.inspected.has(t.id))
	if targets.is_empty():
		targets = state.ships.filter(func(t): return t.owner == "P1" and Rules.alive(t) and t.landed == "")
	if targets.is_empty():
		var hold := search_orbit(state, s, "terra", 2, 800)
		return _follow(state, s, hold) if not hold.is_empty() else _drift_safe(state, s)
	targets.sort_custom(func(a, b): return Hex.distance(a.pos, s.pos) < Hex.distance(b.pos, s.pos))
	var t: Dictionary = targets[0]
	var need_match := Rules.is_disabled(state, t)
	var plan2 := search_intercept(state, s, t, 0 if need_match else 1, 1800)
	if plan2.is_empty(): return _drift_safe(state, s)
	return {"burns": plan2.burns[0]}

# ---- Lateral 7

static func _lateral7(state: Dictionary, s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	if s.owner == "P2":
		if s.type == "liner":
			if state.sd.passengers != s.id: return _drift_safe(state, s)
			if s.landed != "": return {"takeoff": true}
			var low: bool = int(s.fuel) <= 2 and not (Rules.orbit_body(state, s) in ["terra", "mars", "callisto"])
			if low:
				var refuel := {}
				for b in ["mars", "terra", "callisto"]:
					var p := search_orbit(state, s, b, 0, 1400)
					if not p.is_empty() and (refuel.is_empty() or p.turns < refuel.turns): refuel = p
				if not refuel.is_empty(): return _follow(state, s, refuel)
			var go := _cached_or_plan(state, s, "visit:ganymede", func(): return search_visit(state, s, "ganymede", 0, 3000))
			return _follow(state, s, go) if not go.is_empty() else _drift_safe(state, s)
		# dreadnought: insegue i pirati rilevati, altrimenti scorta la nave di linea
		if s.locked: return {}
		var foes: Array = state.ships.filter(func(t): return t.owner == "P1" and Rules.alive(t) and not t.get("dummy", false) and Rules.is_known(state, "P2", t))
		var holder := Rules.ship(state, state.sd.passengers)
		if not holder.is_empty() and holder.owner == "P1": foes = [holder]
		var target: Dictionary = foes[0] if not foes.is_empty() else holder
		if foes.size() > 1:
			foes.sort_custom(func(a, b): return Hex.distance(a.pos, s.pos) < Hex.distance(b.pos, s.pos))
			target = foes[0]
		if target.is_empty(): return {}
		var p2 := search_intercept(state, s, target, 1, 1600)
		if p2.is_empty(): return _drift_safe(state, s)
		return {"burns": p2.burns[0], "dummies": []}
	# Pirati
	var holder2 := Rules.ship(state, state.sd.passengers)
	if holder2.id == s.id:
		var cl := SolarMap.body(map, "clandestine")
		if s.pos == cl.hex and s.vel == Vector2i.ZERO: return {}
		var home := _cached_or_plan(state, s, "stop:clandestine", func(): return search_stop(state, s, cl.hex, 3000))
		return _follow(state, s, home) if not home.is_empty() else _drift_safe(state, s)
	if s.landed != "": return {"takeoff": true}
	if holder2.is_empty() or holder2.landed != "":
		# attende la partenza della nave di linea restando immobile fra gli asteroidi
		return {}
	var match_needed: bool = holder2.owner == "P2" and (Rules.is_disabled(state, holder2) or holder2.surrendered)
	var pi := search_intercept(state, s, holder2, 0 if match_needed else 2, 2200)
	if not pi.is_empty() and not pi.get("partial", false):
		return {"burns": pi.burns[0], "dummies": []}
	# imboscata: la nave di linea deve passare da Ganimede, i pirati la aspettano in orbita
	var amb := _cached_or_plan(state, s, "orbit:ganymede", func(): return search_orbit(state, s, "ganymede", 2, 2500))
	if Rules.orbit_body(state, s) == "ganymede": return {"burns": [], "dummies": []}
	if not amb.is_empty():
		var pl := _follow(state, s, amb)
		pl.dummies = []
		return pl
	if pi.is_empty(): return _drift_safe(state, s)
	return {"burns": pi.burns[0], "dummies": []}

# ---------------------------------------------------------------- piani memorizzati

static func _cached_or_plan(state: Dictionary, s: Dictionary, goal: String, planner: Callable) -> Dictionary:
	var memo: Dictionary = state.ai.get(s.id, {})
	var goals: Dictionary = memo.get("goals", {})
	var entry: Dictionary = goals.get(goal, {})
	if int(entry.get("turn", -1)) == int(state.turn): return entry.plan
	if int(entry.get("turn", -1)) == int(state.turn) - 1 and not entry.plan.is_empty():
		var plan: Dictionary = entry.plan
		if plan.expect.size() > 1 and plan.expect[1].pos == s.pos and plan.expect[1].vel == s.vel and Rules.pending_sum(s) == _expected_g(plan, 1):
			var shifted := {"burns": plan.burns.slice(1), "expect": plan.expect.slice(1), "turns": int(plan.turns) - 1, "partial": plan.get("partial", false)}
			if not shifted.burns.is_empty():
				goals[goal] = {"turn": state.turn, "plan": shifted}
				memo.goals = goals
				state.ai[s.id] = memo
				return shifted
	var fresh: Dictionary = planner.call()
	goals[goal] = {"turn": state.turn, "plan": fresh}
	# dimentica i piani vecchi
	for k in goals.keys():
		if int(goals[k].turn) < int(state.turn) - 1: goals.erase(k)
	memo.goals = goals
	memo.goal = goal
	state.ai[s.id] = memo
	return fresh

static func _expected_g(plan: Dictionary, i: int) -> Vector2i:
	return plan.expect[i].get("g", Vector2i.ZERO)

static func _follow(state: Dictionary, s: Dictionary, plan: Dictionary) -> Dictionary:
	if plan.is_empty() or plan.burns.is_empty(): return _drift_safe(state, s)
	var burns: Array = plan.burns[0]
	if not s.infinite_fuel and burns.size() > int(s.fuel): return _drift_safe(state, s)
	return {"burns": burns}

## Senza un piano valido: frena e resta sulla plancia, evitando corpi e asteroidi.
static func _drift_safe(state: Dictionary, s: Dictionary) -> Dictionary:
	if s.landed != "": return {}
	var map := Rules.map_of(state)
	var options: Array = [[]]
	if s.infinite_fuel or int(s.fuel) > 0:
		for d in range(6): options.append([d])
	var best: Array = []
	var best_score := INF
	for burns in options:
		var r := Rules.simulate(map, s.pos, s.vel, s.grav, Rules.burn_vector(burns), false, state.asteroids, state.special, s.access_special)
		if r.crash != "" or r.offmap or r.special: continue
		var g := Vector2i.ZERO
		for a in r.grav: g += a
		var node := {"pos": r.dest, "vel": r.vel, "g": g, "fuel": int(s.fuel) - burns.size()}
		var frugal := 0.4 if (s.infinite_fuel or int(s.fuel) > 4) else 3.0
		var score: float = float(Hex.length(r.vel)) + frugal * burns.size() + 3.0 * r.asteroids.size()
		if not _survivable(map, state, s, node): score += 100.0
		if not _can_stop_on_map(map, r.dest, r.vel + g): score += 20.0
		if score < best_score: best_score = score; best = burns
	return {"burns": best}

# ---------------------------------------------------------------- ricerca A*

## Stato del nodo: [pos, vel, gsum, fuel, turns, cost, parent, burns, orbit_body, visits]
static func _search(state: Dictionary, s: Dictionary, goal: Callable, heuristic: Callable, budget: int, reserve: int, allow_offmap := false, weight := 1.3) -> Dictionary:
	var map := Rules.map_of(state)
	var start := {"pos": s.pos, "vel": s.vel, "g": Rules.pending_sum(s), "fuel": int(s.fuel), "turns": 0, "cost": 0.0, "parent": -1, "burns": [], "orbit": ""}
	var nodes: Array = [start]
	var heap: Array = [] # [f, index]
	_push(heap, [heuristic.call(start), 0])
	var seen := {}
	var best_idx := -1
	var best_h := INF
	var infinite: bool = s.infinite_fuel
	var speed_cap := maxi(MAX_SPEED, Hex.length(s.vel + Rules.pending_sum(s)) + 1)
	var expansions := 0
	while not heap.is_empty() and expansions < budget:
		var top: Array = _pop(heap)
		var idx: int = top[1]
		var node: Dictionary = nodes[idx]
		expansions += 1
		var options: Array = [[]]
		if infinite or int(node.fuel) > reserve:
			for d in range(6): options.append([d])
		for burns in options:
			var bv := Rules.burn_vector(burns)
			var r := Rules.simulate(map, node.pos, node.vel, [node.g], bv, false, state.asteroids, state.special, s.access_special)
			if r.crash != "" or r.special: continue
			var g := Vector2i.ZERO
			for a in r.grav: g += a
			var child := {"pos": r.dest, "vel": r.vel, "g": g, "fuel": int(node.fuel) - burns.size(),
				"turns": int(node.turns) + 1, "parent": idx, "burns": burns, "orbit": "", "r": r}
			if burns.is_empty() and Hex.length(r.vel) == 1 and map.gravity.has(node.pos) and map.gravity.has(r.dest):
				for ga in map.gravity[node.pos]:
					for gb in map.gravity[r.dest]:
						if ga.body == gb.body: child.orbit = ga.body
			var hazard := 0.0
			if not r.asteroids.is_empty(): hazard = 4.0 * r.asteroids.size()
			child.cost = float(node.cost) + 1.0 + 0.04 * burns.size() + hazard
			if Hex.length(r.vel) > speed_cap: continue
			if goal.call(child, r) and (r.offmap or _survivable(map, state, s, child)):
				nodes.append(child)
				return _extract(nodes, nodes.size() - 1)
			if r.offmap: continue
			if not allow_offmap and not _can_stop_on_map(map, r.dest, r.vel): continue
			var key := _key(child)
			if seen.has(key) and float(seen[key]) <= child.cost: continue
			seen[key] = child.cost
			child.erase("r")
			nodes.append(child)
			var h: float = heuristic.call(child)
			if h < best_h: best_h = h; best_idx = nodes.size() - 1
			_push(heap, [child.cost + weight * h, nodes.size() - 1])
	if best_idx > 0 and allow_offmap == false:
		var partial := _extract(nodes, best_idx)
		partial.partial = true
		return partial
	return {}

## Frenando di un esagono per turno, la nave si fermerebbe ancora sulla plancia?
static func _can_stop_on_map(map: Dictionary, pos: Vector2i, vel: Vector2i) -> bool:
	var L := Hex.length(vel)
	if L <= 2: return true
	var p := Hex.to_point(pos) + Hex.to_point(vel) * (float(L - 1) * 0.5)
	return map.cells.has(Hex.from_point(p))

## Dopo aver raggiunto l'obiettivo la nave deve poter restare sulla plancia per qualche turno.
static func _survivable(map: Dictionary, state: Dictionary, s: Dictionary, node: Dictionary) -> bool:
	var pos: Vector2i = node.pos; var vel: Vector2i = node.vel; var grav: Array = [node.g]
	var fuel: int = 99 if s.infinite_fuel else int(node.fuel)
	for _turn in range(9):
		var best := {}
		var best_speed := 999
		var options: Array = [Vector2i.ZERO]
		if fuel > 0:
			for d in Hex.DIRS: options.append(d)
		for b in options:
			var r := Rules.simulate(map, pos, vel, grav, b, false, state.asteroids, state.special, s.access_special)
			if r.crash != "" or r.offmap or r.special: continue
			var sp := Hex.length(r.vel) * 10 + (0 if b == Vector2i.ZERO else 1)
			if sp < best_speed: best_speed = sp; best = r; best.burned = b != Vector2i.ZERO
		if best.is_empty(): return false
		pos = best.dest; vel = best.vel; grav = best.grav
		if best.burned: fuel -= 1
		if Hex.length(vel) <= 1: return true
	return true

static func _extract(nodes: Array, idx: int) -> Dictionary:
	var burns: Array = []
	var expect: Array = []
	var i := idx
	while i >= 0:
		var n: Dictionary = nodes[i]
		expect.push_front({"pos": n.pos, "vel": n.vel, "g": n.g})
		if int(n.parent) >= 0: burns.push_front(n.burns)
		i = int(n.parent)
	return {"burns": burns, "expect": expect, "turns": burns.size()}

static func _key(n: Dictionary) -> int:
	var p: Vector2i = n.pos; var v: Vector2i = n.vel; var g: Vector2i = n.g
	return (((((p.x + 64) * 256 + (p.y + 64)) * 32 + (v.x + 16)) * 32 + (v.y + 16)) * 32 + (g.x + 16)) * 32 + (g.y + 16)

static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent][0] <= heap[i][0]: break
		var tmp: Array = heap[parent]; heap[parent] = heap[i]; heap[i] = tmp
		i = parent

static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty(): return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1; var r := l + 1; var m := i
		if l < n and heap[l][0] < heap[m][0]: m = l
		if r < n and heap[r][0] < heap[m][0]: m = r
		if m == i: break
		var tmp: Array = heap[m]; heap[m] = heap[i]; heap[i] = tmp
		i = m
	return top

## Euristica: per ogni asse cubico il moto è 1D con accelerazione |a| <= 1 per turno.
## La tabella dà i turni minimi per portare (scarto, velocità relativa) dentro |x| <= R, |v| <= S.
const TAB_X := 110
const TAB_V := 12
static var _tables := {}

static func _table(S: int, R: int) -> PackedInt32Array:
	var key := S * 100 + R
	if _tables.has(key): return _tables[key]
	var w := TAB_V * 2 + 1
	var size := (TAB_X * 2 + 1) * w
	var dist := PackedInt32Array()
	dist.resize(size)
	dist.fill(999)
	var queue: Array[int] = []
	for x in range(-TAB_X, TAB_X + 1):
		for v in range(-TAB_V, TAB_V + 1):
			if absi(x) <= R and absi(v) <= S:
				var i := (x + TAB_X) * w + (v + TAB_V)
				dist[i] = 0
				queue.append(i)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]; head += 1
		var x := cur / w - TAB_X
		var v := cur % w - TAB_V
		var px := x - v
		if px < -TAB_X or px > TAB_X: continue
		for a in [-1, 0, 1]:
			var pv: int = v - a
			if pv < -TAB_V or pv > TAB_V: continue
			var pi := (px + TAB_X) * w + (pv + TAB_V)
			if dist[pi] == 999:
				dist[pi] = dist[cur] + 1
				queue.append(pi)
	_tables[key] = dist
	return dist

## Turni minimi stimati per avere |pos - tpos| <= R (per asse) e |vel - tvel| <= S.
static func h_arrive(pos: Vector2i, vel: Vector2i, tpos: Vector2i, tvel: Vector2i, S: int, R: int) -> int:
	var tab := _table(S, R)
	var w := TAB_V * 2 + 1
	var dp := pos - tpos
	var dv := vel - tvel
	var xs := [dp.x, dp.y, -dp.x - dp.y]
	var vs := [dv.x, dv.y, -dv.x - dv.y]
	var best := 0
	for i in range(3):
		var x: int = xs[i]; var v: int = vs[i]
		if absi(x) > TAB_X or absi(v) > TAB_V: return 60 + Hex.length(dp)
		best = maxi(best, tab[(x + TAB_X) * w + (v + TAB_V)])
	return best

## Minimo numero di turni (stima ottimistica) per portarsi entro `radius` da `target`.
static func reach_bound(pos: Vector2i, vel: Vector2i, target: Vector2i, radius: int) -> int:
	for t in range(0, 40):
		var p := pos + vel * t
		if Hex.distance(p, target) - radius <= t * (t + 1) / 2: return t
	return 40

static func _reach_bound_body(map: Dictionary, s: Dictionary, body_id: String) -> int:
	var b := SolarMap.body(map, body_id)
	return reach_bound(s.pos, s.vel + Rules.pending_sum(s), b.hex, 2 if body_id == "sol" else 1)

static func search_visit(state: Dictionary, s: Dictionary, body_id: String, reserve: int, budget: int) -> Dictionary:
	var map := Rules.map_of(state)
	var b := SolarMap.body(map, body_id)
	var radius := 2 if body_id == "sol" and not map.sol_classic else 1
	var goal := func(_n: Dictionary, r: Dictionary) -> bool: return not r.offmap and r.visits.has(body_id) and (s.infinite_fuel or int(_n.fuel) >= reserve)
	var h := func(n: Dictionary) -> float: return float(reach_bound(n.pos, n.vel + n.g, b.hex, radius))
	return _search(state, s, goal, h, budget, 0)

static func search_orbit(state: Dictionary, s: Dictionary, body_id: String, reserve: int, budget: int) -> Dictionary:
	var map := Rules.map_of(state)
	var b := SolarMap.body(map, body_id)
	var goal := func(n: Dictionary, r: Dictionary) -> bool: return not r.offmap and n.orbit == body_id and (s.infinite_fuel or int(n.fuel) >= reserve)
	var h := func(n: Dictionary) -> float:
		return float(h_arrive(n.pos, n.vel + n.g, b.hex, Vector2i.ZERO, 1, 1) + 1)
	var plan := _search(state, s, goal, h, budget, 0, false, 1.5)
	if not plan.is_empty() and not plan.get("partial", false): return plan
	# avvicinamento rilassato: entra nel campo di gravità a bassa velocità, l'inserimento si rifinisce dopo
	var approach := func(n: Dictionary, r: Dictionary) -> bool:
		return not r.offmap and Hex.distance(n.pos, b.hex) <= 2 and Hex.length(n.vel + n.g) <= 2 and (s.infinite_fuel or int(n.fuel) >= reserve + 3)
	var h2 := func(n: Dictionary) -> float: return float(h_arrive(n.pos, n.vel + n.g, b.hex, Vector2i.ZERO, 2, 2))
	var plan2 := _search(state, s, approach, h2, budget, 0, false, 1.5)
	return plan2 if not plan2.is_empty() else plan

static func search_stop(state: Dictionary, s: Dictionary, hex: Vector2i, budget: int) -> Dictionary:
	var goal := func(n: Dictionary, r: Dictionary) -> bool: return n.pos == hex and n.vel == Vector2i.ZERO and not r.offmap
	var h := func(n: Dictionary) -> float: return float(h_arrive(n.pos, n.vel + n.g, hex, Vector2i.ZERO, 0, 0))
	return _search(state, s, goal, h, budget, 0, false, 1.5)

## Uscita dal bordo oltre Giove (righe r < 0), preferibilmente con carburante per fermarsi.
static func search_exit(state: Dictionary, s: Dictionary, budget: int) -> Dictionary:
	var goal := func(n: Dictionary, r: Dictionary) -> bool:
		return r.offmap and r.dest.y < 0 and int(n.fuel) >= Hex.length(r.vel) + 1
	var h := func(n: Dictionary) -> float:
		var vy: int = n.vel.y + n.g.y
		for t in range(0, 40):
			if n.pos.y + vy * t - t * (t + 1) / 2 < 0: return float(t)
		return 40.0
	var plan := _search(state, s, goal, h, budget, 0, true)
	if not plan.is_empty(): return plan
	var goal2 := func(_n: Dictionary, r: Dictionary) -> bool: return r.offmap and r.dest.y < 0
	return _search(state, s, goal2, h, budget, 0, false)

## Intercetta un bersaglio che si suppone prosegua per inerzia.
## mode 1: portarsi a distanza ≤ 1 con velocità relativa ≤ 2 (fuoco); mode 0: accoppiare la rotta.
static func search_intercept(state: Dictionary, s: Dictionary, t: Dictionary, mode: int, budget: int) -> Dictionary:
	var map := Rules.map_of(state)
	var track: Array = [{"pos": t.pos, "vel": t.vel}]
	var pos: Vector2i = t.pos; var vel: Vector2i = t.vel; var grav: Array = t.grav.duplicate()
	if t.landed != "":
		for i in range(30): track.append({"pos": t.pos, "vel": Vector2i.ZERO})
	else:
		for i in range(30):
			var r := Rules.simulate(map, pos, vel, grav, Vector2i.ZERO, false, [], [], true)
			pos = r.dest; vel = r.vel; grav = r.grav
			track.append({"pos": pos, "vel": vel})
			if r.crash != "" or r.offmap: break
	var last := track.size() - 1
	# il bersaglio è fermo durante il nostro segmento: dopo k nostre mosse ha mosso k-1 volte
	var goal := func(n: Dictionary, r: Dictionary) -> bool:
		if r.offmap: return false
		var tp: Dictionary = track[clampi(int(n.turns) - 1, 0, last)]
		if mode == 0: return n.pos == tp.pos and n.vel == tp.vel
		var reach := 999
		for hh in r.path: reach = mini(reach, Hex.distance(hh, tp.pos))
		if mode == 2: return reach <= 2 and Hex.distance(n.vel, tp.vel) <= 3
		return reach <= 1 and Hex.distance(n.vel, tp.vel) <= 2
	var h := func(n: Dictionary) -> float:
		var tp: Dictionary = track[clampi(int(n.turns), 0, last)]
		var sv = [0, 2, 3][mode]
		var rr = [0, 1, 2][mode]
		return float(h_arrive(n.pos, n.vel + n.g, tp.pos, tp.vel, sv, rr))
	return _search(state, s, goal, h, budget, 0, false, 1.5)

# ---------------------------------------------------------------- ordigni, combattimento, rifornimento

static func plan_ordnance(state: Dictionary) -> void:
	var me := Rules.current_player(state)
	for s in state.ships:
		if s.owner != me or not Rules.alive(s) or s.get("dummy", false): continue
		if int(s.inv.get("torpedo", 0)) <= 0 or Rules.can_launch(state, s, "torpedo") != "": continue
		var map := Rules.map_of(state)
		for t in state.ships:
			if t.owner == me or not Rules.alive(t) or t.landed != "" or t.get("dummy", false) or not Rules.is_known(state, me, t): continue
			if Hex.distance(t.pos, s.pos) > 6: continue
			# prova le dodici accelerazioni di lancio: il siluro deve finire sul bersaglio
			var t_next := Rules.simulate(map, t.pos, t.vel, t.grav, Vector2i.ZERO, false, [], [], true)
			for d1 in range(6):
				for extra in [-1, d1]:
					var burns: Array = [d1] if extra < 0 else [d1, extra]
					var r := Rules.simulate(map, s.pos, s.vel, s.grav, Rules.burn_vector(burns), false, [], [], true)
					if r.path.has(t.pos) or r.dest == t_next.dest:
						if Rules.launch(state, s.id, "torpedo", burns) == "": return

## Dichiara un attacco favorevole, se possibile di gruppo.
## Restituisce true se un attacco è stato avviato o risolto.
static func plan_combat(state: Dictionary) -> bool:
	var me := Rules.current_player(state)
	var now := Rules.tick(state)
	var shooters: Array = state.ships.filter(func(s): return s.owner == me and Rules.can_fire(state, s) and int(s.attacked_tick) != now)
	if shooters.is_empty(): return false
	var best := {}
	var best_score := 0.0
	var risk_weight := 1.1 if state.scenario == "grand-tour" else 0.6
	for t in state.ships:
		if not Rules.can_be_attacked(state, me, t) or int(t.targeted_tick) == now: continue
		# gruppo: tutte le navi che da sole avrebbero almeno una possibilità
		var group: Array = []
		for a in shooters:
			var p1 := Rules.attack_preview(state, [a], [t])
			if int(p1.column) >= 0 and _chance(p1) > 0.0: group.append(a)
		if group.is_empty(): continue
		var candidates: Array = [group]
		for a2 in group:
			if group.size() > 1: candidates.append([a2])
		for g in candidates:
			var p := Rules.attack_preview(state, g, [t])
			if int(p.column) < 0: continue
			var hit := _chance(p)
			var risk := 0.0
			if not t.commercial:
				var back := Rules.attack_preview(state, [t], g)
				if int(back.column) >= 0: risk = _chance(back)
			var score = hit - risk_weight * risk + (0.0 if state.scenario == "grand-tour" else 0.3) - 0.05 * g.size()
			if t.get("passengers", false): score = hit - 0.2 * risk
			if hit >= 0.3 and score > best_score:
				best_score = score
				best = {"a": g.map(func(x): return x.id), "t": t.id}
	if best.is_empty(): return false
	if Rules.declare_attack(state, best.a, [best.t]) != "": return false
	if Rules.player(state, state.pending_attack.defender).type == "ai": respond_counter(state)
	return true

static func _chance(p: Dictionary) -> float:
	var hit := 0.0
	for res in p.chances:
		if res != "-": hit += float(p.chances[res]) / 6.0
	return hit

static func respond_counter(state: Dictionary) -> void:
	var cands := Rules.counter_candidates(state)
	var att: Array = state.pending_attack.attackers
	if not cands.is_empty():
		var p := Rules.attack_preview(state, cands.map(func(id): return Rules.ship(state, id)), att.map(func(id): return Rules.ship(state, id)))
		if int(p.column) < 0: cands = []
	Rules.resolve_attack(state, cands, att if not cands.is_empty() else [])

static func plan_resupply(state: Dictionary) -> void:
	var me := Rules.current_player(state)
	for s in state.ships:
		if s.owner != me or not Rules.alive(s) or s.get("dummy", false): continue
		match state.scenario:
			"escape":
				if me == "P2":
					for t in state.ships:
						if t.owner == "P1" and Rules.matched(s, t): Scenarios.inspect(state, s.id, t.id)
			"lateral-7":
				var holder := Rules.ship(state, state.sd.passengers)
				if me == "P1" and not holder.is_empty() and holder.owner == "P2" and Rules.matched(s, holder):
					Scenarios.transfer_passengers(state, holder.id, s.id)
				for kind in ["mine", "torpedo"]:
					while Rules.can_load(state, s, kind) == "" and int(s.inv[kind]) < 2:
						Rules.load_ordnance(state, s.id, kind)
