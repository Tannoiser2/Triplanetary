class_name TriplanetaryBoard
extends Control

var state: Dictionary
var selected_ship := "p1"
const MAP_SIZE := Vector2(2048, 1447)
const HEX_X := 36.0
const HEX_Y := 41.0
const ORIGIN := Vector2(25, 25)
const PLAYER_COLORS := [Color("59d6c7"), Color("ff6f76"), Color("f4c95d"), Color("9b8cff"), Color("ff9f43"), Color("74b9ff")]
var map_texture: Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/local-reference/map-source.jpg"):
		map_texture = load("res://assets/local-reference/map-source.jpg")

func axial_to_pixel(hex: Vector2i) -> Vector2:
	var column := hex.x
	var row := hex.y + (column - (column & 1)) / 2
	return ORIGIN + Vector2(HEX_X * column, HEX_Y * row + (HEX_Y * 0.5 if column & 1 else 0.0))

func _draw() -> void:
	var scale_factor: float = minf(size.x / MAP_SIZE.x, size.y / MAP_SIZE.y)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("071326"))
	if map_texture:
		# La sorgente è portrait: trasformazione 90° oraria, senza generare un derivato.
		draw_set_transform(Vector2(MAP_SIZE.x * scale_factor, 0), PI / 2.0, Vector2.ONE * scale_factor)
		draw_texture(map_texture, Vector2.ZERO)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	else:
		for column in range(56):
			for row in range(35): _draw_hex(_offset_to_axial(column, row), Color("25415d"))
		for hex: Vector2i in state.get("asteroids", []):
			draw_circle(axial_to_pixel(hex), 7, Color("ad7b4d"))
		for hex: Vector2i in state.get("special_asteroids", []):
			draw_circle(axial_to_pixel(hex), 8, Color("6f9fc5"))
	for field: Dictionary in state.gravity:
		var p := axial_to_pixel(field.hex)
		var target := axial_to_pixel(field.hex + field.acceleration)
		draw_line(p, p.lerp(target, 0.42), Color("6f8796") if field.weak else Color("d6a947"), 2)
	for body: Dictionary in state.bodies:
		var p := axial_to_pixel(body.hex)
		draw_circle(p, 13 if body.id == "sol" else 9, Color("f6b94c") if body.id == "sol" else Color("dceaf3"))
		draw_string(ThemeDB.fallback_font, p + Vector2(13, -11), body.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d8e7f4"))
	for ship: Dictionary in state.ships:
		if ship.owner != state.segment and not state.get("knowledge", {}).get(state.segment, {}).get(ship.id, false): continue
		var p := axial_to_pixel(ship.position) + Vector2(-5 if ship.owner == "P1" else 5, 0)
		var color: Color = PLAYER_COLORS[clampi(int(ship.owner.trim_prefix("P")) - 1, 0, PLAYER_COLORS.size() - 1)]
		var trail: Array = ship.get("trail", [])
		if trail.size() > 1:
			for i in range(1, trail.size()):
				draw_line(axial_to_pixel(trail[i - 1]), axial_to_pixel(trail[i]), Color(color, 0.72), 3)
				draw_circle(axial_to_pixel(trail[i]), 2.5, color)
		draw_circle(p, 7, color)
		if ship.id == selected_ship: draw_arc(p, 10, 0, TAU, 24, Color.WHITE, 2)
		draw_line(p, axial_to_pixel(ship.position + ship.velocity), color, 2)
		if ship.id == selected_ship and state.phase == "astrogation":
			var command: Dictionary = state.get("commands", {}).get(ship.id, {})
			var projected_velocity: Vector2i = ship.velocity
			for gravity: Vector2i in ship.get("pending_gravity", []): projected_velocity += gravity
			for thrust: Vector2i in command.get("thrust_steps", []): projected_velocity += thrust
			var projected := axial_to_pixel(ship.position + projected_velocity)
			draw_dashed_line(p, projected, Color("ffffff"), 3, 10)
			draw_circle(projected, 9, Color("ffffff80"), false, 2)
	for item: Dictionary in state.get("ordnance", []):
		var p := axial_to_pixel(item.position)
		var label := "M" if item.kind == "mine" else ("T" if item.kind == "torpedo" else "N")
		draw_circle(p, 6, Color("d74848") if item.kind == "nuke" else Color("2d2d2d"))
		draw_string(ThemeDB.fallback_font, p + Vector2(8, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("2d2d2d"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _offset_to_axial(column: int, row: int) -> Vector2i:
	return Vector2i(column, row - (column - (column & 1)) / 2)

func _draw_hex(hex: Vector2i, color: Color) -> void:
	var center := axial_to_pixel(hex)
	var points := PackedVector2Array()
	for i in range(6):
		points.append(center + Vector2.from_angle(deg_to_rad(60.0 * i)) * 24.0)
	points.append(points[0])
	draw_polyline(points, color, 1)

