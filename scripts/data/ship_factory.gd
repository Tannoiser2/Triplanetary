class_name ShipFactory
extends RefCounted

const RULESET_PATH := "res://data/ruleset_updated_second.json"

static func create(id: String, owner: String, type: String, position: Vector2i, name := "") -> Dictionary:
	var ruleset: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULESET_PATH))
	if not ruleset is Dictionary or not ruleset.get("ships", {}).has(type): return {}
	var spec: Dictionary = ruleset.ships[type]
	var infinite_fuel: bool = spec.get("infinite_fuel", false)
	var max_fuel: int = 0 if infinite_fuel else int(spec.get("fuel", 0))
	return {
		"id":id, "owner":owner, "name":name if name != "" else _display_name(type) + " " + owner,
		"type":type, "position":position, "previous_position":position, "velocity":Vector2i.ZERO,
		"fuel":max_fuel, "fuel_spent":0, "max_fuel":max_fuel, "infinite_fuel":infinite_fuel,
		"combat":int(spec.get("combat", 0)), "commercial":bool(spec.get("defense_only", false)),
		"cargo_capacity":-1 if spec.get("infinite_cargo", false) else int(spec.get("cargo", 0)),
		"inventory":{"mine":0,"torpedo":0,"nuke":0}, "pending_gravity":[],
		"disabled_until_turn":0, "destroyed":false, "overload_available":true,
		"visited_bodies":[], "landed_at":"", "base_side":0, "must_burn_after_takeoff":false,
		"heroic":false, "last_attack_key":"", "last_target_key":"", "launched_key":"",
		"must_change_after_launch":false, "dreadnought":type == "dreadnought"
	}

static func _display_name(type: String) -> String:
	return {"transport":"Trasporto","tanker":"Cisterna","liner":"Liner","corvette":"Corvetta","corsair":"Corsaro","frigate":"Fregata","dreadnought":"Dreadnought","torch":"Torch","orbital_base":"Base orbitale"}.get(type, type.capitalize())
