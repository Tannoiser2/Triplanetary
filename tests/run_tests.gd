extends SceneTree
## Test headless del motore: godot --headless --path . --script tests/run_tests.gd

var failures := 0
var count := 0

func check(cond: bool, label: String) -> void:
	count += 1
	if not cond:
		failures += 1
		printerr("FALLITO: " + label)

func _init() -> void:
	test_map()
	test_inertia_and_gravity()
	test_orbit()
	test_crash_geometry()
	test_takeoff_and_landing()
	test_weak_gravity()
	test_combat()
	test_damage()
	test_ordnance()
	test_persistence()
	test_grand_tour_setup()
	test_escape()
	test_lateral7()
	test_ai_grand_tour()
	test_ai_scenario("escape")
	test_ai_scenario("lateral-7")
	test_fleet_shop()
	test_orbital_base()
	test_new_scenarios()
	test_variants()
	test_xmap()
	test_xmap_full()
	test_replay()
	if failures == 0: print("OK: %d controlli" % count)
	else: printerr("%d/%d controlli falliti" % [failures, count])
	quit(1 if failures else 0)

func empty_state() -> Dictionary:
	var st := Scenarios._base_state("grand-tour", [{"name": "A"}, {"name": "B"}], {"seed": 42})
	st.sd = {"required": [], "finishers": []}
	st.scenario = "test"
	return st

func add_ship(st: Dictionary, id: String, owner: String, type: String, pos: Vector2i, vel := Vector2i.ZERO) -> Dictionary:
	var s := ShipTypes.make(id, owner, type)
	s.pos = pos; s.vel = vel
	st.ships.append(s)
	return s

func run_segment_movement(st: Dictionary) -> void:
	st.phase = "ordnance"
	Rules.end_phase(st) # -> movimento eseguito

func test_map() -> void:
	var m := SolarMap.get_map()
	check(m.cells.size() == 2277, "celle della mappa")
	check(m.bodies.size() == 13, "corpi")
	check(m.gravity.size() == 77, "esagoni di gravità")
	check(m.asteroids.size() == 67, "asteroidi")
	var full := SolarMap.full_gravity_bodies(m)
	check(full.size() == 8 and full.has("sol") and full.has("ganymede") and not full.has("luna"), "corpi a gravità piena: %s" % [full])
	var shared: Array = m.gravity.get(SolarMap.body(m, "jupiter").hex + Hex.DIRS[5], [])
	check(shared.size() == 2, "esagono condiviso Giove/Io")
	var classic := SolarMap.get_map(true)
	check(classic.gravity.size() == 65, "variante Sol classica: %d" % classic.gravity.size())

func test_inertia_and_gravity() -> void:
	var st := empty_state()
	var s := add_ship(st, "a", "P1", "corvette", Vector2i(10, 30), Vector2i(1, 0))
	run_segment_movement(st)
	check(s.pos == Vector2i(11, 30) and s.vel == Vector2i(1, 0), "inerzia")
	# Passaggio in un esagono di gravità di Marte: effetto al turno dopo.
	var m := Rules.map_of(st)
	var mars: Vector2i = SolarMap.body(m, "mars").hex
	var start: Vector2i = mars + Hex.DIRS[0] * 2
	var st2 := empty_state()
	var s2 := add_ship(st2, "b", "P1", "corvette", start, Hex.DIRS[3])
	run_segment_movement(st2)
	check(s2.grav.size() >= 1, "gravità acquisita entrando nel campo di Marte")
	check(s2.vel == Hex.DIRS[3], "la gravità non agisce nel turno di ingresso")

