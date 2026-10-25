extends Control

const HexMathRef = preload("res://scripts/engine/hex.gd")
const GameRulesRef = preload("res://scripts/engine/game.gd")
const GrandTourDevRef = preload("res://scripts/data/grand_tour_dev.gd")
const BoardRef = preload("res://scripts/ui/board.gd")
const PersistenceRef = preload("res://scripts/engine/persistence.gd")
const OrdnanceRulesRef = preload("res://scripts/engine/ordnance.gd")

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

func _ready() -> void:
	state = GrandTourDevRef.create_state()
	_build_ui()
	_refresh()

func _build_ui() -> void:
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root)
	var header := HBoxContainer.new(); header.custom_minimum_size.y = 76; root.add_child(header)
	var title := Label.new(); title.text = "  TRIPLANETARY\n  GRAND TOUR · HOT-SEAT"; title.add_theme_font_size_override("font_size", 24); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(title)
	var reset := Button.new(); reset.text = "Nuova partita"; reset.custom_minimum_size.x = 110; reset.pressed.connect(_reset); header.add_child(reset)
	var save := Button.new(); save.text = "Salva"; save.custom_minimum_size.x = 70; save.pressed.connect(_save); header.add_child(save)
	var load_game := Button.new(); load_game.text = "Carica"; load_game.custom_minimum_size.x = 70; load_game.pressed.connect(_load); header.add_child(load_game)
	var copy_game := Button.new(); copy_game.text = "Esporta"; copy_game.tooltip_text = "Copia un salvataggio portabile negli appunti"; copy_game.pressed.connect(_copy_portable_save); header.add_child(copy_game)
	var paste_game := Button.new(); paste_game.text = "Importa"; paste_game.tooltip_text = "Carica il salvataggio presente negli appunti"; paste_game.pressed.connect(_paste_portable_save); header.add_child(paste_game)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(split)
	board = BoardRef.new(); board.custom_minimum_size = Vector2(760, 600); board.size_flags_horizontal = Control.SIZE_EXPAND_FILL; board.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.add_child(board)
	var panel := VBoxContainer.new(); panel.custom_minimum_size.x = 360; split.add_child(panel)
	status = Label.new(); status.add_theme_font_size_override("font_size", 20); panel.add_child(status)
	ships_box = VBoxContainer.new(); panel.add_child(ships_box)
	var thrust_title := Label.new(); thrust_title.text = "SPINTA"; panel.add_child(thrust_title)
	var grid := GridContainer.new(); grid.columns = 3; panel.add_child(grid)
	for i in range(6):
		var button := Button.new(); button.text = "Direzione %d" % (i + 1); button.pressed.connect(_set_thrust.bind(i)); grid.add_child(button)
	overload_button = Button.new(); overload_button.pressed.connect(_toggle_overload); panel.add_child(overload_button)
	weak_button = Button.new(); weak_button.pressed.connect(_toggle_weak_gravity); panel.add_child(weak_button)
	var coast := Button.new(); coast.text = "Nessuna spinta"; coast.pressed.connect(_coast); panel.add_child(coast)
	surface_button = Button.new(); surface_button.pressed.connect(_surface_action); panel.add_child(surface_button)
	for kind in ["mine", "torpedo", "nuke"]:
		var ordnance_button := Button.new(); ordnance_button.text = "LANCIA " + String(kind).to_upper(); ordnance_button.pressed.connect(_launch_ordnance.bind(kind)); panel.add_child(ordnance_button); ordnance_buttons[kind] = ordnance_button
	var torpedo_title := Label.new(); torpedo_title.text = "SILURO: DIREZIONE E SPINTA"; panel.add_child(torpedo_title); torpedo_controls.append(torpedo_title)
	var torpedo_grid := GridContainer.new(); torpedo_grid.columns = 6; panel.add_child(torpedo_grid); torpedo_controls.append(torpedo_grid)
	for magnitude in [1, 2]:
		for i in range(6):
			var torpedo_step := Button.new(); torpedo_step.text = "%d×%d" % [i + 1, magnitude]; torpedo_step.tooltip_text = "Direzione %d, accelerazione %d" % [i + 1, magnitude]; torpedo_step.pressed.connect(_launch_torpedo.bind(i, magnitude)); torpedo_grid.add_child(torpedo_step)
	attack_button = Button.new(); attack_button.text = "ATTACCA NAVE NEMICA"; attack_button.pressed.connect(_attack); panel.add_child(attack_button)
	counter_yes_button = Button.new(); counter_yes_button.text = "CONTRATTACCA"; counter_yes_button.pressed.connect(_counter.bind(true)); panel.add_child(counter_yes_button)
	counter_no_button = Button.new(); counter_no_button.text = "RINUNCIA AL CONTRATTACCO"; counter_no_button.pressed.connect(_counter.bind(false)); panel.add_child(counter_no_button)
	advance_button = Button.new(); advance_button.text = "AVANZA FASE"; advance_button.pressed.connect(_advance); panel.add_child(advance_button)
	log_label = Label.new(); log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL; panel.add_child(log_label)
	var note := Label.new(); note.text = "Mappa di sviluppo: coordinate non definitive.\nNessun asset allegato è incluso."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; panel.add_child(note)
	_build_privacy_overlay()

