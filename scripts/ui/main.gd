extends Control

const HexMathRef = preload("res://scripts/engine/hex.gd")
const GameRulesRef = preload("res://scripts/engine/game.gd")
const GrandTourDevRef = preload("res://scripts/data/grand_tour_dev.gd")
const EscapeScenarioRef = preload("res://scripts/data/escape.gd")
const Lateral7ScenarioRef = preload("res://scripts/data/lateral7.gd")
const BoardRef = preload("res://scripts/ui/board.gd")
const ThrustSelectorRef = preload("res://scripts/ui/thrust_selector.gd")
const PersistenceRef = preload("res://scripts/engine/persistence.gd")
const OrdnanceRulesRef = preload("res://scripts/engine/ordnance.gd")
const ReplayRulesRef = preload("res://scripts/engine/replay.gd")

var state: Dictionary
var board: Control
var status: Label
var ships_box: VBoxContainer
var log_label: Label
var overload_button: Button
var weak_button: Button
var thrust_selector: Control
var surface_button: Button
var attack_button: Button
var inspect_button: Button
var ram_button: Button
var target_picker: OptionButton
var selected_target_id := ""
var passenger_button: Button
var load_mine_button: Button
var counter_yes_button: Button
var counter_no_button: Button
var advance_button: Button
var ordnance_buttons: Dictionary = {}
var torpedo_controls: Array[Control] = []
var overload_planning := false
var privacy_overlay: ColorRect
var privacy_title: Label
var privacy_detail: Label
var replay_overlay: ColorRect
var replay_text: Label
var replay_cursor := 0
var menu_overlay: ColorRect
const SCENARIO_TITLES := ["GRAND TOUR · 2037 AD", "ESCAPE", "LATERAL 7", "NOVA", "RETRIBUTION", "THE FLEET MUTINY", "INTERPLANETARY WAR", "PROSPECTING"]
const SCENARIO_DESCRIPTIONS := [
	"Gara orbitale: visita ogni campo di gravità piena e torna sulla Terra.",
	"Tre trasporti tentano la fuga mentre le pattuglie danno la caccia.",
	"Pirati, falsi bersagli e una nave di linea nel sistema interno.",
	"Tre fazioni si contendono il sistema mentre incombe una bomba nova.",
	"Una successione di corvette affronta le unità degli Enforcers.",
	"La flotta si divide: identità ribelli segrete e basi orbitali.",
	"Campagna economica e militare fra mondi terrestri e ribelli.",
	"Esplorazione mineraria, mercati di Ceres e Luna e cristalli CT."
]
var scenario_buttons: Array[Button] = []
var selected_scenario := 0
var player_name_fields: Array[LineEdit] = []
var player_type_fields: Array[OptionButton] = []
var menu_note: Label
var start_button: Button
var main_title: Label
var phase_help: Label
var help_overlay: ColorRect
var help_body: Label

func _ready() -> void:
	state = GrandTourDevRef.create_state()
	_build_ui()
	_refresh()
	_show_main_menu()