func test_orbit() -> void:
	var st := empty_state()
	var m := Rules.map_of(st)
	var s := add_ship(st, "o", "P1", "corvette", Vector2i.ZERO)
	Scenarios._orbit(s, m, "terra", 0)
	var terra: Vector2i = SolarMap.body(m, "terra").hex
	var ok := true
	for i in range(8):
		st.phase = "ordnance"; st.seg = 0
		Rules.end_phase(st)
		if Hex.distance(s.pos, terra) != 1 or s.destroyed: ok = false
	check(ok, "orbita stabile attorno alla Terra per 8 turni senza carburante")
	check(int(s.fuel) == 20, "l'orbita non consuma carburante")
	check(Rules.orbit_body(st, s) == "terra", "riconoscimento dell'orbita")

func test_crash_geometry() -> void:
	var m := SolarMap.get_map()
	var mars: Vector2i = SolarMap.body(m, "mars").hex
	var r := Rules.simulate(m, mars + Hex.DIRS[3] * 2, Hex.DIRS[0] * 4, [], Vector2i.ZERO, false, [], [], false)
	check(r.crash == "mars", "rotta attraverso il disco di Marte = schianto")
	# Rotta tangente fra due esagoni di gravità: nessuno schianto.
	var r2 := Rules.simulate(m, mars + Hex.DIRS[0], Hex.DIRS[2], [], Vector2i.ZERO, false, [], [], false)
	check(r2.crash == "", "passaggio fra esagoni di gravità adiacenti")
	var sol: Vector2i = SolarMap.body(m, "sol").hex
	var r3 := Rules.simulate(m, sol + Hex.DIRS[3] * 3, Hex.DIRS[0] * 6, [], Vector2i.ZERO, false, [], [], false)
	check(r3.crash == "sol", "schianto sul Sole")

func test_takeoff_and_landing() -> void:
	var st := Scenarios.create("grand-tour", [{"name": "A"}, {"name": "B"}], {"seed": 7})
	var s: Dictionary = st.ships[0]
	check(s.landed == "terra", "partenza atterrata")
	check(Rules.set_plot(st, s.id, {"takeoff": true}) == "", "ordine di decollo")
	st.phase = "ordnance"; Rules.end_phase(st)
	check(s.landed == "" and s.vel == Vector2i.ZERO and s.grav.size() == 1, "booster: fermo nell'esagono di gravità")
	# senza spinta ricade e si schianta
	var st2 := st.duplicate(true)
	var s2: Dictionary = st2.ships[0]
	st2.phase = "ordnance"; Rules.end_phase(st2)
	check(s2.destroyed, "ricaduta senza spinta")
	# con una spinta tangenziale entra in orbita
	var terra: Vector2i = SolarMap.body(Rules.map_of(st), "terra").hex
	var side := Hex.dir_index(s.pos - terra)
	st.phase = "astrogation"; st.seg = 0
	var tangential := (side + 1) % 6
	check(Rules.set_plot(st, s.id, {"burns": [tangential]}) == "", "spinta dopo il decollo")
	st.phase = "ordnance"; Rules.end_phase(st)
	check(not s.destroyed and Hex.distance(s.pos, terra) == 1, "dopo il decollo resta attorno alla Terra")
	st.plots = {}
	st.phase = "ordnance"; st.seg = 0; Rules.end_phase(st)
	check(Rules.orbit_body(st, s) == "terra", "in orbita dopo un giro libero")
	st.phase = "astrogation"
	var sides := Rules.landing_sides(st, s)
	check(not sides.is_empty(), "lati di atterraggio disponibili")
	check(Rules.set_plot(st, s.id, {"land": sides[0]}) == "", "ordine di atterraggio")
	st.phase = "ordnance"; Rules.end_phase(st)
	check(s.landed == "terra", "atterraggio riuscito")

