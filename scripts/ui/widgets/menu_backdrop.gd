class_name MenuBackdrop
extends Control
## Sfondo animato del menu: cielo procedurale, Sole a sinistra e orbite tratteggiate.

var _t := 0.0
var _stars: Array

func _ready() -> void:
	_stars = Art.stars(500)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(Art.sky(), Rect2(Vector2.ZERO, size), false)
	for st in _stars:
		var p: Vector2 = st[0]
		var b: float = st[1]
		var pos := Vector2(p.x * size.x, p.y * size.y)
		draw_rect(Rect2(pos, Vector2.ONE * (0.8 + b * 1.4)), Color(0.85, 0.9, 1.0, 0.3 + 0.7 * b))
	var sun := Vector2(-size.y * 0.15, size.y * 0.58)
	draw_texture_rect(Art.glow(), Rect2(sun - Vector2.ONE * size.y * 0.7, Vector2.ONE * size.y * 1.4), false, Color(1.0, 0.55, 0.2, 0.5))
	for i in range(6):
		var r := size.y * (0.38 + i * 0.22)
		var col := Color(0.4, 0.6, 1.0, 0.10)
		var segs := 90
		for k in range(segs):
			if k % 2 == 1: continue
			var a0 := -1.0 + 2.0 * k / segs
			var a1 := -1.0 + 2.0 * (k + 1) / segs
			draw_line(sun + Vector2.from_angle(a0) * r, sun + Vector2.from_angle(a1) * r, col, 1.5)
		var a := -0.6 + fmod(_t * (0.03 / (i + 1)) + i * 0.7, 1.2)
		var planet := sun + Vector2.from_angle(a) * r
		draw_circle(planet, 3.0 + i * 0.6, Color(0.9, 0.85, 0.75, 0.55))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.06, 0.25))
