class_name Board
extends Control
## Plancia: rendering procedurale del Sistema Solare interno e input del mouse.
## Il controller (main.gd) le passa lo stato e un dizionario `overlay` con ciò che va
## evidenziato; la plancia non decide nulla di regolamentare.

signal hex_clicked(hex: Vector2i, button: int)
signal hex_hovered(hex: Vector2i)
## Richieste di inquadratura, inoltrate anche al tavolo 3D.
signal focus_requested(hex: Vector2i, min_zoom: float)
signal fit_requested
signal zoom_requested(factor: float)

## Con il tavolo 3D attivo la plancia 2D non disegna e non riceve input (resta la fonte dei dati).
var hide_for_3d := false:
	set(v):
		hide_for_3d = v
		mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP
		queue_redraw()

var state: Dictionary = {}
var viewer := ""              # giocatore dal cui punto di vista si mostra l'informazione nascosta
var selected := ""
var overlay: Dictionary = {}
var show_detection := false
var show_numbers := true
var show_trails := true           # rotte percorse
var show_drift := false           # vettori di deriva (inerzia + gravità, senza spinte)
var safe_rect := Rect2()          # area dello schermo non coperta dall'interfaccia

var zoom := 22.0
var offset := Vector2.ZERO
var hover := Vector2i(9999, 9999)

var anim_t := 1.0
var anim_moves: Dictionary = {}   # id -> {from: Vector2, to: Vector2}
var fx_list: Array = []           # {kind, world, t0}

var _map: Dictionary
var _grid_lines := PackedVector2Array()
var _map_rect := Rect2()
var _rocks := {}
var _stars: Array
var _dragging := false
var _press_pos := Vector2.ZERO
var _press_offset := Vector2.ZERO
var _moved := false
var _fitted := false
var _time := 0.0
var nose_on_course := true       # le navi puntano lungo la rotta; la fiamma esce dal lato della spinta
var replay: Dictionary = {}       # replay di fine partita (Replay.build); vuoto = gioco normale
var replay_u := 0.0               # tempo del replay, in turni
var _body_from := {}              # pianeti in moto: id -> posizione di partenza dell'animazione
var _body_t := 1.0
var _has_puffs := false

const HEX_CORNERS := [Vector2(1, 0), Vector2(0.5, 0.8660254), Vector2(-0.5, 0.8660254), Vector2(-1, 0), Vector2(-0.5, -0.8660254), Vector2(0.5, -0.8660254)]

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Art.board_fonts()
	_stars = Art.stars()
	resized.connect(func(): if not _fitted: fit())

func set_state(st: Dictionary) -> void:
	var first = state.is_empty() or _map.is_empty() or st.options.get("sol_classic", false) != state.get("options", {}).get("sol_classic", false) or st.has("planets") != state.has("planets")
	state = st
	if first: _build_static()
	queue_redraw()

func _build_static() -> void:
	_map = Rules.map_of(state)
	_grid_lines = PackedVector2Array()
	var edges := {}
	var minp := Vector2(INF, INF); var maxp := Vector2(-INF, -INF)
	for h in _map.cells:
		var c := world(h)
		minp = minp.min(c); maxp = maxp.max(c)
		for i in range(6):
			var a: Vector2 = c + HEX_CORNERS[i]
			var b: Vector2 = c + HEX_CORNERS[(i + 1) % 6]
			var key := "%d,%d,%d,%d" % [roundi(minf(a.x, b.x) * 100), roundi(minf(a.y, b.y) * 100), roundi(maxf(a.x, b.x) * 100), roundi(maxf(a.y, b.y) * 100)]
			if edges.has(key): continue
			edges[key] = true
			_grid_lines.append(a); _grid_lines.append(b)
	_map_rect = Rect2(minp - Vector2(1.2, 1.2), maxp - minp + Vector2(2.4, 2.4))
	_rocks = {}
	var rng := RandomNumberGenerator.new()
	for h in _map.asteroids + _map.special_asteroids:
		rng.seed = hash(h)
		var list := []
		for i in range(7):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 0.62
			list.append([Vector2(cos(a), sin(a)) * r, 0.06 + rng.randf() * 0.11, rng.randf()])
		_rocks[h] = list

# ---------------------------------------------------------------- coordinate

## Vista orizzontale: la mappa sorgente (verticale) è ruotata di 90° in senso orario,
## così Sol sta a sinistra e Giove a destra come sulla plancia originale.
static func world(h: Vector2i) -> Vector2:
	var p := Hex.to_point(h)
	return Vector2(-p.y, p.x)

static func world_to_hex(w: Vector2) -> Vector2i:
	return Hex.from_point(Vector2(w.y, -w.x))

func to_screen(w: Vector2) -> Vector2:
	return w * zoom + offset

func to_world(s: Vector2) -> Vector2:
	return (s - offset) / zoom

func hex_at(screen_pos: Vector2) -> Vector2i:
	return world_to_hex(to_world(screen_pos))

func _safe() -> Rect2:
	return safe_rect if safe_rect.size.x > 50 else Rect2(Vector2.ZERO, size)

func fit() -> void:
	fit_requested.emit()
	if _map_rect.size == Vector2.ZERO or size.x < 10: return
	var r := _safe()
	zoom = minf(r.size.x / _map_rect.size.x, r.size.y / _map_rect.size.y)
	offset = r.get_center() - _map_rect.get_center() * zoom
	_fitted = true
	queue_redraw()

func center_on(h: Vector2i, min_zoom := 0.0) -> void:
	focus_requested.emit(h, min_zoom)
	if min_zoom > 0.0: zoom = maxf(zoom, min_zoom)
	offset = _safe().get_center() - world(h) * zoom
	queue_redraw()

func zoom_by(factor: float, at: Vector2) -> void:
	if hide_for_3d:
		zoom_requested.emit(factor)
		return
	var before := to_world(at)
	var min_z := minf(size.x / _map_rect.size.x, size.y / _map_rect.size.y) * 0.8 if _map_rect.size.x > 0 else 5.0
	zoom = clampf(zoom * factor, min_z, 120.0)
	offset = at - before * zoom
	_fitted = true
	queue_redraw()

# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed: zoom_by(1.12, mb.position); accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed: zoom_by(1.0 / 1.12, mb.position); accept_event()
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_dragging = true; _moved = false
				_press_pos = mb.position; _press_offset = offset
			else:
				_dragging = false
				if not _moved and mb.button_index != MOUSE_BUTTON_MIDDLE:
					hex_clicked.emit(hex_at(mb.position), mb.button_index)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			if mm.position.distance_to(_press_pos) > 6.0: _moved = true
			if _moved:
				offset = _press_offset + (mm.position - _press_pos)
				_fitted = true
				queue_redraw()
		var h := hex_at(mm.position)
		if h != hover:
			hover = h
			hex_hovered.emit(h)
			queue_redraw()
	elif event is InputEventMagnifyGesture:
		zoom_by((event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)
	elif event is InputEventPanGesture:
		offset -= (event as InputEventPanGesture).delta * 12.0
		queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	var busy = anim_t < 1.0 or not fx_list.is_empty() or overlay.get("pulse", false)
	if not fx_list.is_empty():
		fx_list = fx_list.filter(func(f): return _time - float(f.t0) < 1.6)
	if _body_t < 1.0:
		_body_t = minf(1.0, _body_t + delta / 1.4)
		busy = true
	if not replay.is_empty() or (_has_puffs and not show_trails and not show_drift): busy = true
	if busy or selected != "": queue_redraw()

func add_fx(kind: String, hex: Vector2i, delay := 0.0) -> void:
	fx_list.append({"kind": kind, "world": world(hex), "t0": _time + delay})

# ---------------------------------------------------------------- disegno

func _draw() -> void:
	if state.is_empty() or _map.is_empty() or hide_for_3d: return
	# con i pianeti in moto la mappa cambia a fine turno: si aggiorna senza ricostruire il reticolo
	var m := Rules.map_of(state)
	if not replay.is_empty() and state.has("planets0"):
		var ps := {"planets": state.planets0, "planet_clock": 0, "xvariant": state.get("xvariant", "xmap"), "options": state.options}
		m = SolarMap.get_xmap(Planets.future(ps, maxi(0, floori(replay_u) - 1)), Planets.variant(state))
	if not is_same(m, _map):
		if m.get("xmap", false) != _map.get("xmap", false) or m.cells.size() != _map.cells.size(): _build_static()
		else:
			# i pianeti hanno fatto un passo: si fanno scivolare dalla vecchia alla nuova posizione
			_body_from = {}
			for b in m.bodies:
				var old := SolarMap.body(_map, b.id)
				if not old.is_empty() and old.hex != b.hex: _body_from[b.id] = world(old.hex)
			if not _body_from.is_empty(): _body_t = 0.0
			_map = m
	_draw_sky()
	draw_set_transform(offset, 0.0, Vector2(zoom, zoom))
	_draw_map_frame()
	if _map.get("xmap", false): _draw_orbits()
	if not replay.is_empty():
		_draw_gravity()
		_draw_asteroids()
		_draw_bodies()
		_draw_replay()
		_draw_fx()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if show_detection: _draw_detection()
	_draw_gravity()
	_draw_choices(true)
	_draw_asteroids()
	_draw_bodies()
	_draw_bases()
	_draw_prospecting()
	_draw_overlay_hexes()
	if show_trails: _draw_histories()
	_draw_ordnance()
	if show_drift: _draw_drift()
	_draw_predictions()
	_draw_choices(false)
	_draw_ships()
	_draw_fx()
	_draw_hover()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_sky() -> void:
	var tex := Art.sky()
	var rect := Rect2(Vector2.ZERO, size)
	draw_texture_rect(tex, rect, false)
	# stelle con lieve parallasse
	var par := offset * 0.04
	for st in _stars:
		var p: Vector2 = st[0]
		var pos := Vector2(fposmod(p.x * size.x + par.x, size.x), fposmod(p.y * size.y + par.y, size.y))
		var b: float = st[1]
		var tw := 0.75 + 0.25 * sin(_time * 1.3 + float(st[2]) * 20.0) if b > 0.5 else 1.0
		var c := Color(0.85, 0.9, 1.0, (0.25 + 0.75 * b) * tw)
		var r := 0.6 + b * 1.1
		draw_rect(Rect2(pos - Vector2(r, r) * 0.5, Vector2(r, r)), c)

func _draw_map_frame() -> void:
	# velo che delimita l'area giocabile
	draw_rect(_map_rect, Color(0.02, 0.05, 0.12, 0.35))
	var w := 1.0 / zoom
	var a := clampf((zoom - 6.0) / 14.0, 0.25, 1.0)
	draw_multiline(_grid_lines, Color(0.45, 0.62, 0.95, 0.13 * a + 0.04), w)
	draw_rect(_map_rect, Color(0.3, 0.5, 0.9, 0.35), false, 2.0 / zoom)
	# bordo di Giove: lato da cui si "esce oltre Giove" in Escape
	if state.scenario == "escape":
		var x := _map_rect.end.x
		draw_line(Vector2(x, _map_rect.position.y), Vector2(x, _map_rect.end.y), Color(UITheme.PHOSPHOR, 0.7), 4.0 / zoom)

func _hex_poly(c: Vector2, r := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in HEX_CORNERS: pts.append(c + k * r)
	return pts

func _draw_detection() -> void:
	for b in state.bases:
		if not b.active or b.owner == "all": continue
		var body := SolarMap.body(_map, b.body)
		var col := UITheme.player_color(state, b.owner)
		draw_circle(world(body.hex), 5.0 * Hex.SQRT3, Color(col, 0.05))
		draw_arc(world(body.hex), 5.0 * Hex.SQRT3, 0, TAU, 64, Color(col, 0.35), 1.5 / zoom)

## Mappa ampliata: le orbite dei corpi in moto, con la posizione dei prossimi turni.
func _draw_orbits() -> void:
	var paths := Planets.orbit_paths(state)
	for id in paths:
		var b := SolarMap.body(_map, id)
		if b.is_empty(): continue
		var sol := world(SolarMap.body(_map, "sol").hex)
		var rad := float(Planets.orbit_def(id).radius) * Hex.SQRT3
		draw_arc(sol, rad, 0, TAU, 256, Color(b.color, 0.2), 1.6 / zoom, true)
		# freccia del verso del moto e prossimo esagono
		var p: Array = paths[id]
		var i := int(state.planets.get(id, 0))
		var nxt: Vector2i = p[(i + 1) % p.size()]
		var a := world(b.hex); var c := world(nxt)
		_arrow_head(c, (c - a).normalized(), Color(b.color, 0.55), 0.3)

func _draw_gravity() -> void:
	for h in _map.gravity:
		var list: Array = _map.gravity[h]
		var body := SolarMap.body(_map, list[0].body)
		# durante il passo d'orbita le frecce scivolano insieme al loro corpo
		var c := world(h) + _body_shift(list[0].body)
		var tint: Color = body.color
		draw_colored_polygon(_hex_poly(c, 0.97), Color(tint, 0.09))
		var n := list.size()
		for i in range(n):
			var g: Dictionary = list[i]
			c = world(h) + _body_shift(g.body)
			var dir := world(g.acc).normalized()
			var side := Vector2(-dir.y, dir.x)
			var shift := side * (float(i) - float(n - 1) * 0.5) * 0.38
			var len := 0.7 if n == 1 else 0.52
			_draw_arrow(c + shift - dir * len * 0.5, dir, len, g.weak, n, tint)

func _draw_arrow(start: Vector2, dir: Vector2, len: float, hollow: bool, n: int, tint := Color.WHITE) -> void:
	var side := Vector2(-dir.y, dir.x)
	var w := 0.11 if n == 1 else 0.08
	var hw := 0.26 if n == 1 else 0.2
	var hl := 0.28 if n == 1 else 0.22
	var tip := start + dir * len
	var neck := tip - dir * hl
	var pts := PackedVector2Array([start + side * w, neck + side * w, neck + side * hw, tip, neck - side * hw, neck - side * w, start - side * w])
	var col := Color(0.86, 0.92, 1.0).lerp(tint, 0.35)
	col.a = 0.8
	if hollow:
		var closed := pts.duplicate(); closed.append(pts[0])
		draw_polyline(closed, col, 1.6 / zoom, true)
	else:
		draw_colored_polygon(pts, col)

func _draw_asteroids() -> void:
	for h in _rocks:
		var special: bool = state.special.has(h)
		if not special and not state.asteroids.has(h): continue
		var c := world(h)
		if special:
			draw_colored_polygon(_hex_poly(c, 0.97), Color(0.35, 0.55, 1.0, 0.13))
		for r in _rocks[h]:
			var p: Vector2 = c + r[0]
			var rad: float = r[1]
			var base := Color("8a7a66") if not special else Color("7f9fd8")
			var shade := base.lerp(Color("4a3f35") if not special else Color("33508a"), float(r[2]))
			draw_circle(p, rad, shade)
			draw_circle(p - Vector2(rad, rad) * 0.3, rad * 0.45, Color(base.lightened(0.35), 0.6))

## Spostamento residuo di un corpo che sta scivolando verso il nuovo esagono (zero se è fermo).
func _body_shift(id: String) -> Vector2:
	if _body_t >= 1.0 or not _body_from.has(id): return Vector2.ZERO
	var b := SolarMap.body(_map, id)
	if b.is_empty(): return Vector2.ZERO
	return _body_pos(b) - world(b.hex)

## Navi a terra o nell'anello di gravità di un corpo in movimento: scivolano con lui.
func _carried_shift(s: Dictionary) -> Vector2:
	if _body_t >= 1.0 or _body_from.is_empty(): return Vector2.ZERO
	if s.landed != "": return _body_shift(s.landed)
	for id in _body_from:
		var b := SolarMap.body(_map, id)
		if not b.is_empty() and Hex.distance(s.pos, b.hex) <= 1: return _body_shift(id)
	return Vector2.ZERO

## Posizione disegnata di un corpo (durante lo scivolamento dopo un passo d'orbita).
func _body_pos(b: Dictionary) -> Vector2:
	var to := world(b.hex)
	if _body_t >= 1.0 or not _body_from.has(b.id): return to
	return _body_from[b.id].lerp(to, ease(_body_t, -2.0))

func _draw_bodies() -> void:
	for b in _map.bodies:
		var c := _body_pos(b)
		if _body_from.has(b.id) and _body_t < 1.0:
			# scia del passo appena fatto
			draw_line(_body_from[b.id], c, Color(b.color, 0.5 * (1.0 - _body_t)), 0.25, true)
		var r: float = b.radius
		if b.id == "sol":
			var t := 0.5 + 0.5 * sin(_time * 0.8)
			draw_texture_rect(Art.glow(), Rect2(c - Vector2(3.6, 3.6), Vector2(7.2, 7.2)), false, Color(1.0, 0.62, 0.22, 0.55 + 0.08 * t))
			draw_texture_rect(Art.glow(), Rect2(c - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), false, Color(1.0, 0.85, 0.5, 0.9))
		if r > 0.0:
			if b.id != "sol":
				var halo: Color = b.color
				draw_texture_rect(Art.glow(), Rect2(c - Vector2(r, r) * 3.2, Vector2(r, r) * 6.4), false, Color(halo, 0.42))
				draw_circle(c, r * 1.08, Color(0, 0, 0, 0.55))
			draw_texture_rect(Art.planet(b.id, b.color), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
			if b.id == "saturn":
				# anelli: ellisse inclinata
				var pts := PackedVector2Array()
				for k in range(49):
					var a := TAU * k / 48.0
					pts.append(c + Vector2(cos(a) * r * 2.2, sin(a) * r * 0.62).rotated(-0.35))
				draw_polyline(pts, Color("e8d6a8", 0.85), r * 0.18, true)
				draw_polyline(pts, Color("8a7650", 0.6), r * 0.05, true)
		else:
			# Ceres e Clandestine: asteroidi-base
			var col: Color = Color("d9cbb4") if b.id != "clandestine" else Color("b8ccef")
			draw_circle(c, 0.2, col.darkened(0.4))
			draw_circle(c + Vector2(-0.05, -0.05), 0.13, col)
		for d in state.devastated:
			if d.body == b.id:
				var dv := world(Hex.DIRS[int(d.side)]).normalized()
				draw_arc(c, r + 0.08, dv.angle() - 0.5, dv.angle() + 0.5, 12, UITheme.DANGER, 0.12)
				draw_circle(c + dv * (r + 0.1), 0.09, Color(1.0, 0.55, 0.2))
		for d2 in state.sd.get("suppressed", []) if state.scenario == "fleet-mutiny" else []:
			if d2.body == b.id:
				var dv2 := world(Hex.DIRS[int(d2.side)]).normalized()
				draw_arc(c, r + 0.1, dv2.angle() - 0.48, dv2.angle() + 0.48, 12, Color(UITheme.WARN, 0.95), 0.1)
	# nomi
	if zoom >= 7.0:
		for b in _map.bodies:
			var c2 := _body_pos(b)
			var off := Vector2(0, 1.32)
			if b.id == "sol": off = Vector2(0, 2.7)
			if b.radius <= 0.0: off = Vector2(0, 0.62)
			_text_world(b.name.to_upper(), c2 + off, 0.42, Color(0.92, 0.88, 0.78, 0.85), Art.board_font_bold, true)

func _text_world(text: String, pos: Vector2, height: float, col: Color, font: Font, centered := false, outline := true) -> void:
	# disegno in coordinate di schermo per avere testo nitido a ogni zoom
	var sp := to_screen(pos)
	var px := int(clampf(height * zoom, 6.0, 64.0))
	if px < 7: return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := sp + Vector2(-w * 0.5 if centered else 0.0, px * 0.35)
	if outline: draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, px / 5), Color(0.01, 0.03, 0.08, 0.9))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	draw_set_transform(offset, 0.0, Vector2(zoom, zoom))

func _draw_bases() -> void:
	for b in state.bases:
		var body := SolarMap.body(_map, b.body)
		var col: Color = Color("e9e2cf") if b.owner == "all" else UITheme.player_color(state, b.owner)
		if not b.active: col = Color(0.4, 0.4, 0.4)
		var c := world(body.hex)
		if int(b.side) < 0:
			draw_arc(c, 0.42, 0, TAU, 24, Color(col, 0.9), 0.07)
			draw_arc(c, 0.52, 0, TAU, 24, Color(col, 0.4), 0.03)
			continue
		var dir := world(Hex.DIRS[int(b.side)]).normalized()
		var p := c + dir * (float(body.radius) + 0.12)
		var pts := _hex_poly(p, 0.11)
		draw_colored_polygon(pts, Color(0.02, 0.04, 0.1))
		var closed := pts.duplicate(); closed.append(pts[0])
		draw_polyline(closed, col, 0.045)
		draw_circle(p, 0.04, col)
		if not b.get("fuel", true) and state.scenario == "grand-tour":
			pass

func _draw_prospecting() -> void:
	if state.scenario != "prospecting": return
	for k in state.sd.prospected:
		var parts: PackedStringArray = k.split(",")
		var h := Vector2i(int(parts[0]), int(parts[1]))
		var c := world(h)
		if state.sd.prospected[k] == "ore":
			var pts := _hex_poly(c, 0.92)
			var closed := pts.duplicate(); closed.append(pts[0])
			draw_polyline(closed, Color("ffd36a"), 2.2 / zoom)
			draw_circle(c + Vector2(0.45, -0.45), 0.14, Color("ffd36a"))
		else:
			draw_line(c + Vector2(-0.2, -0.2), c + Vector2(0.2, 0.2), Color(1, 1, 1, 0.45), 1.6 / zoom)
			draw_line(c + Vector2(-0.2, 0.2), c + Vector2(0.2, -0.2), Color(1, 1, 1, 0.45), 1.6 / zoom)
	for k in state.sd.claims:
		var cl: Dictionary = state.sd.claims[k]
		var cc := world(cl.hex)
		var col := UITheme.player_color(state, cl.owner)
		draw_rect(Rect2(cc + Vector2(-0.62, 0.3), Vector2(0.34, 0.34)), col)
		if cl.guards: draw_arc(cc, 0.8, 0, TAU, 24, Color(col, 0.8), 2.0 / zoom)
		if zoom > 14.0: _text_world("%.0ft" % (int(cl.stock10) / 10.0), cc + Vector2(-0.45, 0.85), 0.28, col.lightened(0.3), Art.board_font_bold, true)

func _draw_overlay_hexes() -> void:
	for h in overlay.get("place_hexes", []):
		var pts := _hex_poly(world(h), 0.9)
		draw_colored_polygon(pts, Color(UITheme.PHOSPHOR, 0.18 + 0.08 * sin(_time * 4.0)))
		var pc := pts.duplicate(); pc.append(pts[0])
		draw_polyline(pc, Color(UITheme.PHOSPHOR, 0.7), 1.5 / zoom)
	for h in overlay.get("mark_hexes", []):
		if not overlay.get("mark_outline", true): continue
		var pts2 := _hex_poly(world(h), 0.95)
		var closed := pts2.duplicate(); closed.append(pts2[0])
		draw_polyline(closed, Color(UITheme.WARN, 0.8), 2.0 / zoom)

func _ship_world(s: Dictionary) -> Vector2:
	if anim_t < 1.0 and anim_moves.has(s.id):
		var m: Dictionary = anim_moves[s.id]
		var t := _ease(anim_t)
		return m.from.lerp(m.to, t)
	if s.landed != "":
		var body := SolarMap.body(_map, s.landed)
		var dir := world(Hex.DIRS[maxi(0, int(s.side))]).normalized()
		return _body_pos(body) + dir * (float(body.radius) + 0.26)
	return world(s.pos) + _carried_shift(s)

static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func _visible_ship(s: Dictionary) -> bool:
	if not Rules.alive(s) and not (anim_t < 1.0 and anim_moves.has(s.id)): return false
	return true

func _concealed(s: Dictionary) -> bool:
	if not state.rules.get("hidden", false): return false
	if s.owner == viewer: return false
	if s.get("dummy", false): return true
	return not state.knowledge.get(viewer, {}).get(s.id, false)

## Vettori di deriva: dove andrebbe ogni nave visibile senza accendere i motori.
## Tratteggio = inerzia (ripete l'ultimo spostamento); freccia ambra = gravità in arrivo.
func _draw_drift() -> void:
	if anim_t < 1.0: return
	for s in state.ships:
		if not Rules.alive(s) or s.landed != "" or s.get("dummy", false) or _concealed(s): continue
		var col := UITheme.player_color(state, s.owner).lightened(0.2)
		var r := Rules.simulate(_map, s.pos, s.vel, s.grav, Vector2i.ZERO, false, Rules.hazard_rocks(state, s), state.special, s.access_special)
		var a := world(s.pos)
		var inertial: Vector2i = s.pos + s.vel
		var mid := world(inertial)
		var g := Vector2i.ZERO
		for v in s.grav: g += v
		var dest := world(r.dest) if r.crash == "" else world(r.path[-1])
		var bad: bool = r.crash != "" or r.offmap or r.special
		var w := 1.5 / zoom
		if s.vel != Vector2i.ZERO:
			_dashed(a, mid, Color(col, 0.75), w, 0.22)
		else:
			draw_arc(a, 0.42, 0, TAU, 18, Color(col, 0.55), w)
		if g != Vector2i.ZERO:
			# ogni spinta di gravità in arrivo, in sequenza dall'estremo inerziale
			var p := inertial
			for v in s.grav:
				var p2: Vector2i = p + v
				var wa := world(p); var wb := world(p2)
				draw_line(wa, wb, Color(UITheme.WARN, 0.9), 2.2 / zoom, true)
				_arrow_head(wb, (wb - wa).normalized(), Color(UITheme.WARN, 0.9), 0.22)
				p = p2
			draw_circle(mid, 0.07, Color(col, 0.8))
		elif s.vel != Vector2i.ZERO:
			_arrow_head(mid, (mid - a).normalized(), Color(col, 0.75), 0.24)
		if s.vel != Vector2i.ZERO or g != Vector2i.ZERO:
			var ring := _hex_poly(dest, 0.5)
			var closed := ring.duplicate(); closed.append(ring[0])
			draw_polyline(closed, Color(UITheme.DANGER if bad else col, 0.7), w, true)
		if bad:
			draw_line(dest + Vector2(-0.25, -0.25), dest + Vector2(0.25, 0.25), UITheme.DANGER, 2.5 / zoom)
			draw_line(dest + Vector2(-0.25, 0.25), dest + Vector2(0.25, -0.25), UITheme.DANGER, 2.5 / zoom)

func _draw_histories() -> void:
	var lw := 2.4 / zoom
	for s in state.ships:
		if s.get("dummy", false) or _concealed(s): continue
		var col := UITheme.player_color(state, s.owner)
		var hist: Array = s.history
		var n := hist.size()
		var first := maxi(0, n - 10)
		for i in range(first, n):
			var e: Dictionary = hist[i]
			var age := n - 1 - i
			var alpha := clampf(1.0 - age * 0.11, 0.18, 0.95)
			if not Rules.alive(s): alpha *= 0.4
			var a := world(e.from); var b := world(e.to)
			if i == n - 1 and anim_t < 1.0 and anim_moves.has(s.id):
				b = a.lerp(b, _ease(anim_t))
			if a.distance_to(b) < 0.01: continue
			var c := Color(col, alpha)
			draw_line(a, b, c, lw, true)
			_arrow_head(b, (b - a).normalized(), c, 0.28)
			var burns: int = e.burns.size()
			var dir := (b - a).normalized()
			for k in range(burns):
				draw_arc(a + dir * (0.22 + 0.2 * k), 0.12, 0, TAU, 14, c, 1.6 / zoom)
			if show_numbers and zoom > 16.0 and e.has("turn") and int(e.turn) > 0:
				var mid := a.lerp(b, 0.5) + Vector2(-dir.y, dir.x) * 0.28
				_text_world(str(e.turn), mid, 0.34, Color(col.lightened(0.3), alpha), Art.board_font_bold, true)
		if Rules.alive(s) and s.landed == "" and s.vel == Vector2i.ZERO and n > 0 and zoom > 10.0 and anim_t >= 1.0:
			# convenzione: quadrato per una nave ferma
			var p := world(s.pos)
			draw_rect(Rect2(p - Vector2(0.62, 0.62), Vector2(1.24, 1.24)), Color(col, 0.35), false, 1.4 / zoom)

func _arrow_head(tip: Vector2, dir: Vector2, col: Color, size_w: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * size_w + side * size_w * 0.5, tip - dir * size_w - side * size_w * 0.5]), col)