func test_weak_gravity() -> void:
	var m := SolarMap.get_map()
	var luna: Vector2i = SolarMap.body(m, "luna").hex
	# attraversa due esagoni deboli consecutivi della Luna
	var start: Vector2i = luna + Hex.DIRS[1] + Hex.DIRS[3] * 2
	var r := Rules.simulate(m, start, Hex.DIRS[0] * 3, [], Vector2i.ZERO, false, [], [], false)
	var weak_hexes := 0
	for h in r.path:
		if m.gravity.has(h) and m.gravity[h][0].weak: weak_hexes += 1
	var r2 := Rules.simulate(m, start, Hex.DIRS[0] * 3, [], Vector2i.ZERO, true, [], [], false)
	check(weak_hexes >= 2, "il percorso di prova attraversa %d esagoni deboli" % weak_hexes)
	check(r.grav.size() == weak_hexes - 1, "prima freccia debole ignorata, la seconda obbligatoria")
	check(r2.grav.size() == weak_hexes, "frecce deboli usate tutte su richiesta")

func test_combat() -> void:
	check(Rules.odds_column(2, 4) == 0, "1:2")
	check(Rules.odds_column(3, 2) == 1, "arrotondamento a favore del difensore")
	check(Rules.odds_column(1, 3) == -1, "sotto 1:2 nessun effetto")
	check(Rules.odds_column(20, 4) == 4, "oltre 4:1")
	var st := empty_state()
	st.phase = "combat"
	var a := add_ship(st, "a", "P1", "corsair", Vector2i(10, 30), Vector2i(1, 0))
	a.last_path = [Vector2i(9, 30), Vector2i(10, 30)]
	var t := add_ship(st, "t", "P2", "corvette", Vector2i(12, 30), Vector2i(-2, 0))
	var p := Rules.attack_preview(st, [a], [t])
	check(p.column == 2 and p.range == 2 and p.rv == 3 and p.mod == -3, "modificatori: %s" % [p])
	check(Rules.declare_attack(st, ["a"], ["t"]) == "", "dichiarazione d'attacco")
	check(Rules.counter_candidates(st) == ["t"], "candidati al contrattacco")
	check(Rules.resolve_attack(st, ["t"], ["a"]) == "", "risoluzione")
	check(Rules.declare_attack(st, ["a"], ["t"]) != "", "una sola volta per fase")

func test_damage() -> void:
	var st := empty_state()
	var s := add_ship(st, "d", "P1", "corvette", Vector2i(10, 30))
	Rules._apply_damage(st, s, "D3", "test")
	check(Rules.disabled_turns(st, s) == 3, "D3")
	Rules._apply_damage(st, s, "D2", "test")
	check(Rules.disabled_turns(st, s) == 5 and not s.destroyed, "cumulo a 5")
	Rules._apply_damage(st, s, "D1", "test")
	check(s.destroyed, "6 turni di disabilitazione = distrutta")

func test_ordnance() -> void:
	var st := empty_state()
	st.rules.ordnance = true
	var a := add_ship(st, "a", "P1", "frigate", Vector2i(10, 30), Vector2i(1, 0))
	a.inv.torpedo = 1; a.inv.mine = 1
	var t := add_ship(st, "t", "P2", "corvette", Vector2i(13, 30), Vector2i.ZERO)
	st.phase = "astrogation"
	Rules.set_plot(st, "a", {"burns": [2]})
	st.phase = "ordnance"
	check(Rules.launch(st, "a", "torpedo", [0, 0]) == "", "lancio del siluro")
	check(Rules.launch(st, "a", "mine") != "", "un solo ordigno per turno")
	Rules.end_phase(st)
	check(st.ordnance.is_empty() and st.log.any(func(e): return "Siluro" in e.text), "il siluro raggiunge il bersaglio")

func test_persistence() -> void:
	var st := Scenarios.create("grand-tour", [{"name": "A"}, {"name": "B"}], {"seed": 3})
	var txt := Persistence.to_json(st)
	var back := Persistence.from_json(txt)
	check(not back.is_empty() and back.ships[0].pos == st.ships[0].pos and back.ships[0].pos is Vector2i, "salvataggio JSON")
	check(typeof(back.turn) == TYPE_INT, "interi preservati")

