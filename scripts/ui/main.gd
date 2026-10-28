extends Control
## Controller della partita: menu, HUD, flusso delle fasi, IA, animazioni e salvataggi.

const TOP_H := 64
const SIDE_W := 356
const BOTTOM_H := 66
const PHASE_ORDER := ["astrogation", "ordnance", "movement", "combat", "resupply"]
const PHASE_SHORT := {"astrogation": "ASTROGAZIONE", "ordnance": "ORDIGNI", "movement": "MOVIMENTO", "combat": "COMBATTIMENTO", "resupply": "RIFORNIMENTO"}

var state: Dictionary = {}
var board: Board
var sel := ""
var mode := ""
var torpedo_burns: Array = []
var attackers: Array = []
var targets: Array = []
var busy := false
var shown_for := ""
var anim_speed := 1.0
var hover_hex := Vector2i(9999, 9999)

# HUD
var hud: Control
var top_scenario: Label
var top_day: Label
var phase_pills: Array = []
var player_chip: PanelContainer
var player_dot: Panel
var player_label: Label
var fleet_box: VBoxContainer
var detail_box: VBoxContainer
var actions: VBoxContainer
var objective_box: VBoxContainer
var hint: RichTextLabel
var primary: Button
var log_text: RichTextLabel
var log_panel: PanelContainer
var tip: PanelContainer
var tip_text: RichTextLabel
var toast: Label
var toast_tween: Tween
var thinking: Label
var detect_toggle: Button
var trails_toggle: Button
var drift_toggle: Button
const SETTINGS_PATH := "user://impostazioni.cfg"

## Interruttore di visualizzazione ricordato fra una sessione e l'altra.
func _view_toggle(text: String, tip_s: String, key: String, default_on: bool) -> Button:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var on: bool = cfg.get_value("vista", key, default_on)
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip_s
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("pressed", UITheme.box(Color("123a3a"), UITheme.CYAN, 5, 2, 12))
	b.add_theme_stylebox_override("hover_pressed", UITheme.box(Color("16484a"), UITheme.CYAN, 5, 2, 12))
	b.add_theme_color_override("font_pressed_color", UITheme.CYAN)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.toggled.connect(func(v):
		match key:
			"trails": board.show_trails = v
			"drift": board.show_drift = v
			"radar": board.show_detection = v
		var c2 := ConfigFile.new()
		c2.load(SETTINGS_PATH)
		c2.set_value("vista", key, v)
		c2.save(SETTINGS_PATH)
		board.queue_redraw())
	b.button_pressed = on
	match key:
		"trails": board.show_trails = on
		"drift": board.show_drift = on
		"radar": board.show_detection = on
	return b

# schermate
var menu: Control
## Collegamento a Firebase (resta vivo fra menu e partita) e partita online in corso (null se locale).
var net: Net
var online: Online = null
var lobby := {}               # stanza in preparazione: {code, seat, role, config}
var lobby_box: Control
var replay_bar: PanelContainer
var replay_play := false
var replay_speed := 1.0
var replay_slider: HSlider
var replay_label: Label
var replay_toggle: Button
var autoplay := false         # prove automatiche: l'IA gioca anche per il giocatore locale
var _gen := 0                 # cambia a ogni nuova partita: ferma le attese della precedente
var privacy: Control
var dialog: Control
var victory: Control
var help: Control

var menu_scenario := "grand-tour"
var menu_seats: Array = []
var menu_detail: VBoxContainer
var menu_options := {"sol_classic": false, "liner_terra": false, "nova_allied": true, "length": 120,
	"route": "free", "aliens": 4, "mutiny_ships": 12, "mutiny_hidden": false, "map": "classic"}

func _ready() -> void:
	theme = UITheme.theme()
	UITheme.load_fonts()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board = Board.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.hex_clicked.connect(_on_hex_clicked)
	board.hex_hovered.connect(_on_hex_hovered)
	add_child(board)
	net = Net.new()
	add_child(net)
	_build_hud()
	_build_replay_bar()
	_build_menu()
	_build_help()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_show_menu()

# ================================================================ HUD

func _panel(bg := UITheme.PANEL, border := UITheme.LINE, radius := 8, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(bg, border, radius, 1, pad))
	return p

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	# --- barra superiore
	var top := _panel(Color("070f22ee"), UITheme.LINE, 0, 10)
	top.name = "Top"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_H
	hud.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	var logo := UITheme.label("TRIPLANETARY", 22, UITheme.PHOSPHOR, UITheme.display)
	logo.add_theme_color_override("font_outline_color", Color("c2321f"))
	logo.add_theme_constant_override("outline_size", 3)
	row.add_child(logo)
	top_scenario = UITheme.label("", 16, UITheme.TEXT_DIM, UITheme.body_bold)
	top_scenario.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(top_scenario)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	top_day = UITheme.label("GIORNO 1", 22, UITheme.TEXT, UITheme.display)
	top_day.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(top_day)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 3)
	row.add_child(pills)
	for i in range(PHASE_ORDER.size()):
		var pill := PanelContainer.new()
		var l := UITheme.label(PHASE_SHORT[PHASE_ORDER[i]], 12, UITheme.TEXT_FAINT, UITheme.body_bold)
		pill.add_child(l)
		pills.add_child(pill)
		phase_pills.append(pill)
	var sp2 := Control.new(); sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp2)
	player_chip = _panel(Color("0c1a38"), UITheme.LINE_BRIGHT, 20, 8)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	player_chip.add_child(chip_row)
	player_dot = Panel.new()
	player_dot.custom_minimum_size = Vector2(16, 16)
	player_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(player_dot)
	player_label = UITheme.label("", 17, UITheme.TEXT, UITheme.body_bold)
	chip_row.add_child(player_label)
	row.add_child(player_chip)
	var finish := _icon_button("FINE", "Termina la partita, aggiudica la vittoria e passa alla schermata finale con il replay")
	finish.pressed.connect(func():
		if state.is_empty(): return
		if state.over: _show_victory()
		else: _confirm_end())
	row.add_child(finish)
	var guide := _icon_button("GUIDA", "Regole e comandi")
	guide.pressed.connect(func(): help.visible = true)
	row.add_child(guide)
	var menu_btn := _icon_button("MENU", "Salva, carica, nuova partita")
	menu_btn.pressed.connect(_open_game_menu)
	row.add_child(menu_btn)
	# --- pannello laterale
	var side := _panel(Color("08122aee"), UITheme.LINE, 10, 14)
	side.name = "Side"
	hud.add_child(side)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(side_scroll)
	var side_v := VBoxContainer.new()
	side_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_v.add_theme_constant_override("separation", 10)
	side_scroll.add_child(side_v)
	objective_box = VBoxContainer.new()
	objective_box.add_theme_constant_override("separation", 4)
	side_v.add_child(objective_box)
	side_v.add_child(UITheme.caption("Flotta"))
	fleet_box = VBoxContainer.new()
	fleet_box.add_theme_constant_override("separation", 5)
	side_v.add_child(fleet_box)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 6)
	side_v.add_child(detail_box)
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	side_v.add_child(actions)
	# --- barra inferiore
	var bottom := _panel(Color("070f22ee"), UITheme.LINE, 0, 12)
	bottom.name = "Bottom"
	hud.add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	bottom.add_child(brow)
	var zoom_box := HBoxContainer.new()
	zoom_box.add_theme_constant_override("separation", 4)
	for spec in [["−", "Riduci", func(): board.zoom_by(1.0 / 1.25, board.size * 0.5)], ["+", "Ingrandisci", func(): board.zoom_by(1.25, board.size * 0.5)], ["⌂", "Tutta la plancia", func(): board.fit()], ["◎", "Centra la nave selezionata", _center_selected]]:
		var zb := Button.new(); zb.text = spec[0]; zb.tooltip_text = spec[1]; zb.custom_minimum_size = Vector2(38, 38)
		zb.add_theme_font_size_override("font_size", 20)
		zb.pressed.connect(spec[2])
		zoom_box.add_child(zb)
	brow.add_child(zoom_box)
	var log_btn := Button.new(); log_btn.text = "REGISTRO"; log_btn.toggle_mode = true; log_btn.button_pressed = true
	log_btn.toggled.connect(func(on): log_panel.visible = on)
	brow.add_child(log_btn)
	trails_toggle = _view_toggle("ROTTE", "Rotte percorse da ogni nave, con il giorno del movimento (tasto R)", "trails", true)
	brow.add_child(trails_toggle)
	drift_toggle = _view_toggle("DERIVA", "Vettori di deriva di tutte le navi visibili: dove andrebbero senza spinte, con la gravità in arrivo in ambra (tasto D)", "drift", false)
	brow.add_child(drift_toggle)
	detect_toggle = _view_toggle("RADAR", "Raggio dei rilevatori delle basi, 5 esagoni (tasto V)", "radar", false)
	brow.add_child(detect_toggle)
	hint = RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.scroll_active = false
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.add_theme_font_size_override("normal_font_size", 17)
	hint.add_theme_font_size_override("bold_font_size", 17)
	brow.add_child(hint)
	primary = UITheme.primary_button("CONFERMA ▸")
	primary.custom_minimum_size = Vector2(250, 42)
	primary.pressed.connect(_on_primary)
	brow.add_child(primary)
	# --- registro
	log_panel = _panel(Color("070f22dd"), UITheme.LINE, 8, 10)
	log_panel.name = "Log"
	hud.add_child(log_panel)
	var lv := VBoxContainer.new()
	log_panel.add_child(lv)
	lv.add_child(UITheme.caption("Registro di bordo"))
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_size_override("normal_font_size", 15)
	log_text.add_theme_font_size_override("bold_font_size", 15)
	lv.add_child(log_text)
	# --- suggerimento al passaggio del mouse
	tip = _panel(Color("08122af4"), UITheme.CYAN, 6, 8)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip_text = RichTextLabel.new()
	tip_text.bbcode_enabled = true
	tip_text.fit_content = true
	tip_text.custom_minimum_size = Vector2(250, 0)
	tip_text.scroll_active = false
	tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_text.add_theme_font_size_override("normal_font_size", 15)
	tip_text.add_theme_font_size_override("bold_font_size", 15)
	tip.add_child(tip_text)
	hud.add_child(tip)
	# --- messaggi
	toast = UITheme.label("", 22, UITheme.TEXT, UITheme.display)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_outline_color", Color("020610"))
	toast.add_theme_constant_override("outline_size", 8)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.modulate.a = 0.0
	hud.add_child(toast)
	thinking = UITheme.label("", 18, UITheme.CYAN, UITheme.body_bold)
	thinking.add_theme_color_override("font_outline_color", Color("020610"))
	thinking.add_theme_constant_override("outline_size", 6)
	thinking.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(thinking)