func _dashed(a: Vector2, b: Vector2, col: Color, width: float, dash := 0.28) -> void:
	var len := a.distance_to(b)
	if len < 0.001: return
	var dir := (b - a) / len
	var t := 0.0
	var phase := fmod(_time * 0.6, dash * 2.0) if overlay.get("animate_dash", true) else 0.0
	t = -phase
	while t < len:
		var s0 := maxf(t, 0.0)
		var s1 := minf(t + dash, len)
		if s1 > s0: draw_line(a + dir * s0, a + dir * s1, col, width, true)
		t += dash * 2.0

func _draw_ordnance() -> void:
	for o in state.ordnance:
		var col := UITheme.player_color(state, o.owner)
		var p := world(o.pos)
		if anim_t < 1.0 and anim_moves.has(o.id):
			var m: Dictionary = anim_moves[o.id]
			p = m.from.lerp(m.to, _ease(anim_t))
		# vettore previsto
		var nxt := world(o.pos + o.vel + _gsum(o.grav) + o.get("launch_burn", Vector2i.ZERO))
		_dashed(p, nxt, Color(col, 0.55), 1.4 / zoom, 0.18)
		var letter: String = {"mine": "M", "torpedo": "T", "nuke": "N"}[o.kind]
		var r := 0.3
		var pts := PackedVector2Array()
		for i in range(4):
			pts.append(p + Vector2.from_angle(PI * 0.5 * i + PI * 0.25) * r)
		draw_colored_polygon(pts, Color("120a06") if o.kind != "nuke" else Color("2a0606"))
		var closed := pts.duplicate(); closed.append(pts[0])
		draw_polyline(closed, col, 0.06)
		_text_world(letter, p + Vector2(0, -0.02), 0.36, col.lightened(0.3), Art.board_display, true, false)
		if zoom > 18.0:
			_text_world("%d" % (Rules.ORDNANCE_LIFE - int(o.age)), p + Vector2(0.34, 0.28), 0.24, Color(1, 1, 1, 0.7), Art.board_font, false)