func _build_ui() -> void:
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root)
	var header := HBoxContainer.new(); header.custom_minimum_size.y = 68; header.add_theme_constant_override("separation", 3); root.add_child(header)
	main_title = Label.new(); main_title.text = " TRIPLANETARY\n HOT-SEAT"; main_title.add_theme_font_size_override("font_size", 20); main_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; main_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; header.add_child(main_title)
	var reset := Button.new(); reset.text = "NUOVA"; reset.tooltip_text = "Nuova partita"; reset.pressed.connect(_reset); header.add_child(reset)
	var save := Button.new(); save.text = "SALVA"; save.pressed.connect(_save); header.add_child(save)
	var load_game := Button.new(); load_game.text = "CARICA"; load_game.pressed.connect(_load); header.add_child(load_game)
	var copy_game := Button.new(); copy_game.text = "Esporta"; copy_game.tooltip_text = "Copia un salvataggio portabile negli appunti"; copy_game.pressed.connect(_copy_portable_save); header.add_child(copy_game)
	var paste_game := Button.new(); paste_game.text = "Importa"; paste_game.tooltip_text = "Carica il salvataggio presente negli appunti"; paste_game.pressed.connect(_paste_portable_save); header.add_child(paste_game)
	var replay := Button.new(); replay.text = "Replay"; replay.pressed.connect(_open_replay); header.add_child(replay)
	var help := Button.new(); help.text = "GUIDA"; help.tooltip_text = "Come si gioca"; help.pressed.connect(_open_help); header.add_child(help)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(split)
	board = BoardRef.new(); board.custom_minimum_size = Vector2(600, 520); board.size_flags_horizontal = Control.SIZE_EXPAND_FILL; board.size_flags_vertical = Control.SIZE_EXPAND_FILL; board.hex_clicked.connect(_on_board_hex_clicked); split.add_child(board)
	var panel := VBoxContainer.new(); panel.custom_minimum_size.x = 350; panel.add_theme_constant_override("separation", 8); split.add_child(panel)
	var controls_scroll := ScrollContainer.new(); controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; panel.add_child(controls_scroll)
	var controls_column := VBoxContainer.new(); controls_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; controls_column.add_theme_constant_override("separation", 8); controls_scroll.add_child(controls_column)
	var info_section := _make_section(controls_column, "STATO E NAVI")
	status = Label.new(); status.add_theme_font_size_override("font_size", 18); info_section.add_child(status)
	phase_help = Label.new(); phase_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; phase_help.modulate = Color("9fd9ed"); info_section.add_child(phase_help)
	var ship_scroll := ScrollContainer.new(); ship_scroll.custom_minimum_size.y = 58; ship_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; info_section.add_child(ship_scroll)
	ships_box = VBoxContainer.new(); ships_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ship_scroll.add_child(ships_box)
	var thrust_section := _make_section(controls_column, "VETTORE E SPINTA")
	thrust_selector = ThrustSelectorRef.new(); thrust_selector.tooltip_text = "Clicca uno dei sei esagoni per scegliere la direzione di spinta"; thrust_selector.direction_selected.connect(_set_thrust); thrust_section.add_child(thrust_selector)
	overload_button = Button.new(); overload_button.pressed.connect(_toggle_overload); thrust_section.add_child(overload_button)
	weak_button = Button.new(); weak_button.pressed.connect(_toggle_weak_gravity); thrust_section.add_child(weak_button)
	var coast := Button.new(); coast.text = "NESSUNA SPINTA"; coast.pressed.connect(_coast); thrust_section.add_child(coast)
	var actions_section := _make_section(controls_column, "AZIONI")
	var target_row := HBoxContainer.new(); actions_section.add_child(target_row)
	var target_label := Label.new(); target_label.text = "BERSAGLIO"; target_label.custom_minimum_size.x = 82; target_row.add_child(target_label)
	target_picker = OptionButton.new(); target_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; target_picker.item_selected.connect(_target_selected); target_row.add_child(target_picker)
	var actions_grid := GridContainer.new(); actions_grid.columns = 2; actions_section.add_child(actions_grid)
	surface_button = Button.new(); surface_button.pressed.connect(_surface_action); actions_grid.add_child(surface_button)
	for kind in ["mine", "torpedo", "nuke"]:
		var ordnance_button := Button.new(); ordnance_button.text = "LANCIA " + String(kind).to_upper(); ordnance_button.pressed.connect(_launch_ordnance.bind(kind)); actions_grid.add_child(ordnance_button); ordnance_buttons[kind] = ordnance_button
	var torpedo_title := Label.new(); torpedo_title.text = "SILURO: DIREZIONE E SPINTA"; actions_section.add_child(torpedo_title); torpedo_controls.append(torpedo_title)
	var torpedo_grid := GridContainer.new(); torpedo_grid.columns = 6; actions_section.add_child(torpedo_grid); torpedo_controls.append(torpedo_grid)
	for magnitude in [1, 2]:
		for i in range(6):
			var torpedo_step := Button.new(); torpedo_step.text = "%d×%d" % [i + 1, magnitude]; torpedo_step.tooltip_text = "Direzione %d, accelerazione %d" % [i + 1, magnitude]; torpedo_step.pressed.connect(_launch_torpedo.bind(i, magnitude)); torpedo_grid.add_child(torpedo_step)
	attack_button = Button.new(); attack_button.text = "ATTACCA NAVE NEMICA"; attack_button.pressed.connect(_attack); actions_grid.add_child(attack_button)
	ram_button = Button.new(); ram_button.text = "PIANIFICA SPERONAMENTO"; ram_button.pressed.connect(_plan_ram); actions_grid.add_child(ram_button)
	inspect_button = Button.new(); inspect_button.text = "ISPEZIONA / CATTURA"; inspect_button.pressed.connect(_inspect_or_capture); actions_grid.add_child(inspect_button)
	passenger_button = Button.new(); passenger_button.text = "TRASFERISCI PASSEGGERI"; passenger_button.pressed.connect(_transfer_passengers); actions_grid.add_child(passenger_button)
	load_mine_button = Button.new(); load_mine_button.text = "CARICA MINA"; load_mine_button.pressed.connect(_load_lateral_mine); actions_grid.add_child(load_mine_button)
	counter_yes_button = Button.new(); counter_yes_button.text = "CONTRATTACCA"; counter_yes_button.pressed.connect(_counter.bind(true)); actions_grid.add_child(counter_yes_button)
	counter_no_button = Button.new(); counter_no_button.text = "RINUNCIA AL CONTRATTACCO"; counter_no_button.pressed.connect(_counter.bind(false)); actions_grid.add_child(counter_no_button)
	advance_button = Button.new(); advance_button.text = "AVANZA FASE"; advance_button.custom_minimum_size.y = 36; advance_button.pressed.connect(_advance); actions_grid.add_child(advance_button)
	var log_section := _make_section(controls_column, "REGISTRO")
	var log_scroll := ScrollContainer.new(); log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; log_scroll.custom_minimum_size.y = 120; log_section.add_child(log_scroll)
	log_label = Label.new(); log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; log_scroll.add_child(log_label)
	_build_privacy_overlay()
	_build_replay_overlay()
	_build_main_menu()
	_build_help_overlay()

func _make_section(parent: VBoxContainer, title_text: String, expand := false) -> VBoxContainer:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new(); style.bg_color = Color("0d1928"); style.border_color = Color("27435e"); style.set_border_width_all(1); style.corner_radius_top_left = 7; style.corner_radius_top_right = 7; style.corner_radius_bottom_left = 7; style.corner_radius_bottom_right = 7; style.content_margin_left = 10; style.content_margin_right = 10; style.content_margin_top = 8; style.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", style)
	if expand: frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation", 5); frame.add_child(content)
	var title := Label.new(); title.text = title_text; title.modulate = Color("79cce8"); title.add_theme_font_size_override("font_size", 14); content.add_child(title)
	return content

