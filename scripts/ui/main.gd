extends Control

const HexMathRef = preload("res://scripts/engine/hex.gd")
const GameRulesRef = preload("res://scripts/engine/game.gd")
const GrandTourDevRef = preload("res://scripts/data/grand_tour_dev.gd")
const BoardRef = preload("res://scripts/ui/board.gd")
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
var surface_button: Button
var attack_button: Button
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
var scenario_picker: OptionButton
var player_count: SpinBox
var player_names_input: LineEdit
var menu_note: Label
var start_button: Button
var main_title: Label
var phase_help: Label
var help_overlay: ColorRect

func _ready() -> void:
	state = GrandTourDevRef.create_state()
	_build_ui()
	_refresh()
	_show_main_menu()

func _build_ui() -> void:
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root)
	var header := HBoxContainer.new(); header.custom_minimum_size.y = 76; root.add_child(header)
	main_title = Label.new(); main_title.text = "  TRIPLANETARY\n  GRAND TOUR · HOT-SEAT"; main_title.add_theme_font_size_override("font_size", 24); main_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(main_title)
	var reset := Button.new(); reset.text = "Nuova partita"; reset.custom_minimum_size.x = 110; reset.pressed.connect(_reset); header.add_child(reset)
	var save := Button.new(); save.text = "Salva"; save.custom_minimum_size.x = 70; save.pressed.connect(_save); header.add_child(save)
	var load_game := Button.new(); load_game.text = "Carica"; load_game.custom_minimum_size.x = 70; load_game.pressed.connect(_load); header.add_child(load_game)
	var copy_game := Button.new(); copy_game.text = "Esporta"; copy_game.tooltip_text = "Copia un salvataggio portabile negli appunti"; copy_game.pressed.connect(_copy_portable_save); header.add_child(copy_game)
	var paste_game := Button.new(); paste_game.text = "Importa"; paste_game.tooltip_text = "Carica il salvataggio presente negli appunti"; paste_game.pressed.connect(_paste_portable_save); header.add_child(paste_game)
	var replay := Button.new(); replay.text = "Replay"; replay.pressed.connect(_open_replay); header.add_child(replay)
	var help := Button.new(); help.text = "Come si gioca"; help.pressed.connect(_open_help); header.add_child(help)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(split)
	board = BoardRef.new(); board.custom_minimum_size = Vector2(760, 600); board.size_flags_horizontal = Control.SIZE_EXPAND_FILL; board.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.add_child(board)
	var panel := VBoxContainer.new(); panel.custom_minimum_size.x = 390; panel.add_theme_constant_override("separation", 8); split.add_child(panel)
	var controls_scroll := ScrollContainer.new(); controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; panel.add_child(controls_scroll)
	var controls_column := VBoxContainer.new(); controls_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; controls_column.add_theme_constant_override("separation", 8); controls_scroll.add_child(controls_column)
	var info_section := _make_section(controls_column, "STATO E NAVI")
	status = Label.new(); status.add_theme_font_size_override("font_size", 18); info_section.add_child(status)
	phase_help = Label.new(); phase_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; phase_help.modulate = Color("9fd9ed"); info_section.add_child(phase_help)
	var ship_scroll := ScrollContainer.new(); ship_scroll.custom_minimum_size.y = 58; ship_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; info_section.add_child(ship_scroll)
	ships_box = VBoxContainer.new(); ships_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ship_scroll.add_child(ships_box)
	var thrust_section := _make_section(controls_column, "VETTORE E SPINTA")
	var grid := GridContainer.new(); grid.columns = 3; thrust_section.add_child(grid)
	var direction_labels := ["EST  1", "NE  2", "NO  3", "OVEST  4", "SO  5", "SE  6"]
	for i in range(6):
		var button := Button.new(); button.text = direction_labels[i]; button.tooltip_text = "Spinta nella direzione %d" % (i + 1); button.pressed.connect(_set_thrust.bind(i)); grid.add_child(button)
	overload_button = Button.new(); overload_button.pressed.connect(_toggle_overload); thrust_section.add_child(overload_button)
	weak_button = Button.new(); weak_button.pressed.connect(_toggle_weak_gravity); thrust_section.add_child(weak_button)
	var coast := Button.new(); coast.text = "NESSUNA SPINTA"; coast.pressed.connect(_coast); thrust_section.add_child(coast)
	# Le azioni restano sempre visibili; solo stato e pianificazione scorrono se lo spazio è ridotto.
	var actions_section := _make_section(panel, "AZIONI")
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
	counter_yes_button = Button.new(); counter_yes_button.text = "CONTRATTACCA"; counter_yes_button.pressed.connect(_counter.bind(true)); actions_grid.add_child(counter_yes_button)
	counter_no_button = Button.new(); counter_no_button.text = "RINUNCIA AL CONTRATTACCO"; counter_no_button.pressed.connect(_counter.bind(false)); actions_grid.add_child(counter_no_button)
	advance_button = Button.new(); advance_button.text = "AVANZA FASE"; advance_button.custom_minimum_size.y = 36; advance_button.pressed.connect(_advance); actions_grid.add_child(advance_button)
	var log_section := _make_section(panel, "REGISTRO")
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
	var title := Label.new(); title.text = "COME SI GIOCA · GRAND TOUR"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size", 28); card.add_child(title)
	var body := Label.new(); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_font_size_override("font_size", 18); body.text = "OBIETTIVO\nAttraversa almeno un campo di gravità piena di ogni corpo e torna ad atterrare sulla Terra.\n\n1 · ASTROGAZIONE — Seleziona la nave e una direzione di spinta, oppure Nessuna spinta. Il vettore è azzurro tratteggiato; la spinta è il tratteggio giallo più fine e termina nell'esagono di arrivo. La rotta effettivamente percorsa resta come arco continuo e spesso.\n\n2 · ORDNANCE — Se disponibili, lancia mine, siluri o testate.\n\n3 · MOVIMENTO — Premi Avanza fase: inerzia, spinta e gravità pendente vengono applicate.\n\n4 · COMBATTIMENTO — Se un bersaglio rilevato è raggiungibile, dichiara l’attacco; l’altro giocatore sceglie il contrattacco.\n\n5 · RIFORNIMENTO — Atterrando su Terra, Venere, Marte o Callisto recuperi carburante e sovraccarico.\n\nMAPPA — Usa la rotella per ingrandire o ridurre e trascina con il tasto sinistro o centrale.\n\nDECOLLO — Premi Decolla, poi pianifica almeno una spinta nel turno successivo: senza spinta la nave ricade."; card.add_child(body)
	var close := Button.new(); close.text = "HO CAPITO"; close.custom_minimum_size.y = 56; close.pressed.connect(_close_help); card.add_child(close)

