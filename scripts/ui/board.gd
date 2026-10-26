class_name TriplanetaryBoard
extends Control

signal hex_clicked(hex: Vector2i)

var state: Dictionary
var selected_ship := "p1"
const MAP_SIZE := Vector2(2048, 1447)
const HEX_X := 36.0
const HEX_Y := 41.0
const ORIGIN := Vector2(25, 25)
const PLAYER_COLORS := [Color("59d6c7"), Color("ff6f76"), Color("f4c95d"), Color("9b8cff"), Color("ff9f43"), Color("74b9ff")]
var map_texture: Texture2D
var camera_zoom := 1.0
var camera_offset := Vector2.ZERO
var dragging := false
var drag_last := Vector2.ZERO
var drag_origin := Vector2.ZERO
var drag_distance := 0.0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://assets/local-reference/map-source.jpg"):
		map_texture = load("res://assets/local-reference/map-source.jpg")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_zoom_at(event.position, 1.18 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.18)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				dragging = true; drag_last = event.position; drag_origin = event.position; drag_distance = 0.0
			else:
				if dragging and event.button_index == MOUSE_BUTTON_LEFT and drag_distance < 5.0: hex_clicked.emit(_nearest_hex(event.position))
				dragging = false
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		drag_distance += event.position.distance_to(drag_last)
		camera_offset += event.position - drag_last
		drag_last = event.position
		_clamp_camera()
		queue_redraw()
		accept_event()

func _nearest_hex(screen_position: Vector2) -> Vector2i:
	var map_position := (screen_position - _view_origin()) / _effective_scale()
	var best := Vector2i.ZERO
	var best_distance := INF
	for column in range(56):
		for row in range(35):
			var candidate := _offset_to_axial(column, row)
			var distance := axial_to_pixel(candidate).distance_squared_to(map_position)
			if distance < best_distance: best_distance = distance; best = candidate
	return best

func _zoom_at(mouse_position: Vector2, factor: float) -> void:
	var old_scale := _effective_scale()
	var old_origin := _view_origin()
	var map_point := (mouse_position - old_origin) / old_scale
	camera_zoom = clampf(camera_zoom * factor, 0.75, 4.0)
	var new_base_origin := (size - MAP_SIZE * _effective_scale()) * 0.5
	camera_offset = mouse_position - new_base_origin - map_point * _effective_scale()
	_clamp_camera()
	queue_redraw()

func _base_scale() -> float:
	return minf(size.x / MAP_SIZE.x, size.y / MAP_SIZE.y)

func _effective_scale() -> float:
	return _base_scale() * camera_zoom

func _view_origin() -> Vector2:
	return (size - MAP_SIZE * _effective_scale()) * 0.5 + camera_offset

func _clamp_camera() -> void:
	var scaled := MAP_SIZE * _effective_scale()
	var limit_x := maxf(0.0, (scaled.x - size.x) * 0.5 + size.x * 0.35)
	var limit_y := maxf(0.0, (scaled.y - size.y) * 0.5 + size.y * 0.35)
	camera_offset.x = clampf(camera_offset.x, -limit_x, limit_x)
	camera_offset.y = clampf(camera_offset.y, -limit_y, limit_y)

func axial_to_pixel(hex: Vector2i) -> Vector2:
	var column := hex.x
	var row := hex.y + (column - (column & 1)) / 2
	return ORIGIN + Vector2(HEX_X * column, HEX_Y * row + (HEX_Y * 0.5 if column & 1 else 0.0))