func _build_help_overlay() -> void:
	help_overlay = ColorRect.new(); help_overlay.color = Color("07111fff"); help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; help_overlay.visible = false; add_child(help_overlay)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); help_overlay.add_child(center)
	var card := VBoxContainer.new(); card.custom_minimum_size = Vector2(720, 540); center.add_child(card)
	var title := Label.new(); title.text = "COME SI GIOCA"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 28); card.add_child(title)
	help_body = Label.new(); help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; help_body.size_flags_vertical = Control.SIZE_EXPAND_FILL; help_body.add_theme_font_size_override("font_size", 18); card.add_child(help_body)
	var close := Button.new(); close.text = "HO CAPITO"; close.custom_minimum_size.y = 56; close.pressed.connect(_close_help); card.add_child(close)

func _build_main_menu() -> void:
	menu_overlay = ColorRect.new(); menu_overlay.color = Color("061526ff"); menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(menu_overlay)
	var layout := HBoxContainer.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 34); layout.add_theme_constant_override("separation", 34); menu_overlay.add_child(layout)
	var art_panel := VBoxContainer.new(); art_panel.custom_minimum_size.x = 360; layout.add_child(art_panel)
	var cover := TextureRect.new(); cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; cover.size_flags_vertical = Control.SIZE_EXPAND_FILL; art_panel.add_child(cover)
	cover.texture = load("res://assets/ui/original-cover.webp")
	var rights := Label.new(); rights.text = "Edizione digitale non ufficiale · uso personale\nCopertina fornita dall’utente; diritti dell’opera ai rispettivi autori ed editori."; rights.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; rights.modulate = Color("9db2c6"); art_panel.add_child(rights)
	var form_scroll := ScrollContainer.new(); form_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(form_scroll)
	var form := VBoxContainer.new(); form.size_flags_horizontal = Control.SIZE_EXPAND_FILL; form.add_theme_constant_override("separation", 5); form_scroll.add_child(form)
	var display_font := FontVariation.new(); display_font.base_font = ThemeDB.fallback_font; display_font.variation_embolden = 1.1; display_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.13, 1), Vector2.ZERO)
	var brand := Label.new(); brand.text = "TRIPLANETARY"; brand.add_theme_font_override("font", display_font); brand.add_theme_font_size_override("font_size", 52); brand.add_theme_color_override("font_color", Color("19e18e")); brand.add_theme_color_override("font_outline_color", Color("d6343d")); brand.add_theme_constant_override("outline_size", 3); form.add_child(brand)
	var subtitle := Label.new(); subtitle.text = "SPACE COMBAT IN THE SOLAR SYSTEM"; subtitle.add_theme_font_size_override("font_size", 17); subtitle.add_theme_color_override("font_color", Color("f4f6e9")); form.add_child(subtitle)
	var scenario_label := _menu_heading("SCEGLI LO SCENARIO"); form.add_child(scenario_label)
	var scenario_grid := GridContainer.new(); scenario_grid.columns = 2; scenario_grid.add_theme_constant_override("h_separation", 8); scenario_grid.add_theme_constant_override("v_separation", 5); form.add_child(scenario_grid)
	for i in range(SCENARIO_TITLES.size()):
		var scenario_button := Button.new(); scenario_button.text = "%s\n%s" % [SCENARIO_TITLES[i], SCENARIO_DESCRIPTIONS[i]]; scenario_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; scenario_button.alignment = HORIZONTAL_ALIGNMENT_LEFT; scenario_button.custom_minimum_size = Vector2(330, 58); scenario_button.toggle_mode = true; scenario_button.pressed.connect(_scenario_selected.bind(i)); scenario_grid.add_child(scenario_button); scenario_buttons.append(scenario_button)
	var players_label := _menu_heading("EQUIPAGGI"); form.add_child(players_label)
	var players_grid := GridContainer.new(); players_grid.columns = 6; players_grid.add_theme_constant_override("h_separation", 8); players_grid.add_theme_constant_override("v_separation", 6); form.add_child(players_grid)
	for i in range(6):
		var seat := Label.new(); seat.text = "P%d" % (i + 1); seat.custom_minimum_size.x = 32; seat.modulate = Color("33d2bf"); players_grid.add_child(seat)
		var name_field := LineEdit.new(); name_field.text = "Giocatore %d" % (i + 1); name_field.placeholder_text = "Nome"; name_field.custom_minimum_size = Vector2(175, 38); players_grid.add_child(name_field); player_name_fields.append(name_field)
		var type_field := OptionButton.new(); type_field.add_item("UMANO"); type_field.add_item("IA"); type_field.add_item("NESSUNO"); type_field.select(0 if i < 2 else 2); type_field.custom_minimum_size = Vector2(108, 38); type_field.item_selected.connect(_player_setup_changed); players_grid.add_child(type_field); player_type_fields.append(type_field)
	menu_note = Label.new(); menu_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_note.custom_minimum_size.y = 36; form.add_child(menu_note)
	start_button = Button.new(); start_button.text = "INIZIA LA MISSIONE"; start_button.custom_minimum_size.y = 46; start_button.pressed.connect(_start_from_menu); form.add_child(start_button)
	_apply_menu_theme(menu_overlay)
	_scenario_selected(0)

func _show_main_menu() -> void:
	menu_overlay.visible = true
	menu_overlay.move_to_front()

func _scenario_selected(index: int) -> void:
	selected_scenario = index
	for i in range(scenario_buttons.size()): scenario_buttons[i].button_pressed = i == index
	_refresh_menu_availability()

func _player_setup_changed(_index: int) -> void:
	_refresh_menu_availability()

