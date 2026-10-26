class_name Art
extends RefCounted
## Grafica procedurale originale: cielo stellato, pianeti, silhouette delle navi.
## Niente immagini di terzi: tutto è generato qui.

static var _planets: Dictionary = {}
static var _sky: Texture2D
static var _glow: Texture2D
static var board_font: Font
static var board_font_bold: Font
static var board_display: Font

static func board_fonts() -> void:
	if board_font != null: return
	UITheme.load_fonts()
	board_font = _msdf("res://assets/fonts/Rajdhani-SemiBold.ttf")
	board_font_bold = _msdf("res://assets/fonts/Rajdhani-Bold.ttf")
	board_display = _msdf("res://assets/fonts/Audiowide-Regular.ttf")

static func _msdf(path: String) -> Font:
	# copia della risorsa importata: nei pacchetti esportati il .ttf originale non c'è
	var f: FontFile = (load(path) as FontFile).duplicate()
	f.fallbacks = UITheme.fallbacks()
	f.multichannel_signed_distance_field = true
	f.msdf_pixel_range = 8
	f.msdf_size = 48
	return f

# ---------------------------------------------------------------- cielo

static func sky() -> Texture2D:
	if _sky != null: return _sky
	var w := 400; var h := 250
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 1973
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 4
	var noise2 := FastNoiseLite.new()
	noise2.seed = 81
	noise2.frequency = 0.011
	noise2.fractal_octaves = 3
	var deep := Color("040916"); var mid := Color("0a1838"); var violet := Color("2a1640"); var rust := Color("3a1a12")
	for y in range(h):
		for x in range(w):
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var m := noise2.get_noise_2d(x + 300, y) * 0.5 + 0.5
			var c := deep.lerp(mid, clampf(n * 1.15 - 0.15, 0.0, 1.0))
			c = c.lerp(violet, clampf((m - 0.55) * 1.6, 0.0, 0.55))
			# un velo caldo verso il Sole (a sinistra)
			var warm := clampf(1.0 - float(x) / (w * 0.55), 0.0, 1.0)
			c = c.lerp(rust, warm * warm * 0.35 * n)
			img.set_pixel(x, y, c)
	_sky = ImageTexture.create_from_image(img)
	return _sky

## Stelle in coordinate normalizzate [0,1]², con luminosità.
static func stars(count := 700) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2001
	var out := []
	for i in range(count):
		var b := rng.randf()
		out.append([Vector2(rng.randf(), rng.randf()), b * b, rng.randf()])
	return out

static func glow() -> Texture2D:
	if _glow != null: return _glow
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.55))
	g.add_point(0.6, Color(1, 1, 1, 0.12))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128; t.height = 128
	_glow = t
	return _glow

# ---------------------------------------------------------------- pianeti

