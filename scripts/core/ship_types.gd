class_name ShipTypes
extends RefCounted
## Tabella 1 del manuale (Updated Second Edition).

const TYPES := {
	"dreadnought": {"name": "Dreadnought", "combat": 15, "fuel": 15, "cargo": 50, "commercial": false, "cost": 600},
	"transport":   {"name": "Trasporto",   "combat": 1,  "fuel": 10, "cargo": 50, "commercial": true,  "cost": 10},
	"tanker":      {"name": "Cisterna",    "combat": 1,  "fuel": 50, "cargo": 0,  "commercial": true,  "cost": 10},
	"liner":       {"name": "Nave di linea", "combat": 2, "fuel": 10, "cargo": 50, "commercial": true, "cost": 50},
	"packet":      {"name": "Packet",      "combat": 1,  "fuel": 10, "cargo": 50, "commercial": false, "cost": 20},
	"corvette":    {"name": "Corvetta",    "combat": 2,  "fuel": 20, "cargo": 5,  "commercial": false, "cost": 40},
	"corsair":     {"name": "Corsaro",     "combat": 4,  "fuel": 20, "cargo": 10, "commercial": false, "cost": 80},
	"frigate":     {"name": "Fregata",     "combat": 8,  "fuel": 20, "cargo": 40, "commercial": false, "cost": 150},
	"torch":       {"name": "Torcia",      "combat": 8,  "fuel": -1, "cargo": 10, "commercial": false, "cost": 400},
}

const ORDNANCE_MASS := {"mine": 10, "torpedo": 20, "nuke": 20}
const ORDNANCE_NAME := {"mine": "Mina", "torpedo": "Siluro", "nuke": "Testata nucleare"}

static func strength_label(type: String) -> String:
	var t: Dictionary = TYPES[type]
	return "%d%s" % [t.combat, "D" if t.commercial else ""]

static func make(id: String, owner: String, type: String, display_name := "") -> Dictionary:
	var t: Dictionary = TYPES[type]
	var infinite: bool = int(t.fuel) < 0
	return {
		"id": id, "owner": owner, "type": type,
		"name": display_name if display_name != "" else t.name,
		"pos": Vector2i.ZERO, "vel": Vector2i.ZERO, "grav": [],
		"fuel": 0 if infinite else int(t.fuel), "max_fuel": 0 if infinite else int(t.fuel),
		"infinite_fuel": infinite, "fuel_spent": 0,
		"combat": int(t.combat), "commercial": bool(t.commercial), "cargo": int(t.cargo),
		"inv": {"mine": 0, "torpedo": 0, "nuke": 0},
		"landed": "", "side": -1,
		"disabled_until": 0, "destroyed": false, "reason": "", "escaped": false, "captured": false,
		"heroic": false, "overload_ok": true, "surrendered": false,
		"visited": [], "history": [], "last_path": [],
		"attacked_tick": -1, "targeted_tick": -1, "launched_seg": -1, "fired_seg": -1, "resupplied_seg": -1,
		"must_change_course": false, "first_burn_pending": false, "locked": false,
		"access_special": false, "concealed": false,
	}

static func cargo_used(ship: Dictionary) -> int:
	var total := 0
	for k in ship.inv: total += int(ship.inv[k]) * int(ORDNANCE_MASS.get(k, 0))
	if ship.get("passengers", false): total += 0
	return total

static func can_carry(ship: Dictionary, kind: String) -> bool:
	if kind == "torpedo" and ship.commercial: return false
	if kind == "nuke" and ship.commercial and int(ship.inv.nuke) >= 1: return false
	return cargo_used(ship) + int(ORDNANCE_MASS[kind]) <= int(ship.cargo)