func _icon_button(text: String, tip_text_s: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip_text_s
	b.add_theme_font_size_override("font_size", 14)
	return b

func _layout() -> void:
	var vs := get_viewport_rect().size
	var side_w := SIDE_W if vs.x > 1000 else 300
	var side: Control = hud.get_node("Side")
	side.position = Vector2(vs.x - side_w - 10, TOP_H + 10)
	side.size = Vector2(side_w, vs.y - TOP_H - BOTTOM_H - 20)
	var bottom: Control = hud.get_node("Bottom")
	bottom.position = Vector2(0, vs.y - BOTTOM_H)
	bottom.size = Vector2(vs.x, BOTTOM_H)
	log_panel.position = Vector2(10, vs.y - BOTTOM_H - 150)
	log_panel.size = Vector2(minf(440, vs.x * 0.34), 140)
	board.safe_rect = Rect2(10, TOP_H + 6, vs.x - side_w - 30, vs.y - TOP_H - BOTTOM_H - 12)
	toast.position = Vector2(0, TOP_H + 22)
	toast.size = Vector2(vs.x - side_w, 40)
	thinking.position = Vector2(16, TOP_H + 14)
	thinking.size = Vector2(600, 30)
	if replay_bar != null:
		replay_bar.position = Vector2(20, vs.y - 78)
		replay_bar.size = Vector2(vs.x - 40, 66)
		if replay_bar.visible: board.safe_rect = Rect2(10, 10, vs.x - 20, vs.y - 100)

# ================================================================ avvio partita

func _start_game(st: Dictionary, net_game := false) -> void:
	if not net_game and online != null: _leave_online()
	_gen += 1
	busy = false
	if dialog != null: dialog.queue_free(); dialog = null
	state = st
	sel = ""
	mode = ""
	attackers = []; targets = []
	shown_for = ""
	board.set_state(state)
	board.selected = ""
	board.fit()
	log_text.clear()
	for e in state.log: _append_log(e)
	menu.visible = false
	hud.visible = true
	board.visible = true
	_refresh()
	_flow()

func _append_log(e: Dictionary) -> void:
	var col := "#b9c4dc"
	match e.get("kind", "info"):
		"combat": col = "#ff9a6a"
		"loss": col = "#ff6070"
		"victory": col = "#5be38f"
		"detect": col = "#7fe0ee"
		"supply": col = "#d6e48a"
		"hazard": col = "#ffcf5a"
		"ordnance": col = "#ffb070"
		"move": col = "#9fb3d8"
	var who: String = e.get("player", "")
	var dot := ""
	if who != "":
		dot = "[color=%s]●[/color] " % UITheme.player_color(state, who).to_html(false)
	log_text.append_text("[color=#5f6f92]G%d[/color] %s[color=%s]%s[/color]\n" % [int(e.get("turn", 0)), dot, col, e.text])

# ================================================================ flusso delle fasi

func _human_seat() -> String:
	if online != null: return online.pid
	for p in state.players:
		if p.type == "human": return p.id
	return ""

func _active_player() -> String:
	if state.is_empty(): return ""
	if not state.pending_attack.is_empty(): return state.pending_attack.defender
	if state.phase == "setup": return state.setup.get("player", "P1")
	return Rules.current_player(state)

func _is_human(pid: String) -> bool:
	if online != null: return pid == online.pid
	return Rules.player(state, pid).get("type", "human") == "human"

func _needs_privacy() -> bool:
	if online != null: return false
	if not state.rules.get("hidden", false) and state.scenario != "escape": return false
	var humans = state.players.filter(func(p): return p.type == "human")
	return humans.size() >= 2

## Ciclo principale: esegue i passi automatici (IA, fasi senza scelte) finché
## serve un intervento del giocatore umano.
func _flow() -> void:
	if busy: return
	busy = true
	if online != null: online.watching = false
	var gen := _gen
	var guard := 0
	while not state.over and guard < 400:
		guard += 1
		var who := _active_player()
		if online != null and not online.controls(state, who):
			# decide un altro dispositivo: si passa la mano e si aspetta la sua istantanea
			board.viewer = online.pid
			thinking.text = "In attesa di %s…" % Rules.player(state, who).name
			_refresh()
			var pk := await online.handoff(state, who)
			if gen != _gen: return
			thinking.text = ""
			if pk.is_empty(): break
			if pk.has("takeover"): continue
			await _apply_packet(pk)
			if gen != _gen: return
			guard = 0
			continue
		if not _is_human(who) or autoplay:
			if online != null and online.away.has(who) and await online.check_back(state, who):
				if gen != _gen: return
				continue
			board.viewer = _human_seat() if _human_seat() != "" else who
			thinking.text = "%s sta pianificando…" % Rules.player(state, who).name
			_refresh()
			await get_tree().process_frame
			await get_tree().process_frame
			if gen != _gen: return
			var before_phase: String = state.phase
			var log_n: int = state.log.size()
			if not state.pending_attack.is_empty(): AI.respond_counter(state)   # anche per un umano assente
			else: AI.play_step(state)
			thinking.text = ""
			_after_step(log_n)
			if before_phase == "ordnance" and state.phase == "combat" or state.phase == "combat" and not state.moves.is_empty() and before_phase == "ordnance":
				pass
			if state.get("moves", []).size() > 0 and before_phase == "ordnance":
				await _animate_moves()
			await get_tree().create_timer(0.12 / anim_speed).timeout
			if gen != _gen: return
			continue
		# giocatore umano
		if _needs_privacy() and shown_for != who:
			await _show_privacy(who)
			if gen != _gen: return
		shown_for = who
		board.viewer = who
		if not state.pending_attack.is_empty():
			# l'IA ha attaccato una nave umana: si decide il contrattacco
			if dialog == null:
				busy = false
				_refresh()
				_show_counter_dialog()
			return
		_auto_select(who)
		if _auto_skip():
			var log_n2: int = state.log.size()
			var ph: String = state.phase
			Rules.end_phase(state)
			_after_step(log_n2)
			if ph == "ordnance": await _animate_moves()
			continue
		break
	busy = false
	_refresh()
	if online != null:
		if state.over:
			var o := online
			await o.publish(state)
			o.finish()
		else:
			online.watch()
	if state.over: _show_victory()

var _focus_key := ""

## A inizio segmento seleziona la prima nave del giocatore e la inquadra.
func _auto_select(who: String) -> void:
	var key := "%d:%d:%s" % [int(state.turn), int(state.seg), state.phase]
	if key == _focus_key: return
	_focus_key = key
	if state.phase == "setup" and state.scenario == "lateral-7":
		var lm := Rules.map_of(state)
		board.center_on(SolarMap.body(lm, "ceres").hex + Vector2i(8, 1) if not lm.get("xmap", false) else SolarMap.body(lm, "clandestine").hex, 17.0)
		return
	if state.phase == "setup":
		if state.setup.get("step", "") == "deploy":
			var sp: Array = Fleet.spots(state).keys()
			if not sp.is_empty() and sp.size() < 200:
				var c := Vector2.ZERO
				for h in sp: c += Board.world(h)
				c /= sp.size()
				board.zoom = maxf(board.zoom, 15.0)
				board.offset = board._safe().get_center() - c * board.zoom
				board.queue_redraw()
			else: board.fit()
		return
	var cur := Rules.ship(state, sel)
	if not cur.is_empty() and cur.owner == who and Rules.alive(cur): return
	for s in state.ships:
		if s.owner == who and Rules.alive(s) and not s.get("dummy", false) and not _finished(s):
			sel = s.id
			if state.phase == "astrogation":
				board.center_on(s.pos if s.landed == "" else SolarMap.body(Rules.map_of(state), s.landed).hex, 26.0)
			return

func _after_step(log_from: int) -> void:
	for i in range(log_from, state.log.size()): _append_log(state.log[i])
	for f in state.get("fx", []): board.add_fx(f.kind, f.hex, 0.75 / anim_speed if state.phase == "combat" else 0.0)
	Persistence.save_slot(state, "online" if online != null else "auto")

func _animate_moves(record := true) -> void:
	var moves: Array = state.get("moves", [])
	if moves.is_empty(): return
	if record and online != null: online.moves_out.append(moves.duplicate(true))
	board.anim_moves = {}
	for m in moves:
		board.anim_moves[m.id] = {"from": Board.world(m.from), "to": Board.world(m.to)}
	board.anim_t = 0.0
	var dur := 0.85 / anim_speed
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		t += get_process_delta_time()
		board.anim_t = clampf(t / dur, 0.0, 1.0)
		board.queue_redraw()
	board.anim_t = 1.0
	board.anim_moves = {}
	state.moves = []
	board.queue_redraw()

## Vero se la fase corrente non offre scelte al giocatore umano.
func _auto_skip() -> bool:
	if not state.pending_attack.is_empty(): return false
	var me := Rules.current_player(state)
	match state.phase:
		"setup": return false
		"astrogation":
			if state.scenario == "interplanetary-war" and ScenWar.can_buy_now(state, me) == "": return false
			if state.scenario == "retribution" and me == "P1" and ScenRetribution.can_form(state): return false
			return not state.ships.any(func(s): return s.owner == me and Rules.alive(s) and not s.get("dummy", false) and not s.get("is_base", false) and not s.get("parked", false) and (s.landed == "" or Rules.can_take_off(state, s)) and not _finished(s))
		"ordnance":
			if not state.rules.get("ordnance", true): return true
			for s in state.ships:
				if s.owner != me or not Rules.alive(s): continue
				for k in ["mine", "torpedo", "nuke"]:
					if int(s.inv.get(k, 0)) > 0 and Rules.can_launch(state, s, k) == "": return false
			return true
		"movement": return true
		"combat":
			if not state.rules.get("combat", true): return true
			if state.scenario == "fleet-mutiny" and state.ships.any(func(x): return x.owner == me and not ScenMutiny.suppress_target(state, x).is_empty()): return false
			return _possible_attacks(me).is_empty()
		"resupply":
			return not _resupply_has_choices(me)
	return false

func _finished(s: Dictionary) -> bool:
	return state.scenario == "grand-tour" and state.sd.finishers.has(s.id)

func _possible_attacks(me: String) -> Array:
	var out := []
	var now := Rules.tick(state)
	for a in state.ships:
		if a.owner != me or not Rules.can_fire(state, a) or int(a.attacked_tick) == now: continue
		for t in state.ships:
			if Rules.can_be_attacked(state, me, t) and int(t.targeted_tick) != now:
				var p := Rules.attack_preview(state, [a], [t])
				if int(p.column) >= 0 and _hit_chance(p) > 0.0: out.append([a.id, t.id])
	return out

func _hit_chance(p: Dictionary) -> float:
	var hit := 0.0
	for res in p.chances:
		if res != "-": hit += float(p.chances[res]) / 6.0
	return hit

func _resupply_has_choices(me: String) -> bool:
	for s in state.ships:
		if s.owner != me or not Rules.alive(s) or s.get("dummy", false): continue
		if state.scenario == "prospecting":
			if ScenProspecting.can_sell(state, s) == "" or not ScenProspecting.claim_actions(state, s).is_empty(): return true
			if ScenProspecting.can_buy(state, s, "fuel") == "": return true
		for k in ["mine", "torpedo", "nuke"]:
			if Rules.can_load(state, s, k) == "": return true
		if _matched_actions(s).size() > 0: return true
	return false

func _matched_actions(s: Dictionary) -> Array:
	var out := []
	for t in state.ships:
		if t.id == s.id or not Rules.matched(s, t): continue
		if state.scenario == "escape" and s.owner == "P2" and t.owner == "P1":
			out.append({"label": "ISPEZIONA %s" % t.name.to_upper(), "call": func(): return Scenarios.inspect(state, s.id, t.id)})
		if state.scenario == "lateral-7" and state.sd.passengers == t.id and s.owner != t.owner:
			out.append({"label": "PRENDI I PASSEGGERI", "call": func(): return Scenarios.transfer_passengers(state, t.id, s.id)})
		if state.scenario == "lateral-7" and state.sd.passengers == s.id and t.owner == s.owner:
			out.append({"label": "TRASFERISCI PASSEGGERI A %s" % t.name.to_upper(), "call": func(): return Scenarios.transfer_passengers(state, s.id, t.id)})
		if t.owner == s.owner and not s.infinite_fuel and int(s.fuel) > 0 and int(t.fuel) < int(t.max_fuel):
			out.append({"label": "CEDI 1 CARBURANTE A %s" % t.name.to_upper(), "call": func(): return Rules.transfer_fuel(state, s.id, t.id, 1)})
	return out

func _on_primary() -> void:
	if busy or state.is_empty() or state.over: return
	if state.phase == "setup": return
	if not state.pending_attack.is_empty(): return
	if state.phase == "combat" and not attackers.is_empty() and not targets.is_empty():
		_fire()
		return
	var log_n: int = state.log.size()
	var ph: String = state.phase
	mode = ""
	attackers = []; targets = []
	Rules.end_phase(state)
	_after_step(log_n)
	busy = true
	if ph == "ordnance": await _animate_moves()
	busy = false
	_refresh()
	_flow()

# ================================================================ interazione con la plancia

func _on_hex_clicked(h: Vector2i, button: int) -> void:
	if busy or state.is_empty() or state.over: return
	if button == MOUSE_BUTTON_RIGHT:
		sel = ""; mode = ""; attackers = []; targets = []
		_refresh()
		return
	var me := _active_player()
	if not _is_human(me): return
	match state.phase:
		"setup": _click_setup(h)
		"astrogation": _click_astrogation(h)
		"ordnance": _click_ordnance(h)
		"combat": _click_combat(h)
		_: _select_at(h)
	_refresh()

func _ships_at(h: Vector2i) -> Array:
	var out := []
	for s in state.ships:
		if not Rules.alive(s): continue
		if s.pos == h and s.landed == "": out.append(s)
	for s in state.ships:
		if Rules.alive(s) and s.landed != "" and s.pos == h: out.append(s)
	return out

func _select_at(h: Vector2i) -> bool:
	var here := _ships_at(h).filter(func(s): return s.owner == _active_player() and not s.get("dummy", false))
	if here.is_empty(): return false
	# clic ripetuti sullo stesso esagono scorrono la pila
	var idx := 0
	for i in range(here.size()):
		if here[i].id == sel: idx = (i + 1) % here.size()
	sel = here[idx].id
	return true

func _click_setup(h: Vector2i) -> void:
	var step: String = state.setup.get("step", "")
	if step == "deploy":
		var err0 := Fleet.place(state, h)
		if err0 != "": _toast(err0, true)
		else:
			_after_step(state.log.size())
			_flow()
		return
	if step == "designate":
		for s in _ships_at(h):
			if s.owner == "P1":
				var e1 := ScenMutiny.toggle_pick(state, s.id)
				if e1 != "": _toast(e1, true)
				return
		return
	if state.scenario == "escape":
		for s in _ships_at(h):
			if s.owner == "P1":
				var err := Scenarios.choose_fugitive(state, s.id)
				if err == "":
					_toast("Fuggitivi a bordo del %s" % s.name)
					_after_step(state.log.size() - 1)
					_flow()
				return
		return
	if state.scenario == "lateral-7":
		var err2 := Scenarios.place(state, h)
		if err2 != "": _toast(err2, true)
		else:
			_after_step(state.log.size())
			if state.phase != "setup" or _active_player() != shown_for: _flow()

func _click_astrogation(h: Vector2i) -> void:
	var s := Rules.ship(state, sel)
	# Lateral 7: scelta dei falsi bersagli da ritirare
	if not s.is_empty() and _needs_dummy_choice(s):
		for d in _ships_at(h):
			if d.get("dummy", false) and d.owner == s.owner:
				var plot: Dictionary = state.plots.get(s.id, {}).duplicate(true)
				var list: Array = plot.get("dummies", [])
				if list.has(d.id): list.erase(d.id)
				elif list.size() < 3: list.append(d.id)
				plot.dummies = list
				state.plots[s.id] = plot
				return
	if not s.is_empty() and Rules.can_plot(state, s):
		for ch in _choices(s):
			if ch.hex == h:
				var plot2: Dictionary = state.plots.get(s.id, {}).duplicate(true)
				var burns: Array = ch.burns
				if plot2.get("burns", []) == burns and not burns.is_empty(): burns = []
				plot2.burns = burns
				plot2.erase("land"); plot2.erase("takeoff")
				var err := Rules.set_plot(state, s.id, plot2)
				if err != "": _toast(err, true)
				return
	_select_at(h)

func _click_ordnance(h: Vector2i) -> void:
	var s := Rules.ship(state, sel)
	if mode == "torpedo" and not s.is_empty():
		for ch in _torpedo_choices(s):
			if ch.hex == h:
				var err := Rules.launch(state, s.id, "torpedo", ch.burns)
				if err != "": _toast(err, true)
				else:
					_append_log(state.log[-1])
					mode = ""
				return
	_select_at(h)

func _click_combat(h: Vector2i) -> void:
	var me := Rules.current_player(state)
	var here := _ships_at(h)
	var own := here.filter(func(s): return s.owner == me and Rules.can_fire(state, s) and int(s.attacked_tick) != Rules.tick(state))
	var foes := here.filter(func(s): return Rules.can_be_attacked(state, me, s) and int(s.targeted_tick) != Rules.tick(state))
	if not foes.is_empty():
		# i bersagli devono stare nello stesso esagono
		if not targets.is_empty() and Rules.ship(state, targets[0]).pos != h: targets = []
		var all_in := foes.all(func(f): return targets.has(f.id))
		if all_in: targets = []
		else:
			# aggiunge una nave alla volta
			for f in foes:
				if not targets.has(f.id): targets.append(f.id); break
		if attackers.is_empty() and not Rules.ship(state, sel).is_empty() and own.is_empty():
			var cur := Rules.ship(state, sel)
			if cur.owner == me and Rules.can_fire(state, cur): attackers = [sel]
		return
	if not own.is_empty():
		for o in own:
			if attackers.has(o.id): attackers.erase(o.id)
			else: attackers.append(o.id); sel = o.id
			break
		return
	_select_at(h)

func _on_hex_hovered(h: Vector2i) -> void:
	hover_hex = h
	_update_tip()
	if state.phase == "astrogation" or mode == "torpedo": _refresh_overlay()

func _update_tip() -> void:
	if state.is_empty() or menu.visible:
		tip.visible = false
		return
	var map := Rules.map_of(state)
	if not map.cells.has(hover_hex):
		tip.visible = false
		return
	var lines: Array = []
	if map.body_at.has(hover_hex):
		var b: Dictionary = map.body_at[hover_hex]
		var gtxt = {"full": "gravità piena", "weak": "gravità debole", "sol": "stella", "none": "asteroide-base"}[b.gravity]
		lines.append("[b]%s[/b] · %s" % [b.name.to_upper(), gtxt])
		var bases = state.bases.filter(func(x): return x.body == b.id and x.active)
		if not bases.is_empty():
			var owner: String = bases[0].owner
			var who: String = "uso libero" if owner == "all" else Rules.player(state, owner).get("name", owner)
			var extra := ""
			if not bases[0].get("fuel", true): extra = " · niente carburante"
			lines.append("%d base/i · %s%s" % [bases.size(), who, extra])
	if map.gravity.has(hover_hex):
		var names := {}
		var weak := false
		for g in map.gravity[hover_hex]:
			names[SolarMap.body(map, g.body).name] = true
			if g.weak: weak = true
		lines.append("Gravità di %s%s · %d freccia/e" % [", ".join(names.keys()), " (debole)" if weak else "", map.gravity[hover_hex].size()])
	if state.special.has(hover_hex): lines.append("[color=#8fb3ff]Asteroidi speciali di Clandestine[/color]")
	elif state.asteroids.has(hover_hex): lines.append("[color=#e0c080]Asteroidi[/color]: tiro di pericolo sopra velocità 1")
	for s in _ships_at(hover_hex):
		if s.get("dummy", false) and s.owner != board.viewer or board._concealed(s):
			lines.append("[color=#a0a8bc]Pedina coperta[/color]")
			continue
		var col := UITheme.player_color(state, s.owner).to_html(false)
		var st := "%s · %s · carb. %s · v=%d" % [ShipTypes.TYPES[s.type].name, ShipTypes.strength_label(s.type), "∞" if s.infinite_fuel else str(s.fuel), Hex.length(s.vel)]
		if s.get("dummy", false): st = "falso bersaglio"
		lines.append("[color=#%s]■[/color] [b]%s[/b]\n   %s" % [col, s.name, st])
	for o in state.ordnance:
		if o.pos == hover_hex: lines.append("%s di %s · %d turni" % [ShipTypes.ORDNANCE_NAME[o.kind], Rules.player(state, o.owner).name, Rules.ORDNANCE_LIFE - int(o.age)])
	if lines.is_empty():
		tip.visible = false
		return
	tip_text.text = "\n".join(lines)
	tip.visible = true
	var mp := get_viewport().get_mouse_position()
	tip.reset_size()
	var vs := get_viewport_rect().size
	tip.position = Vector2(minf(mp.x + 18, vs.x - tip.size.x - 8), minf(mp.y + 18, vs.y - tip.size.y - 8))

# ================================================================ scelte di spinta

func _inertial(s: Dictionary) -> Dictionary:
	var map := Rules.map_of(state)
	return Rules.simulate(map, s.pos, s.vel, s.grav, Vector2i.ZERO, state.plots.get(s.id, {}).get("weak", false), state.asteroids, state.special, s.access_special)

func _choices(s: Dictionary) -> Array:
	if s.landed != "" or Rules.is_disabled(state, s) or s.get("locked", false): return []
	var map := Rules.map_of(state)
	var base_end: Vector2i = s.pos + s.vel + Rules.pending_sum(s)
	var cur: Array = state.plots.get(s.id, {}).get("burns", [])
	var out := []
	var fuel_ok: bool = s.infinite_fuel or int(s.fuel) >= 1
	var weak: bool = state.plots.get(s.id, {}).get("weak", false)
	var add := func(burns: Array, kind: String) -> void:
		var r := Rules.simulate(map, s.pos, s.vel, s.grav, Rules.burn_vector(burns), weak, state.asteroids, state.special, s.access_special)
		out.append({"hex": s.pos + r.vel, "burns": burns, "kind": kind, "picked": cur == burns,
			"danger": r.crash != "" or r.offmap or r.special, "hover": s.pos + r.vel == hover_hex})
	add.call([], "drift")
	if fuel_ok:
		for d in range(6): add.call([d], "burn")
	if cur.size() >= 1 and Rules.can_overload(state, s):
		var first: int = int(cur[0])
		for d in range(6):
			if d == (first + 3) % 6: continue
			var hex: Vector2i = base_end + Hex.DIRS[first] + Hex.DIRS[d]
			if out.any(func(c): return c.hex == hex): continue
			add.call([first, d], "overload")
	return out

func _torpedo_choices(s: Dictionary) -> Array:
	var map := Rules.map_of(state)
	var out := []
	var seen := {}
	for d1 in range(6):
		for d2 in [-1, 0, 1, 2, 3, 4, 5]:
			var burns: Array = [d1] if d2 < 0 else [d1, d2]
			if d2 >= 0 and d2 == (d1 + 3) % 6: continue
			var r := Rules.simulate(map, s.pos, s.vel, s.grav, Rules.burn_vector(burns), false, [], [], true)
			var hex: Vector2i = s.pos + r.vel
			if seen.has(hex) or hex == s.pos + s.vel + Rules.pending_sum(s): continue
			seen[hex] = true
			out.append({"hex": hex, "burns": burns, "kind": "burn" if burns.size() == 1 else "overload", "picked": false, "hover": hex == hover_hex})
	return out

func _needs_dummy_choice(s: Dictionary) -> bool:
	if state.scenario != "lateral-7" or not s.get("first_burn_pending", false): return false
	if state.plots.get(s.id, {}).get("burns", []).is_empty(): return false
	return state.ships.any(func(d): return d.get("dummy", false) and d.owner == s.owner and Rules.alive(d))

# ================================================================ aggiornamento dell'interfaccia

func _refresh() -> void:
	if state.is_empty(): return
	board.state = state
	board.selected = sel
	_refresh_top()
	_refresh_side()
	_refresh_bottom()
	_refresh_overlay()

func _refresh_overlay() -> void:
	var ov := {}
	var me := _active_player()
	var human := _is_human(me)
	if state.phase == "astrogation" and human:
		var preds := {}
		for s in state.ships:
			if s.owner != me or not Rules.alive(s) or s.get("dummy", false): continue
			if s.landed != "" and not state.plots.get(s.id, {}).get("takeoff", false): continue
			preds[s.id] = Rules.predict(state, s, state.plots.get(s.id, {}))
		ov.predictions = preds
		var s2 := Rules.ship(state, sel)
		if not s2.is_empty() and s2.owner == me: ov.choices = _choices(s2)
		if not s2.is_empty() and _needs_dummy_choice(s2):
			ov.mark_hexes = state.ships.filter(func(d): return d.get("dummy", false) and d.owner == me and Rules.alive(d) and state.plots.get(s2.id, {}).get("dummies", []).has(d.id)).map(func(d): return d.pos)
	elif state.phase == "ordnance" and human and mode == "torpedo":
		var s3 := Rules.ship(state, sel)
		if not s3.is_empty(): ov.choices = _torpedo_choices(s3)
	elif state.phase == "combat" and human and state.pending_attack.is_empty():
		ov.attackers = attackers.duplicate()
		ov.targets_sel = targets.duplicate()
		var tg := []
		for pair in _possible_attacks(me):
			if not tg.has(pair[1]): tg.append(pair[1])
		ov.targetable = tg
	elif state.phase == "setup" and human and state.setup.get("step", "") == "deploy":
		ov.place_hexes = Fleet.spots(state).keys()
		ov.pulse = true
	elif state.phase == "setup" and human and state.setup.get("step", "") == "designate":
		ov.attackers = state.setup.picks.duplicate()
		ov.targetable = state.ships.filter(func(x): return x.owner == "P1" and Rules.alive(x)).map(func(x): return x.id)
	elif state.phase == "setup" and human and state.scenario == "lateral-7":
		ov.place_hexes = state.asteroids.filter(func(h): return Scenarios.can_place(state, h))
		ov.pulse = true
	board.overlay = ov
	board.queue_redraw()

func _refresh_top() -> void:
	var info := Scenarios.info(state.scenario)
	top_scenario.text = "%s%s" % [info.title.to_upper(), (" · " + info.year) if info.year != "" else ""]
	top_day.text = "GIORNO %d" % int(state.turn)
	var cur := PHASE_ORDER.find(state.phase)
	for i in range(phase_pills.size()):
		var pill: PanelContainer = phase_pills[i]
		var l: Label = pill.get_child(0)
		if i == cur:
			pill.add_theme_stylebox_override("panel", UITheme.box(Color("ff7a2f"), Color("ffb27a"), 4, 1, 7))
			l.add_theme_color_override("font_color", Color("1a0c04"))
		elif i < cur:
			pill.add_theme_stylebox_override("panel", UITheme.box(Color("12244a"), UITheme.LINE, 4, 1, 7))
			l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		else:
			pill.add_theme_stylebox_override("panel", UITheme.box(Color("0a1530"), Color("16284d"), 4, 1, 7))
			l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	var who := _active_player()
	var p := Rules.player(state, who)
	var col := UITheme.player_color(state, who)
	player_dot.add_theme_stylebox_override("panel", UITheme.box(col, col.lightened(0.4), 8, 1, 0))
	var role: String = p.get("side", "")
	var nm: String = p.get("name", "")
	player_label.text = "%s%s%s" % [nm, (" · " + role) if role != "" and role != "Pilota" and role != nm else "", "  (IA)" if p.get("type", "") == "ai" else ""]
	player_chip.add_theme_stylebox_override("panel", UITheme.box(Color(col, 0.16), col, 20, 1, 8))
	if state.phase == "setup":
		top_day.text = {"shop": "ACQUISTI", "deploy": "SCHIERAMENTO", "choose": "PREPARAZIONE", "designate": "AMMUTINAMENTO"}.get(state.setup.get("step", ""), "SCHIERAMENTO")

func _clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()

func _refresh_side() -> void:
	_clear(objective_box); _clear(fleet_box); _clear(detail_box); _clear(actions)
	var me := _active_player()
	var view := board.viewer if board.viewer != "" else me
	_build_objectives(view)
	var mine: Array = state.ships.filter(func(s): return s.owner == view and not s.get("dummy", false) and not s.get("retired", false) and (Rules.alive(s) or s.destroyed))
	if mine.is_empty():
		fleet_box.add_child(UITheme.label("Nessuna nave in gioco.", 15, UITheme.TEXT_DIM))
	for s in mine:
		fleet_box.add_child(_ship_card(s))
	var dummies = state.ships.filter(func(s): return s.owner == view and s.get("dummy", false) and Rules.alive(s)).size()
	if dummies > 0:
		fleet_box.add_child(UITheme.label("+ %d falsi bersagli nella Fascia" % dummies, 14, UITheme.TEXT_DIM))
	var s2 := Rules.ship(state, sel)
	if not s2.is_empty(): _build_detail(s2)
	if _is_human(me) and not busy: _build_actions(me)

func _build_objectives(view: String) -> void:
	match state.scenario:
		"grand-tour":
			objective_box.add_child(UITheme.caption("Grand Tour · tappe"))
			var mine: Array = state.ships.filter(func(s): return s.owner == view)
			if mine.is_empty(): return
			var s: Dictionary = mine[0]
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			var map := Rules.map_of(state)
			for item in Scenarios.grand_tour_progress(state, s):
				var b := SolarMap.body(map, item.id)
				var nxt: bool = item.get("next", false)
				var chip := _panel(Color(b.color, 0.28) if item.done else Color("0a1530"), Color(b.color) if item.done else (UITheme.ACCENT if nxt else UITheme.LINE), 4, 5)
				var prefix: String = "✓ " if item.done else (("%d. " % item.n) if item.has("n") else "")
				var l := UITheme.label(prefix + b.name, 14, UITheme.TEXT if item.done else (UITheme.ACCENT if nxt else UITheme.TEXT_FAINT), UITheme.body_bold)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				chip.add_child(l)
				chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(chip)
			objective_box.add_child(grid)
			var left := Scenarios.gt_missing(state, s)
			var msg := "Rientra e atterra sulla Terra!" if left.is_empty() else ("Rotta obbligata: prossima tappa %s" % SolarMap.body(map, left[0]).name if state.sd.has("route") else "%d di %d corpi visitati" % [state.sd.required.size() - left.size(), state.sd.required.size()])
			objective_box.add_child(UITheme.label(msg, 14, UITheme.PHOSPHOR if left.is_empty() else UITheme.TEXT_DIM))
		"escape":
			objective_box.add_child(UITheme.caption("Escape"))
			var txt := ""
			if view == "P1":
				var f := Rules.ship(state, state.sd.get("fugitive", ""))
				txt = "Fuggitivi a bordo: [b]%s[/b]. Esci dal bordo di Giove (a destra) con carburante ≥ velocità + 1." % (f.name if not f.is_empty() else "da scegliere")
			else:
				txt = "Uno dei tre trasporti porta i fuggitivi. Disabilitalo, accoppia la rotta e ispezionalo; poi riportalo a una base."
				if not state.sd.inspected.is_empty(): txt += "\nIspezionati: " + ", ".join(state.sd.inspected.map(func(id): return Rules.ship(state, id).name))
			objective_box.add_child(_rich(txt, 15))
		"lateral-7":
			objective_box.add_child(UITheme.caption("Lateral 7"))
			var holder := Rules.ship(state, state.sd.passengers)
			var t2 := ""
			if view == "P1": t2 = "Disabilita la nave di linea, accoppia la rotta e prendi i passeggeri; poi fermati a Clandestine."
			else: t2 = "Porta la nave di linea in un campo di gravità di Ganimede. Il Tycho Brahe si muove solo dopo aver rilevato un pirata."
			t2 += "\nPasseggeri: [b]%s[/b]" % (holder.name if not holder.is_empty() and Rules.is_known(state, view, holder) else "nave sconosciuta")
			objective_box.add_child(_rich(t2, 15))
		_:
			_objectives_extra(view)

func _objectives_extra(view: String) -> void:
	var map := Rules.map_of(state)
	match state.scenario:
		"nova":
			objective_box.add_child(UITheme.caption("Nova"))
			var aliens: Array = state.ships.filter(func(x): return x.owner == "P3")
			var alive_n := aliens.filter(func(x): return Rules.alive(x)).size()
			var txt := ""
			if view == "P3": txt = "Porta un corsaro in [b]orbita attorno al Sole[/b] (velocità 1 fra due esagoni di gravità solare, senza spinta)."
			else: txt = "Distruggi l'ultima nave aliena prima che entri in orbita attorno al Sole. Vince chi la abbatte."
			if not state.sd.colony.is_empty():
				txt += "\nColonie: WestBloc a [b]%s[/b], EastBloc a [b]%s[/b]." % [SolarMap.body(map, state.sd.colony.P1).name, SolarMap.body(map, state.sd.colony.P2).name]
			if not aliens.is_empty(): txt += "\nNavi aliene in gioco: [b]%d / 4[/b]" % alive_n
			objective_box.add_child(_rich(txt, 15))
		"retribution":
			objective_box.add_child(UITheme.caption("Retribution"))
			var sd: Dictionary = state.sd
			var t2 := "Corvette partite: [b]%d / 10[/b] · a Clandestine: [b]%d[/b] · schiantate sulla Terra: [b]%d[/b]" % [int(sd.spawned), ScenRetribution.parked(state).size(), int(sd.terra_hits)]
			if sd.formed: t2 = "La [b]Flotta della Libertà[/b] è in campo."
			if view == "P1": t2 += "\nObiettivo: distruggere la flotta Enforcer."
			else:
				t2 += "\nObiettivo: sopravvivere e schiacciare la ribellione."
				if not sd.patrol.is_empty() and not sd.formed: t2 += "\nIn Security Patrol: %s" % ", ".join(sd.patrol.map(func(id): return Rules.ship(state, id).name))
			if int(sd.enf_grounded) > 0: t2 += "\n[color=#ffc94a]Enforcers a terra da %d turni (12 = sconfitta)[/color]" % int(sd.enf_grounded)
			if int(sd.reb_grounded) > 0: t2 += "\n[color=#ffc94a]Ribelli a terra da %d turni (12 = sconfitta)[/color]" % int(sd.reb_grounded)
			objective_box.add_child(_rich(t2, 15))
		"fleet-mutiny":
			objective_box.add_child(UITheme.caption("The Fleet Mutiny"))
			var n := ScenMutiny.terra_suppressed(state)
			var t3 := "Lati della Terra soppressi: [b]%d / 6[/b]" % n
			t3 += "\nRibelli: ne bastano 4. Impero: elimina tutti i ribelli con meno di 3 lati soppressi."
			t3 += "\nPer sopprimere: nave in orbita sopra il lato, in fase di combattimento."
			objective_box.add_child(_rich(t3, 15))
		"interplanetary-war":
			objective_box.add_child(UITheme.caption("Interplanetary War"))
			var t4 := "Lati devastati: Terra [b]%d[/b] · Luna [b]%d[/b]" % [ScenWar.devastated(state, "terra"), ScenWar.devastated(state, "luna")]
			if view == "P1":
				t4 += "\nCrediti: Terra [b]%s[/b] · Luna %s · Venere %s (da portare con navi commerciali)" % [Fleet.fmt_mcr(state.sd.pool.terra), Fleet.fmt_mcr(state.sd.pool.luna), Fleet.fmt_mcr(state.sd.pool.venus)]
			else:
				t4 += "\nCrediti ribelli: [b]%s MCr[/b]" % Fleet.fmt_mcr(state.sd.mcr.P2)
			var hw: String = ScenWar.home(view)
			if state.sd.stock.has(hw):
				var stk: Dictionary = state.sd.stock[hw]
				t4 += "\nDeposito di %s: %d mine, %d siluri, %d testate" % [SolarMap.body(map, hw).name, int(stk.mine), int(stk.torpedo), int(stk.nuke)]
			objective_box.add_child(_rich(t4, 15))
		"prospecting":
			objective_box.add_child(UITheme.caption("Prospecting · giorno %d di %d" % [int(state.turn), int(state.sd.length)]))
			var lines := []
			for p in state.players:
				var col := UITheme.player_color(state, p.id).to_html(false)
				lines.append("[color=#%s]■[/color] %s: [b]%s MCr[/b]" % [col, p.name, Fleet.fmt_mcr(state.sd.mcr.get(p.id, 0.0))])
			var mine_claims := 0
			for k in state.sd.claims:
				if state.sd.claims[k].owner == view: mine_claims += 1
			lines.append("Asteroidi prospettati: %d · tue concessioni: %d" % [state.sd.prospected.size(), mine_claims])
			objective_box.add_child(_rich("\n".join(lines), 15))

func _rich(text: String, size := 16) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _ship_card(s: Dictionary) -> Control:
	var col := UITheme.player_color(state, s.owner)
	var is_sel: bool = s.id == sel
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal_box := UITheme.box(Color("0c1a38") if not is_sel else Color(col, 0.22), col if is_sel else UITheme.LINE, 6, 2 if is_sel else 1, 8)
	card.add_theme_stylebox_override("panel", normal_box)
	card.mouse_entered.connect(func(): if not is_sel: card.add_theme_stylebox_override("panel", UITheme.box(Color("12244a"), col, 6, 1, 8)))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", normal_box))
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			sel = s.id
			if s.landed == "" and Rules.alive(s): board.center_on(s.pos)
			_refresh())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var icon := ShipIcon.new()
	icon.type = s.type; icon.color = col; icon.custom_minimum_size = Vector2(38, 38)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var name_l := UITheme.label(s.name, 16, UITheme.TEXT if Rules.alive(s) else UITheme.TEXT_FAINT, UITheme.body_bold)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var status := _ship_status(s)
	var st_l := UITheme.label(status[0], 14, status[1])
	st_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(st_l)
	var fuel := FuelBar.new()
	fuel.value = 1.0 if s.infinite_fuel else float(s.fuel) / maxf(1.0, float(s.max_fuel))
	fuel.text = "∞" if s.infinite_fuel else str(s.fuel)
	fuel.custom_minimum_size = Vector2(46, 34)
	fuel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fuel)
	return card