static func _gsum(list: Array) -> Vector2i:
	var t := Vector2i.ZERO
	for g in list: t += g
	return t

func _draw_predictions() -> void:
	var preds: Dictionary = overlay.get("predictions", {})
	for id in preds:
		var s := Rules.ship(state, id)
		if s.is_empty(): continue
		var pr: Dictionary = preds[id]
		var col := UITheme.player_color(state, s.owner)
		var a := _ship_world(s)
		var b := world(pr.dest)
		var bad: bool = pr.get("crash", "") != "" or pr.get("offmap", false) or pr.get("special", false)
		var c := UITheme.DANGER if bad else col.lightened(0.25)
		var sel: bool = id == selected
		var w := (2.6 if sel else 1.6) / zoom
		if pr.get("crash", "") != "":
			b = world(pr.path[-1])
		_dashed(a, b, Color(c, 0.95 if sel else 0.6), w)
		_arrow_head(b, (b - a).normalized() if a.distance_to(b) > 0.01 else Vector2.RIGHT, Color(c, 0.95 if sel else 0.6), 0.3)
		if bad:
			var x := b
			draw_line(x + Vector2(-0.3, -0.3), x + Vector2(0.3, 0.3), UITheme.DANGER, 3.0 / zoom)
			draw_line(x + Vector2(-0.3, 0.3), x + Vector2(0.3, -0.3), UITheme.DANGER, 3.0 / zoom)
		elif sel or preds.size() <= 3:
			var ghost := _hex_poly(b, 0.55)
			var closed := ghost.duplicate(); closed.append(ghost[0])
			draw_polyline(closed, Color(c, 0.7), 1.6 / zoom)
		# asteroidi a rischio
		for h in pr.get("asteroids", []):
			draw_arc(world(h), 0.75, 0, TAU, 20, Color(UITheme.WARN, 0.8), 2.0 / zoom)

