extends SceneTree

const HexMathRef = preload("res://scripts/engine/hex.gd")
const GameRulesRef = preload("res://scripts/engine/game.gd")
const CombatRulesRef = preload("res://scripts/engine/combat.gd")

var failures := 0

func _init() -> void:
	_check(HexMathRef.distance(Vector2i.ZERO, Vector2i(2, -1)) == 2, "distanza esagonale")
	_check(HexMathRef.line(Vector2i.ZERO, Vector2i(2, 0)).size() == 3, "linea inclusiva")
	var ship := {"id":"s","owner":"P1","name":"Test","position":Vector2i.ZERO,"velocity":Vector2i(2,-1),"fuel":3,"pending_gravity":[],"disabled_until_turn":0,"destroyed":false}
	var moved: Dictionary = GameRulesRef.move_ship(ship, {}, [], 1)
	_check(moved.position == Vector2i(2, -1), "inerzia")
	ship.pending_gravity = [Vector2i(-1, 1)]
	moved = GameRulesRef.move_ship(ship, {}, [], 1)
	_check(moved.velocity == Vector2i(1, 0), "gravità differita")
	_check(CombatRulesRef.odds_column(5, 3) == 1, "rapporti arrotondati al difensore")
	_check(CombatRulesRef.gun_damage(4, 2, 6, 0, 3) == "D4", "velocità relativa oltre due")
	if failures == 0: print("OK: 6 test")
	quit(failures)

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