func _ship_status(s: Dictionary) -> Array:
	if s.destroyed: return ["Perduta: " + s.reason, UITheme.DANGER]
	if s.escaped: return ["In fuga oltre Giove", UITheme.GOOD]
	if s.get("captured", false): return ["Catturata", UITheme.DANGER]
	var parts := []
	var col := UITheme.TEXT_DIM
	var dt := Rules.disabled_turns(state, s)
	if dt > 0: parts.append("Disabilitata %d" % dt); col = UITheme.DANGER
	if s.landed != "": parts.append("A terra · " + SolarMap.body(Rules.map_of(state), s.landed).name)
	else:
		var ob := Rules.orbit_body(state, s)
		if ob != "": parts.append("In orbita · " + SolarMap.body(Rules.map_of(state), ob).name)
		else: parts.append("Velocità %d" % Hex.length(s.vel))
	if state.phase == "astrogation" and s.owner == _active_player():
		var plot: Dictionary = state.plots.get(s.id, {})
		if plot.get("takeoff", false): parts.append("DECOLLO")
		elif int(plot.get("land", -1)) >= 0: parts.append("ATTERRAGGIO")
		elif not plot.get("burns", []).is_empty(): parts.append("spinta ×%d" % plot.burns.size()); col = UITheme.ACCENT_SOFT
	if s.heroic: parts.append("eroica")
	return [" · ".join(parts), col]