func _refresh_menu_availability() -> void:
	var active_players := 0
	var has_ai := false
	for field in player_type_fields:
		if field.selected != 2: active_players += 1
		if field.selected == 1: has_ai = true
	var required_players := 2 if selected_scenario == 1 else 2
	var scenario_available := selected_scenario in [0, 1, 2]
	var count_valid := active_players >= required_players if selected_scenario == 0 else active_players == required_players
	var playable := scenario_available and count_valid and not has_ai
	start_button.disabled = not playable
	if not scenario_available:
		menu_note.text = "Scenario presente nelle regole ma non ancora giocabile in questa build."
	elif has_ai:
		menu_note.text = "La modalità IA è predisposta nel menu, ma il pilota automatico fedele alle regole è ancora da implementare."
	elif not count_valid:
		menu_note.text = "Grand Tour richiede almeno due giocatori; Escape ne richiede esattamente due."
	elif selected_scenario == 1:
		menu_note.text = "Escape: Pellegrini contro Enforcers, identità segreta e fuga oltre Giove."
	elif selected_scenario == 2:
		menu_note.text = "Lateral 7: collocazione libera nella Fascia, falsi bersagli e cattura del liner."
	else:
		menu_note.text = "Grand Tour disponibile per %d giocatori in modalità hot-seat." % active_players

func _start_from_menu() -> void:
	var normalized := []
	var player_types := []
	for i in range(player_type_fields.size()):
		if player_type_fields[i].selected == 2: continue
		var candidate := player_name_fields[i].text.strip_edges()
		normalized.append(candidate if candidate != "" else "Giocatore %d" % (i + 1))
		player_types.append("human" if player_type_fields[i].selected == 0 else "ai")
	if selected_scenario == 1: state = EscapeScenarioRef.create_state(normalized)
	elif selected_scenario == 2: state = Lateral7ScenarioRef.create_state(normalized)
	else: state = GrandTourDevRef.create_state(normalized)
	state.player_types = player_types
	board.selected_ship = state.ships[0].id
	var scenario_name := "ESCAPE" if selected_scenario == 1 else ("LATERAL 7" if selected_scenario == 2 else "GRAND TOUR")
	main_title.text = "  TRIPLANETARY\n  %s · HOT-SEAT %d GIOCATORI" % [scenario_name, normalized.size()]
	menu_overlay.visible = false
	_refresh()
	if selected_scenario == 2: _show_privacy("P2", "La Marina colloca per prima il Tycho Brahe e tre falsi bersagli nella Fascia.")

func _menu_heading(text: String) -> Label:
	var label := Label.new(); label.text = text; label.add_theme_font_size_override("font_size", 18); label.add_theme_color_override("font_color", Color("f04b4f")); return label

func _apply_menu_theme(root: Control) -> void:
	var normal := StyleBoxFlat.new(); normal.bg_color = Color("09243a"); normal.border_color = Color("197e82"); normal.set_border_width_all(2); normal.corner_radius_top_left = 5; normal.corner_radius_top_right = 5; normal.corner_radius_bottom_left = 5; normal.corner_radius_bottom_right = 5; normal.content_margin_left = 12; normal.content_margin_right = 12
	var hover := normal.duplicate(); hover.bg_color = Color("0c3a4a"); hover.border_color = Color("33d2bf")
	var pressed := normal.duplicate(); pressed.bg_color = Color("17394a"); pressed.border_color = Color("ef4147"); pressed.set_border_width_all(3)
	var theme := Theme.new(); theme.set_stylebox("normal", "Button", normal); theme.set_stylebox("hover", "Button", hover); theme.set_stylebox("pressed", "Button", pressed); theme.set_stylebox("hover_pressed", "Button", pressed); theme.set_stylebox("focus", "Button", pressed); theme.set_color("font_color", "Button", Color("eaf9f4")); theme.set_color("font_hover_color", "Button", Color("ffffff")); theme.set_color("font_pressed_color", "Button", Color("ffffff")); theme.set_font_size("font_size", "Button", 14); root.theme = theme

func _build_privacy_overlay() -> void:
	privacy_overlay = ColorRect.new(); privacy_overlay.color = Color("070b16f2"); privacy_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); privacy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; privacy_overlay.visible = false; add_child(privacy_overlay)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); privacy_overlay.add_child(center)
	var card := VBoxContainer.new(); card.custom_minimum_size = Vector2(440, 240); center.add_child(card)
	privacy_title = Label.new(); privacy_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; privacy_title.add_theme_font_size_override("font_size", 32); card.add_child(privacy_title)
	privacy_detail = Label.new(); privacy_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; privacy_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; privacy_detail.add_theme_font_size_override("font_size", 18); card.add_child(privacy_detail)
	var reveal := Button.new(); reveal.text = "MOSTRA LA PLANCIA"; reveal.custom_minimum_size.y = 70; reveal.pressed.connect(_dismiss_privacy); card.add_child(reveal)

func _build_replay_overlay() -> void:
	replay_overlay = ColorRect.new(); replay_overlay.color = Color("070b16f2"); replay_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); replay_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; replay_overlay.visible = false; add_child(replay_overlay)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); replay_overlay.add_child(center)
	var card := VBoxContainer.new(); card.custom_minimum_size = Vector2(560, 360); center.add_child(card)
	var title := Label.new(); title.text = "REPLAY DELLA PARTITA"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 28); card.add_child(title)
	replay_text = Label.new(); replay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; replay_text.size_flags_vertical = Control.SIZE_EXPAND_FILL; replay_text.add_theme_font_size_override("font_size", 18); card.add_child(replay_text)
	var controls := HBoxContainer.new(); controls.alignment = BoxContainer.ALIGNMENT_CENTER; card.add_child(controls)
	var previous := Button.new(); previous.text = "◀ PRECEDENTE"; previous.pressed.connect(_replay_step.bind(-1)); controls.add_child(previous)
	var close := Button.new(); close.text = "TORNA ALLA PARTITA"; close.pressed.connect(_close_replay); controls.add_child(close)
	var following := Button.new(); following.text = "SUCCESSIVO ▶"; following.pressed.connect(_replay_step.bind(1)); controls.add_child(following)

