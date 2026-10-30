class_name Board3D
extends SubViewportContainer
## Tavolo in 3D. Legge stato, overlay e animazioni dalla plancia 2D (src) e li mostra in tre dimensioni:
## reticolo deformato dai pozzi di gravità, pianeti e navi in 3D, rotte, derive e scelte di spinta
## disegnate sulla superficie. Camera con rotazione, spostamento e zoom (mouse, trackpad e touch).
## Emette gli stessi segnali della plancia 2D, così il controller non cambia.

signal hex_clicked(hex: Vector2i, button: int)
signal hex_hovered(hex: Vector2i)

const SHIP_SCALE := {"dreadnought": 0.62, "orbital_base": 0.6, "frigate": 0.5, "liner": 0.5, "tanker": 0.48, "transport": 0.46,
	"torch": 0.5, "corsair": 0.42, "packet": 0.4, "corvette": 0.38, "alien": 0.46}
## Modelli dei corpi celesti (le lune minori e gli asteroidi-base sono sfere o rocce semplici).
const BODY_MODEL := {"sol": "sol", "mercury": "mercury", "venus": "venus", "terra": "terra", "luna": "mercury", "mars": "mars",
	"jupiter": "jupiter", "io": "io", "europa": "europa", "ganymede": "ganymede", "callisto": "callisto", "saturn": "saturn",
	"titan": "titan", "uranus": "uranus", "neptune": "neptune", "pluto": "ganymede", "triton": "europa"}

var src: Board
var enabled := false

var vp: SubViewport
var world_root: Node3D
var cam: Camera3D
var sun_light: OmniLight3D
var grid_mi: MeshInstance3D
var grid_mat: ShaderMaterial
var arrow_mat: ShaderMaterial
var overlay_mi: MeshInstance3D
var overlay_mesh: ImmediateMesh
var rocks_mi: MultiMeshInstance3D
var bodies_root: Node3D
var ships_root: Node3D

# camera
var target := Vector3.ZERO
var yaw := 0.0
var pitch := 0.95
var dist := 60.0
var _cam_ready := false

# stato della scena
var _map_key := ""
var _map: Dictionary = {}
var _bodies := {}          # id -> {node, pos: Vector2, depth, spread, r3}
var _wells: Array = []     # [Vector2 pos, depth, spread] per il calcolo dell'altezza
var _ships := {}           # id -> {node, model, ring, sel, flame, type, ang}
var _models := {}
var _map_rect := Rect2()
var _time := 0.0
var hover := Vector2i(9999, 9999)

# input
var _press := false
var _press_btn := 0
var _press_pos := Vector2.ZERO
var _moved := false
var _touches := {}
var _multi := false
var _last_pinch := {}

# ---------------------------------------------------------------- costruzione

func _init(p_src: Board) -> void:
	src = p_src
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	world_root = Node3D.new()
	vp.add_child(world_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = _star_panorama()
	sky.sky_material = pano
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.46, 0.58)
	e.ambient_light_energy = 0.9
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.15
	e.glow_hdr_threshold = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world_root.add_child(env)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60, 30, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.78, 1.0)
	world_root.add_child(fill)
	sun_light = OmniLight3D.new()
	sun_light.omni_range = 600.0
	sun_light.omni_attenuation = 0.15
	sun_light.light_energy = 1.6
	sun_light.light_color = Color(1.0, 0.92, 0.8)
	world_root.add_child(sun_light)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.1
	cam.far = 3000.0
	world_root.add_child(cam)
	cam.current = true
	grid_mi = MeshInstance3D.new()
	grid_mat = ShaderMaterial.new()
	grid_mat.shader = _well_shader(true)
	grid_mi.material_override = grid_mat
	grid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(grid_mi)
	arrow_mat = ShaderMaterial.new()
	arrow_mat.shader = _well_shader(false)
	rocks_mi = MultiMeshInstance3D.new()
	world_root.add_child(rocks_mi)
	bodies_root = Node3D.new()
	world_root.add_child(bodies_root)
	ships_root = Node3D.new()
	world_root.add_child(ships_root)
	overlay_mesh = ImmediateMesh.new()
	overlay_mi = MeshInstance3D.new()
	overlay_mi.mesh = overlay_mesh
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.vertex_color_use_as_albedo = true
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.cull_mode = BaseMaterial3D.CULL_DISABLED
	om.no_depth_test = false
	om.render_priority = 2
	overlay_mi.material_override = om
	overlay_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(overlay_mi)
	src.focus_requested.connect(_on_focus)
	src.fit_requested.connect(fit)
	src.zoom_requested.connect(func(f): dist = clampf(dist / f, 4.0, 900.0))

## Il reticolo e le frecce si abbassano nei pozzi di gravità: lo stesso calcolo è in height().
func _well_shader(grid: bool) -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled%s;
uniform vec4 wells[48];
uniform int count = 0;
uniform vec4 base_color : source_color = vec4(0.30, 0.50, 0.95, 0.30);
uniform vec4 deep_color : source_color = vec4(0.55, 0.85, 1.0, 0.9);
varying float depth;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 0.0;
	for (int i = 0; i < count; i++) {
		vec2 d = w.xz - wells[i].xy;
		float q = dot(d, d) / (wells[i].w * wells[i].w);
		h += wells[i].z / (1.0 + q);
	}
	depth = h;
	w.y -= h;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}