func _build_main_menu() -> void:
	menu_overlay = ColorRect.new(); menu_overlay.color = Color("050b17ff"); menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(menu_overlay)
	var layout := HBoxContainer.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 54); layout.add_theme_constant_override("separation", 48); menu_overlay.add_child(layout)
	var art_panel := VBoxContainer.new(); art_panel.custom_minimum_size.x = 430; layout.add_child(art_panel)
	var cover := TextureRect.new(); cover.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL; cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; cover.size_flags_vertical = Control.SIZE_EXPAND_FILL; art_panel.add_child(cover)
	cover.texture = load("res://assets/ui/original-cover.webp")
	var rights := Label.new(); rights.text = "Edizione digitale non ufficiale · uso personale\nCopertina fornita dall’utente; diritti dell’opera ai rispettivi autori ed editori."; rights.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; rights.modulate = Color("9db2c6"); art_panel.add_child(rights)
	var form := VBoxContainer.new(); form.size_flags_horizontal = Control.SIZE_EXPAND_FILL; form.alignment = BoxContainer.ALIGNMENT_CENTER; layout.add_child(form)
	var brand := Label.new(); brand.text = "TRIPLANETARY"; brand.add_theme_font_size_override("font_size", 48); brand.modulate = Color("e7f5ff"); form.add_child(brand)
	var subtitle := Label.new(); subtitle.text = "COMBATTIMENTO SPAZIALE NEL SISTEMA SOLARE"; subtitle.add_theme_font_size_override("font_size", 16); subtitle.modulate = Color("74c9e8"); form.add_child(subtitle)
	var spacer := Control.new(); spacer.custom_minimum_size.y = 32; form.add_child(spacer)
	var scenario_label := Label.new(); scenario_label.text = "SCENARIO"; form.add_child(scenario_label)
	scenario_picker = OptionButton.new(); scenario_picker.custom_minimum_size.y = 48; form.add_child(scenario_picker)
	for title in ["Grand Tour, 2037 AD", "Escape", "Lateral 7", "Nova", "Retribution", "The Fleet Mutiny", "Interplanetary War", "Prospecting"]: scenario_picker.add_item(title)
	scenario_picker.item_selected.connect(_scenario_selected)
	var count_label := Label.new(); count_label.text = "GIOCATORI"; form.add_child(count_label)
	player_count = SpinBox.new(); player_count.min_value = 2; player_count.max_value = 6; player_count.value = 2; player_count.custom_minimum_size.y = 44; form.add_child(player_count)
	var names_label := Label.new(); names_label.text = "NOMI (separati da virgola)"; form.add_child(names_label)
	player_names_input = LineEdit.new(); player_names_input.text = "Giocatore 1, Giocatore 2"; player_names_input.custom_minimum_size.y = 44; form.add_child(player_names_input)
	menu_note = Label.new(); menu_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; menu_note.custom_minimum_size.y = 75; form.add_child(menu_note)
	start_button = Button.new(); start_button.text = "INIZIA PARTITA"; start_button.custom_minimum_size.y = 64; start_button.pressed.connect(_start_from_menu); form.add_child(start_button)
	_scenario_selected(0)

