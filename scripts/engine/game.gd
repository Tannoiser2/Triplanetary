class_name GameRules
extends RefCounted

const HexMathRef = preload("res://scripts/engine/hex.gd")

const PHASES := ["astrogation", "ordnance", "movement", "combat", "resupply"]

static func move_ship(ship: Dictionary, command: Dictionary, gravity_fields: Array, turn: int) -> Dictionary:
	var next := ship.duplicate(true)
	if next.destroyed: return next
	var thrust: Vector2i = command.get("thrust", Vector2i.ZERO) if next.disabled_until_turn < turn else Vector2i.ZERO
	if thrust != Vector2i.ZERO:
		if next.fuel <= 0: push_error("Carburante esaurito"); return next
		next.fuel -= 1
		next.fuel_spent = next.get("fuel_spent", 0) + 1
	var applied := Vector2i.ZERO
	for acceleration: Vector2i in next.pending_gravity: applied += acceleration
	next.velocity += applied + thrust
	var destination: Vector2i = next.position + next.velocity
	var path := HexMathRef.line(next.position, destination)
	next.position = destination
	next.pending_gravity = []
	for hex: Vector2i in path.slice(1):
		for field: Dictionary in gravity_fields:
			if field.hex == hex and not field.get("weak", false):
				next.pending_gravity.append(field.acceleration)
				if not field.body_id in next.visited_bodies:
					next.visited_bodies.append(field.body_id)
	return next

static func advance_phase(state: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var index := PHASES.find(next.phase)
	if next.phase == "movement":
		for i in range(next.ships.size()):
			if next.ships[i].owner == next.segment:
				var command: Dictionary = next.commands.get(next.ships[i].id, {})
				next.ships[i] = move_ship(next.ships[i], command, next.gravity, next.turn)
				next.log.append("G%d %s · %s → %s" % [next.turn, next.segment, next.ships[i].name, next.ships[i].position])
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