void fragment() {
	%s
}
""" % [", blend_add" if grid else "", "vec4 c = mix(base_color, deep_color, clamp(depth * 0.4, 0.0, 1.0)); ALBEDO = c.rgb; ALPHA = c.a;" if grid else "ALBEDO = COLOR.rgb; ALPHA = COLOR.a;"]
	return sh

func _star_panorama() -> Texture2D:
	var w := 2048; var h := 1024
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.008, 0.012, 0.03))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2001
	var noise := FastNoiseLite.new()
	noise.frequency = 0.004
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var n := noise.get_noise_2d(x, y * 2.0) * 0.5 + 0.5
			var c := Color(0.008, 0.012, 0.03).lerp(Color(0.06, 0.04, 0.12), clampf(n * n * 1.6, 0.0, 1.0))
			img.set_pixel(x, y, c); img.set_pixel(x + 1, y, c); img.set_pixel(x, y + 1, c); img.set_pixel(x + 1, y + 1, c)
	for i in range(5000):
		var x := rng.randi_range(0, w - 1); var y := rng.randi_range(0, h - 1)
		var b := pow(rng.randf(), 3.0)
		var col := Color(0.6 + b * 0.4, 0.65 + b * 0.35, 0.8 + b * 0.2) * (0.25 + b * 0.9)
		img.set_pixel(x, y, col)
		if b > 0.7:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x >= 0 and p.x < w and p.y >= 0 and p.y < h: img.set_pixel(p.x, p.y, col * 0.45)
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- mappa

func _rebuild_map(m: Dictionary) -> void:
	_map = m
	var cells: Dictionary = m.cells
	# reticolo: lati degli esagoni, spezzati in tre per seguire la curvatura dei pozzi
	var verts := PackedVector3Array()
	var seen := {}
	var minp := Vector2(INF, INF); var maxp := Vector2(-INF, -INF)
	for h in cells:
		var c := Board.world(h)
		minp = minp.min(c); maxp = maxp.max(c)
		for i in range(6):
			var a: Vector2 = c + Board.HEX_CORNERS[i]
			var b: Vector2 = c + Board.HEX_CORNERS[(i + 1) % 6]
			var key := "%d,%d,%d,%d" % [roundi(minf(a.x, b.x) * 100), roundi(minf(a.y, b.y) * 100), roundi(maxf(a.x, b.x) * 100), roundi(maxf(a.y, b.y) * 100)]
			if seen.has(key): continue
			seen[key] = true
			for k in range(3):
				var p0 := a.lerp(b, k / 3.0); var p1 := a.lerp(b, (k + 1) / 3.0)
				verts.append(Vector3(p0.x, 0, p0.y)); verts.append(Vector3(p1.x, 0, p1.y))
	_map_rect = Rect2(minp, maxp - minp)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	am.custom_aabb = AABB(Vector3(minp.x - 2, -6, minp.y - 2), Vector3(maxp.x - minp.x + 4, 8, maxp.y - minp.y + 4))
	grid_mi.mesh = am
	_build_rocks()
	for c in bodies_root.get_children(): c.queue_free()
	_bodies = {}
	_build_bodies(m)

func _build_rocks() -> void:
	var list: Array = _map.asteroids + _map.special_asteroids
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var rock := SphereMesh.new()
	rock.radial_segments = 6; rock.rings = 4
	rock.radius = 0.5; rock.height = 0.8
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.roughness = 0.95
	rock.material = rm
	mm.mesh = rock
	mm.instance_count = list.size() * 6
	var rng := RandomNumberGenerator.new()
	var i := 0
	for h in list:
		rng.seed = hash(h)
		var special: bool = _map.special_asteroids.has(h)
		var c := Board.world(h)
		for k in range(6):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 0.6
			var p := c + Vector2(cos(a), sin(a)) * r
			var s := 0.08 + rng.randf() * 0.14
			var t := Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)).scaled(Vector3(s, s * 0.8, s * 1.2)), Vector3(p.x, rng.randf_range(-0.1, 0.25), p.y))
			mm.set_instance_transform(i, t)
			mm.set_instance_color(i, Color("7f9fd8") if special else Color("8a7a66").lerp(Color("4a3f35"), rng.randf()))
			i += 1
	rocks_mi.multimesh = mm

func _model(path: String) -> PackedScene:
	if not _models.has(path):
		_models[path] = load(path) if ResourceLoader.exists(path) else null
	return _models[path]

func _build_bodies(m: Dictionary) -> void:
	# frecce di gravità raggruppate per corpo: si muovono con lui
	var arrows := {}
	for h in m.gravity:
		var list: Array = m.gravity[h]
		var n := list.size()
		for i in range(n):
			var g: Dictionary = list[i]
			if not arrows.has(g.body): arrows[g.body] = []
			arrows[g.body].append([h, g.acc, g.weak, i, n])
	for b in m.bodies:
		var node := Node3D.new()
		bodies_root.add_child(node)
		var depth := 0.0; var spread := 1.0
		match b.gravity:
			"sol": depth = 4.2; spread = 2.6
			"full": depth = 1.7; spread = 1.35
			"weak": depth = 0.7; spread = 1.0
		if b.id == "jupiter": depth = 2.8; spread = 1.8
		var r3: float = maxf(float(b.radius) * 1.45, 0.22)
		if b.id == "sol": r3 = 1.15
		var holder := Node3D.new()
		holder.name = "Holder"
		node.add_child(holder)
		var mp: String = BODY_MODEL.get(b.id, "")
		var scene := _model("res://assets/3d/bodies/%s.glb" % mp) if mp != "" else null
		if scene != null:
			var inst: Node3D = scene.instantiate()
			holder.add_child(inst)
			inst.scale = Vector3.ONE * r3
			if b.id == "luna" or b.id == "pluto": _tint(inst, Color(0.85, 0.85, 0.9))
			if b.id == "sol": _unshaded(inst, 1.6)
		elif b.gravity == "none" or float(b.radius) <= 0.0:
			# asteroide-base: roccia con un anello luminoso
			var rock := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.2; sm.height = 0.32; sm.radial_segments = 7; sm.rings = 5
			var mat := StandardMaterial3D.new(); mat.albedo_color = b.color; mat.roughness = 0.9
			sm.material = mat
			rock.mesh = sm
			holder.add_child(rock)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new(); tm.inner_radius = 0.38; tm.outer_radius = 0.43; tm.rings = 32; tm.ring_segments = 6
			tm.material = _flat(Color(b.color, 0.9))
			ring.mesh = tm
			holder.add_child(ring)
			r3 = 0.2
		else:
			var sp := MeshInstance3D.new()
			var sm2 := SphereMesh.new(); sm2.radius = r3; sm2.height = r3 * 2.0
			var mat2 := StandardMaterial3D.new(); mat2.albedo_color = b.color; mat2.roughness = 0.8
			sm2.material = mat2
			sp.mesh = sm2
			holder.add_child(sp)
		if b.id == "sol":
			var halo := Sprite3D.new()
			halo.texture = Art.glow()
			halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			halo.modulate = Color(1.0, 0.6, 0.2, 0.75)
			halo.pixel_size = 7.5 / maxf(1.0, float(Art.glow().get_width()))
			halo.shaded = false
			halo.no_depth_test = false
			holder.add_child(halo)
		# frecce
		if arrows.has(b.id):
			var mi := MeshInstance3D.new()
			mi.mesh = _arrow_mesh(arrows[b.id], Board.world(b.hex), b.color)
			mi.material_override = arrow_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		var label := Label3D.new()
		label.text = b.name.to_upper()
		label.font = Art.board_font_bold
		label.font_size = 64
		label.pixel_size = 0.0055
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.95, 0.9, 0.78, 0.9)
		label.outline_size = 14
		label.outline_modulate = Color(0.0, 0.02, 0.06, 0.85)
		label.position = Vector3(0, r3 + 0.45, 0)
		label.no_depth_test = true
		label.name = "Label"
		node.add_child(label)
		var w := Board.world(b.hex)
		_bodies[b.id] = {"node": node, "pos": w, "depth": depth, "spread": spread, "r3": r3, "hex": b.hex, "holder": holder}
		node.position = Vector3(w.x, 0, w.y)

func _arrow_mesh(list: Array, center: Vector2, tint: Color) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for e in list:
		var h: Vector2i = e[0]
		var c := Board.world(h) - center
		var dir := Board.world(e[1]).normalized()
		var side := Vector2(-dir.y, dir.x)
		var n: int = e[4]
		var shift := side * (float(e[3]) - float(n - 1) * 0.5) * 0.38
		var ln := 0.7 if n == 1 else 0.52
		var start := c + shift - dir * ln * 0.5
		var tip := start + dir * ln
		var w := 0.1 if n == 1 else 0.07
		var hw := 0.25 if n == 1 else 0.19
		var neck := tip - dir * (0.27 if n == 1 else 0.21)
		var col := Color(0.86, 0.92, 1.0).lerp(tint, 0.35)
		col.a = 0.55 if e[2] else 0.9
		var tris := [start + side * w, neck + side * w, neck - side * w, start + side * w, neck - side * w, start - side * w,
			neck + side * hw, tip, neck - side * hw]
		for p in tris:
			verts.append(Vector3(p.x, 0.04, p.y))
			cols.append(col)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	if verts.is_empty(): return am
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.custom_aabb = AABB(Vector3(-4, -5, -4), Vector3(8, 6, 8))
	return am

func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _each_mesh(n: Node, f: Callable) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		for i in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mat: Material = mi.get_active_material(i)
			if mat is BaseMaterial3D: f.call(mi, i, (mat as BaseMaterial3D).duplicate())

func _unshaded(n: Node, energy: float) -> void:
	_each_mesh(n, func(mi, i, m):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(energy, energy * 0.95, energy * 0.85)
		mi.set_surface_override_material(i, m))

func _tint(n: Node, c: Color) -> void:
	_each_mesh(n, func(mi, i, m):
		m.albedo_color = c
		mi.set_surface_override_material(i, m))

# ---------------------------------------------------------------- altezza della superficie

func height(p: Vector2) -> float:
	var h := 0.0
	for w in _wells:
		var d: Vector2 = p - w[0]
		h += float(w[1]) / (1.0 + d.length_squared() / (float(w[2]) * float(w[2])))
	return -h

## Punto per navi e tracciati: segue il reticolo, ma vicino a un corpo risale al livello della mappa,
## dove stanno i pianeti (che non sprofondano nel loro pozzo).
func p3(p: Vector2, lift := 0.0) -> Vector3:
	var h := height(p)
	for id in _bodies:
		var e: Dictionary = _bodies[id]
		if float(e.depth) <= 0.0: continue
		var d: float = p.distance_to(e.pos)
		h *= smoothstep(float(e.r3) + 0.15, float(e.r3) + 0.95, d)
	return Vector3(p.x, h + lift, p.y)

# ---------------------------------------------------------------- aggiornamento

func _process(delta: float) -> void:
	visible = enabled and src.is_visible_in_tree()
	if not visible or src.state.is_empty(): return
	_time += delta
	var st: Dictionary = src.state
	var m := Rules.map_of(st)
	if not src.replay.is_empty() and st.has("planets0"):
		var ps := {"planets": st.planets0, "planet_clock": 0, "xvariant": st.get("xvariant", "xmap"), "options": st.options}
		m = SolarMap.get_xmap(Planets.future(ps, maxi(0, floori(src.replay_u) - 1)), Planets.variant(st))
	var key := "%s|%d|%d|%s" % [m.get("variant", "classic"), m.cells.size(), m.asteroids.size(), str(m.get("xmap", false))]
	if key != _map_key:
		_map_key = key
		_rebuild_map(m)
		if not _cam_ready: fit(); _cam_ready = true
	elif not is_same(m, _map):
		_map = m
	# corpi: scivolano verso la posizione del turno
	_wells = []
	var wl := []
	for b in _map.bodies:
		if not _bodies.has(b.id): continue
		var e: Dictionary = _bodies[b.id]
		var to := Board.world(b.hex)
		var cur: Vector2 = e.pos
		if cur.distance_to(to) > 6.0: cur = to
		else: cur = cur.lerp(to, 1.0 - exp(-delta * 2.2))
		e.pos = cur
		e.hex = b.hex
		if float(e.depth) > 0.0: _wells.append([cur, e.depth, e.spread])
	for w in _wells: wl.append(Vector4(w[0].x, w[0].y, w[1], w[2]))
	while wl.size() < 48: wl.append(Vector4.ZERO)
	grid_mat.set_shader_parameter("wells", wl.slice(0, 48))
	grid_mat.set_shader_parameter("count", mini(_wells.size(), 48))
	arrow_mat.set_shader_parameter("wells", wl.slice(0, 48))
	arrow_mat.set_shader_parameter("count", mini(_wells.size(), 48))
	for id in _bodies:
		var e2: Dictionary = _bodies[id]
		var p: Vector2 = e2.pos
		e2.node.position = Vector3(p.x, 0, p.y)
		e2.holder.position = Vector3.ZERO
		# rotazione su se stessi: il Sole lento, i pianeti giganti più veloci
		var spin := 0.12 if id == "sol" else (0.6 if id in ["jupiter", "saturn", "uranus", "neptune"] else 0.4)
		e2.holder.rotate_y(delta * spin)
		var lab: Label3D = e2.node.get_node("Label")
		lab.position = Vector3(0, float(e2.r3) + 0.5, 0)
		lab.visible = dist < 140.0
	if _bodies.has("sol"):
		var sp: Vector2 = _bodies.sol.pos
		sun_light.position = Vector3(sp.x, 1.5, sp.y)
	_update_ships(delta)
	_update_camera()
	_draw_overlay()

# ---------------------------------------------------------------- navi

func _ship_type(s: Dictionary) -> String:
	if s.get("flags", {}).get("nova_bomb", false) or (src.state.scenario == "nova" and s.owner == "P3"): return "alien"
	return str(s.type)

func _ship_node(s: Dictionary) -> Dictionary:
	if _ships.has(s.id): return _ships[s.id]
	var t := _ship_type(s)
	var pivot := Node3D.new()
	ships_root.add_child(pivot)
	var model: Node3D = null
	var scene := _model("res://assets/3d/ships/%s.glb" % t)
	if scene != null:
		model = scene.instantiate()
		var k: float = SHIP_SCALE.get(t, 0.45)
		model.scale = Vector3.ONE * k
		model.rotation = Vector3(0, -PI * 0.5, 0)   # muso dei modelli lungo -X: lo si porta su -Z
		pivot.add_child(model)
	var col := UITheme.player_color(src.state, s.owner)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.46; tm.outer_radius = 0.52; tm.rings = 36; tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = _flat(Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, 0.95))
	ring.scale = Vector3(1, 0.25, 1)
	pivot.add_child(ring)
	var sel := MeshInstance3D.new()
	var tm2 := TorusMesh.new(); tm2.inner_radius = 0.6; tm2.outer_radius = 0.66; tm2.rings = 40; tm2.ring_segments = 6
	sel.mesh = tm2
	sel.material_override = _flat(UITheme.ACCENT)
	sel.scale = Vector3(1, 0.25, 1)
	pivot.add_child(sel)
	var unknown := MeshInstance3D.new()
	var oct := SphereMesh.new(); oct.radius = 0.28; oct.height = 0.56; oct.radial_segments = 4; oct.rings = 2
	unknown.mesh = oct
	var um := StandardMaterial3D.new(); um.albedo_color = Color("8a93a8"); um.metallic = 0.4; um.roughness = 0.4
	unknown.material_override = um
	pivot.add_child(unknown)
	var flames := Node3D.new()
	pivot.add_child(flames)
	var e := {"node": pivot, "model": model, "ring": ring, "sel": sel, "unknown": unknown, "flames": flames, "type": t, "ang": NAN, "col": col}
	_ships[s.id] = e
	return e

func _flame(parent: Node3D, dir3: Vector3, at: Vector3, strength: float) -> void:
	var m := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0; cone.bottom_radius = 0.09 + 0.03 * strength; cone.height = 0.5 + 0.25 * strength
	cone.radial_segments = 8; cone.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.62, 0.2, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cone.material = mat
	m.mesh = cone
	parent.add_child(m)
	# il cono punta lungo +Y: lo si orienta lungo la direzione del getto (opposta alla spinta)
	var back := -dir3.normalized()
	m.position = at + back * (cone.height * 0.5)
	var up := Vector3.UP
	m.basis = Basis(Quaternion(up, back))

func _body_shift_for(s: Dictionary) -> Vector2:
	for id in _bodies:
		var e: Dictionary = _bodies[id]
		var hx: Vector2i = e.hex
		if s.landed == id or (s.landed == "" and Hex.distance(s.pos, hx) <= 1 and float(e.depth) > 0.0):
			return e.pos - Board.world(hx)
	return Vector2.ZERO

func _update_ships(_delta: float) -> void:
	var st: Dictionary = src.state
	var used := {}
	if not src.replay.is_empty():
		_update_replay_ships()
		return
	var groups := {}
	for s in st.ships:
		if not src._visible_ship(s): continue
		var k = s.pos if s.landed == "" else Vector2i(-999 - int(s.side), s.landed.hash())
		if not groups.has(k): groups[k] = []
		groups[k].append(s)
	for k in groups:
		var list: Array = groups[k]
		var n := list.size()
		for i in range(n):
			var s: Dictionary = list[i]
			used[s.id] = true
			var e := _ship_node(s)
			var p2 := Board.world(s.pos) + _body_shift_for(s)
			var scale := 1.0
			if s.landed != "" and _bodies.has(s.landed):
				var b: Dictionary = _bodies[s.landed]
				var dir := Board.world(Hex.DIRS[maxi(0, int(s.side))]).normalized()
				p2 = b.pos + dir * (float(b.r3) + 0.25)
				scale = 0.55
			if src.anim_t < 1.0 and src.anim_moves.has(s.id):
				var mv: Dictionary = src.anim_moves[s.id]
				p2 = mv.from.lerp(mv.to, Board._ease(src.anim_t))
			if n > 1:
				p2 += Vector2.from_angle(TAU * float(i) / n - PI * 0.5) * 0.34
				scale *= 0.8
			var lift := 0.45 if s.landed == "" else 0.3
			e.node.position = p3(p2, lift)
			e.node.scale = Vector3.ONE * scale
			_orient_ship(s, e)
	for id in _ships.keys():
		if not used.has(id):
			_ships[id].node.queue_free()
			_ships.erase(id)

func _orient_ship(s: Dictionary, e: Dictionary) -> void:
	var st: Dictionary = src.state
	var concealed := src._concealed(s)
	var dummy: bool = s.get("dummy", false)
	if e.model != null: e.model.visible = not concealed and not dummy
	e.unknown.visible = concealed
	if concealed: e.unknown.rotate_y(0.02)
	var ring_col: Color = Color("8a93a8") if concealed else e.col
	var dead := not Rules.alive(s)
	(e.ring.material_override as StandardMaterial3D).albedo_color = Color(ring_col, 0.35 if dummy else (0.4 if dead else 0.95))
	# selezione, attaccanti, bersagli
	var ov: Dictionary = src.overlay
	var sel_on: bool = s.id == src.selected or ov.get("attackers", []).has(s.id) or ov.get("targets_sel", []).has(s.id) or ov.get("targetable", []).has(s.id)
	e.sel.visible = sel_on
	if sel_on:
		var c: Color = UITheme.ACCENT
		if ov.get("targets_sel", []).has(s.id) or (ov.get("targetable", []).has(s.id) and s.id != src.selected): c = UITheme.DANGER
		var pulse := 0.6 + 0.4 * sin(_time * 4.0)
		(e.sel.material_override as StandardMaterial3D).albedo_color = Color(c, pulse)
	if Rules.is_disabled(st, s) and not concealed:
		(e.ring.material_override as StandardMaterial3D).albedo_color = Color(UITheme.DANGER, 0.5 + 0.4 * sin(_time * 6.0))
	# direzione: lungo la rotta; spinta come fiamma
	var heading := Vector2.ZERO
	if s.vel != Vector2i.ZERO: heading = Board.world(s.vel)
	elif not s.history.is_empty() and s.history[-1].from != s.history[-1].to: heading = Board.world(s.history[-1].to) - Board.world(s.history[-1].from)
	if src.anim_t < 1.0 and src.anim_moves.has(s.id):
		var mv: Dictionary = src.anim_moves[s.id]
		if mv.from.distance_to(mv.to) > 0.01: heading = mv.to - mv.from
	var thrust := Vector2i.ZERO
	if s.landed == "" and not concealed and not dummy: thrust = src._thrust_of(s)
	if not src.nose_on_course and thrust != Vector2i.ZERO: heading = Board.world(thrust)
	if s.landed != "" and _bodies.has(s.landed): heading = Board.world(Hex.DIRS[maxi(0, int(s.side))])
	var want: float = atan2(-heading.x, -heading.y) if heading.length() > 0.01 else (float(e.ang) if not is_nan(float(e.ang)) else 0.0)
	var cur: float = e.ang if not is_nan(float(e.ang)) else want
	cur = lerp_angle(cur, want, 0.15)
	e.ang = cur
	if e.model != null: e.model.get_parent().rotation = Vector3(0, 0, 0)
	e.node.rotation = Vector3(0, cur, 0)
	for f in e.flames.get_children(): f.queue_free()
	if thrust != Vector2i.ZERO:
		var flick := 0.85 + 0.15 * sin(_time * 31.0 + hash(s.id))
		if src.nose_on_course:
			for d in src._burn_dirs(thrust):
				var w := Board.world(d).normalized()
				var local = e.node.basis.inverse() * Vector3(w.x, 0, w.y)
				_flame(e.flames, local, local * 0.25, flick)
		else:
			_flame(e.flames, Vector3(0, 0, -1), Vector3(0, 0, 0.35), float(Hex.length(thrust)) * flick)

func _update_replay_ships() -> void:
	var rp: Dictionary = src.replay
	var u: float = src.replay_u
	var used := {}
	for id in rp.tracks:
		var inf: Dictionary = rp.info.get(id, {})
		if inf.is_empty() or inf.kind != "ship": continue
		var tr: Dictionary = rp.tracks[id]
		if u > float(rp.lost.get(id, INF)): continue
		var cur = Replay.pos_at(tr, u)
		if cur == null: continue
		var s := Rules.ship(src.state, id)
		if s.is_empty(): continue
		used[id] = true
		var e := _ship_node(s)
		e.node.position = p3(cur, 0.45)
		e.node.scale = Vector3.ONE
		e.unknown.visible = false
		if e.model != null: e.model.visible = true
		e.sel.visible = false
		var ahead = Replay.pos_at(tr, minf(u + 0.08, float(tr.times[-1])))
		var behind = Replay.pos_at(tr, maxf(u - 0.08, float(tr.times[0])))
		if ahead != null and behind != null and (ahead - behind).length() > 0.01:
			var hd: Vector2 = ahead - behind
			e.ang = atan2(-hd.x, -hd.y)
		e.node.rotation = Vector3(0, float(e.ang) if not is_nan(float(e.ang)) else 0.0, 0)
		for f in e.flames.get_children(): f.queue_free()
		var burn := Replay.burn_at(tr, u)
		if burn != Vector2i.ZERO and fmod(u - float(rp.tmin), 1.0) < 0.55:
			for d in src._burn_dirs(burn):
				var w := Board.world(d).normalized()
				var local = e.node.basis.inverse() * Vector3(w.x, 0, w.y)
				_flame(e.flames, local, local * 0.25, 1.0)
	for id in _ships.keys():
		if not used.has(id):
			_ships[id].node.queue_free()
			_ships.erase(id)

# ---------------------------------------------------------------- sovrapposizioni (rotte, derive, scelte)

var _im_open := false

func _begin() -> void:
	overlay_mesh.clear_surfaces()
	overlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_im_open = true
	_tri_count = 0

var _tri_count := 0

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		overlay_mesh.surface_set_color(col)
		overlay_mesh.surface_add_vertex(p)
	_tri_count += 2

## Nastro piatto che segue la superficie da a a b.
func _ribbon(a: Vector2, b: Vector2, w: float, col: Color, lift := 0.06) -> void:
	var len := a.distance_to(b)
	if len < 0.001: return
	var dir := (b - a) / len
	var side := Vector2(-dir.y, dir.x) * w * 0.5
	var steps := clampi(ceili(len / 0.5), 1, 60)
	for k in range(steps):
		var p0 := a.lerp(b, float(k) / steps); var p1 := a.lerp(b, float(k + 1) / steps)
		_quad(p3(p0 + side, lift), p3(p1 + side, lift), p3(p1 - side, lift), p3(p0 - side, lift), col)

func _dashed(a: Vector2, b: Vector2, w: float, col: Color, dash := 0.3) -> void:
	var len := a.distance_to(b)
	if len < 0.001: return
	var dir := (b - a) / len
	var t := -fmod(_time * 0.6, dash * 2.0)
	while t < len:
		var s0 := maxf(t, 0.0); var s1 := minf(t + dash, len)
		if s1 > s0: _ribbon(a + dir * s0, a + dir * s1, w, col)
		t += dash * 2.0

func _arrow_tip(tip: Vector2, dir: Vector2, size_w: float, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var a := p3(tip, 0.07); var b := p3(tip - dir * size_w + side * size_w * 0.5, 0.07); var c := p3(tip - dir * size_w - side * size_w * 0.5, 0.07)
	_quad(a, b, c, c, col)

func _hex_ring(c: Vector2, r: float, w: float, col: Color) -> void:
	for i in range(6):
		var a: Vector2 = c + Board.HEX_CORNERS[i] * r
		var b: Vector2 = c + Board.HEX_CORNERS[(i + 1) % 6] * r
		_ribbon(a, b, w, col)

func _hex_fill(c: Vector2, r: float, col: Color) -> void:
	for i in range(6):
		var a: Vector2 = c + Board.HEX_CORNERS[i] * r
		var b: Vector2 = c + Board.HEX_CORNERS[(i + 1) % 6] * r
		var cc := p3(c, 0.05)
		_quad(cc, p3(a, 0.05), p3(b, 0.05), p3(b, 0.05), col)

func _circle(c: Vector2, r: float, w: float, col: Color, segs := 40) -> void:
	for i in range(segs):
		var a := c + Vector2.from_angle(TAU * i / segs) * r
		var b := c + Vector2.from_angle(TAU * (i + 1) / segs) * r
		_ribbon(a, b, w, col)

func _draw_overlay() -> void:
	_begin()
	var st: Dictionary = src.state
	var ov: Dictionary = src.overlay
	var lw := clampf(dist * 0.0035, 0.06, 0.5)
	# orbite (mappa ampliata)
	if _map.get("xmap", false) and _bodies.has("sol"):
		var paths := Planets.orbit_paths(st)
		for id in paths:
			var b := SolarMap.body(_map, id)
			if b.is_empty(): continue
			var rad := float(Planets.orbit_def(id).radius) * Hex.SQRT3
			_circle(_bodies.sol.pos, rad, lw * 0.6, Color(b.color, 0.28), 160)
	if not src.replay.is_empty():
		_draw_replay_trails(lw)
		_finish()
		return
	if src.show_detection:
		for b in st.bases:
			if not b.active or b.owner == "all" or not (b.owner == src.viewer): continue
			var bb := SolarMap.body(_map, b.body)
			if not bb.is_empty(): _circle(Board.world(bb.hex), 5.0 * Hex.SQRT3, lw, Color(UITheme.CYAN, 0.3))
	# basi
	for b in st.bases:
		var body := SolarMap.body(_map, b.body)
		if body.is_empty() or not _bodies.has(b.body): continue
		var col: Color = Color("e9e2cf") if b.owner == "all" else UITheme.player_color(st, b.owner)
		if not b.active: col = Color(0.4, 0.4, 0.4)
		var c: Vector2 = _bodies[b.body].pos
		if int(b.side) < 0:
			continue
		var dir := Board.world(Hex.DIRS[int(b.side)]).normalized()
		var p: Vector2 = c + dir * (float(_bodies[b.body].r3) + 0.18)
		_hex_fill(p, 0.13, Color(col, 0.95))
	# esagoni da piazzare / segnati
	for h in ov.get("place_hexes", []):
		_hex_fill(Board.world(h), 0.85, Color(UITheme.PHOSPHOR, 0.16 + 0.08 * sin(_time * 4.0)))
		_hex_ring(Board.world(h), 0.88, lw * 0.7, Color(UITheme.PHOSPHOR, 0.7))
	for h in ov.get("mark_hexes", []):
		_hex_ring(Board.world(h), 0.95, lw, Color(UITheme.WARN, 0.85))
	# scie delle rotte
	if src.show_trails:
		for s in st.ships:
			if s.get("dummy", false) or src._concealed(s): continue
			var col2 := UITheme.player_color(st, s.owner)
			var hist: Array = s.history
			var n := hist.size()
			for i in range(maxi(0, n - 10), n):
				var e: Dictionary = hist[i]
				var age := n - 1 - i
				var alpha := clampf(1.0 - age * 0.11, 0.18, 0.95)
				if not Rules.alive(s): alpha *= 0.4
				var a := Board.world(e.from); var bpt := Board.world(e.to)
				if i == n - 1 and src.anim_t < 1.0 and src.anim_moves.has(s.id): bpt = a.lerp(bpt, Board._ease(src.anim_t))
				if a.distance_to(bpt) < 0.01: continue
				_ribbon(a, bpt, lw, Color(col2, alpha))
				_arrow_tip(bpt, (bpt - a).normalized(), 0.32, Color(col2, alpha))
	# derive
	if src.show_drift and src.anim_t >= 1.0:
		for s in st.ships:
			if not Rules.alive(s) or s.landed != "" or s.get("dummy", false) or src._concealed(s): continue
			var col3 := UITheme.player_color(st, s.owner).lightened(0.2)
			var r := Rules.simulate(Rules.map_of(st), s.pos, s.vel, s.grav, Vector2i.ZERO, false, Rules.hazard_rocks(st, s), st.special, s.access_special)
			var a2 := Board.world(s.pos)
			var inertial: Vector2i = s.pos + s.vel
			if s.vel != Vector2i.ZERO: _dashed(a2, Board.world(inertial), lw * 0.9, Color(col3, 0.8))
			var p := inertial
			for v in s.grav:
				var p2: Vector2i = p + v
				_ribbon(Board.world(p), Board.world(p2), lw * 1.2, Color(UITheme.WARN, 0.9))
				_arrow_tip(Board.world(p2), (Board.world(p2) - Board.world(p)).normalized(), 0.3, Color(UITheme.WARN, 0.9))
				p = p2
			var bad: bool = r.crash != "" or r.offmap or r.special
			if s.vel != Vector2i.ZERO or not s.grav.is_empty():
				_hex_ring(Board.world(r.dest if r.crash == "" else r.path[-1]), 0.5, lw * 0.8, Color(UITheme.DANGER if bad else col3, 0.75))
	# ordigni
	for o in st.ordnance:
		var col4 := UITheme.player_color(st, o.owner)
		var po := Board.world(o.pos)
		if src.anim_t < 1.0 and src.anim_moves.has(o.id):
			var m: Dictionary = src.anim_moves[o.id]
			po = m.from.lerp(m.to, Board._ease(src.anim_t))
		var nxt := Board.world(o.pos + o.vel + Board._gsum(o.grav) + o.get("launch_burn", Vector2i.ZERO))
		_dashed(po, nxt, lw * 0.7, Color(col4, 0.6), 0.2)
		var k := 0.28
		var q := [p3(po + Vector2(k, 0), 0.3), p3(po + Vector2(0, k), 0.3), p3(po + Vector2(-k, 0), 0.3), p3(po + Vector2(0, -k), 0.3)]
		var oc := Color("ff5040") if o.kind == "nuke" else (Color("ffd050") if o.kind == "mine" else col4.lightened(0.3))
		_quad(q[0], q[1], q[2], q[3], oc)
	# rotte previste
	var preds: Dictionary = ov.get("predictions", {})
	for id in preds:
		var s2 := Rules.ship(st, id)
		if s2.is_empty(): continue
		var pr: Dictionary = preds[id]
		var colp := UITheme.player_color(st, s2.owner)
		var a3 := Board.world(s2.pos) + _body_shift_for(s2)
		if s2.landed != "" and _bodies.has(s2.landed): a3 = _bodies[s2.landed].pos
		var b3 := Board.world(pr.dest)
		var bad2: bool = pr.get("crash", "") != "" or pr.get("offmap", false) or pr.get("special", false)
		if pr.get("crash", "") != "": b3 = Board.world(pr.path[-1])
		var c2 := UITheme.DANGER if bad2 else colp.lightened(0.25)
		var sel: bool = id == src.selected
		_dashed(a3, b3, lw * (1.4 if sel else 1.0), Color(c2, 0.95 if sel else 0.6))
		if a3.distance_to(b3) > 0.01: _arrow_tip(b3, (b3 - a3).normalized(), 0.34, Color(c2, 0.95 if sel else 0.6))
		if bad2:
			_ribbon(b3 + Vector2(-0.3, -0.3), b3 + Vector2(0.3, 0.3), lw * 1.3, UITheme.DANGER)
			_ribbon(b3 + Vector2(-0.3, 0.3), b3 + Vector2(0.3, -0.3), lw * 1.3, UITheme.DANGER)
		elif sel or preds.size() <= 3:
			_hex_ring(b3, 0.55, lw * 0.8, Color(c2, 0.7))
		for h in pr.get("asteroids", []): _circle(Board.world(h), 0.75, lw * 0.8, Color(UITheme.WARN, 0.8), 24)
	# scelte di spinta
	for ch in ov.get("choices", []):
		var cc := Board.world(ch.hex)
		var kind: String = ch.kind
		var colc := UITheme.CYAN
		if kind == "overload": colc = UITheme.ACCENT_SOFT
		if kind == "drift": colc = Color("d8e2ff")
		var picked: bool = ch.get("picked", false)
		if picked and kind != "drift": _hex_fill(cc, 0.8, Color(UITheme.ACCENT, 0.3))
		elif ch.get("hover", false): _hex_fill(cc, 0.8, Color(colc, 0.2))
		var al := 0.55 + 0.25 * sin(_time * 3.0)
		_hex_ring(cc, 0.82, lw * (1.4 if picked else 1.0), Color(colc if not picked else UITheme.ACCENT, 1.0 if picked else al))
		if ch.get("danger", false):
			_ribbon(cc + Vector2(-0.3, -0.3), cc + Vector2(0.3, 0.3), lw * 0.8, Color(UITheme.DANGER, 0.6))
			_ribbon(cc + Vector2(-0.3, 0.3), cc + Vector2(0.3, -0.3), lw * 0.8, Color(UITheme.DANGER, 0.6))
	# prospezione
	if st.scenario == "prospecting":
		for k2 in st.sd.prospected:
			var parts: PackedStringArray = k2.split(",")
			var hh := Vector2i(int(parts[0]), int(parts[1]))
			if st.sd.prospected[k2] == "ore": _hex_ring(Board.world(hh), 0.9, lw, Color("ffd36a"))
	# effetti (fuoco, esplosioni)
	for f in src.fx_list:
		var age: float = src._time - float(f.t0)
		if age < 0.0: continue
		var t := clampf(age / 1.4, 0.0, 1.0)
		var pf: Vector2 = f.world
		match f.kind:
			"explosion", "nuke":
				var big := 2.2 if f.kind == "nuke" else 1.0
				_circle(pf, (0.3 + t * 1.6) * big, lw * 2.0, Color(1.0, 0.5, 0.15, 1.0 - t), 28)
				_hex_fill(pf, (0.2 + t * 0.9) * big, Color(1.0, 0.8, 0.35, (1.0 - t) * 0.6))
			"blast", "ram", "flak", "hit", "rock":
				_circle(pf, 0.25 + t * 0.9, lw * 1.4, Color(1.0, 0.8, 0.4, 1.0 - t), 24)
			"fire":
				var to: Vector2 = f.get("to", pf)
				var a4 := p3(pf, 0.5); var b4 := p3(pf.lerp(to, minf(1.0, t * 3.0)), 0.5)
				var sd := Vector3(0, 0.05, 0)
				_quad(a4 + sd, b4 + sd, b4 - sd, a4 - sd, Color(1.0, 0.9, 0.5, 1.0 - t))
	# esagono sotto il puntatore
	if _map.cells.has(hover): _hex_ring(Board.world(hover), 0.97, lw * 0.6, Color(1, 1, 1, 0.45))
	_finish()

func _draw_replay_trails(lw: float) -> void:
	var rp: Dictionary = src.replay
	var u: float = src.replay_u
	for id in rp.tracks:
		var inf: Dictionary = rp.info.get(id, {})
		if inf.is_empty(): continue
		var tr: Dictionary = rp.tracks[id]
		var col := UITheme.player_color(src.state, inf.owner)
		var end_u := minf(u, float(rp.lost.get(id, INF)))
		var prev = null
		var t := float(tr.times[0])
		while t <= end_u:
			var p = Replay.pos_at(tr, t)
			if prev != null and p != null: _ribbon(prev, p, lw * (1.0 if inf.kind == "ship" else 0.6), Color(col, 0.45))
			prev = p
			t += 0.2
		if u > float(rp.lost.get(id, INF)):
			var age := u - float(rp.lost[id])
			if age < 0.8 and prev != null:
				var k := age / 0.8
				_hex_fill(prev, 0.25 + k * 0.9, Color(1.0, 0.7, 0.3, (1.0 - k) * 0.7))
		elif inf.kind != "ship":
			var cur = Replay.pos_at(tr, u)
			if cur != null: _hex_fill(cur, 0.2, col.lightened(0.3))

func _finish() -> void:
	if _tri_count == 0:
		# una superficie vuota non è ammessa: un triangolo invisibile
		_quad(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color(0, 0, 0, 0))
	overlay_mesh.surface_end()
	_im_open = false

# ---------------------------------------------------------------- camera

func _update_camera() -> void:
	pitch = clampf(pitch, 0.22, 1.5)
	dist = clampf(dist, 3.0, 900.0)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP if pitch < 1.49 else Vector3(-sin(yaw), 0, -cos(yaw)))
	# il punto mirato va al centro dell'area libera (non coperta dai pannelli)
	var r: Rect2 = src._safe()
	var h: float = maxf(1.0, size.y)
	var tanf := tan(deg_to_rad(cam.fov) * 0.5)
	cam.h_offset = -(r.get_center().x - size.x * 0.5) / (h * 0.5) * tanf * dist
	cam.v_offset = (r.get_center().y - size.y * 0.5) / (h * 0.5) * tanf * dist

func fit() -> void:
	if _map_rect.size == Vector2.ZERO: return
	var r: Rect2 = src._safe()
	yaw = 0.0
	pitch = 0.95
	var c := _map_rect.get_center()
	target = Vector3(c.x, 0, c.y)
	var tanf := tan(deg_to_rad(cam.fov) * 0.5)
	var aspect := r.size.x / maxf(1.0, r.size.y)
	var need_h := _map_rect.size.y * 0.5 / tanf
	var need_w := _map_rect.size.x * 0.5 / (tanf * aspect)
	dist = maxf(need_h, need_w) * (size.y / maxf(1.0, r.size.y)) * 0.92

func _on_focus(h: Vector2i, min_zoom: float) -> void:
	var w := Board.world(h)
	target = Vector3(w.x, height(w), w.y)
	if min_zoom > 0.0:
		var want := size.y / min_zoom / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
		dist = minf(dist, want * 1.3)

func _ground(screen: Vector2) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var n := cam.project_ray_normal(screen)
	if absf(n.y) < 0.0001: return o
	var y := 0.0
	var p := o
	for i in range(5):
		var t := (y - o.y) / n.y
		p = o + n * t
		y = height(Vector2(p.x, p.z))
	return p

func hex_at(screen: Vector2) -> Vector2i:
	var p := _ground(screen)
	return Board.world_to_hex(Vector2(p.x, p.z))

func _pan(delta: Vector2) -> void:
	var h: float = maxf(1.0, size.y)
	var k := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) * dist / h
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	target += (-right * delta.x + fwd * delta.y / maxf(0.35, sin(pitch))) * k

func _zoom_at(factor: float, screen: Vector2) -> void:
	var before := _ground(screen)
	dist = clampf(dist / factor, 3.0, 900.0)
	_update_camera()
	var after := _ground(screen)
	target += Vector3(before.x - after.x, 0, before.z - after.z)

func _rotate(delta: Vector2) -> void:
	yaw -= delta.x * 0.006
	pitch += delta.y * 0.005

# ---------------------------------------------------------------- input (mouse, trackpad, touch)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed: _touches[t.index] = t.position
		else: _touches.erase(t.index)
		if _touches.size() >= 2:
			_multi = true
			_press = false
			_last_pinch = {}
		elif _touches.is_empty():
			_multi = false
			_last_pinch = {}
		accept_event()
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2: _two_finger()
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed: _zoom_at(1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed: _zoom_at(1.0 / 1.12, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				if _multi: return
				_press = true; _moved = false
				_press_btn = mb.button_index
				_press_pos = mb.position
			else:
				var was := _press
				_press = false
				if was and not _moved and not _multi and mb.button_index != MOUSE_BUTTON_MIDDLE:
					hex_clicked.emit(hex_at(mb.position), mb.button_index)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press and not _multi:
			if mm.position.distance_to(_press_pos) > 6.0: _moved = true
			if _moved:
				var rotate := _press_btn != MOUSE_BUTTON_LEFT or mm.shift_pressed or mm.alt_pressed
				if rotate: _rotate(mm.relative)
				else: _pan(mm.relative)
		var h := hex_at(mm.position)
		if h != hover:
			hover = h
			hex_hovered.emit(h)
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_at(g.factor, g.position)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		if pg.shift_pressed or pg.alt_pressed: _rotate(pg.delta * 6.0)
		else: _pan(-pg.delta * 10.0)

## Due dita: avvicinare/allontanare = zoom, ruotare = girare il tavolo, trascinare in verticale = inclinare,
## trascinare in altre direzioni = spostare.
func _two_finger() -> void:
	var ids := _touches.keys()
	ids.sort()
	var a: Vector2 = _touches[ids[0]]; var b: Vector2 = _touches[ids[1]]
	var mid := (a + b) * 0.5
	var span := a.distance_to(b)
	var ang := (b - a).angle()
	if not _last_pinch.is_empty():
		var dm: Vector2 = mid - _last_pinch.mid
		var ds: float = span / maxf(1.0, float(_last_pinch.span))
		var da: float = wrapf(ang - float(_last_pinch.ang), -PI, PI)
		if absf(ds - 1.0) > 0.002: _zoom_at(ds, mid)
		if absf(da) > 0.002: yaw -= da
		if absf(dm.y) > absf(dm.x) * 1.5 and absf(ds - 1.0) < 0.02: pitch += dm.y * 0.006
		else: _pan(dm)
	_last_pinch = {"mid": mid, "span": span, "ang": ang}
