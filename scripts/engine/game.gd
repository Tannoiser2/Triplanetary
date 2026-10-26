class_name GameRules
extends RefCounted

const HexMathRef = preload("res://scripts/engine/hex.gd")
const CombatRulesRef = preload("res://scripts/engine/combat.gd")
const OrdnanceRulesRef = preload("res://scripts/engine/ordnance.gd")
const LogisticsRulesRef = preload("res://scripts/engine/logistics.gd")
const BaseRulesRef = preload("res://scripts/engine/bases.gd")

const PHASES := ["astrogation", "ordnance", "movement", "combat", "resupply"]

static func move_ship(ship: Dictionary, command: Dictionary, gravity_fields: Array, turn: int) -> Dictionary:
	var next := ship.duplicate(true)
	if next.destroyed or next.get("escaped", false) or next.get("captured", false): return next
	if next.get("landed_at", "") != "": return next
	var thrust_steps: Array = command.get("thrust_steps", []) if next.disabled_until_turn < turn else []
	if thrust_steps.size() > 2: push_error("Comando di spinta non valido"); return next
	if thrust_steps.size() == 2 and not can_overload(next): push_error("Sovraccarico non disponibile"); return next
	var thrust := Vector2i.ZERO
	for step: Vector2i in thrust_steps:
		if step not in HexMathRef.DIRECTIONS: push_error("Direzione di spinta non valida"); return next
		thrust += step
	var cost := thrust_steps.size()
	if not next.get("infinite_fuel", false) and cost > next.fuel: push_error("Carburante esaurito"); return next
	if not next.get("infinite_fuel", false): next.fuel -= cost
	next.fuel_spent = next.get("fuel_spent", 0) + cost
	if cost == 2: next.overload_available = false
	if cost > 0: next.first_acceleration_pending = false
	if next.get("must_burn_after_takeoff", false) and cost == 0:
		next.destroyed = true
		next.destroyed_reason = "Ricaduta dopo il decollo"
		return next
	next.must_burn_after_takeoff = false
	next.previous_position = next.position
	var inertial_end: Vector2i = next.position + next.velocity
	var applied := Vector2i.ZERO
	var gravity_steps: Array = []
	for acceleration: Vector2i in next.pending_gravity:
		applied += acceleration
		gravity_steps.append(acceleration)
	next.velocity += applied + thrust
	var destination: Vector2i = next.position + next.velocity
	var path := HexMathRef.supercover_line(next.position, destination)
	next.position = destination
	if not next.has("trail"): next.trail = [next.previous_position]
	next.trail.append(destination)
	if not next.has("maneuver_history"): next.maneuver_history = []
	next.maneuver_history.append({
		"turn": turn,
		"from": next.previous_position,
		"inertial_end": inertial_end,
		"gravity_steps": gravity_steps,
		"thrust_steps": thrust_steps.duplicate(true),
		"destination": destination
	})
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
				if next.ships[i].get("movement_locked", false) and not next.get("lateral7", {}).get("dreadnought_unlocked", false): command = {}
				var from_position: Vector2i = next.ships[i].position
				if command.get("takeoff", false): _takeoff(next.ships[i], next.bodies)
				elif command.has("land_body_id"): _land(next.ships[i], command.land_body_id, next.bodies)
				else: next.ships[i] = move_ship(next.ships[i], command, next.gravity, next.turn)
				_apply_map_and_body_collisions(next.ships[i], next.bodies, next, from_position)
				_resolve_ram(next, next.ships[i], command, from_position)
				_apply_planetary_defenses(next, next.ships[i])
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
			for base: Dictionary in next.get("bases", []):
				if BaseRulesRef.resupply(next, next.ships[i], base): break
	_check_scenario_victory(next)
	if index < PHASES.size() - 1:
		next.phase = PHASES[index + 1]
	else:
		next.phase = PHASES[0]
		next.commands = {}
		var order: Array = next.get("player_order", ["P1", "P2"])
		var player_index := order.find(next.segment)
		if player_index < order.size() - 1: next.segment = order[player_index + 1]
		else: next.segment = order[0]; next.turn += 1
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
	return not ship.get("commercial", false) and ship.get("overload_available", false) and (ship.get("infinite_fuel", false) or ship.fuel >= 2) and not ship.destroyed and ship.get("landed_at", "") == ""

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
		if state.get("scenario", "") == "escape" and ship.owner == "P1" and ship.type == "transport" and offset.x >= state.map_columns:
			ship.escaped = true
			ship.exit_velocity = ship.velocity
			ship.exit_fuel = ship.fuel
			state.log.append("%s ha superato il bordo oltre Giove" % ship.name)
			return
		ship.destroyed = true; ship.destroyed_reason = "Uscita dalla mappa"; return
	var path: Array = HexMathRef.supercover_line(from_position, ship.position).slice(1)
	for body: Dictionary in bodies:
		if body.hex in path:
			ship.destroyed = true; ship.destroyed_reason = "Collisione con " + body.name; return

static func _body_by_id(bodies: Array, id: String) -> Dictionary:
	for body: Dictionary in bodies:
		if body.id == id: return body
	return {}

static func _check_scenario_victory(state: Dictionary) -> void:
	if state.get("scenario", "") == "grand-tour-2037": _check_grand_tour_victory(state)
	elif state.get("scenario", "") == "escape": _check_escape_victory(state)
	elif state.get("scenario", "") == "lateral-7": _check_lateral7_victory(state)

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

