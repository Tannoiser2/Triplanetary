class_name ThrustSelector
extends Control

signal direction_selected(direction: int)

# Stesso ordine delle sei direzioni assiali del motore, proiettate sulla griglia della scansione.
const DIRECTIONS: Array[Vector2] = [Vector2(0.5, 0.866), Vector2(0.5, -0.866), Vector2(0, -1), Vector2(-0.5, -0.866), Vector2(-0.5, 0.866), Vector2(0, 1)]
const LABELS := ["1", "2", "3", "4", "5", "6"]
const CENTER_RADIUS := 30.0
const STEP := 67.0
const ARROW_LENGTH := 25.0

var enabled := true
var selected_direction := -1

func _ready() -> void:
	custom_minimum_size = Vector2(260, 205)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if not enabled or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var center := size * 0.5
	var best := -1
	var best_distance := INF
	for i in range(6):
		var distance: float = event.position.distance_to(center + DIRECTIONS[i] * STEP)
		if distance < best_distance: best_distance = distance; best = i
	if best_distance <= ARROW_LENGTH:
		selected_direction = best
		direction_selected.emit(best)
		queue_redraw()
		accept_event()

func _draw() -> void:
	var center := size * 0.5
	_draw_hex(center, Color("79cce8"), Color("0a1726"), 2.0)
	draw_circle(center, 6.0, Color("59d6c7"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-18, 20), "NAVE", HORIZONTAL_ALIGNMENT_CENTER, 36, 10, Color("79cce8"))
	for i in range(6):
		var cell: Vector2 = center + DIRECTIONS[i] * STEP
		var active := i == selected_direction
		_draw_arrow(cell, DIRECTIONS[i], Color("f4b52f") if active else Color("39b7c7"), Color("5b4514") if active else Color("10283a"), 2.5 if active else 1.5)
		draw_string(ThemeDB.fallback_font, cell + Vector2(-7, 5), LABELS[i], HORIZONTAL_ALIGNMENT_CENTER, 14, 13, Color.WHITE if enabled else Color("70808c"))

func _draw_hex(center: Vector2, border: Color, fill: Color, width: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(CENTER_RADIUS, 0), center + Vector2(CENTER_RADIUS * 0.5, CENTER_RADIUS * 0.866),
		center + Vector2(-CENTER_RADIUS * 0.5, CENTER_RADIUS * 0.866), center + Vector2(-CENTER_RADIUS, 0),
		center + Vector2(-CENTER_RADIUS * 0.5, -CENTER_RADIUS * 0.866), center + Vector2(CENTER_RADIUS * 0.5, -CENTER_RADIUS * 0.866)
	])
	draw_colored_polygon(points, fill)
	points.append(points[0]); draw_polyline(points, border, width, true)

func _draw_arrow(center: Vector2, direction: Vector2, border: Color, fill: Color, width: float) -> void:
	var angle := direction.angle()
	var local := [Vector2(25, 0), Vector2(7, -14), Vector2(7, -6), Vector2(-20, -6), Vector2(-20, 6), Vector2(7, 6), Vector2(7, 14)]
	var points := PackedVector2Array()
	for point: Vector2 in local: points.append(center + point.rotated(angle))
	draw_colored_polygon(points, fill)
	points.append(points[0]); draw_polyline(points, border, width, true)