func test_grand_tour_setup() -> void:
	var st := Scenarios.create("grand-tour", [{"name": "A"}, {"name": "B"}, {"name": "C"}], {"seed": 3})
	check(st.ships.size() == 3 and st.ships.all(func(s): return s.landed == "terra"), "tre corvette su Terra")
	check(st.sd.required.size() == 8, "otto corpi da visitare")
	var fuel_bases: Array = st.bases.filter(func(b): return b.fuel).map(func(b): return b.body)
	check(fuel_bases.has("callisto") and not fuel_bases.has("luna"), "carburante solo nelle quattro basi")

func test_escape() -> void:
	var st := Scenarios.create("escape", [{"name": "A"}, {"name": "B"}], {"seed": 5})
	check(st.phase == "setup", "scelta segreta dei fuggitivi")
	check(Scenarios.choose_fugitive(st, "pilgrim-b") == "", "fuggitivi designati")
	var c := Rules.ship(st, "enf-corvette")
	check(Rules.orbit_body(st, c) == "terra", "corvetta Enforcer in orbita terrestre")
	var t := Rules.ship(st, "pilgrim-a")
	check(Rules.set_plot(st, t.id, {"takeoff": true}) == "", "i Pellegrini decollano senza base amica")

func test_lateral7() -> void:
	var st := Scenarios.create("lateral-7", [{"name": "A"}, {"name": "B"}], {"seed": 9})
	check(st.phase == "setup" and st.setup.player == "P2", "la Marina schiera per prima")
	Scenarios.auto_place(st)
	check(st.setup.player == "P1", "poi i Pirati")
	Scenarios.auto_place(st)
	check(st.phase == "astrogation", "schieramento completo")
	var dread: Array = st.ships.filter(func(s): return s.type == "dreadnought")
	check(dread.size() == 1 and dread[0].locked, "dreadnought bloccato")
	check(st.ships.filter(func(s): return s.get("dummy", false)).size() == 12, "dodici falsi bersagli")

func test_ai_grand_tour() -> void:
	var st := Scenarios.create("grand-tour", [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}], {"seed": 11})
	var guard := 0
	while not st.over and guard < 2500:
		AI.play_step(st)
		guard += 1
	check(st.over, "partita IA contro IA conclusa (giorno %d)" % st.turn)
	check(st.winner in ["P1", "P2", "pari"], "c'è un vincitore: %s" % st.result)

func test_ai_scenario(id: String) -> void:
	for seed in [21, 22]:
		var st := Scenarios.create(id, [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}], {"seed": seed})
		var guard := 0
		while not st.over and guard < 3000:
			AI.play_step(st)
			guard += 1
		check(st.over, "%s IA contro IA conclusa (seme %d, giorno %d): %s" % [id, seed, st.turn, st.result])
		# il salvataggio deve sopravvivere a qualunque stato raggiunto
		var back := Persistence.from_json(Persistence.to_json(st))
		check(not back.is_empty() and back.ships.size() == st.ships.size(), "salvataggio di fine partita %s" % id)

func test_fleet_shop() -> void:
	var st := Scenarios.create("nova", [{"name": "W"}, {"name": "E"}, {"name": "A"}], {"seed": 4})
	check(st.phase == "setup" and st.setup.kind == "terra3", "Nova: si parte dalla spartizione della Terra")
	Scenarios.choose(st, 0)
	Scenarios.choose(st, 3)
	Scenarios.choose(st, 0)
	check(st.setup.step == "shop" and st.setup.budget == 50.0, "Nova: 50 punti per il WestBloc")
	check(Fleet.price("pts", "liner") == 1.0 and Fleet.price("pts", "transport") == 0.5, "commerciali a metà prezzo")
	for i in range(5): Fleet.add(st, "frigate")
	check(Fleet.add(st, "dreadnought") == "Budget insufficiente.", "budget rispettato")
	Fleet.confirm_shop(st)
	check(st.setup.step == "deploy" and st.setup.queue.size() == 5, "coda di schieramento")
	var spots := Fleet.spots(st)
	check(not spots.is_empty(), "caselle di schieramento disponibili")
	Fleet.auto_deploy(st)
	check(st.ships.filter(func(s): return s.owner == "P1").all(func(s): return s.landed != ""), "le navi dei blocchi partono a terra")
	var terra_bases: Array = st.bases.filter(func(b): return b.body == "terra")
	check(terra_bases.size() == 6 and terra_bases.filter(func(b): return b.owner == "P2").size() == 3, "tre lati della Terra a testa")

