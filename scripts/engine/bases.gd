class_name BaseRules
extends RefCounted

const CombatRulesRef = preload("res://scripts/engine/combat.gd")

static func can_use(ship: Dictionary, base: Dictionary) -> bool:
	if not base.get("active", true) or ship.destroyed: return false
	var owner: String = base.get("owner", "neutral")
	if owner not in ["neutral", "shared", ship.owner]: return false
	match base.get("kind", "planetary"):
		"planetary": return ship.get("landed_at", "") == base.get("body_id", "")
		"asteroid": return ship.position == base.position and ship.velocity == Vector2i.ZERO
		"orbital": return ship.position == base.position and ship.velocity == base.get("velocity", Vector2i.ZERO)
	return false

static func resupply(state: Dictionary, ship: Dictionary, base: Dictionary) -> bool:
	if not can_use(ship, base): return false
	var key := "%d:%s" % [state.turn, state.segment]
	ship.fuel = ship.max_fuel
	ship.overload_available = true
	ship.resupplied_key = key
	base.resupplied_key = key
	state.log.append("G%d %s · rifornimento a %s" % [state.turn, state.segment, base.get("name", base.id)])
	return true

static func defense_result(state: Dictionary, base: Dictionary, ship: Dictionary) -> String:
	if not base.get("active", true) or not base.get("defense", false) or ship.destroyed: return "-"
	if base.get("owner", "") in ["", "neutral", "shared", ship.owner]: return "-"
	var die := _roll_d6(state)
	# Difesa planetaria: colonna 2:1, senza modificatori di distanza o velocità.
	return CombatRulesRef.TABLE[2][die - 1]

static func _roll_d6(state: Dictionary) -> int:
	state.rng_state = int((int(state.rng_state) * 1664525 + 1013904223) & 0xffffffff)
	return int(state.rng_state % 6) + 1