func _build_detail(s: Dictionary) -> void:
	if board._concealed(s) or s.get("dummy", false): return
	detail_box.add_child(UITheme.caption("Nave selezionata"))
	var col := UITheme.player_color(state, s.owner)
	var t: Dictionary = ShipTypes.TYPES[s.type]
	var cargo := ShipTypes.cargo_used(s)
	var inv := []
	for k in ["mine", "torpedo", "nuke"]:
		if int(s.inv.get(k, 0)) > 0: inv.append("%d %s" % [s.inv[k], ShipTypes.ORDNANCE_NAME[k].to_lower()])
	var lines := [
		"[font_size=19][b][color=#%s]%s[/color][/b][/font_size]" % [col.to_html(false), s.name],
		"%s · forza [b]%s[/b]%s" % [t.name, ShipTypes.strength_label(s.type), " · commerciale" if s.commercial else ""],
		"Carburante [b]%s[/b] · stiva %s" % ["∞" if s.infinite_fuel else "%d/%d" % [s.fuel, s.max_fuel], "illimitata" if int(s.cargo) > 1000 else "%d/%d t" % [int(ceilf(cargo)), int(s.cargo)]],
		"Vettore [b]%d[/b] · gravità in arrivo [b]%d[/b] · sovraccarico %s" % [Hex.length(s.vel), s.grav.size(), "pronto" if Rules.can_overload(state, s) else ("no" if s.commercial else "usato")],
	]
	for k in ["automated_mine", "robot_guards", "pm_grapples", "ct_shard"]:
		if int(s.inv.get(k, 0)) > 0: inv.append("%d %s" % [s.inv[k], ShipTypes.ITEM_NAME[k].to_lower()])
	if int(s.get("ore10", 0)) > 0: inv.append("%.1f t di minerale" % (int(s.ore10) / 10.0))
	if float(s.get("mcr", 0.0)) > 0.0: inv.append("%s MCr" % Fleet.fmt_mcr(s.mcr))
	if not inv.is_empty(): lines.append("A bordo: " + ", ".join(inv))
	if s.get("is_base", false): lines.append("[color=#9aa7c2]Base orbitale: rifornisce le navi che accoppiano la rotta e lancia un siluro per turno.[/color]")
	if state.scenario == "retribution" and ScenRetribution.on_patrol(state, s): lines.append("[color=#ffc94a]Terran Security Patrol: resta entro 5 esagoni da Terra o Luna[/color]")
	if s.get("parked", false): lines.append("[color=#5be38f]Missione compiuta: attende la Flotta della Libertà[/color]")
	if state.scenario == "escape" and s.owner == "P1" and board.viewer == "P1" and state.sd.get("fugitive", "") == s.id:
		lines.append("[color=#5be38f]★ Porta i fuggitivi[/color]")
	if state.scenario == "escape" and state.sd.get("inspected", []).has(s.id):
		lines.append("[color=#7fe0ee]Ispezionato: %s[/color]" % ("fuggitivi!" if state.sd.fugitive == s.id else "esca"))
	if s.get("locked", false): lines.append("[color=#ffc94a]Bloccato fino al rilevamento di un pirata[/color]")
	detail_box.add_child(_rich("\n".join(lines), 15))

