class_name ScenNova
extends RefCounted
## NOVA — WestBloc (P1), EastBloc (P2) e Alieni (P3).
## Le colonie si scelgono e si tirano a sorte, i blocchi comprano 50 punti di forza,
## gli alieni entrano dal bordo di Giove con quattro corsari carichi di bombe Nova.

const COLONIES := ["venus", "mars", "ceres", "callisto", "clandestine", "mercury"]

static func setup(state: Dictionary) -> void:
	state.sd = {"terra": {}, "luna": {}, "colony": {}, "kills": {"P1": 0, "P2": 0}}
	state.phase = "setup"
	state.setup = {"step": "choose", "player": "P2", "kind": "terra3", "title": "Lati della Terra",
		"prompt": "EastBloc: scegli tre lati adiacenti della Terra. Gli altri tre vanno al WestBloc.",
		"options": _terra_options()}
	Rules.log_event(state, "Nova: EastBloc e WestBloc si spartiscono la Terra, poi la Luna; le colonie lontane si tirano a sorte.", "info")

static func _terra_options() -> Array:
	var out := []
	for i in range(6):
		out.append({"value": i, "label": "Lati %d-%d-%d" % [i + 1, (i + 1) % 6 + 1, (i + 2) % 6 + 1]})
	return out

static func choose(state: Dictionary, value: int) -> String:
	var st: Dictionary = state.setup
	match st.kind:
		"terra3":
			var east := [value, (value + 1) % 6, (value + 2) % 6]
			for side in range(6): state.sd.terra[str(side)] = "P2" if east.has(side) else "P1"
			Rules.log_event(state, "EastBloc prende i lati %s della Terra." % ", ".join(east.map(func(x): return str(x + 1))), "info")
			state.setup = {"step": "choose", "player": "P1", "kind": "luna1", "title": "Colonia lunare",
				"prompt": "WestBloc: scegli il lato della Luna per la tua colonia.", "options": _luna_options(state)}
		"luna1":
			state.sd.luna[str(value)] = "P1"
			state.setup = {"step": "choose", "player": "P2", "kind": "luna2", "title": "Colonia lunare",
				"prompt": "EastBloc: scegli un altro lato della Luna.", "options": _luna_options(state)}
		"luna2":
			state.sd.luna[str(value)] = "P2"
			_roll_colonies(state)
			_build_bases(state)
			if state.options.get("nova_allied", true): _befriend(state)
			_open_bloc_shop(state, "P1")
	return ""

static func _luna_options(state: Dictionary) -> Array:
	var out := []
	for i in range(6):
		if not state.sd.luna.has(str(i)): out.append({"value": i, "label": "Lato %d" % (i + 1)})
	return out

static func _roll_colonies(state: Dictionary) -> void:
	var a := 0; var b := 0
	while a == b:
		a = Rules.roll(state); b = Rules.roll(state)
	state.sd.colony = {"P1": COLONIES[a - 1], "P2": COLONIES[b - 1]}
	var map := Rules.map_of(state)
	Rules.log_event(state, "Colonie lontane: WestBloc a %s (dado %d), EastBloc a %s (dado %d)." % [SolarMap.body(map, COLONIES[a - 1]).name, a, SolarMap.body(map, COLONIES[b - 1]).name, b], "info")

static func _build_bases(state: Dictionary) -> void:
	state.bases = []
	var map := Rules.map_of(state)
	for side in range(6):
		var o: String = state.sd.terra[str(side)]
		state.bases.append({"id": "base-terra-%d" % side, "body": "terra", "side": side, "owner": o, "active": true, "defense": true, "fuel": true, "ordnance": true, "kind": "planetary"})
	for k in state.sd.luna:
		state.bases.append({"id": "base-luna-%s" % k, "body": "luna", "side": int(k), "owner": state.sd.luna[k], "active": true, "defense": true, "fuel": true, "ordnance": true, "kind": "planetary"})
	for pid in ["P1", "P2"]:
		var bid: String = state.sd.colony[pid]
		if bid in ["terra", "luna"]: continue
		var body := SolarMap.body(map, bid)
		if body.asteroid_base:
			state.bases.append({"id": "base-%s" % bid, "body": bid, "side": -1, "owner": pid, "active": true, "defense": false, "fuel": true, "ordnance": true, "kind": "asteroid"})
		else:
			var sides: Array = body.base_sides if not body.base_sides.is_empty() else [0]
			var side: int = int(sides[Rules.roll(state) % sides.size()])
			state.bases.append({"id": "base-%s-%d" % [bid, side], "body": bid, "side": side, "owner": pid, "active": true, "defense": true, "fuel": true, "ordnance": true, "kind": "planetary"})

