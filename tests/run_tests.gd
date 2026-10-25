extends SceneTree

const HexMathRef = preload("res://scripts/engine/hex.gd")
const GameRulesRef = preload("res://scripts/engine/game.gd")
const CombatRulesRef = preload("res://scripts/engine/combat.gd")
const GrandTourDevRef = preload("res://scripts/data/grand_tour_dev.gd")
const PersistenceRef = preload("res://scripts/engine/persistence.gd")

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
	var collision_state: Dictionary = GrandTourDevRef.create_state(); var terra: Dictionary = collision_state.bodies.filter(func(body): return body.id == "terra")[0]
	collision_state.ships[0].landed_at = ""; collision_state.ships[0].position = terra.hex + Vector2i(2,0); collision_state.ships[0].velocity = Vector2i(-4,0); collision_state.phase = "movement"
	collision_state = GameRulesRef.advance_phase(collision_state)
	_check(collision_state.ships[0].destroyed, "collisione con corpo attraversato")
	if failures == 0: print("OK: 14 test")
	quit(failures)

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
