class_name ThrustSelector
extends Control

signal direction_selected(direction: int)

# Stesso ordine delle sei direzioni assiali del motore, proiettate sulla griglia della scansione.
const DIRECTIONS: Array[Vector2] = [Vector2(0.5, 0.866), Vector2(0.5, -0.866), Vector2(0, -1), Vector2(-0.5, -0.866), Vector2(-0.5, 0.866), Vector2(0, 1)]
const LABELS := ["1", "2", "3", "4", "5", "6"]
const RADIUS := 27.0
const STEP := 49.0

var enabled := true
var selected_direction := -1

func _ready() -> void:
	custom_minimum_size = Vector2(235, 155)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if not enabled or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var center := size * 0.5
	var best := -1
	var best_distance := INF
	for i in range(6):
		var distance: float = event.position.distance_to(center + DIRECTIONS[i] * STEP)
		if distance < best_distance: best_distance = distance; best = i
	if best_distance <= RADIUS:
		selected_direction = best
		direction_selected.emit(best)
		queue_redraw()
		accept_event()

func _draw() -> void:
	var center := size * 0.5
	_draw_hex(center, Color("27435e"), Color("0a1726"), 2.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-8, 5), "N", HORIZONTAL_ALIGNMENT_CENTER, 16, 13, Color("79cce8"))
	for i in range(6):
		var cell: Vector2 = center + DIRECTIONS[i] * STEP
		var active := i == selected_direction
		_draw_hex(cell, Color("f4b52f") if active else Color("39b7c7"), Color("433616") if active else Color("10283a"), 2.5 if active else 1.5)
		draw_string(ThemeDB.fallback_font, cell + Vector2(-8, 6), LABELS[i], HORIZONTAL_ALIGNMENT_CENTER, 16, 16, Color.WHITE if enabled else Color("70808c"))

func _draw_hex(center: Vector2, border: Color, fill: Color, width: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(RADIUS, 0), center + Vector2(RADIUS * 0.5, RADIUS * 0.866),
		center + Vector2(-RADIUS * 0.5, RADIUS * 0.866), center + Vector2(-RADIUS, 0),
		center + Vector2(-RADIUS * 0.5, -RADIUS * 0.866), center + Vector2(RADIUS * 0.5, -RADIUS * 0.866)
	])
	draw_colored_polygon(points, fill)
	points.append(points[0]); draw_polyline(points, border, width, true)
