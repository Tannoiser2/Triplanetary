class_name GameRules
extends RefCounted

const HexMathRef = preload("res://scripts/engine/hex.gd")
const CombatRulesRef = preload("res://scripts/engine/combat.gd")
const OrdnanceRulesRef = preload("res://scripts/engine/ordnance.gd")
const LogisticsRulesRef = preload("res://scripts/engine/logistics.gd")

const PHASES := ["astrogation", "ordnance", "movement", "combat", "resupply"]

static func move_ship(ship: Dictionary, command: Dictionary, gravity_fields: Array, turn: int) -> Dictionary:
	var next := ship.duplicate(true)
	if next.destroyed: return next
	if next.get("landed_at", "") != "": return next
	var thrust_steps: Array = command.get("thrust_steps", []) if next.disabled_until_turn < turn else []
	if thrust_steps.size() > 2: push_error("Comando di spinta non valido"); return next
	if thrust_steps.size() == 2 and not can_overload(next): push_error("Sovraccarico non disponibile"); return next
	var thrust := Vector2i.ZERO
	for step: Vector2i in thrust_steps:
		if step not in HexMathRef.DIRECTIONS: push_error("Direzione di spinta non valida"); return next
		thrust += step
	var cost := thrust_steps.size()
	if cost > next.fuel: push_error("Carburante esaurito"); return next
	next.fuel -= cost
	next.fuel_spent = next.get("fuel_spent", 0) + cost
	if cost == 2: next.overload_available = false
	if next.get("must_burn_after_takeoff", false) and cost == 0:
		next.destroyed = true
		next.destroyed_reason = "Ricaduta dopo il decollo"
		return next
	next.must_burn_after_takeoff = false
	next.previous_position = next.position
	var applied := Vector2i.ZERO
	for acceleration: Vector2i in next.pending_gravity: applied += acceleration
	next.velocity += applied + thrust
	var destination: Vector2i = next.position + next.velocity
	var path := HexMathRef.supercover_line(next.position, destination)
	next.position = destination
	next.pending_gravity = []
	var weak_count_by_body := {}
	for hex: Vector2i in path.slice(1):
		for field: Dictionary in gravity_fields:
			if field.hex != hex: continue
			if field.get("weak", false):
				var count: int = weak_count_by_body.get(field.body_id, 0)
				weak_count_by_body[field.body_id] = count + 1
				if count > 0 or command.get("use_first_weak_gravity", false):
					next.pending_gravity.append(field.acceleration)
			else:
				next.pending_gravity.append(field.acceleration)
				if not field.body_id in next.visited_bodies: next.visited_bodies.append(field.body_id)
	return next

