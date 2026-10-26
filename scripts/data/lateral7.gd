class_name Lateral7Scenario
extends RefCounted

const GrandTourRef = preload("res://scripts/data/grand_tour_dev.gd")
const ShipFactoryRef = preload("res://scripts/data/ship_factory.gd")
const ReplayRulesRef = preload("res://scripts/engine/replay.gd")
const LogisticsRulesRef = preload("res://scripts/engine/logistics.gd")

const SETUP_UNITS := [
	{"owner":"P2", "kind":"ship", "id":"navy-dreadnought", "type":"dreadnought", "name":"Tycho Brahe 101"},
	{"owner":"P2", "kind":"dummy", "id":"navy-dummy-1"},
	{"owner":"P2", "kind":"dummy", "id":"navy-dummy-2"},
	{"owner":"P2", "kind":"dummy", "id":"navy-dummy-3"},
	{"owner":"P1", "kind":"ship", "id":"pirate-corsair-1", "type":"corsair", "name":"Corsaro pirata A"},
	{"owner":"P1", "kind":"ship", "id":"pirate-corsair-2", "type":"corsair", "name":"Corsaro pirata B"},
	{"owner":"P1", "kind":"ship", "id":"pirate-corvette", "type":"corvette", "name":"Corvetta pirata"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-1"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-2"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-3"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-4"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-5"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-6"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-7"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-8"},
	{"owner":"P1", "kind":"dummy", "id":"pirate-dummy-9"}
]

static func create_state(player_names: Array = ["Pirati", "Marina"]) -> Dictionary:
	var names := player_names.duplicate()
	while names.size() < 2: names.append("Giocatore %d" % (names.size() + 1))
	var state := GrandTourRef.create_state(names.slice(0, 2))
	state.scenario = "lateral-7"
	state.seed = 2039; state.rng_state = 2039
	state.player_order = ["P1", "P2"]; state.player_names = names.slice(0, 2); state.player_types = ["human", "human"]
	state.phase = "setup"; state.segment = "P2"; state.turn = 0
	state.winner = ""; state.victory_level = ""; state.log = []; state.events = []; state.replay_frames = []; state.commands = {}
	state.ships = []; state.dummies = []; state.setup_index = 0
	var venus := _body(state.bodies, "venus")
	var liner := ShipFactoryRef.create("navy-liner", "P2", "liner", venus.hex, "Liner Lateral 7")
	liner.landed_at = "venus"; liner.base_side = 0; liner.trail = [venus.hex]; liner.has_passengers = true
	state.ships.append(liner)
	state.bases = []
	for body_id in ["mars", "terra", "callisto"]:
		var body := _body(state.bodies, body_id); body.base = true; body.owner = "P2"
		state.bases.append({"id":"base-" + body_id, "name":"Base della Marina a " + body.name, "kind":"planetary", "body_id":body_id, "owner":"P2", "active":true, "defense":true})
	var clandestine := _body(state.bodies, "clandestine"); clandestine.base = true; clandestine.owner = "P1"
	state.bases.append({"id":"base-clandestine", "name":"Base pirata Clandestine", "kind":"asteroid", "body_id":"clandestine", "position":clandestine.hex, "owner":"P1", "active":true, "defense":false})
	state.knowledge = {"P1":{"navy-liner":true}, "P2":{"navy-liner":true}}
	state.lateral7 = {"passenger_holder":"navy-liner", "setup_complete":false, "dreadnought_unlocked":false, "pending_dummy_removal":{}}
	state.log.append("Lateral 7: la Marina deve collocare il dreadnought e tre falsi bersagli nella Fascia")
	ReplayRulesRef.record(state, "Inizio setup Lateral 7")
	return state

static func next_setup_unit(state: Dictionary) -> Dictionary:
	var index: int = int(state.get("setup_index", 0))
	return SETUP_UNITS[index] if index >= 0 and index < SETUP_UNITS.size() else {}

