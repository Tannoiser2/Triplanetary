extends Control

const HexMathRef = preload("res://scripts/engine/hex.gd")
const GameRulesRef = preload("res://scripts/engine/game.gd")
const GrandTourDevRef = preload("res://scripts/data/grand_tour_dev.gd")
const BoardRef = preload("res://scripts/ui/board.gd")

var state: Dictionary
var board: Control
var status: Label
var ships_box: VBoxContainer
var log_label: Label

func _ready() -> void:
	state = GrandTourDevRef.create_state()
	_build_ui()
	_refresh()

func _build_ui() -> void:
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root)
	var header := HBoxContainer.new(); header.custom_minimum_size.y = 100; root.add_child(header)
	var title := Label.new(); title.text = "  TRIPLANETARY\n  PROTOTIPO GODOT · HOT-SEAT"; title.add_theme_font_size_override("font_size", 30); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(title)
	var reset := Button.new(); reset.text = "Nuova partita"; reset.pressed.connect(_reset); header.add_child(reset)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; root.add_child(split)
	board = BoardRef.new(); board.custom_minimum_size = Vector2(900, 650); board.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.add_child(board)
	var panel := VBoxContainer.new(); panel.custom_minimum_size.x = 320; split.add_child(panel)
	status = Label.new(); status.add_theme_font_size_override("font_size", 20); panel.add_child(status)
	ships_box = VBoxContainer.new(); panel.add_child(ships_box)
	var thrust_title := Label.new(); thrust_title.text = "SPINTA"; panel.add_child(thrust_title)
	var grid := GridContainer.new(); grid.columns = 3; panel.add_child(grid)
	for i in range(6):
		var button := Button.new(); button.text = "Direzione %d" % (i + 1); button.pressed.connect(_set_thrust.bind(i)); grid.add_child(button)
	var coast := Button.new(); coast.text = "Nessuna spinta"; coast.pressed.connect(_coast); panel.add_child(coast)
	var advance := Button.new(); advance.text = "AVANZA FASE"; advance.pressed.connect(_advance); panel.add_child(advance)
	log_label = Label.new(); log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL; panel.add_child(log_label)
	var note := Label.new(); note.text = "Mappa di sviluppo: coordinate non definitive.\nNessun asset allegato è incluso."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; panel.add_child(note)

func _refresh() -> void:
	board.state = state; board.queue_redraw()
	status.text = "GIORNO %d\n%s · %s%s" % [state.turn, state.segment, String(state.phase).to_upper(), "\nVINCITORE: " + state.winner if state.winner != "" else ""]
	for child in ships_box.get_children(): child.queue_free()
	for ship: Dictionary in state.ships:
		var button := Button.new(); button.text = "%s · %s · fuel %d · v%s\nVisitati: %s" % [ship.name, ship.owner, ship.fuel, ship.velocity, ", ".join(ship.visited_bodies)]; button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.pressed.connect(_select.bind(ship.id)); ships_box.add_child(button)
	var recent: Array = state.log.slice(maxi(0, state.log.size() - 8)); recent.reverse(); log_label.text = "REGISTRO\n" + "\n".join(recent)

func _select(id: String) -> void: board.selected_ship = id; board.queue_redraw()
func _set_thrust(direction: int) -> void:
	var ship := _selected()
	if state.phase != "astrogation" or ship.owner != state.segment or ship.fuel <= 0: return
	state.commands[ship.id] = {"thrust": HexMathRef.DIRECTIONS[direction]}; _refresh()
func _coast() -> void:
	var ship := _selected()
	if state.phase == "astrogation" and ship.owner == state.segment: state.commands[ship.id] = {}; _refresh()
func _advance() -> void: state = GameRulesRef.advance_phase(state); _refresh()
func _reset() -> void: state = GrandTourDevRef.create_state(); board.selected_ship = "p1"; _refresh()
func _selected() -> Dictionary:
	for ship: Dictionary in state.ships:
		if ship.id == board.selected_ship: return ship
	return state.ships[0]
