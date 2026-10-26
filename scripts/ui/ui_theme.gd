class_name UITheme
extends RefCounted
## Palette e tipografia ispirate alla scatola GDW del 1973: blu profondo dello spazio,
## arancio segnale del bordo planetario, verde fosforo del logo, crema per i testi.

const BG := Color("050b19")
const PANEL := Color("0a1630f0")
const PANEL_SOLID := Color("0b1832")
const PANEL_LIGHT := Color("13244a")
const LINE := Color("1f3b6e")
const LINE_BRIGHT := Color("3a63a8")
const TEXT := Color("efe7d2")
const TEXT_DIM := Color("9aa7c2")
const TEXT_FAINT := Color("5f6f92")
const ACCENT := Color("ff7a2f")      # arancio segnale
const ACCENT_SOFT := Color("ff9a5c")
const PHOSPHOR := Color("31e08a")    # verde del logo
const CYAN := Color("49d3e6")
const DANGER := Color("ff4d5e")
const WARN := Color("ffc94a")
const GOOD := Color("5be38f")

static var display: Font
static var body: Font
static var body_bold: Font
static var body_semi: Font
static var mono: Font
static var _theme: Theme

static func load_fonts() -> void:
	if display != null: return
	display = _font("res://assets/fonts/Audiowide-Regular.ttf")
	body = _font("res://assets/fonts/Rajdhani-Medium.ttf")
	body_semi = _font("res://assets/fonts/Rajdhani-SemiBold.ttf")
	body_bold = _font("res://assets/fonts/Rajdhani-Bold.ttf")
	mono = _font("res://assets/fonts/ShareTechMono-Regular.ttf")

static var _fallbacks: Array[Font] = []

## Font di riserva per i simboli (✓ ▸ ● ⚠ ∞ → …) che i font a tema non contengono.
static func fallbacks() -> Array[Font]:
	if _fallbacks.is_empty():
		_fallbacks.append(load("res://assets/fonts/NotoSansSymbols2-Regular.ttf"))
		_fallbacks.append(load("res://assets/fonts/NotoSansMath-Regular.ttf"))
	return _fallbacks

static func _font(path: String) -> Font:
	var f: FontFile = load(path)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.fallbacks = fallbacks()
	return f

static func box(bg: Color, border := Color.TRANSPARENT, radius := 6, border_w := 1, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad; s.content_margin_right = pad
	s.content_margin_top = pad * 0.6; s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s

## Tema globale dell'interfaccia.
static func theme() -> Theme:
	if _theme != null: return _theme
	load_fonts()
	var t := Theme.new()
	t.default_font = body_semi
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	# pulsanti
	var normal := box(Color("10224a"), LINE_BRIGHT, 5, 1, 12)
	var hover := box(Color("173066"), CYAN, 5, 1, 12)
	var pressed := box(Color("2a1a10"), ACCENT, 5, 2, 12)
	var disabled := box(Color("0b1630"), Color("1a2b4f"), 5, 1, 12)
	var focus := box(Color.TRANSPARENT, ACCENT_SOFT, 5, 1, 12)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, ACCENT_SOFT)
		t.set_color("font_hover_pressed_color", cls, ACCENT_SOFT)
		t.set_color("font_disabled_color", cls, TEXT_FAINT)
		t.set_font("font", cls, body_bold)
		t.set_font_size("font_size", cls, 16)
	t.set_constant("h_separation", "Button", 8)
	# campi di testo
	var le := box(Color("060f22"), LINE, 4, 1, 10)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(Color("060f22"), CYAN, 4, 1, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_font("font", "LineEdit", body_semi)
	t.set_font_size("font_size", "LineEdit", 17)
	# pannelli
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 8, 1, 12))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 8, 1, 12))
	# barre di scorrimento sottili
	var grab := box(Color("2c4a85"), Color.TRANSPARENT, 3, 0, 0)
	var grab_h := box(CYAN, Color.TRANSPARENT, 3, 0, 0)
	var track := box(Color("0a1530"), Color.TRANSPARENT, 3, 0, 0)
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", sb, grab)
		t.set_stylebox("grabber_highlight", sb, grab_h)
		t.set_stylebox("grabber_pressed", sb, grab_h)
		t.set_stylebox("scroll", sb, track)
	# tooltip
	t.set_stylebox("panel", "TooltipPanel", box(Color("0b1832f8"), CYAN, 4, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", body_semi)
	t.set_font_size("font_size", "TooltipLabel", 15)
	# popup dei menu a tendina
	t.set_stylebox("panel", "PopupMenu", box(Color("0b1832"), LINE_BRIGHT, 4, 1, 6))
	t.set_stylebox("hover", "PopupMenu", box(Color("173066"), Color.TRANSPARENT, 3, 0, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", body_semi)
	t.set_font_size("font_size", "PopupMenu", 16)
	# RichTextLabel
	t.set_font("normal_font", "RichTextLabel", body_semi)
	t.set_font("bold_font", "RichTextLabel", body_bold)
	t.set_font("mono_font", "RichTextLabel", mono)
	t.set_font_size("normal_font_size", "RichTextLabel", 16)
	t.set_font_size("bold_font_size", "RichTextLabel", 16)
	t.set_font_size("mono_font_size", "RichTextLabel", 15)
	t.set_color("default_color", "RichTextLabel", TEXT)
	# CheckBox
	t.set_font("font", "CheckBox", body_semi)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_font_size("font_size", "CheckBox", 16)
	_theme = t
	return t

static func label(text: String, size := 17, color := TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null: l.add_theme_font_override("font", font)
	return l

static func caption(text: String, color := TEXT_DIM) -> Label:
	var l := label(text.to_upper(), 13, color, body_bold)
	return l

static func player_color(state: Dictionary, pid: String) -> Color:
	for p in state.players:
		if p.id == pid: return Color(p.color)
	return Color("aaaaaa")

static func primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_stylebox_override("normal", box(Color("ff7a2f"), Color("ffb27a"), 5, 1, 16))
	b.add_theme_stylebox_override("hover", box(Color("ff8f4d"), Color("ffe0c4"), 5, 1, 16))
	b.add_theme_stylebox_override("pressed", box(Color("d85f1c"), Color("ffe0c4"), 5, 2, 16))
	b.add_theme_stylebox_override("disabled", box(Color("3a2a22"), Color("4a3a30"), 5, 1, 16))
	b.add_theme_color_override("font_color", Color("1a0c04"))
	b.add_theme_color_override("font_hover_color", Color("1a0c04"))
	b.add_theme_color_override("font_pressed_color", Color("1a0c04"))
	b.add_theme_color_override("font_disabled_color", Color("8a7a70"))
	b.add_theme_font_override("font", display)
	b.add_theme_font_size_override("font_size", 16)
	return b
