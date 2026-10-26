class_name ShipIcon
extends Control
## Piccola pedina esagonale con la silhouette della nave, per le schede della flotta.

var type := "corvette"
var color := Color.WHITE

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var pts := PackedVector2Array()
	for k in Board.HEX_CORNERS: pts.append(c + k * r)
	draw_colored_polygon(pts, Color("0a1226"))
	var closed := pts.duplicate(); closed.append(pts[0])
	draw_polyline(closed, color, 2.0, true)
	for poly in Art.ship_polys(type):
		var tp := PackedVector2Array()
		for v in poly: tp.append(c + v * r * 0.7)
		draw_colored_polygon(tp, color.lightened(0.15))