const BLOC_ITEMS := ["dreadnought", "frigate", "corsair", "corvette", "packet", "liner", "transport", "tanker"]

## I blocchi rivali si concedono le basi a vicenda contro gli alieni (regola facoltativa del manuale).
static func _befriend(state: Dictionary) -> void:
	for b in state.bases:
		if b.owner == "P1": b.friends = ["P2"]
		elif b.owner == "P2": b.friends = ["P1"]

static func _open_bloc_shop(state: Dictionary, pid: String) -> void:
	Fleet.open_shop(state, pid, 50.0, "pts", BLOC_ITEMS, {"title": "Flotta del %s" % Rules.player(state, pid).name,
		"note": "50 punti di forza; le navi commerciali costano metà."})

static func shop_done(state: Dictionary, pid: String, _cart: Dictionary, queue: Array, _spent: float) -> void:
	var worlds := ["terra", "luna", state.sd.colony[pid]]
	Fleet.open_deploy(state, pid, queue, {"landed": worlds}, "Schieramento: le navi partono dalle basi amiche")

static func step_done(state: Dictionary) -> void:
	var pid: String = state.setup.player
	if state.setup.step == "deploy" and pid == "P1":
		_open_bloc_shop(state, "P2")
	elif state.setup.step == "deploy" and pid == "P2":
		var q := []
		var names := ["Ombra di Proxima", "Silenzio", "Fiamma Fredda", "Ultima Luce"]
		for i in range(4): q.append({"type": "corsair", "name": "Alieno %s" % names[i], "inv": {"mine": 1}, "flags": {"nova_bomb": true}})
		Fleet.open_deploy(state, "P3", q, {"edge": "jupiter"}, "Ingresso dal bordo di Giove a velocità 1")
	else:
		_start(state)

static func _start(state: Dictionary) -> void:
	# ordine dei segmenti tirato a sorte
	var order: Array = state.players.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := Rules.roll(state) % (i + 1)
		var tmp = order[i]; order[i] = order[j]; order[j] = tmp
	state.players = order
	state.phase = "astrogation"
	state.seg = 0
	state.turn = 1
	state.setup = {}
	Rules.log_event(state, "Ordine di gioco: %s." % ", ".join(order.map(func(p): return p.name)), "info")

static func deploy_score(state: Dictionary, _unit: Dictionary, h: Vector2i, spot: Dictionary) -> float:
	var map := Rules.map_of(state)
	if spot.mode == "edge":
		return -absf(float(Hex.to_point(h).x - Hex.to_point(SolarMap.body(map, "sol").hex).x))
	if spot.body == "terra": return 3.0
	if spot.body == "luna": return 2.0
	return 1.0

## Un alieno disabilitato che andrà comunque perso conta come distrutto.
static func doomed(state: Dictionary, s: Dictionary) -> bool:
	if not Rules.is_disabled(state, s): return false
	var map := Rules.map_of(state)
	var pos: Vector2i = s.pos; var vel: Vector2i = s.vel; var grav: Array = s.grav.duplicate()
	for _i in range(Rules.disabled_turns(state, s) + 1):
		var r := Rules.simulate(map, pos, vel, grav, Vector2i.ZERO, false, [], [], true)
		if r.crash != "" or r.offmap: return true
		pos = r.dest; vel = r.vel; grav = r.grav
	return false

static func after_movement(state: Dictionary) -> void:
	if Rules.current_player(state) != "P3": return
	for s in state.ships:
		if s.owner == "P3" and Rules.alive(s) and not Rules.is_disabled(state, s) and Rules.orbit_body(state, s) == "sol":
			Scenarios._finish(state, "P3", "Gli Alieni attivano una bomba Nova in orbita attorno al Sole: il Sistema Solare è perduto.")
			return

static func check_victory(state: Dictionary) -> void:
	if state.phase == "setup": return
	var aliens: Array = state.ships.filter(func(s): return s.owner == "P3")
	if aliens.is_empty(): return
	for a in aliens:
		if Rules.alive(a) and not doomed(state, a): return
	# l'ultimo alieno è caduto: vince chi l'ha abbattuto
	var who := ""
	for a in aliens:
		if Rules.alive(a): who = a.get("disabled_by", "")
	if who == "":
		var last := Rules.ship(state, state.sd.get("last_alien", ""))
		who = last.get("killed_by", "")
	if who in ["P1", "P2"]:
		Scenarios._finish(state, who, "%s distrugge l'ultima nave aliena e salva il Sole. Gli altri perdono." % Rules.player(state, who).name)
	else:
		Scenarios._finish(state, "pari", "L'ultima nave aliena si perde da sola: i due blocchi si salvano insieme.")

static func on_destroyed(state: Dictionary, s: Dictionary) -> void:
	if s.owner == "P3": state.sd.last_alien = s.id