static func advance_phase(state: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	if next.phase == "combat" and not next.pending_combat.is_empty():
		return next
	var index := PHASES.find(next.phase)
	if next.phase == "movement":
		for i in range(next.ships.size()):
			if next.ships[i].owner == next.segment:
				var command: Dictionary = next.commands.get(next.ships[i].id, {})
				var from_position: Vector2i = next.ships[i].position
				if command.get("takeoff", false): _takeoff(next.ships[i], next.bodies)
				elif command.has("land_body_id"): _land(next.ships[i], command.land_body_id, next.bodies)
				else: next.ships[i] = move_ship(next.ships[i], command, next.gravity, next.turn)
				_apply_map_and_body_collisions(next.ships[i], next.bodies, next, from_position)
				OrdnanceRulesRef.resolve_asteroid_hazards(next, next.ships[i], HexMathRef.supercover_line(from_position, next.ships[i].position))
				if next.ships[i].get("must_change_after_launch", false):
					var launcher_items: Array = next.ordnance.filter(func(item): return item.launcher_id == next.ships[i].id and item.age == 0)
					if not launcher_items.is_empty() and next.ships[i].velocity == launcher_items[0].velocity:
						next.ships[i].destroyed = true; next.ships[i].destroyed_reason = "Mancato cambio di rotta dopo il lancio"
					next.ships[i].must_change_after_launch = false
				next.log.append("G%d %s · %s → %s" % [next.turn, next.segment, next.ships[i].name, next.ships[i].position])
				next.events.append({"turn": next.turn, "segment": next.segment, "phase": "movement", "ship": next.ships[i].id, "command": command.duplicate(true), "position": next.ships[i].position, "velocity": next.ships[i].velocity})
		OrdnanceRulesRef.move_and_resolve(next)
		LogisticsRulesRef.update_detection(next)
	if next.phase == "resupply":
		for i in range(next.ships.size()):
			if next.ships[i].owner != next.segment: continue
			for body: Dictionary in next.bodies:
				if body.base and HexMathRef.distance(next.ships[i].position, body.hex) <= 1 and body.id in ["terra", "venus", "mars", "callisto"]:
					next.ships[i].fuel = next.ships[i].max_fuel
					next.ships[i].overload_available = true
					next.log.append("G%d %s · rifornimento a %s" % [next.turn, next.segment, body.name])
	_check_grand_tour_victory(next)
	if index < PHASES.size() - 1:
		next.phase = PHASES[index + 1]
	else:
		next.phase = PHASES[0]
		next.commands = {}
		if next.segment == "P1": next.segment = "P2"
		else: next.segment = "P1"; next.turn += 1
	return next

static func declare_attack(state: Dictionary, attacker_id: String, target_id: String) -> Dictionary:
	var next := state.duplicate(true)
	if next.phase != "combat" or not next.pending_combat.is_empty(): return next
	var attacker := _ship_by_id(next.ships, attacker_id)
	var target := _ship_by_id(next.ships, target_id)
	var key := "%d:%s" % [next.turn, next.segment]
	if attacker.is_empty() or target.is_empty() or attacker.owner != next.segment or target.owner == next.segment: return next
	if not LogisticsRulesRef.is_detected(next, attacker.owner, target.id): return next
	if attacker.destroyed or target.destroyed or attacker.commercial or attacker.get("landed_at", "") != "": return next
	if attacker.disabled_until_turn >= next.turn and not attacker.get("dreadnought", false): return next
	if attacker.last_attack_key == key or target.last_target_key == key: return next
	next.pending_combat = {"attacker_id": attacker_id, "target_id": target_id, "defender": target.owner}
	next.log.append("%s attacca %s: passare il controllo a %s" % [attacker.name, target.name, target.owner])
	return next

static func respond_to_attack(state: Dictionary, counterattack: bool) -> Dictionary:
	var next := state.duplicate(true)
	if next.phase != "combat" or next.pending_combat.is_empty(): return next
	var attacker := _ship_by_id(next.ships, next.pending_combat.attacker_id)
	var defender := _ship_by_id(next.ships, next.pending_combat.target_id)
	var key := "%d:%s" % [next.turn, next.segment]
	var attack_result := _resolve_gun(next, attacker, defender)
	var counter_result := "-"
	var may_counter: bool = counterattack and not defender.commercial and not defender.destroyed and defender.get("landed_at", "") == ""
	if defender.disabled_until_turn >= next.turn and not defender.get("dreadnought", false): may_counter = false
	if may_counter: counter_result = _resolve_gun(next, defender, attacker)
	attacker.last_attack_key = key
	defender.last_target_key = key
	# I risultati sono applicati solo dopo entrambi i tiri.
	_apply_damage(defender, attack_result, next.turn)
	if may_counter: _apply_damage(attacker, counter_result, next.turn)
	next.log.append("Fuoco: %s → %s [%s]%s" % [attacker.name, defender.name, attack_result, " · contrattacco [%s]" % counter_result if may_counter else ""])
	next.events.append({"turn":next.turn,"segment":next.segment,"phase":"combat","attacker":attacker.id,"defender":defender.id,"attack_result":attack_result,"counter_result":counter_result if may_counter else "none"})
	next.pending_combat = {}
	return next

static func _resolve_gun(state: Dictionary, attacker: Dictionary, defender: Dictionary) -> String:
	var attack_path := HexMathRef.supercover_line(attacker.get("previous_position", attacker.position), attacker.position)
	var range_hexes := 999
	for hex: Vector2i in attack_path: range_hexes = mini(range_hexes, HexMathRef.distance(hex, defender.position))
	var relative_velocity := HexMathRef.distance(attacker.velocity, defender.velocity)
	var die := _roll_d6(state)
	var result := CombatRulesRef.gun_damage(attacker.combat, defender.combat, die, range_hexes, relative_velocity, attacker.get("heroic", false))
	var column := CombatRulesRef.odds_column(attacker.combat, defender.combat)
	if column == 0 and result in ["D2", "D3", "D4", "D5", "E"]: attacker.heroic = true
	state.log.append("Tiro %d; distanza %d; velocità relativa %d" % [die, range_hexes, relative_velocity])
	return result

static func _apply_damage(ship: Dictionary, result: String, turn: int) -> void:
	if result == "-": return
	if result == "E": ship.destroyed = true; ship.destroyed_reason = "Eliminata in combattimento"; return
	var amount := CombatRulesRef.disabled_turns(result)
	var remaining := maxi(0, ship.disabled_until_turn - turn)
	if remaining + amount >= 6:
		ship.destroyed = true; ship.destroyed_reason = "Danni cumulativi"; return
	ship.disabled_until_turn = maxi(turn, ship.disabled_until_turn) + amount

static func _roll_d6(state: Dictionary) -> int:
	state.rng_state = int((int(state.rng_state) * 1664525 + 1013904223) & 0xffffffff)
	return int(state.rng_state % 6) + 1

static func _ship_by_id(ships: Array, id: String) -> Dictionary:
	for ship: Dictionary in ships:
		if ship.id == id: return ship
	return {}

static func can_overload(ship: Dictionary) -> bool:
	return not ship.get("commercial", false) and ship.get("overload_available", false) and ship.fuel >= 2 and not ship.destroyed and ship.get("landed_at", "") == ""

static func can_land(ship: Dictionary, body: Dictionary) -> bool:
	return ship.get("landed_at", "") == "" and ship.fuel >= 1 and HexMathRef.distance(ship.position, body.hex) == 1 and HexMathRef.distance(Vector2i.ZERO, ship.velocity) == 1 and body.base

static func _takeoff(ship: Dictionary, bodies: Array) -> void:
	if ship.get("landed_at", "") == "" or ship.destroyed: return
	var body := _body_by_id(bodies, ship.landed_at)
	ship.position = body.hex + HexMathRef.DIRECTIONS[ship.base_side]
	ship.velocity = Vector2i.ZERO
	ship.pending_gravity = []
	ship.landed_at = ""
	ship.must_burn_after_takeoff = true

static func _land(ship: Dictionary, body_id: String, bodies: Array) -> void:
	var body := _body_by_id(bodies, body_id)
	if not can_land(ship, body): return
	ship.fuel -= 1
	ship.fuel_spent += 1
	ship.base_side = HexMathRef.DIRECTIONS.find(ship.position - body.hex)
	ship.position = body.hex
	ship.velocity = Vector2i.ZERO
	ship.pending_gravity = []
	ship.landed_at = body_id

static func _apply_map_and_body_collisions(ship: Dictionary, bodies: Array, state: Dictionary, from_position: Vector2i) -> void:
	if ship.destroyed or ship.get("landed_at", "") != "": return
	var offset := HexMathRef.axial_to_odd_q(ship.position)
	if offset.x < 0 or offset.x >= state.map_columns or offset.y < 0 or offset.y >= state.map_rows:
		ship.destroyed = true; ship.destroyed_reason = "Uscita dalla mappa"; return
	var path: Array = HexMathRef.supercover_line(from_position, ship.position).slice(1)
	for body: Dictionary in bodies:
		if body.hex in path:
			ship.destroyed = true; ship.destroyed_reason = "Collisione con " + body.name; return

static func _body_by_id(bodies: Array, id: String) -> Dictionary:
	for body: Dictionary in bodies:
		if body.id == id: return body
	return {}

static func _check_grand_tour_victory(state: Dictionary) -> void:
	var required: Array = []
	for body: Dictionary in state.bodies:
		if body.full_gravity: required.append(body.id)
	var terra: Dictionary = state.bodies.filter(func(body): return body.id == "terra")[0]
	for ship: Dictionary in state.ships:
		if HexMathRef.distance(ship.position, terra.hex) > 1: continue
		var complete := true
		for body_id: String in required:
			if not body_id in ship.visited_bodies: complete = false
		if complete:
			state.winner = ship.owner
			if not ("Vittoria Grand Tour: " + ship.owner) in state.log:
				state.log.append("Vittoria Grand Tour: %s, carburante consumato %d" % [ship.owner, ship.fuel_spent])