func _show_main_menu() -> void:
	menu_overlay.visible = true
	menu_overlay.move_to_front()

func _scenario_selected(index: int) -> void:
	var playable := index == 0
	start_button.disabled = not playable
	player_count.editable = playable
	menu_note.text = "Scenario completo disponibile: gara orbitale, carburante, gravità, combattimento e ritorno sulla Terra." if playable else "Scenario trascritto fedelmente dalle regole, ma non ancora abilitato: mancano le meccaniche specifiche necessarie."

func _start_from_menu() -> void:
	var requested := int(player_count.value)
	var names := PackedStringArray(player_names_input.text.split(",", false))
	var normalized := []
	for i in range(requested):
		var candidate := names[i].strip_edges() if i < names.size() else ""
		normalized.append(candidate if candidate != "" else "Giocatore %d" % (i + 1))
	state = GrandTourDevRef.create_state(normalized)
	board.selected_ship = state.ships[0].id
	main_title.text = "  TRIPLANETARY\n  GRAND TOUR · HOT-SEAT %d GIOCATORI" % requested
	menu_overlay.visible = false
	_refresh()

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
	phase_help.text = {"astrogation":"Azzurro tratteggiato: vettore. Giallo fine: spinta. Linea spessa: rotta già percorsa.","ordnance":"Lancia un solo ordigno, se presente a bordo.","movement":"Conferma per applicare vettore, spinta e gravità.","combat":"Dichiara un attacco oppure prosegui.","resupply":"Rifornimento e manutenzione alle basi valide."}.get(state.phase, "")
	for child in ships_box.get_children(): child.queue_free()
	for ship: Dictionary in state.ships:
		if ship.owner != state.segment and not state.get("knowledge", {}).get(state.segment, {}).get(ship.id, false): continue
		var state_text: String = "distrutta" if ship.destroyed else ("a terra: " + ship.landed_at if ship.get("landed_at", "") != "" else "in volo")
		var planned: Array = state.commands.get(ship.id, {}).get("thrust_steps", [])
		var velocity: Vector2i = ship.velocity
		var fuel_text := "illimitato" if ship.get("infinite_fuel", false) else str(ship.fuel)
		var button := Button.new(); button.text = "%s [%s]  |  Fuel %s  |  Vettore (%d,%d)  |  %s" % [ship.name, ship.owner, fuel_text, velocity.x, velocity.y, state_text]; button.tooltip_text = "Spinte pianificate: %d. Corpi visitati: %d." % [planned.size(), ship.visited_bodies.size()]; button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.pressed.connect(_select.bind(ship.id)); ships_box.add_child(button)
	var entries: Array = state.log.duplicate(); entries.reverse(); log_label.text = "Nessun evento registrato." if entries.is_empty() else "\n\n".join(entries)
	var selected := _selected()
	overload_button.text = "Sovraccarico: %s" % ("ATTIVO" if overload_planning else "spento")
	overload_button.disabled = not GameRulesRef.can_overload(selected) or state.phase != "astrogation"
	var command: Dictionary = state.commands.get(selected.id, {})
	weak_button.text = "Prima gravità debole: %s" % ("APPLICA" if command.get("use_first_weak_gravity", false) else "ignora")
	surface_button.visible = selected.get("landed_at", "") != "" or _landable_body(selected) != ""
	surface_button.text = "DECOLLA" if selected.get("landed_at", "") != "" else "ATTERRA"
	for kind in ordnance_buttons:
		ordnance_buttons[kind].visible = kind != "torpedo" and state.phase == "ordnance" and selected.owner == state.segment and selected.inventory.get(kind, 0) > 0
	var show_torpedo: bool = state.phase == "ordnance" and selected.owner == state.segment and selected.inventory.get("torpedo", 0) > 0 and not selected.commercial
	for control in torpedo_controls: control.visible = show_torpedo
	var combat_pending: bool = not state.pending_combat.is_empty()
	attack_button.visible = state.phase == "combat" and not combat_pending and selected.owner == state.segment and not selected.destroyed and not selected.commercial and selected.get("landed_at", "") == "" and _enemy_target(selected.owner) != ""
	counter_yes_button.visible = combat_pending
	counter_no_button.visible = combat_pending
	advance_button.disabled = combat_pending

func _select(id: String) -> void: board.selected_ship = id; overload_planning = false; _refresh()
func _set_thrust(direction: int) -> void:
	var ship := _selected()
	if state.phase != "astrogation" or ship.owner != state.segment or ship.fuel <= 0 or ship.destroyed or ship.get("landed_at", "") != "": return
	var command: Dictionary = state.commands.get(ship.id, {})
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
	ReplayRulesRef.record(state, "Avanzamento fase")
	PersistenceRef.save_game(state)
	_refresh()
	if state.segment != old_segment:
		_select_first_owned_ship()
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
		board.selected_ship = state.ships[0].id
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
		if ship.owner != owner and not ship.destroyed and ship.get("landed_at", "") == "": return ship.id
	return ""