func _draw() -> void:
	var scale_factor := _effective_scale()
	var origin := _view_origin()
	draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("071326"))
	if map_texture:
		# La sorgente è portrait: trasformazione 90° oraria, senza generare un derivato.
		draw_set_transform(origin + Vector2(MAP_SIZE.x * scale_factor, 0), PI / 2.0, Vector2.ONE * scale_factor)
		draw_texture(map_texture, Vector2.ZERO)
		draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)
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
		if ship.get("escaped", false) or ship.get("captured", false): continue
		var known: bool = ship.owner == state.segment or state.get("knowledge", {}).get(state.segment, {}).get(ship.id, false)
		if ship.owner != state.segment and not known and not ship.get("concealed", false): continue
		var p := axial_to_pixel(ship.position) + Vector2(-5 if ship.owner == "P1" else 5, 0)
		var color: Color = PLAYER_COLORS[clampi(int(ship.owner.trim_prefix("P")) - 1, 0, PLAYER_COLORS.size() - 1)]
		if ship.get("concealed", false) and not known:
			_draw_marker_hex(p, 8.0, Color("c7d2dc"), 2.0)
			continue
		var trail: Array = ship.get("trail", [])
		if trail.size() > 1:
			for i in range(1, trail.size()):
				_draw_route_arc(axial_to_pixel(trail[i - 1]), axial_to_pixel(trail[i]), Color(color, 0.9))
				draw_circle(axial_to_pixel(trail[i]), 2.5, color)
		draw_circle(p, 7, color)
		if ship.id == selected_ship: draw_arc(p, 10, 0, TAU, 24, Color.WHITE, 2)
		if ship.id == selected_ship and state.phase == "astrogation":
			var command: Dictionary = state.get("commands", {}).get(ship.id, {})
			var vector_velocity: Vector2i = ship.velocity
			for gravity: Vector2i in ship.get("pending_gravity", []): vector_velocity += gravity
			var vector_end := axial_to_pixel(ship.position + vector_velocity)
			draw_dashed_line(p, vector_end, Color("8bd8f7"), 2.0, 12.0)
			var thrust_total := Vector2i.ZERO
			for thrust: Vector2i in command.get("thrust_steps", []): thrust_total += thrust
			if thrust_total != Vector2i.ZERO:
				var thrust_end := axial_to_pixel(ship.position + vector_velocity + thrust_total)
				draw_dashed_line(vector_end, thrust_end, Color("f4c95d"), 1.25, 5.0)
				_draw_marker_hex(thrust_end, 11.0, Color("f4c95d"), 2.0)
			else:
				draw_circle(vector_end, 7, Color("8bd8f780"), false, 1.5)
	for item: Dictionary in state.get("ordnance", []):
		var p := axial_to_pixel(item.position)
		var label := "M" if item.kind == "mine" else ("T" if item.kind == "torpedo" else "N")
		draw_circle(p, 6, Color("d74848") if item.kind == "nuke" else Color("2d2d2d"))
		draw_string(ThemeDB.fallback_font, p + Vector2(8, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("2d2d2d"))
	for dummy: Dictionary in state.get("dummies", []):
		if not dummy.get("active", true): continue
		var p := axial_to_pixel(dummy.position)
		var color := (Color("ff6f76") if dummy.owner == "P1" else Color("dceaf3")) if dummy.owner == state.segment else Color("c7d2dc")
		draw_circle(p, 7, Color("071326"))
		draw_arc(p, 7, 0, TAU, 6, color, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(12, 12, 330, 54), Color("07111fd9"), true)
	draw_string(ThemeDB.fallback_font, Vector2(24, 34), "Rotella: zoom   Trascina: scorri", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("d8e7f4"))
	draw_string(ThemeDB.fallback_font, Vector2(24, 55), "Vettore: azzurro   Spinta: giallo   Rotta: continua", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("9db2c6"))

func _draw_route_arc(from: Vector2, to: Vector2, color: Color) -> void:
	if from == to: return
	var delta := to - from
	var perpendicular := Vector2(-delta.y, delta.x).normalized()
	var control := (from + to) * 0.5 + perpendicular * clampf(delta.length() * 0.14, 9.0, 34.0)
	var points := PackedVector2Array()
	for i in range(17):
		var t := float(i) / 16.0
		points.append((1.0 - t) * (1.0 - t) * from + 2.0 * (1.0 - t) * t * control + t * t * to)
	draw_polyline(points, color, 5.0, true)

func _draw_marker_hex(center: Vector2, radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(6): points.append(center + Vector2.from_angle(deg_to_rad(60.0 * i)) * radius)
	points.append(points[0])
	draw_polyline(points, color, width, true)

func _offset_to_axial(column: int, row: int) -> Vector2i:
	return Vector2i(column, row - (column - (column & 1)) / 2)

func _draw_hex(hex: Vector2i, color: Color) -> void:
	var center := axial_to_pixel(hex)
	var points := PackedVector2Array()
	for i in range(6):
		points.append(center + Vector2.from_angle(deg_to_rad(60.0 * i)) * 24.0)
	points.append(points[0])
	draw_polyline(points, color, 1)