func _draw_choices(fills: bool) -> void:
	var choices: Array = overlay.get("choices", [])
	for ch in choices:
		var c := world(ch.hex)
		var kind: String = ch.kind
		var col := UITheme.CYAN
		if kind == "overload": col = UITheme.ACCENT_SOFT
		if kind == "drift": col = Color("d8e2ff")
		var picked: bool = ch.get("picked", false)
		var pts := _hex_poly(c, 0.82)
		if fills:
			if picked and kind != "drift": draw_colored_polygon(pts, Color(UITheme.ACCENT, 0.28))
			elif ch.get("hover", false): draw_colored_polygon(pts, Color(col, 0.18))
			continue
		var closed := pts.duplicate(); closed.append(pts[0])
		var a := 0.55 + 0.25 * sin(_time * 3.0)
		draw_polyline(closed, Color(col if not picked else UITheme.ACCENT, 1.0 if picked else a), (2.6 if picked else 1.4) / zoom, true)
		if ch.get("danger", false):
			var k := 0.62
			draw_line(c + Vector2(-k, -k) * 0.5, c + Vector2(k, k) * 0.5, Color(UITheme.DANGER, 0.55), 1.6 / zoom)
			draw_line(c + Vector2(-k, k) * 0.5, c + Vector2(k, -k) * 0.5, Color(UITheme.DANGER, 0.55), 1.6 / zoom)
		if kind == "drift":
			draw_circle(c + Vector2(0, -0.58), 0.07, Color(col, 0.9) if not picked else UITheme.ACCENT)