static func place_next(state: Dictionary, hex: Vector2i) -> Dictionary:
	var next := state.duplicate(true)
	if next.phase != "setup" or hex not in next.asteroids or _occupied(next, hex): return next
	var unit := next_setup_unit(next)
	if unit.is_empty() or unit.owner != next.segment: return next
	if unit.kind == "ship":
		var ship := ShipFactoryRef.create(unit.id, unit.owner, unit.type, hex, unit.name)
		ship.trail = [hex]; ship.concealed = true; ship.first_acceleration_pending = true
		if unit.owner == "P1": ship.special_asteroid_access = true
		if unit.type == "corsair": ship.inventory.mine = 1
		if unit.type == "dreadnought": ship.inventory.mine = 1; ship.inventory.torpedo = 1; ship.movement_locked = true
		next.ships.append(ship)
		next.knowledge.P1[ship.id] = ship.owner == "P1"
		next.knowledge.P2[ship.id] = ship.owner == "P2"
	else:
		next.dummies.append({"id":unit.id, "owner":unit.owner, "position":hex, "active":true, "concealed":true})
	next.setup_index += 1
	next.log.append("Collocato un segnalino nella Fascia (%d/%d)" % [next.setup_index, SETUP_UNITS.size()])
	if next.setup_index == 4:
		next.segment = "P1"
		next.log.append("Passare ai Pirati per la collocazione")
	elif next.setup_index >= SETUP_UNITS.size():
		next.phase = "astrogation"; next.segment = "P1"; next.turn = 1; next.lateral7.setup_complete = true
		next.log.append("Setup completato: inizia il primo giorno")
	return next

static func transfer_passengers(state: Dictionary, from_id: String, to_id: String) -> Dictionary:
	var next := state.duplicate(true)
	if next.get("scenario", "") != "lateral-7" or next.phase != "resupply": return next
	var source := _ship(next.ships, from_id); var target := _ship(next.ships, to_id)
	if source.is_empty() or target.is_empty() or source.id != next.lateral7.passenger_holder or target.owner != "P1": return next
	if source.destroyed or target.destroyed or source.position != target.position or source.velocity != target.velocity: return next
	source.has_passengers = false; target.has_passengers = true; next.lateral7.passenger_holder = target.id
	next.log.append("Passeggeri trasferiti da %s a %s" % [source.name, target.name])
	return next

static func begin_dummy_removal(state: Dictionary, ship_id: String, thrust_steps: Array) -> bool:
	if state.get("scenario", "") != "lateral-7" or not state.lateral7.pending_dummy_removal.is_empty(): return false
	var ship := _ship(state.ships, ship_id)
	if ship.is_empty() or not ship.get("first_acceleration_pending", false): return false
	if ship.get("movement_locked", false) and not state.lateral7.dreadnought_unlocked: return false
	state.lateral7.pending_dummy_removal = {"ship_id":ship_id, "owner":ship.owner, "remaining":3, "thrust_steps":thrust_steps.duplicate(true)}
	return true

static func remove_dummy_at(state: Dictionary, hex: Vector2i) -> bool:
	var pending: Dictionary = state.get("lateral7", {}).get("pending_dummy_removal", {})
	if pending.is_empty(): return false
	for dummy: Dictionary in state.dummies:
		if dummy.active and dummy.owner == pending.owner and dummy.position == hex:
			dummy.active = false; pending.remaining = int(pending.remaining) - 1
			state.log.append("Rimosso falso bersaglio: ne restano %d" % pending.remaining)
			if pending.remaining <= 0:
				var command: Dictionary = state.commands.get(pending.ship_id, {})
				command.thrust_steps = pending.thrust_steps
				command.dummies_removed = true
				state.commands[pending.ship_id] = command
				state.lateral7.pending_dummy_removal = {}
			return true
	return false

static func load_mine(state: Dictionary, ship_id: String) -> Dictionary:
	var next := state.duplicate(true)
	if next.get("scenario", "") != "lateral-7" or next.phase != "resupply": return next
	var ship := _ship(next.ships, ship_id); var clandestine := _body(next.bodies, "clandestine")
	if ship.is_empty() or ship.owner != "P1" or ship.destroyed or ship.position != clandestine.hex or ship.velocity != Vector2i.ZERO: return next
	var inventory: Dictionary = ship.inventory.duplicate(true); inventory.mine = inventory.get("mine", 0) + 1
	if not LogisticsRulesRef.loadout_fits(ship, inventory): return next
	ship.inventory = inventory; next.log.append("%s carica una mina a Clandestine" % ship.name)
	return next

static func _occupied(state: Dictionary, hex: Vector2i) -> bool:
	for ship: Dictionary in state.ships:
		if ship.position == hex: return true
	for dummy: Dictionary in state.dummies:
		if dummy.active and dummy.position == hex: return true
	return false

static func _body(bodies: Array, id: String) -> Dictionary:
	for body: Dictionary in bodies:
		if body.id == id: return body
	return {}

static func _ship(ships: Array, id: String) -> Dictionary:
	for ship: Dictionary in ships:
		if ship.id == id: return ship
	return {}
