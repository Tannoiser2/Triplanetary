class_name EscapeScenario
extends RefCounted

const GrandTourRef = preload("res://scripts/data/grand_tour_dev.gd")
const HexMathRef = preload("res://scripts/engine/hex.gd")
const ShipFactoryRef = preload("res://scripts/data/ship_factory.gd")
const ReplayRulesRef = preload("res://scripts/engine/replay.gd")

static func create_state(player_names: Array = ["Pellegrini", "Enforcers"]) -> Dictionary:
	var names := player_names.duplicate()
	while names.size() < 2: names.append("Giocatore %d" % (names.size() + 1))
	var state := GrandTourRef.create_state(names.slice(0, 2))
	state.scenario = "escape"
	state.seed = 2038
	state.rng_state = 2038
	state.player_order = ["P1", "P2"]
	state.player_names = names.slice(0, 2)
	state.player_types = ["human", "human"]
	state.winner = ""
	state.victory_level = ""
	state.log = []
	state.events = []
	state.replay_frames = []
	state.commands = {}
	var terra: Dictionary = _body(state.bodies, "terra")
	var venus: Dictionary = _body(state.bodies, "venus")
	state.ships = []
	for i in range(3):
		var transport := ShipFactoryRef.create("pilgrim-%d" % (i + 1), "P1", "transport", terra.hex, "Trasporto %s" % char(65 + i))
		transport.landed_at = "terra"
		transport.base_side = i
		transport.trail = [terra.hex]
		transport.secret_cargo = i == 0
		transport.inspected = false
		state.ships.append(transport)
	state.ships.append(_orbiting_ship("enforcer-corvette", "P2", "corvette", terra, 0, "Corvetta Enforcer"))
	state.ships.append(_orbiting_ship("enforcer-corsair", "P2", "corsair", venus, 3, "Corsaro Enforcer"))
	state.bases = []
	for body_id in ["terra", "venus", "io"]:
		var body := _body(state.bodies, body_id)
		body.base = true
		body.owner = "P2"
		state.bases.append({"id":"base-" + body_id, "name":"Base Enforcer di " + body.name, "kind":"planetary", "body_id":body_id, "owner":"P2", "active":true, "defense":false})
	for body: Dictionary in state.bodies:
		if body.id not in ["terra", "venus", "io"]:
			body.base = false
			body.owner = ""
	state.knowledge = {"P1":{}, "P2":{}}
	for ship: Dictionary in state.ships:
		state.knowledge.P1[ship.id] = true
		state.knowledge.P2[ship.id] = true
	state.escape = {"fugitive_ship_id":"pilgrim-1", "enforcer_losses":0, "inspection_log":[]}
	state.log.append("Escape: i Pellegrini preparano tre trasporti; l'identità dei fuggitivi è segreta")
	ReplayRulesRef.record(state, "Inizio scenario Escape")
	return state

static func _orbiting_ship(id: String, owner: String, type: String, body: Dictionary, side: int, name: String) -> Dictionary:
	var position: Vector2i = body.hex + HexMathRef.DIRECTIONS[side]
	var next_position: Vector2i = body.hex + HexMathRef.DIRECTIONS[(side + 1) % 6]
	var ship := ShipFactoryRef.create(id, owner, type, position, name)
	ship.velocity = next_position - position
	ship.previous_position = position - ship.velocity
	ship.trail = [ship.previous_position, position]
	ship.visited_bodies = [body.id]
	return ship

static func _body(bodies: Array, id: String) -> Dictionary:
	for body: Dictionary in bodies:
		if body.id == id: return body
	return {}
