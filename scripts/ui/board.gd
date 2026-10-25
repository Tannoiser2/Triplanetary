class_name TriplanetaryBoard
extends Control

var state: Dictionary
var selected_ship := "p1"
const MAP_SIZE := Vector2(2048, 1447)
const HEX_X := 36.0
const HEX_Y := 41.0
const ORIGIN := Vector2(25, 25)
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
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("f5f3ec"))
	if map_texture:
		# La sorgente è portrait: trasformazione 90° oraria, senza generare un derivato.
		draw_set_transform(Vector2(MAP_SIZE.x * scale_factor, 0), PI / 2.0, Vector2.ONE * scale_factor)
		draw_texture(map_texture, Vector2.ZERO)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	else:
		for column in range(56):
			for row in range(35): _draw_hex(_offset_to_axial(column, row), Color("b9b7ad"))
	for field: Dictionary in state.gravity:
		var p := axial_to_pixel(field.hex)
		var target := axial_to_pixel(field.hex + field.acceleration)
		draw_line(p, p.lerp(target, 0.42), Color("6f8796") if field.weak else Color("d6a947"), 2)
	for body: Dictionary in state.bodies:
		var p := axial_to_pixel(body.hex)
		draw_circle(p, 13 if body.id == "sol" else 9, Color("f6b94c") if body.id == "sol" else Color("dceaf3"))
		draw_string(ThemeDB.fallback_font, p + Vector2(13, -11), body.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a9bfd0"))
	for ship: Dictionary in state.ships:
		var p := axial_to_pixel(ship.position) + Vector2(-5 if ship.owner == "P1" else 5, 0)
		var color := Color("55d6be") if ship.owner == "P1" else Color("ff6b6b")
		draw_circle(p, 7, color)
		if ship.id == selected_ship: draw_arc(p, 10, 0, TAU, 24, Color.WHITE, 2)
		draw_line(p, axial_to_pixel(ship.position + ship.velocity), color, 2)
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