func _draw_ships() -> void:
	# raggruppa per esagono per sfalsare le pedine impilate
	var groups := {}
	for s in state.ships:
		if not _visible_ship(s): continue
		var key = s.pos if s.landed == "" else Vector2i(-999 - int(s.side), s.landed.hash())
		if anim_t < 1.0 and anim_moves.has(s.id): key = Vector2i(-5000, s.id.hash())
		if not groups.has(key): groups[key] = []
		groups[key].append(s)
	for key in groups:
		var list: Array = groups[key]
		var n := list.size()
		for i in range(n):
			var s: Dictionary = list[i]
			var p := _ship_world(s)
			var scale := 0.62 if s.landed == "" else 0.3
			if n > 1:
				var a := TAU * float(i) / n - PI * 0.5
				p += Vector2.from_angle(a) * (0.3 if n == 2 else 0.36)
				scale *= 0.78
			_draw_token(s, p, scale)

## Spinta "di questo turno": quella pianificata ora, altrimenti quella dell'ultimo movimento (se recente).
func _thrust_of(s: Dictionary) -> Vector2i:
	var plot: Dictionary = state.plots.get(s.id, {})
	if not plot.is_empty() and (s.owner == viewer or not state.rules.get("hidden", false)):
		return Rules.burn_vector(plot.get("burns", []))
	if not s.history.is_empty():
		var h: Dictionary = s.history[-1]
		if int(h.turn) >= int(state.turn) - 1 and not h.get("burns", []).is_empty():
			return Rules.burn_vector(h.burns)
	return Vector2i.ZERO