## Disco del pianeta, illuminato dal Sole che sulla plancia sta a sinistra.
static func planet(id: String, base: Color) -> Texture2D:
	if _planets.has(id): return _planets[id]
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = id.hash()
	noise.frequency = 0.09 if id != "jupiter" else 0.05
	noise.fractal_octaves = 4
	var light := Vector3(-0.75, -0.35, 0.56).normalized()
	var c := (n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx := (x - c) / c; var dy := (y - c) / c
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var dz := sqrt(1.0 - d2)
			var shade := clampf(Vector3(dx, dy, dz).dot(light), 0.0, 1.0)
			var col := _surface(id, base, dx, dy, noise)
			var lit := col * (0.18 + 0.95 * shade)
			# atmosfera sul bordo illuminato
			var rim := pow(1.0 - dz, 3.0) * shade
			lit = lit.lerp(Color(0.75, 0.88, 1.0), rim * (0.55 if id in ["terra", "venus"] else 0.2))
			lit.a = clampf((1.0 - sqrt(d2)) * c * 1.4, 0.0, 1.0)
			img.set_pixel(x, y, lit)
	var tex := ImageTexture.create_from_image(img)
	_planets[id] = tex
	return tex

static func _surface(id: String, base: Color, dx: float, dy: float, noise: FastNoiseLite) -> Color:
	var nx := noise.get_noise_2d(dx * 40.0, dy * 40.0)
	match id:
		"terra":
			var land := nx > 0.08
			var c := Color("2f6fc4") if not land else Color("4f8a3c").lerp(Color("b49a62"), clampf(nx * 2.0, 0.0, 1.0))
			if absf(dy) > 0.82: c = Color("e8f0f6")
			var cloud := noise.get_noise_2d(dx * 70.0 + 50.0, dy * 90.0)
			return c.lerp(Color(1, 1, 1), clampf(cloud * 1.6, 0.0, 0.7))
		"mars":
			return Color("b84a2a").lerp(Color("e08a50"), clampf(nx + 0.4, 0.0, 1.0)).lerp(Color("f0e0d0"), 1.0 if absf(dy) > 0.86 else 0.0)
		"venus":
			var sw := noise.get_noise_2d(dx * 25.0, dy * 60.0)
			return Color("e7c98c").lerp(Color("fff1c8"), clampf(sw + 0.5, 0.0, 1.0))
		"jupiter":
			var band := sin(dy * 15.0 + noise.get_noise_2d(dx * 30.0, dy * 10.0) * 2.5)
			var c2 := Color("d8b48a").lerp(Color("a4683e"), clampf(band * 0.5 + 0.5, 0.0, 1.0))
			if Vector2(dx - 0.25, dy - 0.35).length() < 0.16: c2 = Color("c0583a")
			return c2.lerp(Color("f2e6d2"), clampf(-band - 0.6, 0.0, 1.0))
		"sol":
			return Color("ffd27a").lerp(Color("fff6dc"), clampf(nx + 0.5, 0.0, 1.0))
		_:
			var crater := clampf(-nx * 2.2 - 0.3, 0.0, 1.0)
			return base.lerp(base.darkened(0.45), crater).lerp(base.lightened(0.25), clampf(nx, 0.0, 1.0))

# ---------------------------------------------------------------- navi

## Silhouette originali, puntate verso +X, in un quadrato unitario [-1,1].
const SHIPS := {
	"corvette": [[Vector2(0.95, 0), Vector2(0.15, -0.22), Vector2(-0.35, -0.5), Vector2(-0.55, -0.5), Vector2(-0.45, -0.16), Vector2(-0.8, -0.12), Vector2(-0.8, 0.12), Vector2(-0.45, 0.16), Vector2(-0.55, 0.5), Vector2(-0.35, 0.5), Vector2(0.15, 0.22)]],
	"corsair": [[Vector2(0.95, 0), Vector2(0.35, -0.16), Vector2(-0.1, -0.72), Vector2(-0.38, -0.72), Vector2(-0.3, -0.2), Vector2(-0.82, -0.18), Vector2(-0.68, 0), Vector2(-0.82, 0.18), Vector2(-0.3, 0.2), Vector2(-0.38, 0.72), Vector2(-0.1, 0.72), Vector2(0.35, 0.16)]],
	"frigate": [[Vector2(0.95, -0.08), Vector2(0.95, 0.08), Vector2(0.55, 0.2), Vector2(0.2, 0.2), Vector2(0.05, 0.55), Vector2(-0.2, 0.55), Vector2(-0.3, 0.24), Vector2(-0.85, 0.24), Vector2(-0.85, -0.24), Vector2(-0.3, -0.24), Vector2(-0.2, -0.55), Vector2(0.05, -0.55), Vector2(0.2, -0.2), Vector2(0.55, -0.2)]],
	"dreadnought": [[Vector2(0.98, 0), Vector2(0.55, -0.3), Vector2(0.3, -0.3), Vector2(0.22, -0.62), Vector2(-0.12, -0.62), Vector2(-0.2, -0.36), Vector2(-0.88, -0.42), Vector2(-0.95, 0), Vector2(-0.88, 0.42), Vector2(-0.2, 0.36), Vector2(-0.12, 0.62), Vector2(0.22, 0.62), Vector2(0.3, 0.3), Vector2(0.55, 0.3)]],
	"transport": [[Vector2(0.85, -0.18), Vector2(0.85, 0.18), Vector2(0.55, 0.3), Vector2(-0.75, 0.3), Vector2(-0.75, 0.42), Vector2(-0.95, 0.42), Vector2(-0.95, -0.42), Vector2(-0.75, -0.42), Vector2(-0.75, -0.3), Vector2(0.55, -0.3)],
		[Vector2(0.4, -0.55), Vector2(-0.6, -0.55), Vector2(-0.6, -0.36), Vector2(0.4, -0.36)], [Vector2(0.4, 0.36), Vector2(-0.6, 0.36), Vector2(-0.6, 0.55), Vector2(0.4, 0.55)]],
	"tanker": [[Vector2(0.9, 0), Vector2(0.7, -0.22), Vector2(-0.85, -0.22), Vector2(-0.85, 0.22), Vector2(0.7, 0.22)],
		[Vector2(0.45, -0.62), Vector2(-0.6, -0.62), Vector2(-0.7, -0.45), Vector2(-0.6, -0.3), Vector2(0.45, -0.3), Vector2(0.55, -0.45)], [Vector2(0.45, 0.3), Vector2(-0.6, 0.3), Vector2(-0.7, 0.45), Vector2(-0.6, 0.62), Vector2(0.45, 0.62), Vector2(0.55, 0.45)]],
	"liner": [[Vector2(0.95, 0), Vector2(0.75, -0.26), Vector2(-0.6, -0.3), Vector2(-0.85, -0.5), Vector2(-0.95, -0.5), Vector2(-0.82, 0), Vector2(-0.95, 0.5), Vector2(-0.85, 0.5), Vector2(-0.6, 0.3), Vector2(0.75, 0.26)]],
	"packet": [[Vector2(0.75, -0.25), Vector2(0.75, 0.25), Vector2(-0.6, 0.35), Vector2(-0.85, 0.2), Vector2(-0.85, -0.2), Vector2(-0.6, -0.35)]],
	"orbital_base": [[Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)],
		[Vector2(-0.95, -0.12), Vector2(-0.35, -0.12), Vector2(-0.35, 0.12), Vector2(-0.95, 0.12)],
		[Vector2(0.35, -0.12), Vector2(0.95, -0.12), Vector2(0.95, 0.12), Vector2(0.35, 0.12)],
		[Vector2(-0.12, -0.95), Vector2(0.12, -0.95), Vector2(0.12, -0.35), Vector2(-0.12, -0.35)],
		[Vector2(-0.12, 0.35), Vector2(0.12, 0.35), Vector2(0.12, 0.95), Vector2(-0.12, 0.95)]],
	"torch": [[Vector2(0.98, 0), Vector2(0.2, -0.14), Vector2(-0.55, -0.14), Vector2(-0.7, -0.4), Vector2(-0.85, -0.4), Vector2(-0.75, 0), Vector2(-0.85, 0.4), Vector2(-0.7, 0.4), Vector2(-0.55, 0.14), Vector2(0.2, 0.14)]],
}

static func ship_polys(type: String) -> Array:
	return SHIPS.get(type, SHIPS.corvette)
