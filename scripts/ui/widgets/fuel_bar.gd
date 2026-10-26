class_name FuelBar
extends Control
## Indicatore del carburante: barra verticale a segmenti con il valore.

var value := 1.0
var text := ""

func _draw() -> void:
	var w := 12.0
	var h := size.y - 4.0
	var x := size.x - w - 2.0
	draw_rect(Rect2(x, 2, w, h), Color("060f22"))
	var segs := 10
	for i in range(segs):
		var frac := float(i + 1) / segs
		var on := value >= frac - 0.05
		var col := UITheme.GOOD if value > 0.5 else (UITheme.WARN if value > 0.25 else UITheme.DANGER)
		var sh := h / segs
		draw_rect(Rect2(x + 2, 2 + h - sh * (i + 1) + 1, w - 4, sh - 2), col if on else Color("14223f"))
	var f := UITheme.mono
	var sw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(f, Vector2(x - 6 - sw, size.y * 0.5 + 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.TEXT)