func _action_button(text: String, enabled := true, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(0, 38)
	actions.add_child(b)
	return b

func _build_actions(me: String) -> void:
	var s := Rules.ship(state, sel)
	match state.phase:
		"setup":
			if not (state.scenario in ["escape", "lateral-7"]):
				_build_setup_actions(me)
			elif state.scenario == "escape":
				actions.add_child(_rich("Clicca in segreto sul trasporto che porta i [b]fuggitivi[/b] (sulla Terra).", 16))
				for t in state.ships.filter(func(x): return x.owner == "P1"):
					var b := _action_button("FUGGITIVI SUL %s" % t.name.to_upper())
					b.pressed.connect(func():
						Scenarios.choose_fugitive(state, t.id)
						_after_step(state.log.size() - 1)
						_refresh(); _flow())
			elif state.scenario == "lateral-7":
				var unit := Scenarios.next_placement(state)
				if not unit.is_empty():
					var what: String = "falso bersaglio" if unit[1] == "dummy" else unit[2]
					var left: int = state.sd.queue[me].size()
					actions.add_child(_rich("Colloca: [b]%s[/b]\nClicca un esagono di asteroidi libero (evidenziato). Ne restano %d." % [what, left], 16))
					var auto := _action_button("SCHIERAMENTO AUTOMATICO")
					auto.pressed.connect(func():
						var n: int = state.log.size()
						Scenarios.auto_place(state)
						_after_step(n)
						_refresh(); _flow())
		"astrogation":
			_build_scenario_commands(me)
			if s.is_empty() or s.owner != me or not Rules.alive(s):
				actions.add_child(_rich("Seleziona una nave (sulla plancia o nella flotta) per tracciarne la rotta.", 15))
				return
			_build_astrogation_actions(s)
		"ordnance":
			if s.is_empty() or s.owner != me:
				actions.add_child(_rich("Seleziona una nave armata per lanciare un ordigno, oppure conferma.", 15))
				return
			for k in ["mine", "torpedo", "nuke"]:
				if int(s.inv.get(k, 0)) <= 0: continue
				var err := Rules.can_launch(state, s, k)
				var b2 := _action_button("LANCIA %s (%d)" % [ShipTypes.ORDNANCE_NAME[k].to_upper(), s.inv[k]], err == "", err)
				if k == "torpedo":
					b2.pressed.connect(func(): mode = "torpedo"; _refresh(); _toast("Scegli dove spingere il siluro (1 o 2 esagoni)"))
				else:
					b2.pressed.connect(func():
						var e2 := Rules.launch(state, s.id, k)
						if e2 != "": _toast(e2, true)
						else: _append_log(state.log[-1])
						_refresh())
			if mode == "torpedo":
				actions.add_child(_rich("Clicca un esagono evidenziato: il siluro eredita il vettore della nave e accelera di 1 o 2.", 15))
				var c := _action_button("ANNULLA")
				c.pressed.connect(func(): mode = ""; _refresh())
		"combat":
			if not state.pending_attack.is_empty():
				return
			if state.scenario == "fleet-mutiny" and not s.is_empty() and s.owner == me:
				var tg := ScenMutiny.suppress_target(state, s)
				if not tg.is_empty():
					var sb := UITheme.primary_button("SOPPRIMI IL LATO %d DI %s" % [int(tg.side) + 1, String(tg.name).to_upper()])
					sb.custom_minimum_size = Vector2(0, 44)
					sb.tooltip_text = "La nave in orbita usa il suo fuoco per neutralizzare quel lato del pianeta: niente altri attacchi in questa fase."
					sb.pressed.connect(func():
						var n = state.log.size()
						var e := ScenMutiny.suppress(state, s.id)
						if e != "": _toast(e, true)
						_after_step(n)
						_refresh()
						if state.over: _show_victory())
					actions.add_child(sb)
			actions.add_child(_rich("Clicca le tue navi per formare il gruppo d'attacco, poi i bersagli nemici nello stesso esagono.", 15))
			if not attackers.is_empty() and not targets.is_empty():
				var a_list: Array = attackers.map(func(id): return Rules.ship(state, id))
				var t_list: Array = targets.map(func(id): return Rules.ship(state, id))
				var p := Rules.attack_preview(state, a_list, t_list)
				actions.add_child(_odds_panel(p))
				var fire := UITheme.primary_button("APRI IL FUOCO")
				fire.custom_minimum_size = Vector2(0, 44)
				fire.pressed.connect(_fire)
				actions.add_child(fire)
				var clr := _action_button("ANNULLA SELEZIONE")
				clr.pressed.connect(func(): attackers = []; targets = []; _refresh())
		"resupply":
			_build_scenario_commands(me)
			if s.is_empty() or s.owner != me:
				actions.add_child(_rich("Le navi in base o in orbita sopra una base amica si riforniscono a fine fase.", 15))
				return
			var b0 := Rules.docked_base(state, s)
			if not b0.is_empty():
				actions.add_child(_rich("Accoppiata con: [b]%s[/b]." % Rules.base_name(state, b0), 15))
			if state.scenario == "prospecting": _build_prospect_actions(s)
			for k in ["mine", "torpedo", "nuke"]:
				var err3 := Rules.can_load(state, s, k)
				if err3 == "" or int(s.inv.get(k, 0)) > 0 and not b0.is_empty():
					var row := HBoxContainer.new()
					var lbl := UITheme.label("%s: %d" % [ShipTypes.ORDNANCE_NAME[k], s.inv.get(k, 0)], 16)
					lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					row.add_child(lbl)
					var minus := Button.new(); minus.text = "−"; minus.custom_minimum_size = Vector2(36, 32)
					minus.pressed.connect(func(): Rules.unload_ordnance(state, s.id, k); _refresh())
					var plus := Button.new(); plus.text = "+"; plus.custom_minimum_size = Vector2(36, 32); plus.disabled = err3 != ""
					plus.pressed.connect(func(): Rules.load_ordnance(state, s.id, k); _refresh())
					row.add_child(minus); row.add_child(plus)
					actions.add_child(row)
			for act in _matched_actions(s):
				var ab := _action_button(act.label)
				ab.pressed.connect(func():
					var n = state.log.size()
					var e4: String = act.call.call()
					if e4 != "": _toast(e4, true)
					_after_step(n)
					_refresh()
					if state.over: _show_victory())
			if state.rules.get("surrender", false) and not s.surrendered and not s.get("patrol", false) and s.commercial:
				var sb := _action_button("ARRENDITI")
				sb.tooltip_text = "La nave si arrende: il nemico può saccheggiarla senza disabilitarla."
				sb.pressed.connect(func(): Rules.surrender(state, s.id); _append_log(state.log[-1]); _refresh())

# ---------------------------------------------------------------- preparazione degli scenari con acquisti

func _setup_done() -> void:
	_after_step(state.log.size())
	_refresh()
	_flow()

func _build_setup_actions(me: String) -> void:
	var st: Dictionary = state.setup
	var title := UITheme.label(String(st.get("title", "Preparazione")).to_upper(), 17, UITheme.ACCENT, UITheme.display)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(200, 0)
	actions.add_child(title)
	match st.get("step", ""):
		"choose":
			actions.add_child(_rich(st.get("prompt", ""), 16))
			for o in st.options:
				var b := _action_button(String(o.label).to_upper())
				b.pressed.connect(func():
					var err := Scenarios.choose(state, o.value)
					if err != "": _toast(err, true)
					_setup_done())
		"shop": _build_shop(st)
		"deploy":
			var unit := Fleet.current_unit(state)
			if unit.is_empty(): return
			var nm: String = unit.get("name", ShipTypes.TYPES[unit.type].name)
			actions.add_child(_rich("Colloca: [b]%s[/b] (%d da schierare)\nClicca un esagono evidenziato in verde." % [nm, st.queue.size()], 16))
			var spots := Fleet.spots(state)
			var edge: bool = spots.values().any(func(v): return v.mode == "edge")
			var orbit: bool = spots.values().any(func(v): return v.mode == "orbit")
			if edge or orbit:
				var label := ("INGRESSO: %s" % ("DIRITTO" if st.get("ccw", true) else "OBLIQUO")) if edge else ("ORBITA: %s" % ("ANTIORARIA" if st.get("ccw", true) else "ORARIA"))
				var dir := _action_button(label)
				dir.pressed.connect(func(): st.ccw = not st.get("ccw", true); _refresh())
			var auto := _action_button("SCHIERAMENTO AUTOMATICO")
			auto.pressed.connect(func():
				Fleet.auto_deploy(state)
				_setup_done())
		"designate":
			actions.add_child(_rich(st.get("prompt", ""), 15))
			actions.add_child(_rich("Designate: [b]%d / 5[/b] — clicca le unità imperiali sulla plancia." % st.picks.size(), 16))
			for id in st.picks:
				var pk := Rules.ship(state, id)
				actions.add_child(UITheme.label("• " + ("Unità coperta" if board._concealed(pk) else pk.name), 15, UITheme.ACCENT_SOFT))
			var go := UITheme.primary_button("SCATENA L'AMMUTINAMENTO")
			go.custom_minimum_size = Vector2(0, 44)
			go.disabled = st.picks.is_empty()
			go.pressed.connect(func():
				var err := ScenMutiny.confirm_picks(state)
				if err != "": _toast(err, true)
				_setup_done())
			actions.add_child(go)

func _build_shop(st: Dictionary) -> void:
	if st.get("note", "") != "": actions.add_child(_rich("[color=#9aa7c2]%s[/color]" % st.note, 14))
	var unlimited: bool = float(st.budget) > 5000.0
	var spent := Fleet.cart_cost(st)
	var left := float(st.budget) - spent
	var budget_txt := "Spesi [b]%s[/b] · restano [b]%s[/b]" % [Fleet.money_text(spent, st.currency), Fleet.money_text(left, st.currency)]
	if unlimited: budget_txt = "Navi scelte: [b]%d / %d[/b]" % [Fleet.cart_ships(st), int(st.max_ships)]
	actions.add_child(_rich(budget_txt, 17))
	for item in st.items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := ""
		if Fleet.is_ship(item):
			var tdef: Dictionary = ShipTypes.TYPES[item]
			info = " [color=#9aa7c2]%s · carb. %s · stiva %s[/color]" % [ShipTypes.strength_label(item), "∞" if int(tdef.fuel) < 0 else str(tdef.fuel), "∞" if int(tdef.cargo) > 1000 else str(tdef.cargo)]
		var price_txt := "" if unlimited else Fleet.money_text(Fleet.price(st.currency, item), st.currency)
		var lbl := _rich("[b]%s[/b]%s\n[color=#ff9a5c]%s[/color]" % [Fleet.item_name(item), info, price_txt], 14)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var minus := Button.new(); minus.text = "−"; minus.custom_minimum_size = Vector2(32, 32)
		minus.disabled = int(st.cart.get(item, 0)) == 0
		minus.pressed.connect(func(): Fleet.remove(state, item); _refresh())
		row.add_child(minus)
		var cnt := UITheme.label(str(int(st.cart.get(item, 0))), 18, UITheme.TEXT, UITheme.mono)
		cnt.custom_minimum_size = Vector2(26, 0)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(cnt)
		var plus := Button.new(); plus.text = "+"; plus.custom_minimum_size = Vector2(32, 32)
		var why := Fleet.can_add(state, item)
		plus.disabled = why != ""
		plus.tooltip_text = why
		plus.pressed.connect(func():
			var e := Fleet.add(state, item)
			if e != "": _toast(e, true)
			_refresh())
		row.add_child(plus)
		actions.add_child(row)
	var ok := UITheme.primary_button("CONFERMA ACQUISTI")
	ok.custom_minimum_size = Vector2(0, 46)
	ok.pressed.connect(func():
		var err := Fleet.confirm_shop(state)
		if err != "": _toast(err, true)
		else: _setup_done())
	actions.add_child(ok)
	if Scenarios.can_cancel_shop(state):
		var cancel := _action_button("CHIUDI IL CANTIERE")
		cancel.pressed.connect(func(): Scenarios.cancel_shop(state); _refresh())

func _build_astrogation_actions(s: Dictionary) -> void:
	if s.landed != "":
		var plot: Dictionary = state.plots.get(s.id, {})
		var can := Rules.can_take_off(state, s)
		if _finished(s):
			actions.add_child(_rich("[color=#5be38f]Grand Tour completato![/color]", 16))
			return
		var b := _action_button("ANNULLA DECOLLO" if plot.get("takeoff", false) else "DECOLLA CON IL BOOSTER", can, "" if can else "Serve una base amica sul lato di atterraggio")
		b.pressed.connect(func():
			var np := {} if plot.get("takeoff", false) else {"takeoff": true}
			var err := Rules.set_plot(state, s.id, np)
			if err != "": _toast(err, true)
			_refresh())
		actions.add_child(_rich("Il booster porta la nave ferma nell'esagono di gravità sopra la base: al turno dopo [b]deve[/b] accendere i motori o ricade.", 14))
		return
	if Rules.is_disabled(state, s):
		actions.add_child(_rich("[color=#ff6070]Disabilitata[/color]: va alla deriva per %d turni." % Rules.disabled_turns(state, s), 15))
		return
	if s.get("locked", false):
		actions.add_child(_rich("Il dreadnought resta fermo finché un pirata non viene rilevato.", 15))
		return
	var plot2: Dictionary = state.plots.get(s.id, {})
	actions.add_child(_rich("Clicca un esagono [color=#49d3e6]azzurro[/color] attorno al punto d'arrivo per spendere 1 carburante; il centro è la deriva.%s" % (" Dopo la prima spinta compaiono gli esagoni [color=#ff9a5c]arancio[/color] del sovraccarico." if Rules.can_overload(state, s) else ""), 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	actions.add_child(row)
	var drift := Button.new(); drift.text = "DERIVA"; drift.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drift.tooltip_text = "Nessuna spinta (barra spaziatrice)"
	drift.pressed.connect(func(): Rules.set_plot(state, s.id, {"burns": [], "weak": plot2.get("weak", false)}); _refresh())
	row.add_child(drift)
	var nxt := Button.new(); nxt.text = "PROSSIMA ▸"; nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nxt.tooltip_text = "Seleziona la nave successiva (Tab)"
	nxt.pressed.connect(_select_next)
	row.add_child(nxt)
	var sides := Rules.landing_sides(state, s)
	if not sides.is_empty():
		var landing := int(plot2.get("land", -1)) >= 0
		var lb := _action_button("ANNULLA ATTERRAGGIO" if landing else "ATTERRA (1 carburante)")
		lb.pressed.connect(func():
			var err := Rules.set_plot(state, s.id, {} if landing else {"land": sides[0]})
			if err != "": _toast(err, true)
			_refresh())
	# gravità debole sul percorso
	var pr := Rules.predict(state, s, plot2)
	var map := Rules.map_of(state)
	var weak_on_path := false
	for h in pr.get("path", []):
		if map.gravity.has(h) and map.gravity[h].any(func(g): return g.weak): weak_on_path = true
	if weak_on_path or plot2.get("weak", false):
		var cb := CheckBox.new()
		cb.text = "Usa la prima freccia debole (Luna/Io/Europa)"
		cb.button_pressed = plot2.get("weak", false)
		cb.toggled.connect(func(on):
			var np2: Dictionary = state.plots.get(s.id, {}).duplicate(true)
			np2.weak = on
			Rules.set_plot(state, s.id, np2)
			_refresh())
		actions.add_child(cb)
	for tid in Rules.ram_candidates(state, s, pr):
		var t := Rules.ship(state, tid)
		var on: bool = plot2.get("ram", "") == tid
		var rb := _action_button(("✓ " if on else "") + "SPERONA %s" % (t.name.to_upper() if Rules.is_known(state, s.owner, t) else "LA PEDINA"))
		rb.tooltip_text = "Colonna Speronamento: il risultato si applica a entrambe le navi"
		rb.pressed.connect(func():
			var np3: Dictionary = state.plots.get(s.id, {}).duplicate(true)
			np3.ram = "" if on else tid
			Rules.set_plot(state, s.id, np3)
			_refresh())
	if _needs_dummy_choice(s):
		var chosen: Array = plot2.get("dummies", [])
		actions.add_child(_rich("[color=#ffc94a]Prima accensione:[/color] scegli sulla plancia 3 tuoi falsi bersagli da ritirare (%d/3). Se non scegli, li ritiro io." % chosen.size(), 14))
	# avvisi sulla rotta
	if pr.get("crash", "") != "": actions.add_child(_rich("[color=#ff4d5e]⚠ Rotta di collisione con %s![/color]" % SolarMap.body(map, pr.crash).name, 16))
	elif pr.get("offmap", false):
		var esc: bool = state.scenario == "escape" and s.owner == "P1" and pr.dest.y < 0
		actions.add_child(_rich("[color=%s]%s[/color]" % ["#5be38f" if esc else "#ff4d5e", "Uscita oltre Giove: fuga!" if esc else "⚠ La rotta esce dalla plancia: nave perduta."], 16))
	elif pr.get("special", false): actions.add_child(_rich("[color=#ff4d5e]⚠ Asteroidi speciali: distruzione certa.[/color]", 16))
	elif not pr.get("asteroids", []).is_empty(): actions.add_child(_rich("[color=#ffc94a]Attraversa %d esagoni di asteroidi a velocità > 1: tiro di pericolo.[/color]" % pr.asteroids.size(), 15))
	if not pr.get("grav", []).is_empty():
		actions.add_child(_rich("Raccoglie %d spinta/e di gravità per il turno successivo." % pr.grav.size(), 14))

## Comandi di scenario che non dipendono dalla nave selezionata.
func _build_scenario_commands(me: String) -> void:
	if state.scenario == "retribution" and me == "P1" and state.phase == "astrogation" and ScenRetribution.can_form(state):
		var fb := _action_button("FORMA ORA LA FLOTTA DELLA LIBERTÀ")
		fb.tooltip_text = "Le corvette ferme a Clandestine diventano una flotta del doppio della loro forza. Non arriveranno altre corvette."
		fb.pressed.connect(func():
			ScenRetribution.form_fleet(state)
			_setup_done())
	if state.scenario == "interplanetary-war" and ScenWar.can_buy_now(state, me) == "":
		var sb := _action_button("CANTIERE · %s MCr disponibili" % Fleet.fmt_mcr(ScenWar.spendable(state, me)))
		sb.pressed.connect(func():
			var e := ScenWar.open_mid_shop(state, me)
			if e != "": _toast(e, true)
			_refresh())

func _build_prospect_actions(s: Dictionary) -> void:
	var cash := float(state.sd.mcr[s.owner])
	actions.add_child(_rich("Cassa: [b]%s MCr[/b] · minerale a bordo [b]%.1f t[/b]%s" % [Fleet.fmt_mcr(cash), int(s.ore10) / 10.0, (" · %d schegge CT" % int(s.inv.get("ct_shard", 0))) if int(s.inv.get("ct_shard", 0)) > 0 else ""], 15))
	if ScenProspecting.can_sell(state, s) == "":
		var b := UITheme.primary_button("VENDI IL CARICO")
		b.custom_minimum_size = Vector2(0, 42)
		b.pressed.connect(func():
			var n = state.log.size()
			ScenProspecting.sell(state, s.id)
			_after_step(n); _refresh())
		actions.add_child(b)
	for a in ScenProspecting.claim_actions(state, s):
		var label: String = {"place_mine": "INSTALLA LA MINIERA AUTOMATICA", "place_guards": "METTI LE GUARDIE ROBOT", "collect": "CARICA IL MINERALE ESTRATTO"}[a]
		var cb := _action_button(label)
		cb.pressed.connect(func():
			var n = state.log.size()
			ScenProspecting.claim_action(state, s.id, a)
			_after_step(n); _refresh())
	if ScenProspecting.at_base(state, s):
		actions.add_child(UITheme.caption("Acquisti in base"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for spec in [["+1 CARB.", 1], ["+5", 5], ["PIENO", 99]]:
			var fb := Button.new(); fb.text = spec[0]; fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fb.disabled = ScenProspecting.can_buy(state, s, "fuel") != ""
			fb.pressed.connect(func():
				var n = state.log.size()
				ScenProspecting.buy(state, s.id, "fuel", mini(int(spec[1]), int(s.max_fuel) - int(s.fuel)))
				_after_step(n); _refresh())
			row.add_child(fb)
		actions.add_child(row)
		for item in ScenProspecting.EQUIP:
			var why := ScenProspecting.can_buy(state, s, item)
			var eb := _action_button("%s · %d MCr" % [ShipTypes.ITEM_NAME[item].to_upper(), int(Fleet.price("mcr", item))], why == "", why)
			eb.pressed.connect(func():
				var n = state.log.size()
				ScenProspecting.buy(state, s.id, item)
				_after_step(n); _refresh())

func _odds_panel(p: Dictionary) -> Control:
	var box := _panel(Color("0c1a38"), UITheme.LINE_BRIGHT, 6, 10)
	var v := VBoxContainer.new()
	box.add_child(v)
	v.add_child(_rich("[b]%d : %d[/b] → colonna [b]%s[/b]\nDistanza %d · velocità relativa %d · modificatore [b]%+d[/b]%s" % [p.att, p.def, p.odds, p.range, p.rv, p.mod, " · eroica +1" if p.heroic else ""], 15))
	var bar := ChanceBar.new()
	bar.chances = p.chances
	bar.custom_minimum_size = Vector2(0, 26)
	v.add_child(bar)
	return box

func _select_next() -> void:
	var me := _active_player()
	var mine = state.ships.filter(func(s): return s.owner == me and Rules.alive(s) and not s.get("dummy", false))
	if mine.is_empty(): return
	var idx := -1
	for i in range(mine.size()):
		if mine[i].id == sel: idx = i
	sel = mine[(idx + 1) % mine.size()].id
	var s := Rules.ship(state, sel)
	if s.landed == "": board.center_on(s.pos)
	_refresh()

func _center_selected() -> void:
	var s := Rules.ship(state, sel)
	if not s.is_empty(): board.center_on(s.pos, 26.0)

func _refresh_bottom() -> void:
	var me := _active_player()
	var human := _is_human(me)
	primary.disabled = busy or not human or state.over or state.phase == "setup" or not state.pending_attack.is_empty()
	var name: String = Rules.player(state, me).get("name", "")
	match state.phase:
		"setup":
			primary.text = "CONFERMA ▸"
			hint.text = "[b]%s[/b] · %s" % [name, {"shop": "scegli la flotta nel pannello a destra.", "deploy": "colloca le unità sugli esagoni evidenziati.", "choose": "fai la tua scelta nel pannello a destra.", "designate": "designa le unità ribelli sulla plancia."}.get(state.setup.get("step", ""), "preparazione segreta dello scenario.")]
		"astrogation":
			primary.text = "CONFERMA LE ROTTE ▸"
			var pending = state.ships.filter(func(s): return s.owner == me and Rules.alive(s) and not s.get("dummy", false) and s.landed == "" and not Rules.is_disabled(state, s)).size()
			hint.text = "[b]Astrogazione[/b] · scegli la spinta di ogni nave: il tratteggio è la rotta prevista. %s" % ("Nessuna nave in volo." if pending == 0 else "")
		"ordnance":
			primary.text = "MUOVI LE NAVI ▸"
			hint.text = "[b]Ordigni[/b] · al massimo un lancio per nave. Mine e testate richiedono un cambio di rotta."
		"combat":
			primary.text = "APRI IL FUOCO" if not attackers.is_empty() and not targets.is_empty() else "FINE COMBATTIMENTO ▸"
			hint.text = "[b]Combattimento[/b] · ogni nave attacca e viene attaccata una sola volta per fase."
		"resupply":
			primary.text = "FINE TURNO ▸"
			hint.text = "[b]Rifornimento[/b] · carico, ispezioni e trasferimenti fra navi con la stessa rotta."
		"over":
			primary.text = "PARTITA CONCLUSA"
			hint.text = state.result
	if not human and not state.over:
		hint.text = "[color=#7fe0ee]Turno di %s (IA)…[/color]" % name

# ================================================================ combattimento

func _fire() -> void:
	if attackers.is_empty() or targets.is_empty(): return
	var err := Rules.declare_attack(state, attackers, targets)
	if err != "":
		_toast(err, true)
		return
	for a in attackers:
		for t in targets:
			board.fx_list.append({"kind": "fire", "world": Board.world(Rules.ship(state, a).pos), "to": Board.world(Rules.ship(state, t).pos), "t0": board._time})
	attackers = []; targets = []
	var defender: String = state.pending_attack.defender
	if online != null and not online.controls(state, defender):
		# risponde un giocatore su un altro dispositivo
		_refresh()
		_flow()
		return
	if not _is_human(defender):
		var n = state.log.size()
		AI.respond_counter(state)
		_after_step(n)
		_show_combat_result()
		_refresh()
		if state.over: _show_victory()
		return
	_show_counter_dialog()

func _show_combat_result() -> void:
	var lc: Dictionary = state.get("last_combat", {})
	if lc.is_empty(): return
	var main: Dictionary = lc.main
	var txt := "Dado %d %+d → %s" % [main.die, main.mod, _res_word(main.result)]
	if not lc.counter.is_empty(): txt += "   ·   contrattacco: %s" % _res_word(lc.counter.result)
	_toast(txt, main.result == "-")

func _res_word(r: String) -> String:
	if r == "-": return "mancato"
	if r == "E": return "ELIMINATA"
	return "disabilitata %s" % r.substr(1)

func _show_counter_dialog() -> void:
	if dialog != null: dialog.queue_free()
	var pa: Dictionary = state.pending_attack
	dialog = _modal()
	var card: VBoxContainer = dialog.get_meta("card")
	var defender := Rules.player(state, pa.defender)
	card.add_child(UITheme.label("CONTRATTACCO", 28, UITheme.ACCENT, UITheme.display))
	var att_names: Array = pa.attackers.map(func(id): return Rules.ship(state, id).name)
	var tgt_names: Array = pa.targets.map(func(id): return Rules.ship(state, id).name)
	card.add_child(_rich("[b]%s[/b], le tue navi %s sono sotto il fuoco di %s.\nPuoi contrattaccare prima che i danni vengano applicati." % [defender.name, ", ".join(tgt_names), ", ".join(att_names)], 17))
	var cands := Rules.counter_candidates(state)
	var picked_c := cands.duplicate()
	var picked_t: Array = pa.attackers.duplicate()
	if cands.is_empty():
		card.add_child(_rich("[color=#9aa7c2]Nessuna nave può rispondere (commerciale o disabilitata).[/color]", 16))
	else:
		card.add_child(UITheme.caption("Navi che rispondono"))
		for id in cands:
			var cb := CheckBox.new(); cb.text = Rules.ship(state, id).name; cb.button_pressed = true
			cb.toggled.connect(func(on): if on: picked_c.append(id) else: picked_c.erase(id))
			card.add_child(cb)
		card.add_child(UITheme.caption("Bersagli del contrattacco"))
		for id in pa.attackers:
			var cb2 := CheckBox.new(); cb2.text = Rules.ship(state, id).name; cb2.button_pressed = true
			cb2.toggled.connect(func(on): if on: picked_t.append(id) else: picked_t.erase(id))
			card.add_child(cb2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	if not cands.is_empty():
		var yes := UITheme.primary_button("CONTRATTACCA")
		yes.custom_minimum_size = Vector2(200, 46)
		yes.pressed.connect(func(): _resolve_counter(picked_c, picked_t))
		row.add_child(yes)
	var no := Button.new(); no.text = "NESSUNA RISPOSTA" if not cands.is_empty() else "RISOLVI L'ATTACCO"; no.custom_minimum_size = Vector2(200, 46)
	no.pressed.connect(func(): _resolve_counter([], []))
	row.add_child(no)
	add_child(dialog)
	_refresh()

func _resolve_counter(c: Array, t: Array) -> void:
	var n = state.log.size()
	Rules.resolve_attack(state, c, t)
	if dialog != null: dialog.queue_free(); dialog = null
	_after_step(n)
	_show_combat_result()
	_refresh()
	if state.over: _show_victory()
	else: _flow()

# ================================================================ schermate modali

func _modal(width := 560.0) -> Control:
	var root := ColorRect.new()
	root.color = Color(0.01, 0.02, 0.06, 0.78)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := _panel(Color("0a1630"), UITheme.LINE_BRIGHT, 10, 26)
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 12)
	panel.add_child(card)
	root.set_meta("card", card)
	return root

func _show_privacy(pid: String) -> void:
	var p := Rules.player(state, pid)
	board.visible = false
	hud.visible = false
	privacy = _modal(520)
	privacy.color = Color("040914")
	var card: VBoxContainer = privacy.get_meta("card")
	var dot := Panel.new(); dot.custom_minimum_size = Vector2(0, 6)
	dot.add_theme_stylebox_override("panel", UITheme.box(UITheme.player_color(state, pid), Color.TRANSPARENT, 3, 0, 0))
	card.add_child(dot)
	card.add_child(UITheme.label("PASSA IL COMANDO", 16, UITheme.TEXT_DIM, UITheme.body_bold))
	var l := UITheme.label(p.name.to_upper(), 36, UITheme.player_color(state, pid), UITheme.display)
	card.add_child(l)
	card.add_child(_rich("Gli altri giocatori distolgano lo sguardo: in questo scenario ci sono informazioni nascoste.", 17))
	var go := UITheme.primary_button("SONO PRONTO")
	go.custom_minimum_size = Vector2(0, 50)
	card.add_child(go)
	add_child(privacy)
	await go.pressed
	privacy.queue_free()
	privacy = null
	board.visible = true
	hud.visible = true

func _show_victory() -> void:
	if victory != null: victory.queue_free()
	victory = _modal(620)
	var card: VBoxContainer = victory.get_meta("card")
	var title := "PARTITA CONCLUSA"
	var col := UITheme.TEXT
	if state.winner != "" and state.winner != "pari":
		title = "VITTORIA · " + Rules.player(state, state.winner).name.to_upper()
		col = UITheme.player_color(state, state.winner)
	card.add_child(UITheme.label(title, 30, col, UITheme.display))
	card.add_child(_rich(state.result, 19))
	var stats := []
	for s in state.ships:
		if s.get("dummy", false): continue
		var tag: String = "perduta" if s.destroyed else ("in fuga" if s.escaped else "in gioco")
		stats.append("[color=#%s]■[/color] %s — %s, carburante consumato %d" % [UITheme.player_color(state, s.owner).to_html(false), s.name, tag, s.fuel_spent])
	if state.scenario == "escape":
		var f := Rules.ship(state, state.sd.get("fugitive", ""))
		if not f.is_empty(): stats.append("I fuggitivi erano sul [b]%s[/b]." % f.name)
	card.add_child(_rich("\n".join(stats), 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var again := UITheme.primary_button("NUOVA PARTITA")
	again.custom_minimum_size = Vector2(220, 46)
	again.pressed.connect(func(): victory.queue_free(); victory = null; _show_menu())
	row.add_child(again)
	var look := Button.new(); look.text = "GUARDA LA PLANCIA"; look.custom_minimum_size = Vector2(220, 46)
	look.pressed.connect(func(): victory.queue_free(); victory = null)
	row.add_child(look)
	if not state.get("replay", []).is_empty():
		var rp := Button.new(); rp.text = "REPLAY"; rp.custom_minimum_size = Vector2(140, 46)
		rp.tooltip_text = "Rivedi tutta la partita: le navi si muovono insieme, senza pause fra i turni"
		rp.pressed.connect(func(): victory.queue_free(); victory = null; _start_replay())
		row.add_child(rp)
	add_child(victory)

func _toast(text: String, warn := false) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", UITheme.WARN if warn else UITheme.TEXT)
	if toast_tween != null: toast_tween.kill()
	toast.modulate.a = 1.0
	toast_tween = create_tween()
	toast_tween.tween_interval(2.2)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.6)

func _open_game_menu() -> void:
	if dialog != null: dialog.queue_free()
	dialog = _modal(460)
	var card: VBoxContainer = dialog.get_meta("card")
	card.add_child(UITheme.label("MENU", 28, UITheme.ACCENT, UITheme.display))
	var close := func(): dialog.queue_free(); dialog = null
	var items := [
		["RIPRENDI", func(): close.call()],
	]
	if state.over and not state.get("replay", []).is_empty():
		items.append(["REPLAY DELLA PARTITA", func(): close.call(); _start_replay()])
	if not state.over:
		items.append(["TERMINA LA PARTITA E AGGIUDICA", func(): close.call(); _confirm_end()])
	if online != null:
		items.append(["COPIA IL SALVATAGGIO NEGLI APPUNTI", func():
			DisplayServer.clipboard_set(Persistence.to_json(state)); _toast("Salvataggio copiato"); close.call()])
		items.append(["VELOCITÀ ANIMAZIONI: %s" % ("RAPIDA" if anim_speed > 1.0 else "NORMALE"), func():
			anim_speed = 1.0 if anim_speed > 1.0 else 2.2; close.call()])
		items.append(["ESCI (SI PUÒ RIENTRARE CON IL CODICE %s)" % online.code, func(): close.call(); _show_menu()])
	else: items.append_array([
		["SALVA (slot 1)", func():
			Persistence.save_slot(state, "slot1"); _toast("Partita salvata"); close.call()],
		["CARICA (slot 1)", func():
			var st := Persistence.load_slot("slot1")
			close.call()
			if st.is_empty(): _toast("Nessun salvataggio", true)
			else: _start_game(st)],
		["COPIA IL SALVATAGGIO NEGLI APPUNTI", func():
			DisplayServer.clipboard_set(Persistence.to_json(state)); _toast("Salvataggio copiato"); close.call()],
		["INCOLLA UN SALVATAGGIO", func():
			var st2 := Persistence.from_json(DisplayServer.clipboard_get())
			close.call()
			if st2.is_empty(): _toast("Negli appunti non c'è un salvataggio valido", true)
			else: _start_game(st2)],
		["VELOCITÀ ANIMAZIONI: %s" % ("RAPIDA" if anim_speed > 1.0 else "NORMALE"), func():
			anim_speed = 1.0 if anim_speed > 1.0 else 2.2; close.call()],
		["ESCI AL MENU PRINCIPALE", func(): close.call(); _show_menu()],
	])
	for it in items:
		var b := Button.new(); b.text = it[0]; b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(it[1])
		card.add_child(b)
	add_child(dialog)

# ================================================================ guida

func _build_help() -> void:
	help = _modal(820)
	help.visible = false
	var card: VBoxContainer = help.get_meta("card")
	card.add_child(UITheme.label("COME SI GIOCA", 28, UITheme.ACCENT, UITheme.display))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var text := _rich(HELP_TEXT, 16)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	var ok := UITheme.primary_button("HO CAPITO")
	ok.custom_minimum_size = Vector2(0, 46)
	ok.pressed.connect(func(): help.visible = false)
	card.add_child(ok)
	add_child(help)

const HELP_TEXT := """[b][color=#ff9a5c]Il turno[/color][/b]
Ogni turno è un giorno. Ogni giocatore, a rotazione, svolge cinque fasi: [b]Astrogazione[/b] (si pianificano le rotte), [b]Ordigni[/b] (mine, siluri, testate), [b]Movimento[/b] (tutto si muove insieme), [b]Combattimento[/b] e [b]Rifornimento[/b]. Le fasi senza scelte vengono saltate da sole.

[b][color=#ff9a5c]Movimento vettoriale[/color][/b]
Una nave ripete ogni turno lo stesso spostamento del turno precedente (la freccia tratteggiata). Selezionala e clicca uno dei sei esagoni [color=#49d3e6]azzurri[/color] attorno al punto d'arrivo: costa 1 punto carburante e sposta l'arrivo di un esagono. Il centro è la deriva. Le navi da guerra possono fare un [color=#ff9a5c]sovraccarico[/color] (due spinte) una volta fra due manutenzioni. Le rotte percorse restano tracciate col numero del giorno; un cerchietto alla base indica una spinta.

[b][color=#ff9a5c]Gravità[/color][/b]
Le frecce attorno ai corpi celesti spingono di un esagono, ma [b]il turno dopo[/b] averle attraversate, e si sommano. Le frecce vuote (Luna, Io, Europa) sono deboli: la prima si può ignorare, la seconda consecutiva è obbligatoria. Attorno al Sole la mappa usata ha due anelli (le frecce doppie valgono due spinte); nel menu c'è la variante classica a un solo anello.

[b][color=#ff9a5c]Orbite, atterraggi, decolli[/color][/b]
Muovendosi a velocità 1 da un esagono di gravità al successivo dello stesso corpo senza spinta, la nave è in orbita stabile. Da un'orbita si atterra su una base spendendo 1 carburante. Il decollo usa il booster della base: la nave resta ferma sopra la base e al turno dopo deve accendere i motori, altrimenti ricade. Attraversare il disco di un corpo significa schiantarsi; uscire dalla plancia significa perdere la nave.

[b][color=#ff9a5c]Rifornimento[/color][/b]
A terra su una base amica, oppure in orbita sopra un lato con una base, la nave fa il pieno e la manutenzione (torna disponibile il sovraccarico). Ceres e Clandestine sono basi negli asteroidi: ci si ferma nell'esagono.

[b][color=#ff9a5c]Combattimento[/color][/b]
Somma le forze degli attaccanti e dei bersagli (stesso esagono) e riduci il rapporto a favore del difensore: 1:2, 1:1, 2:1, 3:1, 4:1. Al dado si sottrae la distanza minima fra la rotta dell'attaccante e la posizione del bersaglio, e 1 per ogni punto di velocità relativa oltre 2. Il difensore può contrattaccare prima che i danni siano applicati. Dn disabilita per n turni (la nave va alla deriva), E elimina; arrivare a 6 turni di disabilitazione distrugge la nave. Le navi commerciali (forza con la D) non sparano.

[b][color=#ff9a5c]Ordigni e pericoli[/color][/b]
Mine (10 t) e testate (20 t) ereditano il vettore della nave, che deve cambiare rotta; i siluri (20 t, solo navi da guerra) accelerano di 1 o 2 al lancio. Durano cinque turni. Attraversare asteroidi a velocità superiore a 1 richiede un tiro per esagono.

[b][color=#ff9a5c]Scenari con acquisti[/color][/b]
In Nova, Retribution, The Fleet Mutiny, Interplanetary War e Prospecting la partita comincia con la preparazione: scelte nel pannello a destra, acquisti con i pulsanti + e −, poi lo schieramento cliccando gli esagoni evidenziati in verde (il pulsante cambia il verso delle orbite). Nella guerra interplanetaria il cantiere si apre durante l'astrogazione o il rifornimento; in Fleet Mutiny, in fase di combattimento, una nave in orbita sopra un lato della Terra può sopprimerlo.

[b][color=#ff9a5c]Mappa ampliata[/color][/b]
In ogni scenario si può scegliere la mappa ampliata di Mike Rowles (interna fino a Giove o completa fino a Plutone): i pianeti girano attorno al Sole in senso antiorario (il cerchio colorato è l'orbita, la freccia indica il prossimo esagono). Le navi a terra o nei campi di gravità di un pianeta si spostano con lui. L'anello interno del Sole ha gravità tripla, quello di Giove doppia: avvicinarsi al Sole richiede molta prudenza.

[b][color=#ff9a5c]Fine della partita[/color][/b]
Se per 20 giorni non succede nulla (nessuna spinta, nessun combattimento, nessun progresso, navi ferme o in orbita) la partita si chiude da sola e viene aggiudicata; dopo 15 giorni il registro avvisa. Il pulsante FINE in alto la chiude subito: vince chi ha raggiunto più tappe, soppresso più lati, abbattuto più alieni o, negli altri scenari, chi ha più forza ancora in gioco. Poi si passa alla schermata finale con il REPLAY.

[b][color=#ff9a5c]Visualizzazione e replay[/color][/b]
Con ROTTE e DERIVA spenti la plancia si fa pulita: ogni nave mostra la fiamma della spinta scelta per il turno. Con PRUA SULLA ROTTA (nella barra del replay, attivo di norma) la nave punta sempre lungo la sua rotta e la fiamma esce da uno dei sei lati, quello opposto alla spinta; spento, la nave ruota verso la spinta e accende il motore principale. A fine partita il pulsante REPLAY (anche dal MENU) fa rivedere tutta la partita: le navi si muovono insieme su traiettorie continue, senza pause fra i turni, con velocità da ½× a 4× e una barra per saltare a qualunque giorno.

[b][color=#ff9a5c]Gioco online[/color][/b]
Dal menu: CREA UNA STANZA e comunica il codice di 4 lettere; gli amici scrivono il codice e premono ENTRA. Se cade la linea si rientra dallo stesso menu.

[b][color=#ff9a5c]Comandi[/color][/b]
Rotella: zoom · trascina: sposta la plancia · R: rotte percorse · D: vettori di deriva · V: rilevatori · clic destro: annulla la selezione · Tab: nave successiva · barra spaziatrice: deriva · Invio: conferma la fase · F: adatta la plancia."""

# ================================================================ menu principale

func _show_menu() -> void:
	if online != null: _leave_online()
	_gen += 1
	busy = false
	menu.visible = true
	hud.visible = false
	board.visible = false
	tip.visible = false
	_build_menu_detail()

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var bg := MenuBackdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 34)
	menu.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	margin.add_child(cols)
	# colonna sinistra: copertina e titolo
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	var title := UITheme.label("TRIPLANETARY", 46, UITheme.PHOSPHOR, UITheme.display)
	title.add_theme_color_override("font_outline_color", Color("c2321f"))
	title.add_theme_constant_override("outline_size", 6)
	left.add_child(title)
	left.add_child(UITheme.label("COMBATTIMENTO SPAZIALE NEL SISTEMA SOLARE · 2001 AD", 15, UITheme.TEXT, UITheme.body_bold))
	var cover := TextureRect.new()
	cover.texture = load("res://assets/ui/original-cover.webp")
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(cover)
	left.add_child(UITheme.label("Edizione digitale non ufficiale per uso personale.\nRegole: Updated Second Edition, GDW 1973/1981.", 13, UITheme.TEXT_FAINT))
	# colonna centrale: scenari
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(330, 0)
	mid.add_theme_constant_override("separation", 6)
	cols.add_child(mid)
	mid.add_child(UITheme.caption("Scenari", UITheme.ACCENT))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.name = "ScenarioList"
	mid.add_child(list)
	for c in Scenarios.CATALOG:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 46)
		b.text = "%s   ·   %s giocatori%s" % [c.title.to_upper(), c.players, "" if c.playable else "   (presto)"]
		b.disabled = not c.playable
		b.set_meta("id", c.id)
		b.pressed.connect(func(): menu_scenario = c.id; _build_menu_detail())
		list.add_child(b)
	var cont := Button.new()
	cont.name = "Continue"
	cont.custom_minimum_size = Vector2(0, 46)
	cont.pressed.connect(func():
		var st := Persistence.load_slot("auto")
		if not st.is_empty(): _start_game(st))
	mid.add_child(Control.new())
	mid.add_child(cont)
	# colonna destra: dettaglio e equipaggi
	var right_panel := _panel(Color("08122ae6"), UITheme.LINE, 10, 20)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right_panel)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(rs)
	menu_detail = VBoxContainer.new()
	menu_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_detail.add_theme_constant_override("separation", 10)
	rs.add_child(menu_detail)

func _build_menu_detail() -> void:
	var info := Scenarios.info(menu_scenario)
	var list: VBoxContainer = menu.find_child("ScenarioList", true, false)
	for b in list.get_children():
		var on: bool = b.get_meta("id") == menu_scenario
		b.add_theme_stylebox_override("normal", UITheme.box(Color("2a1a10") if on else Color("10224a"), UITheme.ACCENT if on else UITheme.LINE_BRIGHT, 5, 2 if on else 1, 12))
	var cont: Button = menu.find_child("Continue", true, false)
	var summary := Persistence.slot_summary("auto")
	cont.visible = summary != ""
	cont.text = "CONTINUA: " + summary.to_upper()
	_clear(menu_detail)
	menu_detail.add_child(UITheme.label(info.title.to_upper(), 32, UITheme.TEXT, UITheme.display))
	var meta := "%s giocatori · %s" % [info.players, info.length]
	if info.year != "": meta = info.year + " · " + meta
	menu_detail.add_child(UITheme.label(meta, 16, UITheme.ACCENT_SOFT, UITheme.body_bold))
	menu_detail.add_child(_rich(info.blurb, 18))
	menu_detail.add_child(UITheme.caption("Equipaggi"))
	var n_max: int = info.max
	if menu_seats.size() != 6:
		menu_seats = []
		for i in range(6): menu_seats.append({"name": "", "type": "human" if i == 0 else ("ai" if i == 1 else "none")})
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	menu_detail.add_child(grid)
	for i in range(n_max):
		var seat: Dictionary = menu_seats[i]
		var col := Color(Scenarios.PLAYER_COLORS[i])
		var side_name: String = info.sides[i] if i < info.sides.size() else "Giocatore"
		var lbl := UITheme.label(side_name.to_upper(), 15, col, UITheme.body_bold)
		lbl.custom_minimum_size = Vector2(110, 0)
		grid.add_child(lbl)
		var name_edit := LineEdit.new()
		name_edit.placeholder_text = "%s %d" % [side_name, i + 1] if side_name == "Pilota" else side_name
		name_edit.text = seat.name
		name_edit.custom_minimum_size = Vector2(190, 38)
		name_edit.text_changed.connect(func(t): seat.name = t)
		grid.add_child(name_edit)
		var opt := OptionButton.new()
		opt.add_item("UMANO"); opt.add_item("IA")
		var can_none := i >= int(info.min)
		if can_none: opt.add_item("NESSUNO")
		var idx: int = {"human": 0, "ai": 1, "none": 2}.get(seat.type, 0)
		if i < int(info.min) and seat.type == "none": seat.type = "ai"; idx = 1
		opt.select(mini(idx, opt.item_count - 1))
		opt.custom_minimum_size = Vector2(130, 38)
		opt.item_selected.connect(func(k): seat.type = ["human", "ai", "none"][k])
		grid.add_child(opt)
	menu_detail.add_child(UITheme.caption("Opzioni"))
	var sol := CheckBox.new()
	sol.text = "Sol classico: un solo anello di gravità (invece delle frecce doppie della mappa)"
	sol.button_pressed = menu_options.sol_classic
	sol.toggled.connect(func(on): menu_options.sol_classic = on)
	menu_detail.add_child(sol)
	if menu_scenario == "lateral-7":
		var lt := CheckBox.new()
		lt.text = "Variante: la nave di linea parte dalla Terra invece che da Venere"
		lt.button_pressed = menu_options.liner_terra
		lt.toggled.connect(func(on): menu_options.liner_terra = on)
		menu_detail.add_child(lt)
	if menu_scenario == "nova":
		var al := CheckBox.new()
		al.text = "EastBloc e WestBloc si concedono le basi a vicenda (rifornimenti e niente difese fra blocchi)"
		al.button_pressed = menu_options.nova_allied
		al.toggled.connect(func(on): menu_options.nova_allied = on)
		menu_detail.add_child(al)
	if info.get("xmap", false):
		menu_detail.add_child(_option_row("Plancia:", [["classic", "CLASSICA"], ["xmap", "AMPLIATA"], ["xmap_full", "COMPLETA FINO A PLUTONE"]], "map"))
		if menu_options.map == "xmap":
			menu_detail.add_child(_rich("[color=#9aa7c2]Mappa ampliata di Mike Rowles (76 × 53 esagoni, scala variabile, da Mercurio a Giove): i pianeti girano attorno al Sole in senso antiorario, Mercurio di un esagono ogni 2 turni, Venere ogni 3, la Terra ogni 4, Marte ogni 5, Vesta ogni 11, Ceres e Pallade ogni 12, Giove ogni 42. Il Sole ha un anello interno a gravità tripla, Giove gravità doppia. Navi in orbita o a terra si muovono con il loro pianeta. Clandestine è su un asteroide della fascia esterna.[/color]", 14))
		elif menu_options.map == "xmap_full":
			menu_detail.add_child(_rich("[color=#9aa7c2]Mappa completa di Mike Rowles (152 × 53 esagoni): oltre al sistema interno, Saturno con Titano, Urano, Nettuno con Tritone e Plutone con Caronte. I pianeti esterni si muovono lentissimi (Saturno un esagono ogni 112 turni). Per coprire le distanze i serbatoi di tutte le navi sono raddoppiati; nel Grand Tour vanno visitati anche Saturno, Urano e Nettuno.[/color]", 14))
	if menu_scenario == "grand-tour":
		menu_detail.add_child(_option_row("Rotta:", [["free", "LIBERA"], ["alpha", "ALFABETICA"], ["size", "PER DIMENSIONE"], ["distance", "DISTANZA DAL SOLE"]], "route"))
	if menu_scenario == "nova":
		menu_detail.add_child(_option_row("Corsari alieni:", [[2, "2"], [3, "3"], [4, "4"], [5, "5"], [6, "6"]], "aliens"))
	if menu_scenario == "fleet-mutiny":
		menu_detail.add_child(_option_row("Flotta imperiale:", [[8, "8 NAVI"], [10, "10"], [12, "12"], [14, "14"], [16, "16 NAVI"]], "mutiny_ships"))
		var hid := CheckBox.new()
		hid.text = "Pedine coperte: il Ribelle non sa quali navi imperiali sta designando (informazioni nascoste e rilevamento)"
		hid.button_pressed = menu_options.mutiny_hidden
		hid.toggled.connect(func(on): menu_options.mutiny_hidden = on)
		menu_detail.add_child(hid)
	if menu_scenario == "prospecting":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UITheme.label("Durata della corsa:", 16))
		for days in [60, 120, 180]:
			var b := Button.new()
			b.text = "%d GIORNI" % days
			b.toggle_mode = true
			b.button_pressed = int(menu_options.length) == days
			b.pressed.connect(func(): menu_options.length = days; _build_menu_detail())
			row.add_child(b)
		menu_detail.add_child(row)
	var start := UITheme.primary_button("INIZIA LA MISSIONE ▸")
	start.custom_minimum_size = Vector2(0, 52)
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_start_from_menu)
	menu_detail.add_child(start)
	_build_online_menu()

## Riga di pulsanti a scelta singola per un'opzione dello scenario.
func _option_row(caption: String, choices: Array, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UITheme.label(caption, 16))
	for c in choices:
		var b := Button.new()
		b.text = c[1]
		b.toggle_mode = true
		b.button_pressed = str(menu_options.get(key)) == str(c[0])
		b.pressed.connect(func(): menu_options[key] = c[0]; _build_menu_detail())
		row.add_child(b)
	return row

func _scenario_options(opts: Dictionary) -> Dictionary:
	var o := opts.duplicate()
	o.length = int(o.get("length", 120))
	return o

func _start_from_menu() -> void:
	var info := Scenarios.info(menu_scenario)
	var seats := []
	for i in range(int(info.max)):
		var seat: Dictionary = menu_seats[i]
		if seat.type == "none": continue
		var side_name: String = info.sides[i] if i < info.sides.size() else "Giocatore"
		var nm: String = seat.name.strip_edges()
		if nm == "": nm = ("Pilota %d" % (i + 1)) if side_name == "Pilota" else side_name
		seats.append({"name": nm, "type": seat.type})
	if seats.size() < int(info.min):
		_toast("Servono almeno %d giocatori" % info.min, true)
		return
	var st := Scenarios.create(menu_scenario, seats, _scenario_options(menu_options))
	_start_game(st)

## Fine anticipata: chiede conferma, aggiudica la vittoria e passa alla schermata finale (con il replay).
func _confirm_end() -> void:
	if online != null and busy:
		_toast("Online si può terminare solo durante il proprio turno.", true)
		return
	if dialog != null: dialog.queue_free()
	dialog = _modal(520)
	var card: VBoxContainer = dialog.get_meta("card")
	card.add_child(UITheme.label("TERMINARE LA PARTITA?", 26, UITheme.ACCENT, UITheme.display))
	card.add_child(_rich("La vittoria viene assegnata in base allo stato attuale (tappe raggiunte, lati soppressi, alieni abbattuti o forza ancora in gioco). Poi potrai rivedere tutto con il replay.", 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var yes := UITheme.primary_button("TERMINA")
	yes.custom_minimum_size = Vector2(180, 46)
	yes.pressed.connect(func():
		dialog.queue_free(); dialog = null
		var n: int = state.log.size()
		Scenarios.adjudicate(state, "Partita terminata dai giocatori.")
		_after_step(n)
		_refresh()
		if online != null: _flow()
		else: _show_victory())
	row.add_child(yes)
	var no := Button.new(); no.text = "ANNULLA"; no.custom_minimum_size = Vector2(160, 46)
	no.pressed.connect(func(): dialog.queue_free(); dialog = null)
	row.add_child(no)
	add_child(dialog)

# ================================================================ replay di fine partita

func _build_replay_bar() -> void:
	replay_bar = _panel(Color("0a1630f0"), UITheme.LINE_BRIGHT, 10, 12)
	replay_bar.visible = false
	add_child(replay_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	replay_bar.add_child(row)
	replay_label = UITheme.label("GIORNO 1", 20, UITheme.PHOSPHOR, UITheme.display)
	replay_label.custom_minimum_size = Vector2(170, 0)
	row.add_child(replay_label)
	replay_toggle = UITheme.primary_button("PAUSA")
	replay_toggle.custom_minimum_size = Vector2(120, 42)
	replay_toggle.pressed.connect(func():
		if not replay_play and board.replay_u >= float(board.replay.tmax): board.replay_u = float(board.replay.tmin)
		replay_play = not replay_play
		_refresh_replay_bar())
	row.add_child(replay_toggle)
	for sp in [0.5, 1.0, 2.0, 4.0]:
		var b := Button.new()
		b.text = ("%s×" % sp).replace(".0×", "×").replace("0.5×", "½×")
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(54, 42)
		b.set_meta("speed", sp)
		b.pressed.connect(func(): replay_speed = sp; _refresh_replay_bar())
		row.add_child(b)
	replay_slider = HSlider.new()
	replay_slider.custom_minimum_size = Vector2(380, 42)
	replay_slider.step = 0.01
	replay_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replay_slider.value_changed.connect(func(v):
		if absf(v - board.replay_u) > 0.02:
			board.replay_u = v
			board.queue_redraw()
			_refresh_replay_bar(false))
	row.add_child(replay_slider)
	var nose := Button.new()
	nose.text = "PRUA SULLA ROTTA"
	nose.toggle_mode = true
	nose.tooltip_text = "Le navi puntano sempre lungo la rotta e la fiamma esce da uno dei sei lati, opposto alla spinta.\nSpento: la nave ruota verso la spinta e accende il motore principale."
	nose.custom_minimum_size = Vector2(190, 42)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	nose.button_pressed = cfg.get_value("vista", "nose", true)
	board.nose_on_course = nose.button_pressed
	nose.toggled.connect(func(v):
		board.nose_on_course = v
		var c2 := ConfigFile.new()
		c2.load(SETTINGS_PATH)
		c2.set_value("vista", "nose", v)
		c2.save(SETTINGS_PATH)
		board.queue_redraw())
	row.add_child(nose)
	var out := Button.new()
	out.text = "ESCI DAL REPLAY"
	out.custom_minimum_size = Vector2(170, 42)
	out.pressed.connect(_stop_replay)
	row.add_child(out)

func _start_replay() -> void:
	board.replay = Replay.build(state)
	board.replay_u = float(board.replay.tmin)
	replay_play = true
	replay_slider.min_value = float(board.replay.tmin)
	replay_slider.max_value = float(board.replay.tmax) + 0.6
	hud.visible = false
	tip.visible = false
	replay_bar.visible = true
	_layout()
	board.fit()
	_refresh_replay_bar()

func _stop_replay() -> void:
	board.replay = {}
	replay_play = false
	replay_bar.visible = false
	hud.visible = true
	_layout()
	board.queue_redraw()
	_refresh()

func _refresh_replay_bar(set_slider := true) -> void:
	if board.replay.is_empty(): return
	replay_label.text = "GIORNO %d" % clampi(ceili(board.replay_u), 1, 9999)
	replay_toggle.text = "PAUSA" if replay_play else "AVVIA"
	for c in replay_toggle.get_parent().get_children():
		if c is Button and c.has_meta("speed"): c.button_pressed = is_equal_approx(float(c.get_meta("speed")), replay_speed)
	if set_slider: replay_slider.set_value_no_signal(board.replay_u)

func _process(delta: float) -> void:
	if board == null or board.replay.is_empty() or not replay_play: return
	board.replay_u += delta * replay_speed / 0.7
	var end := float(board.replay.tmax) + 0.6
	if board.replay_u >= end:
		board.replay_u = end
		replay_play = false
	_refresh_replay_bar()

# ================================================================ gioco online

func _build_online_menu() -> void:
	menu_detail.add_child(UITheme.caption("Gioca online", UITheme.ACCENT))
	menu_detail.add_child(_rich("[color=#9aa7c2]Chi crea la stanza usa gli equipaggi qui sopra: il primo posto [b]UMANO[/b] è il suo, gli altri posti UMANO sono per gli amici (se restano vuoti li gioca l'IA). Gli amici scrivono il codice di 4 lettere e premono ENTRA.[/color]", 15))
	var sess := net.load_session()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	menu_detail.add_child(row)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Il tuo nome"
	name_edit.text = str(sess.get("name", ""))
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(180, 40)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	var create := Button.new()
	create.text = "CREA UNA STANZA"
	create.custom_minimum_size = Vector2(190, 40)
	row.add_child(create)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	menu_detail.add_child(row2)
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "CODICE"
	code_edit.max_length = 4
	code_edit.custom_minimum_size = Vector2(120, 40)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.text_changed.connect(func(tx):
		var up: String = tx.to_upper()
		if up != tx:
			code_edit.text = up; code_edit.caret_column = up.length())
	row2.add_child(code_edit)
	var join := Button.new()
	join.text = "ENTRA"
	join.custom_minimum_size = Vector2(190, 40)
	row2.add_child(join)
	var status := UITheme.label("", 15, UITheme.WARN)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_detail.add_child(status)
	var buttons := [create, join]
	var nm := func() -> String:
		var s: String = name_edit.text.strip_edges()
		if s == "": status.text = "Scrivi il tuo nome."
		else: net._save({"name": s})
		return s
	create.pressed.connect(func():
		var me: String = nm.call()
		if me == "": return
		for b in buttons: b.disabled = true
		status.text = "Creo la stanza…"
		var err: String = await _online_create(me)
		status.text = err
		for b in buttons: b.disabled = false)
	join.pressed.connect(func():
		var me: String = nm.call()
		if me == "": return
		var c: String = code_edit.text.strip_edges().to_upper()
		if c.length() != 4:
			status.text = "Il codice della stanza è di 4 lettere."
			return
		for b in buttons: b.disabled = true
		status.text = "Entro nella stanza %s…" % c
		var err: String = await _online_join(c, me)
		status.text = err
		for b in buttons: b.disabled = false)
	if str(sess.get("room", "")) != "":
		var back := Button.new()
		back.text = "RIENTRA NELLA STANZA %s" % sess.room
		back.custom_minimum_size = Vector2(0, 40)
		back.pressed.connect(func():
			var me: String = nm.call()
			if me == "": return
			status.text = "Rientro nella stanza %s…" % sess.room
			var err: String = await _online_join(str(sess.room), me)
			if err != "": net.remember_room("")
			status.text = err)
		menu_detail.add_child(back)

## Crea la stanza con la configurazione del menu. Restituisce "" o un messaggio d'errore.
func _online_create(me: String) -> String:
	var info := Scenarios.info(menu_scenario)
	var open := []
	var count := 0
	for i in range(int(info.max)):
		if menu_seats[i].type == "none": continue
		count += 1
		if menu_seats[i].type == "human": open.append(i)
	if count < int(info.min): return "Servono almeno %d giocatori." % info.min
	if open.is_empty(): return "Metti almeno un posto su UMANO: il primo è il tuo."
	var c := await net.create_room(me, open)
	if c == "": return "Non riesco a creare la stanza: %s" % net.last_error
	net.remember_room(c, int(open[0]))
	lobby = {"code": c, "seat": int(open[0]), "role": "host", "name": me,
		"config": {"scenario": menu_scenario, "seats": menu_seats.duplicate(true), "options": menu_options.duplicate()}}
	_show_lobby()
	return ""

## Entra (o rientra) in una stanza. Restituisce "" o un messaggio d'errore.
func _online_join(c: String, me: String) -> String:
	var s := await net.join_room(c, me)
	if s == -1: return "La stanza %s è al completo." % c
	if s < 0:
		return "La stanza %s non esiste o la partita è già iniziata.%s" % [c, ("\n" + net.last_error) if net.last_error != "" else ""]
	net.remember_room(c, s)
	var room: Dictionary = net.last_room
	var role := "host" if room.get("host", "") == net.uid else "guest"
	lobby = {"code": c, "seat": s, "role": role, "name": me}
	if room.get("status", "") in ["playing", "over"]:
		if not await _online_enter(): return "Non riesco a leggere la partita: %s" % net.last_error
		return ""
	_show_lobby()
	return ""

func _show_lobby() -> void:
	if lobby_box != null: lobby_box.queue_free()
	lobby_box = _modal(560)
	var card: VBoxContainer = lobby_box.get_meta("card")
	card.add_child(UITheme.caption("Stanza online"))
	card.add_child(UITheme.label(lobby.code, 54, UITheme.PHOSPHOR, UITheme.display))
	var host: bool = lobby.role == "host"
	card.add_child(_rich("Comunica il codice agli altri giocatori: lo scrivono nel menu e premono [b]ENTRA[/b]." if host else "Sei dentro. Aspetta che chi ha creato la stanza dia il via.", 16))
	var seats_box := VBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 4)
	card.add_child(seats_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	if host:
		var go := UITheme.primary_button("INIZIA ONLINE ▸")
		go.custom_minimum_size = Vector2(240, 46)
		go.pressed.connect(func(): go.disabled = true; _online_start())
		row.add_child(go)
	var leave := Button.new()
	leave.text = "CHIUDI LA STANZA" if host else "ESCI"
	leave.custom_minimum_size = Vector2(200, 46)
	leave.pressed.connect(func():
		if host: net.close_room(lobby.code)
		net.remember_room("")
		lobby = {}
		if lobby_box != null: lobby_box.queue_free(); lobby_box = null)
	row.add_child(leave)
	add_child(lobby_box)
	_lobby_poll(lobby_box, seats_box)

## Aggiorna i posti della stanza ogni 2 secondi; chi non l'ha creata parte quando inizia la partita.
func _lobby_poll(box: Control, seats_box: VBoxContainer) -> void:
	while is_instance_valid(box) and box == lobby_box and not lobby.is_empty():
		var r := await net.db_get(Net.ROOT + "/" + str(lobby.code))
		if not is_instance_valid(box) or box != lobby_box: return
		if r.code != 200:
			_clear(seats_box)
			seats_box.add_child(UITheme.label("Rete non raggiungibile, riprovo… (%s)" % net.last_error, 15, UITheme.WARN))
			await get_tree().create_timer(3.0).timeout
			continue
		var room: Dictionary = r.data if r.data is Dictionary else {}
		if room.is_empty():
			_clear(seats_box)
			seats_box.add_child(UITheme.label("La stanza è stata chiusa.", 16, UITheme.WARN))
			net.remember_room("")
			lobby = {}
			return
		_clear(seats_box)
		var seats := Net._as_dict(room.get("seats", {}))
		var info := Scenarios.info(lobby.config.scenario if lobby.has("config") else menu_scenario)
		for i in room.get("open", []):
			var k := str(int(i))
			var side: String = info.sides[int(i)] if int(i) < info.sides.size() else "Giocatore"
			var who: String = str(seats[k].name) if seats.has(k) else "posto libero (lo giocherà l'IA)"
			seats_box.add_child(_rich("[color=%s]■[/color] [b]%s[/b] — %s" % [Scenarios.PLAYER_COLORS[int(i)], side.to_upper(), who], 16))
		if lobby.role == "guest" and room.get("status", "") in ["playing", "over"]:
			if await _online_enter(): return
		await get_tree().create_timer(2.0).timeout

func _online_start() -> void:
	var cfg: Dictionary = lobby.config
	var room := await net.room(lobby.code)
	var joined := Net._as_dict(room.get("seats", {}))
	var info := Scenarios.info(cfg.scenario)
	var seats := []
	var seat_idx := []
	for i in range(int(info.max)):
		var ms: Dictionary = cfg.seats[i]
		if ms.type == "none": continue
		var side_name: String = info.sides[i] if i < info.sides.size() else "Giocatore"
		var nm: String = ms.name.strip_edges()
		if nm == "": nm = ("Pilota %d" % (i + 1)) if side_name == "Pilota" else side_name
		var typ: String = ms.type
		if typ == "human":
			if joined.has(str(i)): nm = str(joined[str(i)].name)
			else: typ = "ai"
		seats.append({"name": nm, "type": typ})
		seat_idx.append(i if typ == "human" else -1)
	var st := Scenarios.create(cfg.scenario, seats, _scenario_options(cfg.options))
	for k in range(st.players.size()):
		if seat_idx[k] >= 0: st.players[k].seat = seat_idx[k]
	_make_online(lobby.code, int(lobby.seat), "host")
	online.pid = Online.pid_of_seat(st, int(lobby.seat))
	if not await net.start_room(lobby.code, {"scenario": cfg.scenario}):
		_toast("Non riesco ad avviare la stanza: %s" % net.last_error, true)
	await online.publish(st)
	_close_lobby()
	_start_game(st, true)

## Legge l'ultima istantanea della stanza ed entra in partita.
func _online_enter() -> bool:
	_make_online(lobby.code, int(lobby.seat), lobby.role)
	var pk := await online.catch_up()
	if pk.is_empty():
		_leave_online()
		return false
	online.pid = Online.pid_of_seat(pk.state, int(lobby.seat))
	_close_lobby()
	_start_game(pk.state, true)
	if online.pid == "": _toast("Il tuo posto non è in questa partita: la guardi da spettatore.", true)
	return true

func _make_online(c: String, s: int, role: String) -> void:
	if online != null: _leave_online()
	online = Online.new()
	online.setup(net, c, s, role)
	online.status_changed.connect(func(tx): if tx != "": _toast(tx, true))
	online.forced.connect(_on_forced)
	add_child(online)
	online.heartbeat_loop()

func _close_lobby() -> void:
	if lobby_box != null: lobby_box.queue_free(); lobby_box = null
	lobby = {}

func _leave_online() -> void:
	if online == null: return
	online.alive = false
	online.queue_free()
	online = null

## Applica un'istantanea arrivata da un altro dispositivo: registro, animazioni, esito dei combattimenti.
func _apply_packet(pk: Dictionary) -> void:
	var old_log: int = state.log.size()
	var old_combat = state.get("last_combat", {})
	state = pk.state
	board.set_state(state)
	if Rules.ship(state, sel).is_empty(): sel = ""
	mode = ""; attackers = []; targets = []
	if state.log.size() < old_log:
		log_text.clear()
		old_log = 0
	for i in range(old_log, state.log.size()): _append_log(state.log[i])
	_refresh()
	for batch in pk.get("moves", []):
		if batch is Array and not batch.is_empty():
			state.moves = batch
			await _animate_moves(false)
	var lc = state.get("last_combat", {})
	if lc is Dictionary and not lc.is_empty() and JSON.stringify(lc) != JSON.stringify(old_combat): _show_combat_result()
	Persistence.save_slot(state, "online")

## L'host ha già giocato al posto di questo dispositivo (assente troppo a lungo).
func _on_forced(pk: Dictionary) -> void:
	if busy or online == null: return
	if dialog != null: dialog.queue_free(); dialog = null
	busy = true
	var gen := _gen
	await _apply_packet(pk)
	if gen != _gen: return
	busy = false
	_toast("Eri via: l'IA ha giocato al tuo posto.", true)
	_refresh()
	_flow()

# ================================================================ tastiera

func _unhandled_input(event: InputEvent) -> void:
	if state.is_empty() or menu.visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		# comandi di visualizzazione: sempre disponibili, anche mentre decide un altro
		match event.keycode:
			KEY_F: board.fit(); return
			KEY_R: trails_toggle.button_pressed = not trails_toggle.button_pressed; return
			KEY_D: drift_toggle.button_pressed = not drift_toggle.button_pressed; return
			KEY_V: detect_toggle.button_pressed = not detect_toggle.button_pressed; return
	if busy: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER: _on_primary()
			KEY_TAB: _select_next()
			KEY_ESCAPE:
				sel = ""; mode = ""; attackers = []; targets = []
				_refresh()
			KEY_SPACE:
				var s := Rules.ship(state, sel)
				if not s.is_empty() and Rules.can_plot(state, s) and s.landed == "":
					Rules.set_plot(state, s.id, {"burns": []})
					_refresh()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var s2 := Rules.ship(state, sel)
				if not s2.is_empty() and Rules.can_plot(state, s2) and s2.landed == "":
					var err := Rules.set_plot(state, s2.id, {"burns": [int(event.keycode - KEY_1)]})
					if err != "": _toast(err, true)
					_refresh()