func _draw_token(s: Dictionary, p: Vector2, r: float) -> void:
	var concealed := _concealed(s)
	var col := UITheme.player_color(state, s.owner)
	if s.get("dummy", false) and not concealed:
		# falso bersaglio visto dal proprietario
		var dpts := _hex_poly(p, r * 0.9)
		draw_colored_polygon(dpts, Color(col, 0.12))
		var dclosed := dpts.duplicate(); dclosed.append(dpts[0])
		draw_polyline(dclosed, Color(col, 0.6), r * 0.07, true)
		_text_world("F", p + Vector2(0, -0.03), r * 0.75, Color(col, 0.75), Art.board_display, true, false)
		if overlay.get("mark_hexes", []).has(s.pos):
			draw_line(p + Vector2(-r, -r) * 0.7, p + Vector2(r, r) * 0.7, UITheme.DANGER, r * 0.12)
		return
	var sel: bool = s.id == selected
	var dead := not Rules.alive(s)
	if overlay.get("attackers", []).has(s.id) or overlay.get("targets_sel", []).has(s.id):
		var ring := UITheme.ACCENT if overlay.get("attackers", []).has(s.id) else UITheme.DANGER
		draw_arc(p, r * 1.38, 0, TAU, 32, Color(ring, 0.95), 3.0 / zoom)
	elif overlay.get("targetable", []).has(s.id):
		draw_arc(p, r * 1.32, 0, TAU, 32, Color(UITheme.DANGER, 0.45 + 0.3 * sin(_time * 5.0)), 2.0 / zoom)
	if sel:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_arc(p, r * (1.3 + 0.08 * pulse), 0, TAU, 40, Color(UITheme.ACCENT, 0.9), 3.0 / zoom)
	var pts := _hex_poly(p, r)
	var fill := Color("0a1226") if not concealed else Color("1c2333")
	draw_colored_polygon(pts, Color(fill, 0.95 if not dead else 0.5))
	var closed := pts.duplicate(); closed.append(pts[0])
	var edge := col if not concealed else Color("8a93a8")
	draw_polyline(closed, Color(edge, 0.95), r * 0.12, true)
	if concealed:
		_text_world("?", p + Vector2(0, -0.04), r * 0.9, Color("c8d0e0"), Art.board_display, true, false)
		return
	# silhouette orientata secondo il vettore
	var ang := 0.0
	if s.vel != Vector2i.ZERO: ang = world(s.vel).angle()
	elif not s.history.is_empty() and s.history[-1].from != s.history[-1].to: ang = (world(s.history[-1].to) - world(s.history[-1].from)).angle()
	# senza rotte né derive: la nave punta nella direzione della spinta scelta e mostra lo sbuffo dei motori
	if not show_trails and not show_drift and s.landed == "":
		var thrust := _thrust_of(s)
		if thrust != Vector2i.ZERO:
			_has_puffs = true
			if nose_on_course:
				_draw_side_jets(p, thrust, r)
			else:
				var tdir := world(thrust)
				ang = tdir.angle()
				_draw_puff(p, tdir, float(Hex.length(thrust)), r)
	var shape_col := col.lightened(0.15)
	if Rules.is_disabled(state, s): shape_col = shape_col.lerp(Color(0.5, 0.5, 0.55), 0.6)
	for poly in Art.ship_polys(s.type):
		var tp := PackedVector2Array()
		for v in poly: tp.append(p + (v * r * 0.72).rotated(ang))
		draw_colored_polygon(tp, shape_col)
	# badge: forza, disabilitazione, eroismo, passeggeri
	if zoom > 13.0:
		var label := ShipTypes.strength_label(s.type)
		_text_world(label, p + Vector2(0, r * 0.95), r * 0.42, Color(1, 1, 1, 0.85), Art.board_font_bold, true)
	var dt := Rules.disabled_turns(state, s)
	if dt > 0:
		draw_circle(p + Vector2(r * 0.78, -r * 0.7), r * 0.32, UITheme.DANGER)
		_text_world("D%d" % dt, p + Vector2(r * 0.78, -r * 0.72), r * 0.36, Color.WHITE, Art.board_font_bold, true, false)
	if s.heroic:
		_star(p + Vector2(-r * 0.8, -r * 0.7), r * 0.26, UITheme.WARN)
	if s.get("passengers", false):
		draw_circle(p + Vector2(-r * 0.8, r * 0.7), r * 0.22, UITheme.PHOSPHOR)
	if s.get("surrendered", false):
		draw_rect(Rect2(p + Vector2(-r * 0.25, -r * 1.25), Vector2(r * 0.5, r * 0.3)), Color.WHITE)
	if dead:
		draw_line(p + Vector2(-r, -r) * 0.6, p + Vector2(r, r) * 0.6, UITheme.DANGER, r * 0.15)

## Le spinte di un turno scomposte nelle sei direzioni (il sovraccarico ne ha due).
func _burn_dirs(v: Vector2i) -> Array:
	if v == Vector2i.ZERO: return []
	for d in Hex.DIRS:
		if d == v: return [d]
		if d * 2 == v: return [d, d]
	for a in Hex.DIRS:
		for b in Hex.DIRS:
			if a + b == v: return [a, b]
	return [v]

## Fiamme di manovra: la nave tiene la prua sulla rotta e i getti escono da uno dei sei lati,
## quello opposto alla spinta (come le sei scelte di spinta attorno alla deriva).
func _draw_side_jets(p: Vector2, burn: Vector2i, r: float, alpha := 1.0) -> void:
	for d in _burn_dirs(burn):
		var dir := world(d).normalized()
		_draw_puff(p - dir * r * 0.15, dir, 1.0, r * 0.8, alpha)