static func _check_escape_victory(state: Dictionary) -> void:
	if state.winner != "": return
	var fugitive_id: String = state.get("escape", {}).get("fugitive_ship_id", "")
	var fugitive := _ship_by_id(state.ships, fugitive_id)
	if fugitive.is_empty(): return
	if fugitive.get("escaped", false):
		var stopping_fuel := HexMathRef.distance(Vector2i.ZERO, fugitive.get("exit_velocity", Vector2i.ZERO)) + 1
		state.winner = "P1"
		state.victory_level = "decisiva" if fugitive.get("exit_fuel", 0) >= stopping_fuel else "marginale"
	elif fugitive.get("captured", false):
		var captor := _ship_by_id(state.ships, fugitive.get("captured_by", ""))
		if not captor.is_empty() and captor.get("landed_at", "") in ["terra", "venus", "io"]:
			state.winner = "P2"; state.victory_level = "decisiva"
	elif fugitive.destroyed:
		var enforcer_destroyed := false
		for ship: Dictionary in state.ships:
			if ship.owner == "P2" and ship.destroyed: enforcer_destroyed = true
		state.winner = "P1" if enforcer_destroyed else "P2"
		state.victory_level = "morale" if enforcer_destroyed else "marginale"
	if state.winner != "": state.log.append("Escape: vittoria %s di %s" % [state.victory_level, state.winner])

static func _check_lateral7_victory(state: Dictionary) -> void:
	if state.winner != "" or not state.get("lateral7", {}).get("setup_complete", false): return
	var holder := _ship_by_id(state.ships, state.lateral7.passenger_holder)
	if holder.is_empty() or holder.destroyed:
		state.winner = "NESSUNO"; state.victory_level = "sconfitta reciproca"
	elif holder.owner == "P1":
		var clandestine := _body_by_id(state.bodies, "clandestine")
		if holder.position == clandestine.hex and holder.velocity == Vector2i.ZERO:
			state.winner = "P1"
			state.victory_level = "decisiva" if state.ships.any(func(ship): return ship.type == "dreadnought" and ship.destroyed) else "normale"
	else:
		var liner := _ship_by_id(state.ships, "navy-liner")
		if not liner.is_empty() and "ganymede" in liner.visited_bodies:
			state.winner = "P2"
			state.victory_level = "decisiva" if state.ships.any(func(ship): return ship.owner == "P1" and ship.destroyed) else "normale"
	if state.winner != "": state.log.append("Lateral 7: %s, esito %s" % [state.winner, state.victory_level])

static func inspect_or_capture(state: Dictionary, inspector_id: String, target_id: String) -> Dictionary:
	var next := state.duplicate(true)
	if next.get("scenario", "") != "escape" or next.phase != "resupply": return next
	var inspector := _ship_by_id(next.ships, inspector_id)
	var target := _ship_by_id(next.ships, target_id)
	if inspector.is_empty() or target.is_empty() or inspector.owner != "P2" or target.owner != "P1": return next
	if inspector.destroyed or target.destroyed or target.get("escaped", false): return next
	if inspector.position != target.position or inspector.velocity != target.velocity: return next
	target.inspected = true
	var identity := "fuggitivi" if target.get("secret_cargo", false) else "esca"
	next.log.append("%s ispeziona %s: %s" % [inspector.name, target.name, identity])
	if target.get("secret_cargo", false) and target.disabled_until_turn >= next.turn:
		target.captured = true
		target.captured_by = inspector.id
		next.log.append("I fuggitivi sono stati catturati da %s" % inspector.name)
	_check_escape_victory(next)
	return next

static func _resolve_ram(state: Dictionary, attacker: Dictionary, command: Dictionary, from_position: Vector2i) -> void:
	var target_id: String = command.get("ram_target_id", "")
	if target_id == "" or attacker.destroyed or attacker.get("escaped", false): return
	if state.get("scenario", "") != "escape" or attacker.owner != "P1": return
	var target := _ship_by_id(state.ships, target_id)
	if target.is_empty() or target.owner == attacker.owner or target.destroyed: return
	if target.position not in HexMathRef.supercover_line(from_position, attacker.position): return
	var die := _roll_d6(state)
	var result := "D2" if die >= 5 else "-"
	_apply_damage(attacker, result, state.turn)
	_apply_damage(target, result, state.turn)
	state.log.append("Speronamento di %s contro %s: tiro %d [%s]" % [attacker.name, target.name, die, result])
	state.events.append({"turn":state.turn, "segment":state.segment, "phase":"movement", "kind":"ram", "attacker":attacker.id, "target":target.id, "die":die, "result":result})

static func _apply_planetary_defenses(state: Dictionary, ship: Dictionary) -> void:
	if ship.destroyed or ship.get("landed_at", "") != "": return
	for base: Dictionary in state.get("bases", []):
		if base.get("kind", "") != "planetary" or not base.get("defense", false) or base.get("owner", "") in ["", "neutral", "shared", ship.owner]: continue
		var body := _body_by_id(state.bodies, base.get("body_id", ""))
		if body.is_empty() or HexMathRef.distance(ship.position, body.hex) != 1: continue
		var result := BaseRulesRef.defense_result(state, base, ship)
		_apply_damage(ship, result, state.turn)
		state.log.append("Difesa di %s contro %s [%s]" % [base.name, ship.name, result])
		state.events.append({"turn":state.turn, "segment":state.segment, "phase":"movement", "kind":"planetary_defense", "base":base.id, "target":ship.id, "result":result})