func _refresh() -> void:
	board.state = state; board.queue_redraw()
	var combat_prompt := "\nPASSARE A %s: scegliere il contrattacco" % state.pending_combat.defender if not state.pending_combat.is_empty() else ""
	status.text = "GIORNO %d\n%s · %s%s%s" % [state.turn, state.segment, String(state.phase).to_upper(), combat_prompt, "\nVINCITORE: " + state.winner if state.winner != "" else ""]
	phase_help.text = {"setup":"Clicca un esagono di asteroidi libero per collocare il prossimo segnalino coperto.","astrogation":"Seleziona la spinta sul diagramma esagonale. Azzurro: vettore; rosso: gravità; giallo: spinta; arco spesso: rotta.","ordnance":"Lancia un solo ordigno, se presente a bordo.","movement":"Conferma per applicare vettore, spinta e gravità.","combat":"Dichiara un attacco oppure prosegui.","resupply":"Rifornimento e manutenzione alle basi valide."}.get(state.phase, "")
	if state.phase == "setup":
		var setup_unit: Dictionary = Lateral7ScenarioRef.next_setup_unit(state)
		phase_help.text += "\nDa collocare: %s (%d/%d)." % ["nave/segnalino Marina" if setup_unit.get("owner", "") == "P2" else "nave/segnalino Pirati", int(state.get("setup_index", 0)) + 1, Lateral7ScenarioRef.SETUP_UNITS.size()]
	elif state.get("scenario", "") == "lateral-7" and not state.get("lateral7", {}).get("pending_dummy_removal", {}).is_empty():
		phase_help.text = "Prima accelerazione: clicca tre falsi bersagli del tuo colore da rimuovere."
	for child in ships_box.get_children(): child.queue_free()
	for ship: Dictionary in state.ships:
		if ship.owner != state.segment and not state.get("knowledge", {}).get(state.segment, {}).get(ship.id, false): continue
		var state_text: String = "fuggita" if ship.get("escaped", false) else ("catturata" if ship.get("captured", false) else ("distrutta" if ship.destroyed else ("a terra: " + ship.landed_at if ship.get("landed_at", "") != "" else "in volo")))
		var planned: Array = state.commands.get(ship.id, {}).get("thrust_steps", [])
		var velocity: Vector2i = ship.velocity
		var fuel_text := "illimitato" if ship.get("infinite_fuel", false) else str(ship.fuel)
		var display_name: String = ship.name
		if state.get("scenario", "") == "escape" and ship.owner == "P1" and ship.get("secret_cargo", false) and (state.segment == "P1" or ship.get("inspected", false)): display_name += " · FUGGITIVI"
		elif state.get("scenario", "") == "escape" and ship.owner == "P1" and ship.get("inspected", false): display_name += " · ESCA"
		var button := Button.new(); button.text = "%s [%s] · Fuel %s · Vettore (%d,%d) · %s" % [display_name, ship.owner, fuel_text, velocity.x, velocity.y, state_text]; button.tooltip_text = "Spinte pianificate: %d. Corpi visitati: %d." % [planned.size(), ship.visited_bodies.size()]; button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; button.disabled = ship.owner != state.segment; button.pressed.connect(_select.bind(ship.id)); ships_box.add_child(button)
	var entries: Array = state.log.duplicate(); entries.reverse(); log_label.text = "Nessun evento registrato." if entries.is_empty() else "\n\n".join(entries)
	var selected := _selected()
	_refresh_target_picker(selected)
	overload_button.text = "Sovraccarico: %s" % ("ATTIVO" if overload_planning else "spento")
	overload_button.disabled = not GameRulesRef.can_overload(selected) or state.phase != "astrogation"
	var command: Dictionary = state.commands.get(selected.id, {})
	thrust_selector.enabled = state.phase == "astrogation" and selected.owner == state.segment and not selected.destroyed and selected.get("landed_at", "") == ""
	thrust_selector.selected_direction = -1
	if command.get("thrust_steps", []).size() == 1: thrust_selector.selected_direction = HexMathRef.DIRECTIONS.find(command.thrust_steps[0])
	thrust_selector.queue_redraw()
	weak_button.text = "Prima gravità debole: %s" % ("APPLICA" if command.get("use_first_weak_gravity", false) else "ignora")
	surface_button.visible = state.phase != "setup" and (selected.get("landed_at", "") != "" or _landable_body(selected) != "")
	surface_button.text = "DECOLLA" if selected.get("landed_at", "") != "" else "ATTERRA"
	for kind in ordnance_buttons:
		ordnance_buttons[kind].visible = kind != "torpedo" and state.phase == "ordnance" and selected.owner == state.segment and selected.inventory.get(kind, 0) > 0
	var show_torpedo: bool = state.phase == "ordnance" and selected.owner == state.segment and selected.inventory.get("torpedo", 0) > 0 and not selected.commercial
	for control in torpedo_controls: control.visible = show_torpedo
	var combat_pending: bool = not state.pending_combat.is_empty()
	attack_button.visible = state.phase == "combat" and not combat_pending and selected.owner == state.segment and not selected.destroyed and not selected.commercial and selected.get("landed_at", "") == "" and _enemy_target(selected.owner) != ""
	ram_button.visible = state.get("scenario", "") == "escape" and state.phase == "astrogation" and selected.owner == "P1" and selected.get("landed_at", "") == "" and _enemy_target(selected.owner) != ""
	inspect_button.visible = state.get("scenario", "") == "escape" and state.phase == "resupply" and selected.owner == "P2" and _matching_pilgrim(selected) != ""
	passenger_button.visible = state.get("scenario", "") == "lateral-7" and state.phase == "resupply" and selected.owner == "P1" and _passenger_holder_matching(selected) != ""
	load_mine_button.visible = _can_load_lateral_mine(selected)
	counter_yes_button.visible = combat_pending
	counter_no_button.visible = combat_pending
	advance_button.disabled = combat_pending or state.phase == "setup"

