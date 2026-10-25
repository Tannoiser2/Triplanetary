class_name LogisticsRules
extends RefCounted

const HexMathRef = preload("res://scripts/engine/hex.gd")
const ITEM_MASS := {"mine":10,"torpedo":20,"nuke":20,"orbital_base":50,"ore":1,"ct_shard":10,"automated_mine":10,"robot_guards":10,"pm_grapples":40}

static func cargo_mass(ship: Dictionary) -> int:
	var total := 0
	for item in ship.inventory: total += ship.inventory[item] * ITEM_MASS.get(item, 0)
	return total

static func loadout_fits(ship: Dictionary, inventory: Dictionary) -> bool:
	var probe := ship.duplicate(true); probe.inventory = inventory
	if inventory.get("nuke", 0) > 1 and ship.commercial: return false
	if inventory.get("orbital_base", 0) > 0 and ship.get("type", "") != "transport": return false
	return cargo_mass(probe) <= ship.cargo_capacity

static func transfer(state: Dictionary, from_id: String, to_id: String, item: String, amount: int) -> Dictionary:
	var next := state.duplicate(true); var source := _ship_by_id(next.ships, from_id); var target := _ship_by_id(next.ships, to_id)
	if source.is_empty() or target.is_empty() or amount <= 0 or source.position != target.position or source.velocity != target.velocity: return next
	if source.inventory.get(item, 0) < amount: return next
	var proposed: Dictionary = target.inventory.duplicate(true); proposed[item] = proposed.get(item, 0) + amount
	if not loadout_fits(target, proposed): return next
	source.inventory[item] -= amount; target.inventory = proposed
	next.log.append("Trasferiti %d %s da %s a %s" % [amount, item, source.name, target.name]); return next

static func transfer_fuel(state: Dictionary, from_id: String, to_id: String, amount: int) -> Dictionary:
	var next := state.duplicate(true); var source := _ship_by_id(next.ships, from_id); var target := _ship_by_id(next.ships, to_id)
	if source.is_empty() or target.is_empty() or source.position != target.position or source.velocity != target.velocity: return next
	var actual := mini(amount, mini(source.fuel, target.max_fuel - target.fuel))
	if actual <= 0: return next
	source.fuel -= actual; target.fuel += actual; next.log.append("Soccorso carburante: %d punti" % actual); return next

static func update_detection(state: Dictionary) -> void:
	for observer: Dictionary in state.ships:
		if observer.destroyed: continue
		for target: Dictionary in state.ships:
			if target.owner == observer.owner or target.destroyed: continue
			if HexMathRef.distance(observer.position, target.position) <= 3:
				state.knowledge[observer.owner][target.id] = true
	for body: Dictionary in state.bodies:
		var owner: String = body.get("owner", "")
		if owner == "" or owner == "neutral": continue
		for target: Dictionary in state.ships:
			if target.owner != owner and HexMathRef.distance(body.hex, target.position) <= 5: state.knowledge[owner][target.id] = true
	for ship: Dictionary in state.ships:
		if ship.get("landed_at", "") == "": continue
		var body := _body_by_id(state.bodies, ship.landed_at)
		if body.get("owner", "") == ship.owner:
			for viewer in state.knowledge:
				if viewer != ship.owner: state.knowledge[viewer].erase(ship.id)

static func is_detected(state: Dictionary, viewer: String, ship_id: String) -> bool:
	var ship := _ship_by_id(state.ships, ship_id)
	return ship.owner == viewer or state.knowledge.get(viewer, {}).get(ship_id, false)

static func _ship_by_id(ships: Array, id: String) -> Dictionary:
	for ship: Dictionary in ships:
		if ship.id == id: return ship
	return {}
static func _body_by_id(bodies: Array, id: String) -> Dictionary:
	for body: Dictionary in bodies:
		if body.id == id: return body
	return {}