func _build_privacy_overlay() -> void:
	privacy_overlay = ColorRect.new(); privacy_overlay.color = Color("f2070b16"); privacy_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); privacy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; privacy_overlay.visible = false; add_child(privacy_overlay)
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); privacy_overlay.add_child(center)
	var card := VBoxContainer.new(); card.custom_minimum_size = Vector2(440, 240); center.add_child(card)
	privacy_title = Label.new(); privacy_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; privacy_title.add_theme_font_size_override("font_size", 32); card.add_child(privacy_title)
	privacy_detail = Label.new(); privacy_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; privacy_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; privacy_detail.add_theme_font_size_override("font_size", 18); card.add_child(privacy_detail)
	var reveal := Button.new(); reveal.text = "MOSTRA LA PLANCIA"; reveal.custom_minimum_size.y = 70; reveal.pressed.connect(_dismiss_privacy); card.add_child(reveal)

func _refresh() -> void:
	board.state = state; board.queue_redraw()
	var combat_prompt := "\nPASSARE A %s: scegliere il contrattacco" % state.pending_combat.defender if not state.pending_combat.is_empty() else ""
	status.text = "GIORNO %d\n%s · %s%s%s" % [state.turn, state.segment, String(state.phase).to_upper(), combat_prompt, "\nVINCITORE: " + state.winner if state.winner != "" else ""]
	for child in ships_box.get_children(): child.queue_free()
	for ship: Dictionary in state.ships:
		if ship.owner != state.segment and not state.get("knowledge", {}).get(state.segment, {}).get(ship.id, false): continue
		var state_text: String = "distrutta" if ship.destroyed else ("a terra: " + ship.landed_at if ship.get("landed_at", "") != "" else "in volo")
		var planned: Array = state.commands.get(ship.id, {}).get("thrust_steps", [])
		var button := Button.new(); button.text = "%s · %s · fuel %d · v%s · %s\nSpinte: %d · Visitati: %s" % [ship.name, ship.owner, ship.fuel, ship.velocity, state_text, planned.size(), ", ".join(ship.visited_bodies)]; button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.pressed.connect(_select.bind(ship.id)); ships_box.add_child(button)
	var recent: Array = state.log.slice(maxi(0, state.log.size() - 8)); recent.reverse(); log_label.text = "REGISTRO\n" + "\n".join(recent)
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
	_refresh()
func _coast() -> void:
	var ship := _selected()
	if state.phase == "astrogation" and ship.owner == state.segment:
		var command: Dictionary = state.commands.get(ship.id, {})
		command.thrust_steps = []
		state.commands[ship.id] = command
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
	_refresh()
	if not state.pending_combat.is_empty():
		_show_privacy(state.pending_combat.defender, "È richiesta una decisione riservata sul contrattacco.")
func _counter(enabled: bool) -> void:
	state = GameRulesRef.respond_to_attack(state, enabled)
	_refresh()
func _launch_ordnance(kind: String) -> void:
	var ship := _selected()
	state = OrdnanceRulesRef.launch(state, ship.id, kind)
	_refresh()
func _launch_torpedo(direction: int, magnitude: int) -> void:
	var ship := _selected()
	state = OrdnanceRulesRef.launch(state, ship.id, "torpedo", HexMathRef.DIRECTIONS[direction] * magnitude)
	_refresh()
func _advance() -> void:
	var old_segment: String = state.segment
	state = GameRulesRef.advance_phase(state)
	PersistenceRef.save_game(state)
	_refresh()
	if state.segment != old_segment:
		_select_first_owned_ship()
		_show_privacy(state.segment, "Inizia il segmento di %s. Passa il dispositivo senza mostrare la plancia." % state.segment)
func _reset() -> void: state = GrandTourDevRef.create_state(); board.selected_ship = "p1"; overload_planning = false; _refresh()
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