func _select(id: String) -> void:
	for ship: Dictionary in state.ships:
		if ship.id == id and ship.owner == state.segment and not ship.destroyed:
			board.selected_ship = id; overload_planning = false; _refresh(); return
func _target_selected(index: int) -> void:
	selected_target_id = str(target_picker.get_item_metadata(index)) if index >= 0 else ""
	_refresh()
func _on_board_hex_clicked(hex: Vector2i) -> void:
	if state.get("scenario", "") == "lateral-7" and not state.get("lateral7", {}).get("pending_dummy_removal", {}).is_empty():
		if Lateral7ScenarioRef.remove_dummy_at(state, hex): _refresh()
		return
	if state.get("scenario", "") != "lateral-7" or state.phase != "setup": return
	var old_index: int = int(state.get("setup_index", 0))
	var old_segment: String = state.segment
	state = Lateral7ScenarioRef.place_next(state, hex)
	if int(state.get("setup_index", 0)) == old_index: return
	_refresh()
	if old_segment != state.segment and state.phase == "setup": _show_privacy(state.segment, "La Marina ha completato la collocazione. Passare il dispositivo ai Pirati.")
	elif state.phase == "astrogation": _select_first_owned_ship(); _refresh(); _show_privacy("P1", "Setup completato. Iniziano i Pirati.")
func _set_thrust(direction: int) -> void:
	var ship := _selected()
	if state.phase != "astrogation" or ship.owner != state.segment or ship.fuel <= 0 or ship.destroyed or ship.get("landed_at", "") != "": return
	var command: Dictionary = state.commands.get(ship.id, {})
	if state.get("scenario", "") == "lateral-7" and ship.get("first_acceleration_pending", false) and not command.get("dummies_removed", false):
		if Lateral7ScenarioRef.begin_dummy_removal(state, ship.id, [HexMathRef.DIRECTIONS[direction]]):
			state.log.append("Prima accelerazione di %s: rimuovere tre falsi bersagli" % ship.name)
		else:
			state.log.append("Il Tycho Brahe non può muovere finché un pirata non viene rilevato")
		_refresh(); return
	var steps: Array = command.get("thrust_steps", [])
	if overload_planning:
		if not GameRulesRef.can_overload(ship): return
		if steps.size() >= 2: steps = []
		steps.append(HexMathRef.DIRECTIONS[direction])
	else:
		steps = [HexMathRef.DIRECTIONS[direction]]
	command.thrust_steps = steps
	state.commands[ship.id] = command
	ReplayRulesRef.record(state, "Pianificazione spinta " + ship.name)
	_refresh()
func _coast() -> void:
	var ship := _selected()
	if state.phase == "astrogation" and ship.owner == state.segment:
		var command: Dictionary = state.commands.get(ship.id, {})
		command.thrust_steps = []
		state.commands[ship.id] = command
		ReplayRulesRef.record(state, "Deriva pianificata " + ship.name)
		_refresh()
func _toggle_overload() -> void: overload_planning = not overload_planning; _refresh()
func _toggle_weak_gravity() -> void:
	var ship := _selected()
	if state.phase != "astrogation" or ship.owner != state.segment: return
	var command: Dictionary = state.commands.get(ship.id, {})
	command.use_first_weak_gravity = not command.get("use_first_weak_gravity", false)
	state.commands[ship.id] = command; _refresh()
func _surface_action() -> void:
	var ship := _selected()
	if state.phase != "astrogation" or ship.owner != state.segment: return
	var command: Dictionary = state.commands.get(ship.id, {})
	if ship.get("landed_at", "") != "": command = {"takeoff": true}
	else:
		var body_id := _landable_body(ship)
		if body_id == "": return
		command = {"land_body_id": body_id}
	state.commands[ship.id] = command; _refresh()
func _attack() -> void:
	var ship := _selected()
	var target_id := _enemy_target(ship.owner)
	if target_id == "": return
	state = GameRulesRef.declare_attack(state, ship.id, target_id)
	ReplayRulesRef.record(state, "Dichiarazione di attacco")
	_refresh()
	if not state.pending_combat.is_empty():
		_show_privacy(state.pending_combat.defender, "È richiesta una decisione riservata sul contrattacco.")
func _inspect_or_capture() -> void:
	var inspector := _selected()
	var target_id := _matching_pilgrim(inspector)
	if target_id == "": return
	state = GameRulesRef.inspect_or_capture(state, inspector.id, target_id)
	ReplayRulesRef.record(state, "Ispezione Enforcer")
	_refresh()
