class_name ChanceBar
extends Control
## Distribuzione dei sei esiti possibili del dado, colorata per gravità del risultato.

var chances: Dictionary = {}

func _draw() -> void:
	var order := ["E", "D5", "D4", "D3", "D2", "D1", "-"]
	var x := 0.0
	var f := UITheme.body_bold
	for k in order:
		var n: int = int(chances.get(k, 0))
		if n == 0: continue
		var w := size.x * n / 6.0
		var col := Color("2a3550")
		if k == "E": col = UITheme.DANGER
		elif k != "-": col = UITheme.ACCENT.lerp(UITheme.WARN, (5.0 - float(k.substr(1))) / 4.0)
		draw_rect(Rect2(x + 1, 0, w - 2, size.y), col)
		var label = "manca" if k == "-" else k
		var label_text := "%s %d/6" % [label, n]
		var sw := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if sw < w - 4:
			draw_string(f, Vector2(x + (w - sw) * 0.5, size.y * 0.5 + 5), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("101010") if k != "-" else UITheme.TEXT)
		x += w
