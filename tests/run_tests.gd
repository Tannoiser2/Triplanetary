extends SceneTree

const HexMathRef = preload("res://scripts/engine/hex.gd")
const GameRulesRef = preload("res://scripts/engine/game.gd")
const CombatRulesRef = preload("res://scripts/engine/combat.gd")
const GrandTourDevRef = preload("res://scripts/data/grand_tour_dev.gd")
const PersistenceRef = preload("res://scripts/engine/persistence.gd")
const OrdnanceRulesRef = preload("res://scripts/engine/ordnance.gd")
const LogisticsRulesRef = preload("res://scripts/engine/logistics.gd")
const BaseRulesRef = preload("res://scripts/engine/bases.gd")

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
	_check(CombatRulesRef.odds_column(5, 3) == 1, "rapporti arrotondati al difensore")
	_check(CombatRulesRef.gun_damage(4, 2, 6, 0, 3) == "D4", "velocità relativa oltre due")
	var overloaded: Dictionary = GameRulesRef.move_ship(ship, {"thrust_steps":[Vector2i(1,0),Vector2i(0,1)]}, [], 1)
	_check(overloaded.fuel == 1 and not overloaded.overload_available, "sovraccarico consuma due carburante e disponibilità")
	var weak_fields := [{"hex":Vector2i(1,0),"acceleration":Vector2i(-1,0),"weak":true,"body_id":"luna"},{"hex":Vector2i(2,0),"acceleration":Vector2i(-1,0),"weak":true,"body_id":"luna"}]
	var weak_ship := ship.duplicate(true); weak_ship.velocity = Vector2i(2,0); weak_ship.pending_gravity = []
	var weak_result: Dictionary = GameRulesRef.move_ship(weak_ship, {}, weak_fields, 1)
	_check(weak_result.pending_gravity.size() == 1, "seconda gravità debole consecutiva obbligatoria")
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
	if failures == 0: print("OK: 29 test")
	quit(failures)

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