func _plan_ram() -> void:
	var ship := _selected()
	var target_id := _enemy_target(ship.owner)
	if target_id == "": return
	var command: Dictionary = state.commands.get(ship.id, {})
	command.ram_target_id = target_id
	state.commands[ship.id] = command
	state.log.append("Speronamento pianificato da %s" % ship.name)
	_refresh()
func _transfer_passengers() -> void:
	var target := _selected()
	var holder_id := _passenger_holder_matching(target)
	if holder_id == "": return
	state = Lateral7ScenarioRef.transfer_passengers(state, holder_id, target.id)
	ReplayRulesRef.record(state, "Trasferimento passeggeri")
	_refresh()
func _load_lateral_mine() -> void:
	state = Lateral7ScenarioRef.load_mine(state, _selected().id)
	ReplayRulesRef.record(state, "Carico mina a Clandestine")
	_refresh()
func _counter(enabled: bool) -> void:
	state = GameRulesRef.respond_to_attack(state, enabled)
	ReplayRulesRef.record(state, "Risoluzione combattimento")
	_refresh()
func _launch_ordnance(kind: String) -> void:
	var ship := _selected()
	state = OrdnanceRulesRef.launch(state, ship.id, kind)
	ReplayRulesRef.record(state, "Lancio " + kind)
	_refresh()
func _launch_torpedo(direction: int, magnitude: int) -> void:
	var ship := _selected()
	state = OrdnanceRulesRef.launch(state, ship.id, "torpedo", HexMathRef.DIRECTIONS[direction] * magnitude)
	ReplayRulesRef.record(state, "Lancio siluro")
	_refresh()
func _advance() -> void:
	var old_segment: String = state.segment
	state = GameRulesRef.advance_phase(state)
	if state.segment != old_segment: _select_first_owned_ship()
	ReplayRulesRef.record(state, "Avanzamento fase")
	PersistenceRef.save_game(state)
	_refresh()
	if state.segment != old_segment:
		_show_privacy(state.segment, "Inizia il segmento di %s. Passa il dispositivo senza mostrare la plancia." % state.segment)
func _reset() -> void: overload_planning = false; _show_main_menu()
func _save() -> void:
	PersistenceRef.save_game(state)
	state.log.append("Partita salvata localmente")
	_refresh()
func _load() -> void:
	var loaded: Dictionary = PersistenceRef.load_game()
	if loaded.is_empty():
		state.log.append("Nessun salvataggio disponibile")
	else:
		state = loaded
		_select_first_owned_ship()
		state.log.append("Partita caricata")
	_refresh()

func _copy_portable_save() -> void:
	DisplayServer.clipboard_set(PersistenceRef.to_portable_json(state))
	state.log.append("Salvataggio portabile copiato negli appunti")
	_refresh()

func _paste_portable_save() -> void:
	var loaded := PersistenceRef.from_portable_json(DisplayServer.clipboard_get())
	if loaded.is_empty():
		state.log.append("Importazione non riuscita: dati non validi")
	else:
		state = loaded
		_select_first_owned_ship()
		state.log.append("Salvataggio portabile importato")
		PersistenceRef.save_game(state)
	_refresh()

func _show_privacy(player: String, detail: String) -> void:
	privacy_title.text = "PASSA A " + player
	privacy_detail.text = detail
	privacy_overlay.visible = true
	privacy_overlay.move_to_front()

func _dismiss_privacy() -> void:
	privacy_overlay.visible = false

func _open_replay() -> void:
	if state.get("replay_frames", []).is_empty(): return
	replay_cursor = state.replay_frames.size() - 1
	replay_overlay.visible = true
	replay_overlay.move_to_front()
	_refresh_replay()

func _close_replay() -> void:
	replay_overlay.visible = false

func _replay_step(delta: int) -> void:
	replay_cursor = clampi(replay_cursor + delta, 0, state.replay_frames.size() - 1)
	_refresh_replay()

func _refresh_replay() -> void:
	replay_text.text = ReplayRulesRef.describe(state.replay_frames[replay_cursor])

