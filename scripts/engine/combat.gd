class_name CombatRules
extends RefCounted

const TABLE := [
	["-", "-", "-", "-", "D2", "D3"],
	["-", "-", "-", "D2", "D3", "D4"],
	["-", "-", "D2", "D3", "D4", "D5"],
	["-", "D2", "D3", "D4", "D5", "E"],
	["D2", "D3", "D4", "D5", "E", "E"]
]

static func odds_column(attacker: int, defender: int) -> int:
	if attacker * 2 < defender: return -1
	if attacker < defender: return 0
	if attacker < defender * 2: return 1
	if attacker < defender * 3: return 2
	if attacker < defender * 4: return 3
	return 4

static func gun_damage(attacker: int, defender: int, die: int, range_hexes: int, relative_velocity: int, heroic := false) -> String:
	var column := odds_column(attacker, defender)
	if column < 0: return "-"
	var modified := clampi(die - range_hexes - maxi(0, relative_velocity - 2) + (1 if heroic else 0), 1, 6)
	return TABLE[column][modified - 1]
