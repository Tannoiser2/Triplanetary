extends SceneTree

const HexMathRef = preload("res://scripts/engine/hex.gd")
const GameRulesRef = preload("res://scripts/engine/game.gd")
const CombatRulesRef = preload("res://scripts/engine/combat.gd")
const GrandTourDevRef = preload("res://scripts/data/grand_tour_dev.gd")
const EscapeScenarioRef = preload("res://scripts/data/escape.gd")
const Lateral7ScenarioRef = preload("res://scripts/data/lateral7.gd")
const PersistenceRef = preload("res://scripts/engine/persistence.gd")
const OrdnanceRulesRef = preload("res://scripts/engine/ordnance.gd")
const LogisticsRulesRef = preload("res://scripts/engine/logistics.gd")
const BaseRulesRef = preload("res://scripts/engine/bases.gd")
const ReplayRulesRef = preload("res://scripts/engine/replay.gd")
const ShipFactoryRef = preload("res://scripts/data/ship_factory.gd")
const BoardRef = preload("res://scripts/ui/board.gd")
const MainRef = preload("res://scripts/ui/main.gd")

var failures := 0

func _init() -> void:
	_check(HexMathRef.distance(Vector2i.ZERO, Vector2i(2, -1)) == 2, "distanza esagonale")
	_check(HexMathRef.line(Vector2i.ZERO, Vector2i(2, 0)).size() == 3, "linea inclusiva")
	var ship := {"id":"s","owner":"P1","name":"Test","position":Vector2i.ZERO,"velocity":Vector2i(2,-1),"fuel":3,"fuel_spent":0,"pending_gravity":[],"disabled_until_turn":0,"destroyed":false,"commercial":false,"overload_available":true,"visited_bodies":[],"landed_at":"","must_burn_after_takeoff":false}
	var moved: Dictionary = GameRulesRef.move_ship(ship, {}, [], 1)
	_check(moved.position == Vector2i(2, -1), "inerzia")
	ship.pending_gravity = [Vector2i(-1, 1)]
	moved = GameRulesRef.move_ship(ship, {}, [], 1)
	_check(moved.velocity == Vector2i(1, 0), "gravità differita")
	_check(moved.maneuver_history[0].gravity_steps == [Vector2i(-1, 1)], "gravità pendente applicata e registrata nel movimento successivo")
	_check(CombatRulesRef.odds_column(5, 3) == 1, "rapporti arrotondati al difensore")
	_check(CombatRulesRef.gun_damage(4, 2, 6, 0, 3) == "D4", "velocità relativa oltre due")
	var overloaded: Dictionary = GameRulesRef.move_ship(ship, {"thrust_steps":[Vector2i(1,0),Vector2i(0,1)]}, [], 1)
	_check(overloaded.fuel == 1 and not overloaded.overload_available, "sovraccarico consuma due carburante e disponibilità")
	var weak_fields := [{"hex":Vector2i(1,0),"acceleration":Vector2i(-1,0),"weak":true,"body_id":"luna"},{"hex":Vector2i(2,0),"acceleration":Vector2i(-1,0),"weak":true,"body_id":"luna"}]
	var weak_ship := ship.duplicate(true); weak_ship.velocity = Vector2i(2,0); weak_ship.pending_gravity = []
	var weak_result: Dictionary = GameRulesRef.move_ship(weak_ship, {}, weak_fields, 1)
	_check(weak_result.pending_gravity.size() == 1, "seconda gravità debole consecutiva obbligatoria")
	_check(weak_result.maneuver_history[0].gravity_encounters.size() == 1, "casella di gravità attraversata conservata per la traccia sulla mappa")
	weak_result = GameRulesRef.move_ship(weak_ship, {"use_first_weak_gravity":true}, weak_fields, 1)
	_check(weak_result.pending_gravity.size() == 2, "prima gravità debole opzionale applicata")
	var state: Dictionary = GrandTourDevRef.create_state(); state.phase = "movement"; state.commands.p1 = {"takeoff":true}
	state = GameRulesRef.advance_phase(state)
	_check(state.ships[0].landed_at == "" and state.ships[0].must_burn_after_takeoff, "decollo con booster")
	var fallen: Dictionary = GameRulesRef.move_ship(state.ships[0], {}, state.gravity, 2)
	_check(fallen.destroyed and fallen.destroyed_reason == "Ricaduta dopo il decollo", "ricaduta senza spinta dopo decollo")
	_check(HexMathRef.supercover_line(Vector2i.ZERO, Vector2i(3,-1)).front() == Vector2i.ZERO, "supercover include origine")
	var restored: Dictionary = PersistenceRef.round_trip(state)
	_check(restored.ships[0].position == state.ships[0].position and restored.turn == state.turn, "round-trip salvataggio deterministico")
	var portable: Dictionary = PersistenceRef.from_portable_json(PersistenceRef.to_portable_json(state))
	_check(portable.ships[0].position == state.ships[0].position and portable.gravity[0].acceleration is Vector2i, "salvataggio JSON portabile preserva i vettori")
	var collision_state: Dictionary = GrandTourDevRef.create_state(); var terra: Dictionary = collision_state.bodies.filter(func(body): return body.id == "terra")[0]
	collision_state.ships[0].landed_at = ""; collision_state.ships[0].position = terra.hex + Vector2i(2,0); collision_state.ships[0].velocity = Vector2i(-4,0); collision_state.phase = "movement"
	collision_state = GameRulesRef.advance_phase(collision_state)
	_check(collision_state.ships[0].destroyed, "collisione con corpo attraversato")
	var combat_state: Dictionary = GrandTourDevRef.create_state(); combat_state.phase = "combat"
	combat_state.ships[0].landed_at = ""; combat_state.ships[1].landed_at = ""; combat_state.ships[0].position = Vector2i.ZERO; combat_state.ships[1].position = Vector2i.ZERO
	combat_state = GameRulesRef.declare_attack(combat_state, "p1", "p2")
	_check(not combat_state.pending_combat.is_empty(), "dichiarazione attacco attende il difensore")
	var blocked: Dictionary = GameRulesRef.advance_phase(combat_state)
	_check(blocked.phase == "combat", "fase bloccata durante scelta contrattacco")
	var old_rng: int = combat_state.rng_state; combat_state = GameRulesRef.respond_to_attack(combat_state, true)
	_check(combat_state.pending_combat.is_empty() and combat_state.events.size() == 1 and combat_state.rng_state != old_rng, "attacco e contrattacco deterministici")
	var damaged := ship.duplicate(true); damaged.disabled_until_turn = 4
	GameRulesRef._apply_damage(damaged, "D3", 1)
	_check(damaged.destroyed, "danno cumulativo a sei turni distrugge")
	var ord_state: Dictionary = GrandTourDevRef.create_state(); ord_state.phase = "ordnance"; ord_state.ships[0].landed_at = ""; ord_state.ships[0].position = Vector2i(30,0); ord_state.ships[0].velocity = Vector2i(1,0); ord_state.ships[0].inventory.mine = 1
	ord_state = OrdnanceRulesRef.launch(ord_state, "p1", "mine")
	_check(ord_state.ordnance.size() == 1 and ord_state.ships[0].inventory.mine == 0, "lancio mina eredita il vettore")
	var launch_again: Dictionary = OrdnanceRulesRef.launch(ord_state, "p1", "mine")
	_check(launch_again.ordnance.size() == 1, "un solo ordigno per segmento")
	ord_state.ordnance[0].position = Vector2i(40,0); ord_state.ordnance[0].previous_position = Vector2i(40,0); ord_state.ordnance[0].velocity = Vector2i.ZERO
	for ignored in range(5): OrdnanceRulesRef.move_and_resolve(ord_state)
	_check(ord_state.ordnance.is_empty(), "ordigno scade dopo cinque movimenti")
	var commercial_state: Dictionary = GrandTourDevRef.create_state(); commercial_state.phase = "ordnance"; commercial_state.ships[0].landed_at = ""; commercial_state.ships[0].commercial = true; commercial_state.ships[0].inventory.torpedo = 1
	commercial_state = OrdnanceRulesRef.launch(commercial_state, "p1", "torpedo", Vector2i(1,0))
	_check(commercial_state.ordnance.is_empty(), "commerciale non lancia siluri")
	var logistics_state: Dictionary = GrandTourDevRef.create_state()
	logistics_state.ships[0].landed_at = ""; logistics_state.ships[1].landed_at = ""
	logistics_state.ships[0].position = Vector2i.ZERO; logistics_state.ships[1].position = Vector2i.ZERO
	logistics_state.ships[0].velocity = Vector2i(1,0); logistics_state.ships[1].velocity = Vector2i(1,0)
	logistics_state.ships[0].inventory.mine = 1; logistics_state.ships[1].cargo_capacity = 10
	logistics_state = LogisticsRulesRef.transfer(logistics_state, "p1", "p2", "mine", 1)
	_check(logistics_state.ships[0].inventory.mine == 0 and logistics_state.ships[1].inventory.mine == 1, "trasferimento con posizione e rotta coincidenti")
	var refused_transfer: Dictionary = logistics_state.duplicate(true); refused_transfer.ships[0].inventory.mine = 1; refused_transfer.ships[1].velocity = Vector2i.ZERO
	refused_transfer = LogisticsRulesRef.transfer(refused_transfer, "p1", "p2", "mine", 1)
	_check(refused_transfer.ships[0].inventory.mine == 1, "trasferimento rifiutato con rotta diversa")
	_check(not LogisticsRulesRef.loadout_fits(logistics_state.ships[1], {"torpedo":1}), "capacità di carico applicata")
	logistics_state.knowledge.P1.clear(); logistics_state.ships[1].position = Vector2i(3,0)
	LogisticsRulesRef.update_detection(logistics_state)
	_check(LogisticsRulesRef.is_detected(logistics_state, "P1", "p2"), "rilevamento nave entro tre esagoni")
	var base_state: Dictionary = GrandTourDevRef.create_state(); base_state.ships[0].fuel = 1
	var earth_base: Dictionary = base_state.bases.filter(func(base): return base.body_id == "terra")[0]
	_check(BaseRulesRef.resupply(base_state, base_state.ships[0], earth_base) and base_state.ships[0].fuel == 20, "rifornimento su base planetaria condivisa")
	var orbiting: Dictionary = base_state.ships[0].duplicate(true); orbiting.landed_at = ""; orbiting.position += Vector2i(1,0)
	_check(not BaseRulesRef.can_use(orbiting, earth_base), "base planetaria richiede atterraggio")
	var replay_state: Dictionary = GrandTourDevRef.create_state(); replay_state.log.append("evento prova"); ReplayRulesRef.record(replay_state, "Prova")
	_check(replay_state.replay_frames.size() == 2 and "evento prova" in ReplayRulesRef.describe(replay_state.replay_frames[1]), "replay registra fotogrammi navigabili")
	var scenario_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios.json"))
	var ruleset_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ruleset_updated_second.json"))
	_check(scenario_data is Array and scenario_data.size() == 8, "catalogo dati contiene gli otto scenari")
	_check(ruleset_data.ships.dreadnought.combat == 15 and ruleset_data.equipment.nuke.cost_mcr == 300, "tabella navi ed equipaggiamento trascritta")
	var torch: Dictionary = ShipFactoryRef.create("torch-1", "P1", "torch", Vector2i.ZERO)
	_check(torch.infinite_fuel and GameRulesRef.can_overload(torch), "Torch con carburante infinito dal catalogo")
	var multi: Dictionary = GrandTourDevRef.create_state(["Ada", "Bruno", "Carla"]); multi.phase = "resupply"; multi = GameRulesRef.advance_phase(multi)
	_check(multi.ships.size() == 3 and multi.segment == "P2" and multi.ships[2].name.ends_with("Carla"), "Grand Tour multigiocatore e ordine segmenti")
	var trail_ship: Dictionary = ShipFactoryRef.create("trail", "P1", "corvette", Vector2i.ZERO); trail_ship.trail = [Vector2i.ZERO]; trail_ship.velocity = Vector2i(1,0)
	trail_ship = GameRulesRef.move_ship(trail_ship, {}, [], 1)
	_check(trail_ship.trail == [Vector2i.ZERO, Vector2i(1,0)], "rotta percorsa conservata per il tracciamento")
	_check(trail_ship.maneuver_history.size() == 1 and trail_ship.maneuver_history[0].inertial_end == Vector2i(1,0), "componenti della manovra conservate per gravità e spinta persistenti")
	var two_player: Dictionary = GrandTourDevRef.create_state(["Ada", "Bruno"])
	two_player.phase = "resupply"; two_player = GameRulesRef.advance_phase(two_player)
	_check(two_player.segment == "P2" and two_player.phase == "astrogation", "passaggio al segmento del secondo giocatore")
	two_player.ships[1].landed_at = ""; two_player.ships[1].position = Vector2i(10, 5); two_player.ships[1].previous_position = two_player.ships[1].position; two_player.ships[1].velocity = Vector2i.ZERO
	two_player.commands[two_player.ships[1].id] = {"thrust_steps":[Vector2i(1,0)]}; two_player.phase = "movement"
	var p2_from: Vector2i = two_player.ships[1].position; two_player = GameRulesRef.advance_phase(two_player)
	_check(two_player.ships[1].position == p2_from + Vector2i(1,0) and two_player.ships[0].position != two_player.ships[1].position, "il secondo giocatore esegue la propria spinta")
	var board := BoardRef.new(); board.size = Vector2(800, 600); var old_zoom: float = board.camera_zoom; board._zoom_at(Vector2(400,300), 1.18)
	_check(board.camera_zoom > old_zoom, "zoom plancia mantiene un livello navigabile")
	_check(board.axial_to_pixel(board._offset_to_axial(24, 22)) == Vector2(735.5, 925.5), "griglia logica calibrata sui centri della scansione")
	board.free()
	var main_ui := MainRef.new(); main_ui._ready()
	main_ui.state = GrandTourDevRef.create_state(["Ada", "Bruno"]); main_ui.state.phase = "resupply"; main_ui._refresh(); main_ui._advance()
	_check(main_ui.state.segment == "P2" and main_ui.board.selected_ship == "p2", "interfaccia seleziona P2 prima di ridisegnare il nuovo segmento")
	main_ui.queue_free()
	var escape_state: Dictionary = EscapeScenarioRef.create_state(["Pellegrini", "Enforcers"])
	_check(escape_state.ships.size() == 5 and escape_state.ships.filter(func(item): return item.get("secret_cargo", false)).size() == 1 and escape_state.bases.size() == 3, "Escape prepara flotte, identità segreta e sole tre basi")
	var fugitive: Dictionary = escape_state.ships[0]; fugitive.landed_at = ""; fugitive.position = Vector2i(55, -10); fugitive.previous_position = fugitive.position; fugitive.velocity = Vector2i(1, 0); escape_state.phase = "movement"
	escape_state = GameRulesRef.advance_phase(escape_state)
	_check(escape_state.winner == "P1" and escape_state.victory_level == "decisiva" and escape_state.ships[0].escaped, "Escape assegna vittoria decisiva uscendo oltre Giove con carburante di arresto più uno")
	var capture_state: Dictionary = EscapeScenarioRef.create_state(); capture_state.phase = "resupply"; var capture_target: Dictionary = capture_state.ships[0]; var inspector: Dictionary = capture_state.ships[3]
	capture_target.landed_at = ""; capture_target.position = inspector.position; capture_target.velocity = inspector.velocity; capture_target.disabled_until_turn = capture_state.turn + 1
	capture_state = GameRulesRef.inspect_or_capture(capture_state, inspector.id, capture_target.id)
	_check(capture_state.ships[0].inspected and capture_state.ships[0].captured, "Escape rivela e cattura i fuggitivi disabilitati a rotta coincidente")
	capture_state.ships[3].landed_at = "terra"; capture_state = GameRulesRef.advance_phase(capture_state)
	_check(capture_state.winner == "P2" and capture_state.victory_level == "decisiva", "Escape assegna vittoria decisiva agli Enforcers che riportano i prigionieri a una base")
	var ram_state: Dictionary = EscapeScenarioRef.create_state(); ram_state.phase = "movement"; ram_state.rng_state = 2; var rammer: Dictionary = ram_state.ships[0]; var ram_target: Dictionary = ram_state.ships[3]
	rammer.landed_at = ""; rammer.position = Vector2i(5, 5); rammer.previous_position = rammer.position; rammer.velocity = Vector2i(1, 0); ram_target.position = Vector2i(6, 5); ram_target.velocity = Vector2i.ZERO; ram_state.commands[rammer.id] = {"ram_target_id":ram_target.id}
	ram_state = GameRulesRef.advance_phase(ram_state)
	var ram_events: Array = ram_state.events.filter(func(event): return event.get("kind", "") == "ram")
	_check(ram_events.size() == 1 and ram_state.ships[0].disabled_until_turn == 3 and ram_state.ships[3].disabled_until_turn == 3, "Escape risolve lo speronamento sulla colonna Ram per entrambe le navi")
	var lateral: Dictionary = Lateral7ScenarioRef.create_state(["Pirati", "Marina"])
	_check(lateral.phase == "setup" and lateral.segment == "P2" and lateral.ships.size() == 1 and lateral.ships[0].has_passengers, "Lateral 7 apre il setup della Marina con il liner su Venere")
	var setup_hexes: Array = lateral.asteroids.slice(0, 16)
	for setup_hex: Vector2i in setup_hexes: lateral = Lateral7ScenarioRef.place_next(lateral, setup_hex)
	_check(lateral.phase == "astrogation" and lateral.segment == "P1" and lateral.ships.size() == 5 and lateral.dummies.size() == 12, "Lateral 7 colloca flotte e falsi bersagli in esagoni asteroidali distinti")
	var dreadnought: Dictionary = lateral.ships.filter(func(item): return item.type == "dreadnought")[0]
	var pirate_corsairs: Array = lateral.ships.filter(func(item): return item.owner == "P1" and item.type == "corsair")
	_check(dreadnought.movement_locked and dreadnought.inventory.mine == 1 and dreadnought.inventory.torpedo == 1 and pirate_corsairs.all(func(item): return item.inventory.mine == 1 and item.special_asteroid_access), "Lateral 7 applica carichi, blocco dreadnought e accesso pirata agli asteroidi speciali")
	var passenger_target: Dictionary = pirate_corsairs[0]; lateral.phase = "resupply"; passenger_target.position = lateral.ships[0].position; passenger_target.velocity = lateral.ships[0].velocity
	lateral = Lateral7ScenarioRef.transfer_passengers(lateral, "navy-liner", passenger_target.id)
	_check(lateral.lateral7.passenger_holder == passenger_target.id and lateral.ships[0].has_passengers == false, "Lateral 7 trasferisce i passeggeri solo a rotta coincidente")
	var dummy_state: Dictionary = Lateral7ScenarioRef.create_state()
	for setup_hex: Vector2i in dummy_state.asteroids.slice(0, 16): dummy_state = Lateral7ScenarioRef.place_next(dummy_state, setup_hex)
	var first_pirate: Dictionary = dummy_state.ships.filter(func(item): return item.owner == "P1")[0]
	_check(Lateral7ScenarioRef.begin_dummy_removal(dummy_state, first_pirate.id, [Vector2i(1, 0)]), "Lateral 7 richiede la rimozione di tre dummy alla prima accelerazione pirata")
	var pirate_dummy_hexes: Array = dummy_state.dummies.filter(func(item): return item.owner == "P1").slice(0, 3).map(func(item): return item.position)
	for dummy_hex: Vector2i in pirate_dummy_hexes: Lateral7ScenarioRef.remove_dummy_at(dummy_state, dummy_hex)
	_check(dummy_state.dummies.filter(func(item): return item.owner == "P1" and item.active).size() == 6 and dummy_state.commands[first_pirate.id].thrust_steps == [Vector2i(1, 0)], "Lateral 7 applica la spinta solo dopo tre rimozioni scelte")
	var locked_dreadnought: Dictionary = dummy_state.ships.filter(func(item): return item.type == "dreadnought")[0]
	_check(not Lateral7ScenarioRef.begin_dummy_removal(dummy_state, locked_dreadnought.id, [Vector2i(1, 0)]), "Tycho Brahe resta immobile prima del rilevamento")
	first_pirate.position = locked_dreadnought.position; LogisticsRulesRef.update_detection(dummy_state)
	_check(dummy_state.lateral7.dreadnought_unlocked and Lateral7ScenarioRef.begin_dummy_removal(dummy_state, locked_dreadnought.id, [Vector2i(1, 0)]), "rilevamento pirata sblocca il dreadnought")
	var pirate_win: Dictionary = lateral.duplicate(true); var passenger_ship: Dictionary = pirate_win.ships.filter(func(item): return item.id == pirate_win.lateral7.passenger_holder)[0]; var clandestine_body: Dictionary = pirate_win.bodies.filter(func(item): return item.id == "clandestine")[0]
	passenger_ship.position = clandestine_body.hex; passenger_ship.velocity = Vector2i.ZERO; pirate_win.phase = "resupply"; pirate_win = GameRulesRef.advance_phase(pirate_win)
	_check(pirate_win.winner == "P1", "Lateral 7 assegna la vittoria pirata portando i passeggeri a Clandestine")
	var defense_state: Dictionary = dummy_state.duplicate(true); var defended_pirate: Dictionary = defense_state.ships.filter(func(item): return item.owner == "P1")[0]; var terra_body: Dictionary = defense_state.bodies.filter(func(item): return item.id == "terra")[0]
	defense_state.phase = "movement"; defense_state.segment = "P1"; defense_state.turn = 1; defense_state.rng_state = 2; defense_state.commands = {}; defended_pirate.position = terra_body.hex + Vector2i(1, 0); defended_pirate.previous_position = defended_pirate.position; defended_pirate.velocity = Vector2i.ZERO
	defense_state = GameRulesRef.advance_phase(defense_state)
	_check(defense_state.events.any(func(event): return event.get("kind", "") == "planetary_defense") and defense_state.ships.filter(func(item): return item.id == defended_pirate.id)[0].disabled_until_turn == 6, "difesa planetaria spara automaticamente a 2:1 senza modificatori")
	var mine_state: Dictionary = dummy_state.duplicate(true); var mine_ship: Dictionary = mine_state.ships.filter(func(item): return item.owner == "P1" and item.type == "corsair")[0]; var mine_clandestine: Dictionary = mine_state.bodies.filter(func(item): return item.id == "clandestine")[0]
	mine_state.phase = "resupply"; mine_ship.position = mine_clandestine.hex; mine_ship.velocity = Vector2i.ZERO; mine_ship.inventory.mine = 0; mine_state = Lateral7ScenarioRef.load_mine(mine_state, mine_ship.id)
	_check(mine_state.ships.filter(func(item): return item.id == mine_ship.id)[0].inventory.mine == 1, "Lateral 7 rende disponibili le mine ai Pirati a Clandestine entro la stiva")
	if failures == 0: print("OK: 59 test")
	quit(failures)

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