func test_orbital_base() -> void:
	var st := empty_state()
	var m := Rules.map_of(st)
	var b := ShipTypes.make("ob", "P1", "orbital_base")
	Scenarios._orbit(b, m, "terra", 0)
	st.ships.append(b)
	var s := ShipTypes.make("c", "P1", "corvette")
	Scenarios._orbit(s, m, "terra", 0)
	s.fuel = 3
	st.ships.append(s)
	check(Rules.set_plot(st, "ob", {"burns": [0]}) != "", "una base orbitale non accende motori")
	var d := Rules.docked_base(st, s)
	check(d.get("orbital", false), "rotta accoppiata con la base orbitale")
	st.phase = "resupply"
	Rules._do_resupply(st)
	check(int(s.fuel) == 20, "rifornimento dalla base orbitale")
	for i in range(6):
		st.phase = "ordnance"; st.seg = 0
		Rules.end_phase(st)
	check(Rules.orbit_body(st, b) == "terra" and Rules.alive(b), "la base resta in orbita")

func test_new_scenarios() -> void:
	for id in ["nova", "retribution", "fleet-mutiny", "interplanetary-war", "prospecting"]:
		var n := 3 if id == "nova" else 2
		var seats := []
		for i in n: seats.append({"name": "IA%d" % i, "type": "ai"})
		var st := Scenarios.create(id, seats, {"seed": 7, "length": 40})
		var guard := 0
		while not st.over and guard < 2500 and int(st.turn) < 120:
			AI.play_step(st)
			guard += 1
		check(st.phase != "setup", "%s: preparazione completata" % id)
		check(st.over or int(st.turn) >= 40, "%s: la partita procede (giorno %d) %s" % [id, st.turn, st.result])
		var back := Persistence.from_json(Persistence.to_json(st))
		check(not back.is_empty() and back.sd.size() == st.sd.size(), "%s: salvataggio" % id)

func test_variants() -> void:
	var st := Scenarios.create("grand-tour", [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}], {"seed": 3, "route": "distance"})
	check(st.sd.route == ["sol", "mercury", "venus", "mars", "jupiter", "ganymede", "callisto"], "rotta obbligata per distanza dal Sole")
	var s: Dictionary = st.ships[0]
	Scenarios.on_visits(st, s, ["venus"])
	check(int(s.route_idx) == 0, "fuori ordine la tappa non conta")
	Scenarios.on_visits(st, s, ["sol", "mercury"])
	check(int(s.route_idx) == 2 and Scenarios.gt_missing(st, s) == ["venus"], "le tappe in ordine avanzano")
	var nv := Scenarios.create("nova", [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}, {"name": "C", "type": "ai"}], {"seed": 3, "aliens": 6})
	var g := 0
	while nv.phase == "setup" and g < 200:
		AI.play_step(nv); g += 1
	check(nv.ships.filter(func(x): return x.owner == "P3").size() == 6, "Nova con sei corsari alieni")
	var mu := Scenarios.create("fleet-mutiny", [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}], {"seed": 3, "mutiny_ships": 8, "mutiny_hidden": true})
	g = 0
	while mu.phase == "setup" and g < 200:
		AI.play_step(mu); g += 1
	check(mu.rules.hidden and mu.ships.filter(func(x): return not x.get("is_base", false)).size() == 8, "Fleet Mutiny con 8 navi e pedine coperte")