func _open_help() -> void:
	if state.get("scenario", "") == "escape":
		help_body.text = "OBIETTIVO · ESCAPE\nI Pellegrini devono portare il trasporto con i fuggitivi fuori dal bordo oltre Giove. Per la vittoria decisiva deve restare carburante sufficiente ad annullare il vettore, più un punto.\n\nPELLEGRINI — Tre trasporti partono dalla Terra. Solo il giocatore P1 vede quale contiene i fuggitivi. Possono speronare, ma non usare mine o siluri.\n\nENFORCERS — Una corvetta orbita la Terra e un corsaro orbita Venere. Seleziona il bersaglio nel blocco Azioni. A rotta e posizione coincidenti, durante Rifornimento usa Ispeziona/Cattura. Un trasporto disabilitato con i fuggitivi può essere catturato e riportato a Terra, Venere o Io.\n\nVITTORIA — La fuga può essere decisiva o marginale; la distruzione di un Enforcer durante il sacrificio dà una vittoria morale ai Pellegrini. Cattura e ritorno a una base danno vittoria decisiva agli Enforcers.\n\nMAPPA — Rotella per zoomare; trascina per scorrere. Vettore azzurro, spinta gialla, rotta percorsa continua."
	elif state.get("scenario", "") == "lateral-7":
		help_body.text = "OBIETTIVO · LATERAL 7\nI Pirati devono affiancare il liner, trasferire i passeggeri e portarli a Clandestine. La Marina deve condurre il liner a Ganimede. Se i passeggeri vengono distrutti, perdono entrambi.\n\nSETUP — La Marina colloca per prima il Tycho Brahe e tre falsi bersagli in esagoni asteroidali liberi; i Pirati collocano poi tre navi e nove falsi bersagli. Clicca gli esagoni indicati sulla plancia. Tutte le unità reali partono ferme.\n\nFALSI BERSAGLI — Alla prima accelerazione di ciascuna nave pirata, clicca tre dummy pirata da rimuovere. Il dreadnought rimuove i suoi tre dummy alla prima accelerazione e non può muovere finché una nave o base non rileva un pirata.\n\nPASSEGGERI — Con una nave pirata sulla stessa posizione e con lo stesso vettore del liner, usa Trasferisci passeggeri durante Rifornimento. Arriva fermo a Clandestine per vincere.\n\nDOTAZIONI — Ogni corsaro pirata ha una mina. Il Tycho Brahe ha una mina e un siluro. I Pirati attraversano liberamente gli asteroidi blu intorno a Clandestine."
	else:
		help_body.text = "OBIETTIVO · GRAND TOUR\nAttraversa almeno un campo di gravità piena di ogni corpo e torna ad atterrare sulla Terra.\n\n1 · ASTROGAZIONE — Seleziona la nave e una direzione di spinta, oppure Nessuna spinta. Il vettore è azzurro tratteggiato; la spinta è il tratteggio giallo più fine e termina nell'esagono di arrivo. La rotta effettivamente percorsa resta come arco continuo e spesso.\n\n2 · ORDNANCE — Se disponibili, lancia mine, siluri o testate.\n\n3 · MOVIMENTO — Premi Avanza fase: inerzia, spinta e gravità pendente vengono applicate.\n\n4 · COMBATTIMENTO — Seleziona il bersaglio, dichiara l’attacco e lascia scegliere il contrattacco.\n\n5 · RIFORNIMENTO — Atterrando su Terra, Venere, Marte o Callisto recuperi carburante e sovraccarico.\n\nMAPPA — Usa la rotella per ingrandire o ridurre e trascina con il tasto sinistro o centrale.\n\nDECOLLO — Premi Decolla, poi pianifica almeno una spinta nel turno successivo: senza spinta la nave ricade."
	help_overlay.visible = true
	help_overlay.move_to_front()

func _close_help() -> void:
	help_overlay.visible = false

func _select_first_owned_ship() -> void:
	for ship: Dictionary in state.ships:
		if ship.owner == state.segment and not ship.destroyed:
			board.selected_ship = ship.id
			return
func _selected() -> Dictionary:
	for ship: Dictionary in state.ships:
		if ship.id == board.selected_ship: return ship
	return state.ships[0]

func _landable_body(ship: Dictionary) -> String:
	for body: Dictionary in state.bodies:
		if GameRulesRef.can_land(ship, body): return body.id
	return ""

func _enemy_target(owner: String) -> String:
	for ship: Dictionary in state.ships:
		if ship.id == selected_target_id and ship.owner != owner and not ship.destroyed and not ship.get("escaped", false) and not ship.get("captured", false): return ship.id
	for ship: Dictionary in state.ships:
		if ship.owner != owner and not ship.destroyed and not ship.get("escaped", false) and not ship.get("captured", false) and ship.get("landed_at", "") == "": return ship.id
	return ""

func _refresh_target_picker(selected: Dictionary) -> void:
	var prior := selected_target_id
	target_picker.clear()
	for ship: Dictionary in state.ships:
		if ship.owner == selected.owner or ship.destroyed or ship.get("escaped", false) or ship.get("captured", false): continue
		if not state.get("knowledge", {}).get(selected.owner, {}).get(ship.id, false): continue
		target_picker.add_item(ship.name)
		target_picker.set_item_metadata(target_picker.item_count - 1, ship.id)
	var selected_index := -1
	for i in range(target_picker.item_count):
		if str(target_picker.get_item_metadata(i)) == prior: selected_index = i
	if selected_index < 0 and target_picker.item_count > 0: selected_index = 0
	if selected_index >= 0:
		target_picker.select(selected_index)
		selected_target_id = str(target_picker.get_item_metadata(selected_index))
	else: selected_target_id = ""
	target_picker.visible = target_picker.item_count > 0

func _matching_pilgrim(inspector: Dictionary) -> String:
	for ship: Dictionary in state.ships:
		if ship.id == selected_target_id and ship.owner == "P1" and not ship.destroyed and not ship.get("escaped", false) and not ship.get("captured", false) and ship.position == inspector.position and ship.velocity == inspector.velocity: return ship.id
	for ship: Dictionary in state.ships:
		if ship.owner == "P1" and not ship.destroyed and not ship.get("escaped", false) and not ship.get("captured", false) and ship.position == inspector.position and ship.velocity == inspector.velocity: return ship.id
	return ""

func _passenger_holder_matching(target: Dictionary) -> String:
	var holder_id: String = state.get("lateral7", {}).get("passenger_holder", "")
	for ship: Dictionary in state.ships:
		if ship.id == holder_id and not ship.destroyed and ship.position == target.position and ship.velocity == target.velocity: return holder_id
	return ""

func _can_load_lateral_mine(ship: Dictionary) -> bool:
	if state.get("scenario", "") != "lateral-7" or state.phase != "resupply" or ship.owner != "P1": return false
	var clandestine: Dictionary = state.bodies.filter(func(body): return body.id == "clandestine")[0]
	return ship.position == clandestine.hex and ship.velocity == Vector2i.ZERO and not ship.destroyed
