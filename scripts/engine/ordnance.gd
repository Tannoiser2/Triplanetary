class_name OrdnanceRules
extends RefCounted

const HexMathRef = preload("res://scripts/engine/hex.gd")
const MASS := {"mine": 10, "torpedo": 20, "nuke": 20}
const DAMAGE := {"torpedo": ["-", "D5", "E", "E", "E", "E"], "mine": ["-", "-", "-", "D1", "D2", "D3"], "ram": ["-", "-", "-", "-", "D2", "D2"], "asteroid": ["-", "-", "-", "-", "D1", "D2"]}

static func launch(state: Dictionary, ship_id: String, kind: String, acceleration := Vector2i.ZERO) -> Dictionary:
	var next := state.duplicate(true)
	if next.phase != "ordnance" or kind not in MASS: return next
	var ship := _ship_by_id(next.ships, ship_id)
	if ship.is_empty() or ship.owner != next.segment or ship.destroyed or ship.get("landed_at", "") != "": return next
	if ship.disabled_until_turn >= next.turn or ship.get("launched_key", "") == _segment_key(next): return next
	if kind == "torpedo" and ship.commercial: return next
	if ship.inventory.get(kind, 0) <= 0: return next
	if kind == "torpedo" and (HexMathRef.distance(Vector2i.ZERO, acceleration) < 1 or HexMathRef.distance(Vector2i.ZERO, acceleration) > 2): return next
	if kind != "torpedo" and acceleration != Vector2i.ZERO: return next
	ship.inventory[kind] -= 1; ship.launched_key = _segment_key(next)
	var id := "ord-%d-%d" % [next.turn, next.get("next_entity_id", 1)]; next.next_entity_id = next.get("next_entity_id", 1) + 1
	next.ordnance.append({"id":id,"kind":kind,"owner":ship.owner,"position":ship.position,"previous_position":ship.position,"velocity":ship.velocity + acceleration,"pending_gravity":[],"age":0,"active":true,"launcher_id":ship.id})
	if kind in ["mine", "nuke"]: ship.must_change_after_launch = true
	next.log.append("%s lancia %s" % [ship.name, kind])
	return next

static func move_and_resolve(state: Dictionary) -> void:
	for item: Dictionary in state.ordnance:
		if not item.active or item.owner != state.segment: continue
		item.previous_position = item.position
		var gravity_sum := Vector2i.ZERO
		for acceleration: Vector2i in item.pending_gravity: gravity_sum += acceleration
		item.velocity += gravity_sum; item.position += item.velocity; item.pending_gravity = []
		var path := HexMathRef.supercover_line(item.previous_position, item.position)
		for hex: Vector2i in path.slice(1):
			for field: Dictionary in state.gravity:
				if field.hex == hex and not field.get("weak", false): item.pending_gravity.append(field.acceleration)
		item.age += 1; _resolve_item_contacts(state, item, path)
		if item.age >= 5 and item.active: item.active = false; state.log.append("%s si disperde/autodistrugge" % item.id)
	state.ordnance = state.ordnance.filter(func(item): return item.active)

static func resolve_asteroid_hazards(state: Dictionary, ship: Dictionary, path: Array) -> void:
	for hex: Vector2i in path.slice(1):
		if hex in state.get("special_asteroids", []) and ship.get("special_asteroid_access", false) == false:
			ship.destroyed = true; ship.destroyed_reason = "Ingresso negli asteroidi speciali"; return
	if HexMathRef.distance(Vector2i.ZERO, ship.velocity) <= 1: return
	for hex: Vector2i in path.slice(1):
		if hex not in state.get("asteroids", []): continue
		var result: String = DAMAGE.asteroid[_roll_d6(state) - 1]; _apply_damage(ship, result, state.turn)
		state.log.append("Asteroidi: %s [%s]" % [ship.name, result])

static func ram(state: Dictionary, attacker_id: String, target_id: String) -> Dictionary:
	var next := state.duplicate(true)
	if next.phase != "movement": return next
	var attacker := _ship_by_id(next.ships, attacker_id); var target := _ship_by_id(next.ships, target_id)
	if attacker.is_empty() or target.is_empty() or attacker.owner != next.segment or target.owner == next.segment: return next
	if attacker.get("rammed_key", "") == _segment_key(next) or target.position not in HexMathRef.supercover_line(attacker.previous_position, attacker.position): return next
	var result: String = DAMAGE.ram[_roll_d6(next) - 1]; _apply_damage(attacker, result, next.turn); _apply_damage(target, result, next.turn)
	attacker.rammed_key = _segment_key(next); next.log.append("Speronamento %s/%s [%s]" % [attacker.name, target.name, result])
	return next

static func _resolve_item_contacts(state: Dictionary, item: Dictionary, path: Array) -> void:
	for hex: Vector2i in path.slice(1):
		if hex in state.get("special_asteroids", []):
			item.active = false
			if item.kind == "nuke": state.special_asteroids.erase(hex); state.asteroids.erase(hex)
			state.log.append("%s detona negli asteroidi speciali" % item.kind); return
	for body: Dictionary in state.bodies:
		if body.hex in path: item.active = false; state.log.append("%s impatta %s" % [item.kind, body.name]); return
	for ship: Dictionary in state.ships:
		if ship.destroyed or ship.get("landed_at", "") != "": continue
		var hit: bool = ship.position in path if item.kind == "mine" else ship.position == item.position
		if not hit: continue
		if item.kind == "nuke": ship.destroyed = true; ship.destroyed_reason = "Esplosione nucleare"
		else: _apply_damage(ship, DAMAGE[item.kind][_roll_d6(state) - 1], state.turn)
		item.active = false; state.log.append("%s colpisce %s" % [item.kind, ship.name]); return
	for other: Dictionary in state.ordnance:
		if other.id != item.id and other.active and other.position == item.position:
			item.active = false; other.active = false; state.log.append("Collisione tra ordigni"); return

static func _apply_damage(ship: Dictionary, result: String, turn: int) -> void:
	if result == "-": return
	if result == "E": ship.destroyed = true; ship.destroyed_reason = "Distrutta da ordigno/pericolo"; return
	var amount := result.substr(1).to_int(); var remaining := maxi(0, ship.disabled_until_turn - turn)
	if remaining + amount >= 6: ship.destroyed = true; ship.destroyed_reason = "Danni cumulativi"
	else: ship.disabled_until_turn = maxi(turn, ship.disabled_until_turn) + amount

static func _roll_d6(state: Dictionary) -> int:
	state.rng_state = int((int(state.rng_state) * 1664525 + 1013904223) & 0xffffffff); return int(state.rng_state % 6) + 1
static func _segment_key(state: Dictionary) -> String: return "%d:%s" % [state.turn, state.segment]
static func _ship_by_id(ships: Array, id: String) -> Dictionary:
	for ship: Dictionary in ships:
		if ship.id == id: return ship
	return {}