func test_xmap() -> void:
	for id in ["mercury", "terra", "mars", "ceres"]:
		var p := Planets.path(id)
		var ok := true
		for i in range(p.size()):
			if Hex.distance(p[i], p[(i + 1) % p.size()]) != 1: ok = false
		check(ok, "orbita di %s senza salti (%d esagoni)" % [id, p.size()])
	check(Planets.path("terra").size() >= 95 and Planets.path("terra").size() <= 120, "circonferenza dell'orbita terrestre circa 100 esagoni")
	var st := Scenarios.create("grand-tour", [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}], {"seed": 5, "map": "xmap"})
	var m := Rules.map_of(st)
	check(m.get("xmap", false) and m.cells.size() == 4028, "mappa ampliata: 76 x 53 esagoni")
	check(m.gravity[Hex.DIRS[0]][0].acc == -Hex.DIRS[0] * 3, "Sole: anello interno a gravità tripla")
	var terra: Vector2i = SolarMap.body(m, "terra").hex
	check(m.cells.has(terra), "la Terra parte sulla plancia")
	var s: Dictionary = st.ships[0]
	check(s.landed == "terra" and s.pos == terra, "si parte a terra")
	# un'orbita intera: dopo 4 turni la Terra avanza di un esagono e la nave a terra la segue
	for i in range(4): Planets.advance(st)
	var t2: Vector2i = SolarMap.body(Rules.map_of(st), "terra").hex
	check(Hex.distance(t2, terra) == 1, "la Terra avanza di un esagono ogni 4 turni")
	check(s.pos == t2, "la nave a terra si muove con il pianeta")
	var back := Persistence.from_json(Persistence.to_json(st))
	check(back.planets == st.planets, "salvataggio delle posizioni dei pianeti")

func test_xmap_full() -> void:
	var st := Scenarios.create("grand-tour", [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}], {"seed": 9, "map": "xmap_full"})
	var m := Rules.map_of(st)
	check(m.cells.size() > 8000, "mappa completa: 152 x 53 esagoni")
	for id in ["saturn", "uranus", "neptune", "pluto", "titan", "triton", "charon", "clandestine"]:
		check(not SolarMap.body(m, id).is_empty(), "mappa completa: c'è %s" % id)
	check(st.sd.required.has("saturn") and st.sd.required.has("neptune") and not st.sd.required.has("pluto"), "Grand Tour completo: Saturno, Urano e Nettuno obbligatori")
	check(int(st.ships[0].max_fuel) == 40, "serbatoi raddoppiati sulla mappa completa")
	check(int(m.edge_y) < -100, "il bordo esterno è oltre Plutone")
	var x2 := Scenarios.create("retribution", [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}], {"seed": 9, "map": "xmap"})
	check(not SolarMap.body(Rules.map_of(x2), "clandestine").is_empty() and x2.special.size() == 6, "Clandestine e i suoi asteroidi speciali sulla mappa ampliata")

func test_replay() -> void:
	var st := Scenarios.create("grand-tour", [{"name": "A", "type": "ai"}, {"name": "B", "type": "ai"}], {"seed": 4})
	var g := 0
	while int(st.turn) < 8 and g < 400:
		AI.play_step(st); g += 1
	check(st.replay.size() >= 10, "registro del replay (%d movimenti)" % st.replay.size())
	var rp := Replay.build(st)
	var tr: Dictionary = rp.tracks[st.ships[0].id]
	check(tr.times.size() >= 6, "tracciato continuo per ogni nave")
	var a = Replay.pos_at(tr, float(tr.times[2]))
	check(a != null and a.distance_to(tr.pts[2]) < 0.01, "la curva passa per le posizioni di fine turno")
	var back := Persistence.from_json(Persistence.to_json(st))
	check(back.replay.size() == st.replay.size(), "il replay si salva con la partita")