## Sbuffo dei motori: getto dietro la nave, opposto alla direzione della spinta.
func _draw_puff(p: Vector2, dir: Vector2, strength: float, r: float, alpha := 1.0) -> void:
	if dir == Vector2.ZERO: return
	var back := -dir.normalized()
	var flick := 0.85 + 0.15 * sin(_time * 31.0) + 0.08 * sin(_time * 17.0)
	var base := p + back * r * 0.55
	var length := r * (1.25 + 0.45 * strength) * flick
	var side := back.orthogonal() * r * 0.3 * (0.8 + 0.25 * strength)
	draw_colored_polygon(PackedVector2Array([base + side, base - side, base + back * length]), Color(1.0, 0.55, 0.15, 0.75 * alpha))
	draw_colored_polygon(PackedVector2Array([base + side * 0.5, base - side * 0.5, base + back * length * 0.62]), Color(1.0, 0.92, 0.65, 0.9 * alpha))
	# piccole nuvole di gas che si allontanano
	for k in range(4):
		var ph := fmod(_time * 1.6 + k * 0.25, 1.0)
		var off := back * (length * (0.55 + ph * 1.1)) + side * (sin(k * 2.3 + _time * 3.0) * 0.6)
		draw_circle(base + off, r * (0.09 + ph * 0.18), Color(0.85, 0.82, 0.78, (1.0 - ph) * 0.45 * alpha))

## Replay: tracciati e navi in movimento continuo.
func _draw_replay() -> void:
	var u := replay_u
	var tmin: float = replay.tmin
	for id in replay.tracks:
		var tr: Dictionary = replay.tracks[id]
		var inf: Dictionary = replay.info.get(id, {})
		if inf.is_empty(): continue
		var col := UITheme.player_color(state, inf.owner)
		var gone: float = replay.lost.get(id, INF)
		var end_u := minf(u, gone)
		if end_u < float(tr.times[0]): continue
		# scia percorsa finora
		var pts := PackedVector2Array()
		var t := float(tr.times[0])
		while t < end_u:
			pts.append(Replay.pos_at(tr, t)); t += 0.2
		var cur = Replay.pos_at(tr, end_u)
		if cur == null: continue
		pts.append(cur)
		if pts.size() > 1:
			draw_polyline(pts, Color(col, 0.42 if inf.kind == "ship" else 0.25), (1.6 if inf.kind == "ship" else 0.9) / zoom, true)
		if u > gone:
			# esplosione nel momento della perdita
			var age := u - gone
			if age < 0.8:
				var k := age / 0.8
				draw_circle(cur, 0.25 + k * 0.9, Color(1.0, 0.7, 0.3, (1.0 - k) * 0.7))
				draw_circle(cur, 0.12 + k * 0.4, Color(1.0, 0.95, 0.8, (1.0 - k)))
			continue
		var ahead = Replay.pos_at(tr, minf(u + 0.08, float(tr.times[-1])))
		var behind = Replay.pos_at(tr, maxf(u - 0.08, float(tr.times[0])))
		var heading: Vector2 = (ahead - behind) if ahead != null and behind != null else Vector2.ZERO
		if inf.kind != "ship":
			var d := 0.16
			draw_colored_polygon(PackedVector2Array([cur + Vector2(0, -d), cur + Vector2(d, 0), cur + Vector2(0, d), cur + Vector2(-d, 0)]), col.lightened(0.3))
			continue
		var burn := Replay.burn_at(tr, u)
		var ang := heading.angle() if heading.length() > 0.01 else float(tr.get("ang", 0.0))
		tr.ang = ang
		var r := 0.55
		var frac := fmod(u - tmin, 1.0)
		if burn != Vector2i.ZERO and frac < 0.55:
			var fade := 1.0 - frac / 0.55
			if nose_on_course:
				_draw_side_jets(cur, burn, r, fade)
			else:
				# la nave punta nella direzione della spinta e accende il motore principale
				var bdir := world(burn)
				ang = bdir.angle()
				_draw_puff(cur, bdir, float(Hex.length(burn)), r, fade)
		draw_circle(cur, r * 0.9, Color(col, 0.18))
		for poly in Art.ship_polys(str(inf.type)):
			var tp := PackedVector2Array()
			for v in poly: tp.append(cur + (v * r).rotated(ang))
			draw_colored_polygon(tp, col.lightened(0.2))

func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI * 0.5 + i * PI / 5.0) * rr)
	draw_colored_polygon(pts, col)

func _draw_fx() -> void:
	for f in fx_list:
		var age: float = _time - float(f.t0)
		if age < 0.0: continue
		var t := clampf(age / 1.4, 0.0, 1.0)
		var p: Vector2 = f.world
		match f.kind:
			"explosion", "nuke":
				var big := 2.2 if f.kind == "nuke" else 1.0
				draw_circle(p, (0.2 + t * 1.1) * big, Color(1.0, 0.75, 0.3, (1.0 - t) * 0.65))
				draw_arc(p, (0.3 + t * 1.6) * big, 0, TAU, 32, Color(1.0, 0.4, 0.15, 1.0 - t), 3.0 / zoom)
			"blast", "ram", "flak":
				draw_arc(p, 0.2 + t * 1.0, 0, TAU, 24, Color(1.0, 0.85, 0.4, 1.0 - t), 2.5 / zoom)
			"hit":
				draw_arc(p, 0.3 + t * 0.7, 0, TAU, 24, Color(UITheme.DANGER, 1.0 - t), 3.0 / zoom)
			"rock":
				draw_arc(p, 0.3 + t * 0.6, 0, TAU, 16, Color(UITheme.WARN, 1.0 - t), 2.0 / zoom)
			"fire":
				var to: Vector2 = f.get("to", p)
				draw_line(p, p.lerp(to, minf(1.0, t * 3.0)), Color(1.0, 0.9, 0.5, 1.0 - t), 2.0 / zoom)

func _draw_hover() -> void:
	if not _map.cells.has(hover): return
	var pts := _hex_poly(world(hover), 0.98)
	var closed := pts.duplicate(); closed.append(pts[0])
	draw_polyline(closed, Color(1, 1, 1, 0.45), 1.5 / zoom)
