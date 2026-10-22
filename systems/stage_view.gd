class_name StageView
extends Node3D
## Everything you SEE in chapter one — the crack in your table, the paper world that
## rises out of it, props, effects — built from simple shapes in page units. BookWorld drives it through a few
## methods (open, pop, bloom, gate, restore…); none of the rules live here, so
## each prop can later be replaced by a real 3D model.

const OLD_PAPER := Color(0.92, 0.87, 0.74)

var level: PageLevel
var zones: Dictionary = {}
var corner_marks: Node3D
var crack: Node3D
var crack_spine := PackedVector3Array()
var crack_mesh: ImmediateMesh
var crack_mat: ShaderMaterial
var crack_lips: Array[ImmediateMesh] = []
var crack_open: float = 0.0
var rift: Node3D
var rift_mesh: ImmediateMesh
var rift_mat: ShaderMaterial
var rift_glimpse: Node3D
var rift_t: float = 0.0
var popups: Array = []            # {node, delay}
var dead_tree: Node3D
var leaves: Array[Node3D] = []
var grass: Array[Node3D] = []
var buds: Array[Node3D] = []
var flower: Node3D
var flower_head: Node3D
var flower_mat: ShaderMaterial
var flower_bloom: float = 0.0
var light: Node3D
var stream: MeshInstance3D
var stream_mat: ShaderMaterial
var stream_flow: float = 0.0
var gate_doors: Array[Node3D] = []
var gate_open: float = 0.0
var switch_top: Node3D
var switch_mat: ShaderMaterial
var switch_pressed: bool = false
var orb: Node3D
var orb_mat: ShaderMaterial
var page_two_label: Label3D
var butterflies: Array = []
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func build(page: PageLevel, zone_registry: Dictionary) -> void:
	level = page
	zones = zone_registry
	_rng.seed = 1405
	_build_table_marks()
	_build_crack()
	_build_rift()
	_build_blocks()
	_build_props()


# --- your table ------------------------------------------------------------------------
# No book and no board: the paper world rises straight out of a crack in your real
# table. Only a shadow catcher (so the paper casts shadows on the real wood) and four
# faint pencil corner marks show where the play area is.

func _build_table_marks() -> void:
	var hx := PageLevel.BOOK_HALF.x
	var hz := PageLevel.BOOK_HALF.y
	var catcher := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(hx * 2.0 + 2.0, hz * 2.0 + 2.0)
	catcher.mesh = plane
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, shadow_to_opacity, specular_disabled;
void fragment() { ALBEDO = vec3(0.05, 0.04, 0.04); ALPHA = 0.0; }
"""
	mat.shader = sh
	catcher.material_override = mat
	catcher.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	catcher.position.y = 0.002
	add_child(catcher)
	corner_marks = Node3D.new()
	add_child(corner_marks)
	var mark := Sketch.ink(Color(0.2, 0.2, 0.23, 0.7), true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * hx, 0.01, sz * hz)
			Sketch.tube(PackedVector3Array([c - Vector3(sx * 0.9, 0, 0), c, c - Vector3(0, 0, sz * 0.9)]), 0.025, mark, corner_marks)


## The crack the world comes out of: a jagged split across the back of the play area,
## graphite lips on both sides and a warm light deep inside. set_closed(1) = a hairline.
func _build_crack() -> void:
	crack = Node3D.new()
	add_child(crack)
	var spine := PackedVector3Array()
	for k in range(15):
		var u := k / 14.0
		spine.append(Vector3(lerpf(-5.0, 3.4, u), 0.0, -3.0 + sin(u * 11.0) * 0.18 + (_rng.randf() - 0.5) * 0.22))
	crack_spine = spine
	var im := ImmediateMesh.new()
	crack_mesh = im
	crack_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float open = 0.0;
void fragment() {
	float core = 1.0 - abs(UV.y * 2.0 - 1.0);
	vec3 deep = vec3(0.05, 0.04, 0.06);
	vec3 warm = vec3(1.0, 0.82, 0.45);
	ALBEDO = mix(deep, warm, smoothstep(0.55, 1.0, core) * open);
}
"""
	crack_mat.shader = sh
	var node := Sketch.mesh_node(im, crack_mat, crack)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lip := Sketch.ink(Sketch.GRAPHITE)
	for side in [-1.0, 1.0]:
		var edge := ImmediateMesh.new()
		crack_lips.append(edge)
		var e := Sketch.mesh_node(edge, lip, crack)
		e.set_meta("side", side)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_closed(1.0)


## 1 = shut (a hairline crack), 0 = wide open.
func set_closed(amount: float) -> void:
	crack_open = 1.0 - clampf(amount, 0.0, 1.0)
	var w := 0.04 + 0.42 * crack_open
	crack_mesh.clear_surfaces()
	crack_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var lips: Array = [PackedVector3Array(), PackedVector3Array()]
	for k in range(crack_spine.size() - 1):
		var a := crack_spine[k]
		var b := crack_spine[k + 1]
		var ends := 1.0 - absf(float(k) / (crack_spine.size() - 2) * 2.0 - 1.0)
		var wa := w * (0.35 + 0.65 * sqrt(ends)) * (0.8 + 0.4 * sin(k * 2.3))
		var nb := 1.0 - absf(float(k + 1) / (crack_spine.size() - 2) * 2.0 - 1.0)
		var wb := w * (0.35 + 0.65 * sqrt(clampf(nb, 0.0, 1.0))) * (0.8 + 0.4 * sin((k + 1) * 2.3))
		var side := Vector3(-(b - a).z, 0, (b - a).x).normalized()
		var y := 0.006
		var quad := [[a - side * wa, Vector2(0, 0)], [a + side * wa, Vector2(0, 1)], [b + side * wb, Vector2(1, 1)], [a - side * wa, Vector2(0, 0)], [b + side * wb, Vector2(1, 1)], [b - side * wb, Vector2(1, 0)]]
		for v in quad:
			crack_mesh.surface_set_uv(v[1])
			crack_mesh.surface_add_vertex(v[0] + Vector3(0, y, 0))
		lips[0].append(a - side * wa + Vector3(0, 0.02, 0))
		lips[1].append(a + side * wa + Vector3(0, 0.02, 0))
	crack_mesh.surface_end()
	for i in range(2):
		Sketch.build_tube(crack_lips[i], lips[i], 0.035, 4)
	crack_mat.set_shader_parameter("open", crack_open)


func shake(amount: float) -> void:
	rotation = Vector3(sin(_time * 31.0) * 0.006, 0, sin(_time * 27.0) * 0.008) * amount
	crack.position = Vector3(sin(_time * 53.0) * 0.03, 0, cos(_time * 47.0) * 0.03) * amount


## A point inside the crack (page units), u in 0..1 along it.
func crack_point(u: float) -> Vector3:
	var f := clampf(u, 0.0, 1.0) * (crack_spine.size() - 1)
	var k := mini(int(f), crack_spine.size() - 2)
	return crack_spine[k].lerp(crack_spine[k + 1], f - k)


# --- the next crack (end of the chapter) -------------------------------------------------
# A second rift tears open in the air behind the play area, a glimpse of the next
# world inside it, and the chapter title above.

func _build_rift() -> void:
	rift = Node3D.new()
	add_child(rift)
	rift.position = Vector3(0.4, 3.4, -PageLevel.BOOK_HALF.y - 1.0)
	rift.rotation.x = deg_to_rad(-8.0)
	rift_mesh = ImmediateMesh.new()
	rift_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float open = 0.0;
void fragment() {
	float core = 1.0 - abs(UV.x * 2.0 - 1.0);
	vec3 sky = mix(vec3(0.98, 0.93, 0.78), vec3(0.62, 0.82, 0.95), UV.y);
	ALBEDO = mix(vec3(0.05, 0.04, 0.06), sky, smoothstep(0.2, 0.9, core) * open);
}
"""
	rift_mat.shader = sh
	var n := Sketch.mesh_node(rift_mesh, rift_mat, rift)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rift_glimpse = Node3D.new()
	rift.add_child(rift_glimpse)
	var land := Sketch.ink(Color(0.18, 0.18, 0.2))
	var hills := PackedVector3Array()
	for k in range(9):
		hills.append(Vector3(-0.5 + k * 0.125, -0.9 + sin(k * 1.3) * 0.18 + (0.35 if k == 4 else 0.0), 0.04))
	Sketch.tube(hills, 0.025, land, rift_glimpse)
	var tower := PackedVector3Array([Vector3(0.15, -0.6, 0.04), Vector3(0.15, 0.3, 0.04), Vector3(0.28, 0.55, 0.04), Vector3(0.41, 0.3, 0.04), Vector3(0.41, -0.6, 0.04)])
	Sketch.tube(tower, 0.022, land, rift_glimpse)
	rift_glimpse.visible = false
	page_two_label = Label3D.new()
	page_two_label.text = "الفصل الثاني"
	page_two_label.font = load("res://assets/fonts/BalooBhaijaan2-Arabic.ttf")
	page_two_label.font_size = 96
	page_two_label.pixel_size = 0.0075
	page_two_label.modulate = Color(0.16, 0.14, 0.13, 0.0)
	page_two_label.outline_size = 18
	page_two_label.outline_modulate = Color(0.97, 0.94, 0.85, 0.0)
	page_two_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	page_two_label.no_depth_test = true
	page_two_label.position = rift.position + Vector3(0, 2.2, 0.4)
	add_child(page_two_label)
	flip_page(0.0)


## 0 = no rift, 1 = torn wide open (the ending's "next page").
func flip_page(t: float) -> void:
	rift_t = clampf(t, 0.0, 1.0)
	rift_mesh.clear_surfaces()
	rift.visible = rift_t > 0.001
	if not rift.visible:
		return
	var h := 2.6 * smoothstep(0.0, 0.5, rift_t)
	var w := 0.08 + 0.75 * smoothstep(0.25, 1.0, rift_t)
	rift_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	for k in range(n):
		var v0 := float(k) / n
		var v1 := float(k + 1) / n
		var y0 := (v0 - 0.5) * h
		var y1 := (v1 - 0.5) * h
		var w0 := w * sin(v0 * PI) * (0.75 + 0.5 * absf(sin(k * 2.1)))
		var w1 := w * sin(v1 * PI) * (0.75 + 0.5 * absf(sin((k + 1) * 2.1)))
		var j0 := sin(k * 1.9) * 0.1
		var j1 := sin((k + 1) * 1.9) * 0.1
		for v in [[Vector3(j0 - w0, y0, 0), Vector2(0, v0)], [Vector3(j0 + w0, y0, 0), Vector2(1, v0)], [Vector3(j1 + w1, y1, 0), Vector2(1, v1)], [Vector3(j0 - w0, y0, 0), Vector2(0, v0)], [Vector3(j1 + w1, y1, 0), Vector2(1, v1)], [Vector3(j1 - w1, y1, 0), Vector2(0, v1)]]:
			rift_mesh.surface_set_uv(v[1])
			rift_mesh.surface_add_vertex(v[0])
	rift_mesh.surface_end()
	rift_mat.set_shader_parameter("open", smoothstep(0.3, 1.0, rift_t))
	rift_glimpse.visible = rift_t > 0.6
	rift_glimpse.scale = Vector3.ONE * smoothstep(0.6, 1.0, rift_t)


func show_page_two(alpha: float) -> void:
	page_two_label.modulate.a = alpha
	page_two_label.outline_modulate.a = alpha * 0.9


# --- terrain -------------------------------------------------------------------------------

func _pop(node: Node3D, delay: float) -> void:
	node.scale = Vector3(1, 0.01, 1)
	node.visible = false
	popups.append({"node": node, "delay": delay})


## Pop-ups rise from the page in a wave from left to right.
func pop_progress(t: float) -> void:
	for n in popups:
		var node: Node3D = n.node
		var k := clampf((t - n.delay) / 0.45, 0.0, 1.0)
		node.visible = k > 0.0
		node.scale = Vector3(1, maxf(0.01, _ease_out_back(k, 1.6)), 1)


static func _ease_out_back(t: float, s: float) -> float:
	var u := t - 1.0
	return 1.0 + u * u * ((s + 1.0) * u + s)


func _build_blocks() -> void:
	var looks := {
		"P1": [Color(0.78, 0.70, 0.58), Sketch.GRASS.darkened(0.1)],
		"P2": [Color(0.84, 0.78, 0.64), Sketch.GRASS],
		"R": [Color(0.8, 0.76, 0.7), Color(0.74, 0.7, 0.62)],
		"S": [Color(0.84, 0.78, 0.66), Sketch.GRASS.lightened(0.08)],
		"T1": [Color(0.82, 0.76, 0.66), Sketch.GRASS.lightened(0.05)],
		"T2": [Color(0.82, 0.76, 0.66), Sketch.GRASS.lightened(0.1)],
		"T3": [Color(0.82, 0.76, 0.66), Sketch.GRASS.lightened(0.15)],
	}
	for b in level.blocks:
		if not looks.has(b.id):
			continue
		var root := Node3D.new()
		add_child(root)
		var size: Vector3 = b.max - b.min
		var center: Vector3 = (b.max + b.min) * 0.5
		var zone: int = b.zone
		var cliff := Sketch.box(size - Vector3(0, 0.1, 0), Sketch.paper(looks[b.id][0], zone, zones), root)
		cliff.position = center - Vector3(0, 0.05, 0)
		var top := Sketch.box(Vector3(size.x + 0.06, 0.12, size.z + 0.06), Sketch.paper(looks[b.id][1], zone, zones), root)
		top.position = Vector3(center.x, b.max.y - 0.06, center.z)
		Sketch.sketch_box_edges(size, center, 0.02, _rng, root)
		var strata := Sketch.ink(Color(0.5, 0.45, 0.38))
		for k in range(int(size.y * 3.0)):
			var y: float = b.min.y + 0.25 + k * 0.33
			if y > b.max.y - 0.2:
				break
			var pts := PackedVector3Array()
			for s in range(8):
				var t := s / 7.0
				pts.append(Vector3(lerpf(b.min.x + 0.1, b.max.x - 0.1, t), y + sin(t * 9.0 + k) * 0.04, b.max.z + 0.006))
			Sketch.tube(pts, 0.012, strata, root)
		_pop(root, (center.x + 5.5) * 0.12)
		# Grass tufts that only appear when life returns.
		if b.id != "R":
			for g in range(int(size.x * size.z * 0.9)):
				var tuft := Node3D.new()
				add_child(tuft)
				tuft.position = Vector3(_rng.randf_range(b.min.x + 0.1, b.max.x - 0.1), b.max.y, _rng.randf_range(b.min.z + 0.1, b.max.z - 0.1))
				for blade in range(3):
					var c := Sketch.cylinder(0.0, 0.025, 0.16, Sketch.paper(Sketch.GRASS.darkened(_rng.randf_range(0.0, 0.25))), tuft, 4)
					c.position = Vector3((blade - 1) * 0.035, 0.07, 0)
					c.rotation.z = (blade - 1) * 0.3
				tuft.scale = Vector3.ONE * 0.01
				tuft.visible = false
				grass.append(tuft)


func _build_props() -> void:
	# --- start: dead tree, stones, the broken old bridge.
	dead_tree = Node3D.new()
	add_child(dead_tree)
	dead_tree.position = level.dead_tree
	var bark := Sketch.paper(Color(0.47, 0.37, 0.27), 0, zones)
	Sketch.cylinder(0.07, 0.12, 1.25, bark, dead_tree, 6).position.y = 0.62
	var branch := Sketch.ink(Color(0.33, 0.27, 0.21))
	for i in range(5):
		var ang := i * 1.4
		var pts := PackedVector3Array([Vector3(0, 0.7 + i * 0.12, 0), Vector3(cos(ang) * 0.38, 1.05 + i * 0.1, sin(ang) * 0.38), Vector3(cos(ang + 0.4) * 0.55, 1.2 + i * 0.1, sin(ang + 0.4) * 0.55)])
		Sketch.tube(pts, 0.03, branch, dead_tree)
		var leaf := Sketch.sphere(0.24, Sketch.paper(Color(0.42, 0.66, 0.32).lightened(i * 0.04)), dead_tree, 9, 6)
		leaf.position = Vector3(cos(ang + 0.4) * 0.5, 1.25 + i * 0.1, sin(ang + 0.4) * 0.5)
		leaf.scale = Vector3.ONE * 0.01
		leaf.visible = false
		leaves.append(leaf)
	_pop(dead_tree, 0.45)
	var p1 := level.block("P1")
	for i in range(5):
		var rock := Sketch.sphere(_rng.randf_range(0.09, 0.17), Sketch.paper(Sketch.STONE, 0, zones), self, 7, 4)
		rock.position = Vector3(_rng.randf_range(p1.min.x + 0.2, p1.max.x - 0.3), 1.02, _rng.randf_range(p1.min.z + 0.15, p1.min.z + 0.55))
		rock.scale.y = 0.6
		_pop(rock, 0.5)
	var plank := Sketch.paper(Color(0.5, 0.38, 0.26), 0, zones)
	for side in [[p1.max.x, 1.0], [level.block("P2").min.x, -1.0]]:
		var stub := Node3D.new()
		add_child(stub)
		stub.position = Vector3(side[0], 0.98, level.gap_edge.z)
		for k in range(2):
			var pl := Sketch.box(Vector3(0.28, 0.06, 0.55), plank, stub)
			pl.position = Vector3(side[1] * (0.18 + k * 0.3), -0.05 - k * 0.18, _rng.randf_range(-0.05, 0.05))
			pl.rotation.z = -side[1] * (0.35 + k * 0.4)
		var rope := PackedVector3Array([Vector3(0, 0.25, 0.32), Vector3(side[1] * 0.3, -0.1, 0.34), Vector3(side[1] * 0.45, -0.5, 0.3)])
		Sketch.tube(rope, 0.015, Sketch.ink(Color(0.4, 0.32, 0.24)), stub)
		Sketch.cylinder(0.04, 0.045, 0.45, plank, stub).position = Vector3(-side[1] * 0.05, 0.18, 0.34)
		_pop(stub, 0.6 if side[1] > 0 else 0.9)
	# --- the little light across the gap and the one wilted flower.
	light = Node3D.new()
	add_child(light)
	light.position = level.light + Vector3(0, 0.35, 0)
	var glow := Sketch.paper(Sketch.GOLD)
	glow.set_shader_parameter("glow", 1.2)
	Sketch.sphere(0.09, glow, light, 10, 6)
	var halo := Sketch.sphere(0.2, Sketch.ink(Color(1.0, 0.85, 0.35, 0.25), true), light, 10, 6)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pop(light, 0.85)
	flower = Node3D.new()
	add_child(flower)
	flower.position = level.flower
	Sketch.cylinder(0.014, 0.018, 0.32, Sketch.paper(Color(0.4, 0.55, 0.3)), flower, 5).position.y = 0.16
	flower_head = Node3D.new()
	flower_head.position.y = 0.3
	flower.add_child(flower_head)
	flower_mat = Sketch.paper(Color(0.98, 0.8, 0.25))
	flower_mat.set_shader_parameter("life", 0.0)
	for k in range(6):
		var petal := Sketch.sphere(0.06, flower_mat, flower_head, 7, 4)
		petal.position = Vector3(cos(k * TAU / 6.0) * 0.06, 0, sin(k * TAU / 6.0) * 0.06)
		petal.scale = Vector3(1.0, 0.35, 0.6)
		petal.rotation.y = -k * TAU / 6.0
		petal.set_meta("angle", k * TAU / 6.0)
	Sketch.sphere(0.035, Sketch.paper(Color(0.75, 0.45, 0.2)), flower_head, 6, 4)
	_pop(flower, 0.8)
	# Buds that open at the end.
	var colors := [Color(0.9, 0.35, 0.32), Color(0.98, 0.75, 0.3), Color(0.7, 0.5, 0.9), Color(0.95, 0.6, 0.72)]
	for i in range(12):
		var host: Dictionary = level.blocks[[0, 1, 3, 5, 6, 7][i % 6]]
		var bud := Node3D.new()
		add_child(bud)
		bud.position = Vector3(_rng.randf_range(host.min.x + 0.2, host.max.x - 0.2), host.max.y, _rng.randf_range(host.min.z + 0.2, host.max.z - 0.2))
		if Vector2(bud.position.x - level.gate.x, bud.position.z - level.gate.z).length() < 1.0:
			bud.position.x -= 0.6
		Sketch.cylinder(0.01, 0.012, 0.2, Sketch.paper(Color(0.35, 0.6, 0.25)), bud, 4).position.y = 0.1
		var head := Node3D.new()
		head.position.y = 0.21
		bud.add_child(head)
		var mat := Sketch.paper(colors[i % colors.size()])
		for k in range(5):
			var petal := Sketch.sphere(0.04, mat, head, 6, 4)
			petal.position = Vector3(cos(k * TAU / 5.0) * 0.04, 0, sin(k * TAU / 5.0) * 0.04)
			petal.scale = Vector3(1, 0.4, 0.6)
			petal.rotation.y = -k * TAU / 5.0
		Sketch.sphere(0.025, Sketch.paper(Sketch.GOLD), head, 6, 4)
		bud.scale = Vector3.ONE * 0.01
		bud.visible = false
		buds.append(bud)
	# --- the dry stream drawn along P2's front edge.
	var pts := PackedVector3Array()
	for k in range(16):
		var t := k / 15.0
		pts.append(Vector3(lerpf(-1.65, 1.35, t), 1.005, 2.32 + sin(t * 7.0) * 0.08))
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(pts.size() - 1):
		var a := pts[k]
		var b := pts[k + 1]
		var side := Vector3(-(b - a).z, 0, (b - a).x).normalized() * 0.13
		var u0 := float(k) / (pts.size() - 1)
		var u1 := float(k + 1) / (pts.size() - 1)
		for v in [[a - side, Vector2(u0, 0)], [a + side, Vector2(u0, 1)], [b + side, Vector2(u1, 1)], [a - side, Vector2(u0, 0)], [b + side, Vector2(u1, 1)], [b - side, Vector2(u1, 0)]]:
			im.surface_set_uv(v[1])
			im.surface_add_vertex(v[0])
	im.surface_end()
	stream_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float flow = 0.0;
void fragment() {
	float stripe = smoothstep(0.55, 0.6, sin((UV.x * 30.0 - TIME * 2.2) + sin(UV.y * 6.0) * 1.2) * 0.5 + 0.5);
	vec3 dry = vec3(0.62, 0.58, 0.52);
	vec3 water = mix(vec3(0.55, 0.75, 0.88), vec3(0.85, 0.94, 1.0), stripe);
	float bank = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.85, UV.y);
	ALBEDO = mix(dry * (0.85 + 0.15 * bank), water, flow * bank);
}
"""
	stream_mat.shader = sh
	stream = Sketch.mesh_node(im, stream_mat, self)
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pop(stream, 0.9)
	# --- the old gate on P2 with two doors.
	var gate_root := Node3D.new()
	add_child(gate_root)
	var stone := Sketch.paper(Sketch.STONE, 2, zones)
	var gx := level.gate.x
	for z in [0.68, 2.52]:
		var pillar := Sketch.box(Vector3(0.32, 1.7, 0.26), stone, gate_root)
		pillar.position = Vector3(gx, 1.85, z)
		Sketch.sketch_box_edges(Vector3(0.32, 1.7, 0.26), pillar.position, 0.015, _rng, gate_root)
	var lintel := Sketch.box(Vector3(0.4, 0.3, 2.2), stone, gate_root)
	lintel.position = Vector3(gx, 2.85, 1.6)
	lintel.rotation.x = 0.04
	Sketch.sketch_box_edges(Vector3(0.4, 0.3, 2.2), lintel.position, 0.015, _rng, gate_root)
	var door_mat := Sketch.paper(Color(0.55, 0.4, 0.26), 2, zones)
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		gate_root.add_child(hinge)
		hinge.position = Vector3(gx, 1.0, 1.6 + side * 0.82)
		var door := Sketch.box(Vector3(0.08, 1.6, 0.82), door_mat, hinge)
		door.position = Vector3(0, 0.8, -side * 0.41)
		Sketch.sketch_box_edges(Vector3(0.08, 1.6, 0.82), door.position, 0.012, _rng, hinge)
		for k in range(3):
			var bar := Sketch.box(Vector3(0.1, 0.06, 0.8), Sketch.paper(Color(0.35, 0.25, 0.18)), hinge)
			bar.position = Vector3(0, 0.3 + k * 0.5, -side * 0.41)
		hinge.set_meta("side", side)
		gate_doors.append(hinge)
	_pop(gate_root, 0.95)
	# --- the switch on S.
	var sw := Node3D.new()
	add_child(sw)
	sw.position = level.switch_pos
	Sketch.cylinder(PageLevel.SWITCH_RADIUS + 0.1, PageLevel.SWITCH_RADIUS + 0.12, 0.05, Sketch.paper(Sketch.STONE, 2, zones), sw, 16).position.y = 0.025
	switch_mat = Sketch.paper(Color(0.82, 0.78, 0.7), 2, zones)
	switch_top = Sketch.cylinder(PageLevel.SWITCH_RADIUS, PageLevel.SWITCH_RADIUS, 0.07, switch_mat, sw, 16)
	switch_top.position.y = 0.075
	var star := PackedVector3Array()
	for i in range(11):
		var ang := PI * 0.5 + TAU * i / 10.0
		var r := 0.27 if i % 2 == 0 else 0.11
		star.append(Vector3(cos(ang) * r, 0.0, sin(ang) * r))
	Sketch.tube(star, 0.018, Sketch.ink(Color(0.45, 0.35, 0.15)), switch_top).position.y = 0.037
	_pop(sw, 1.0)
	# --- the green orb on T3.
	orb = Node3D.new()
	add_child(orb)
	orb.position = level.orb + Vector3(0, 0.55, 0)
	orb_mat = Sketch.paper(Color(0.45, 0.85, 0.45))
	orb_mat.set_shader_parameter("glow", 0.9)
	orb_mat.set_shader_parameter("glow_color", Color(0.4, 0.95, 0.45))
	Sketch.sphere(0.2, orb_mat, orb, 12, 8)
	var orb_halo := Sketch.sphere(0.4, Sketch.ink(Color(0.5, 1.0, 0.5, 0.22), true), orb, 12, 8)
	orb_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pop(orb, 1.3)


# --- live changes ---------------------------------------------------------------------------

func set_gate_open(t: float) -> void:
	gate_open = t
	for h in gate_doors:
		var side: float = h.get_meta("side")
		h.rotation.y = side * deg_to_rad(100.0) * smoothstep(0.0, 1.0, t)


func set_switch_pressed(on: bool) -> void:
	switch_pressed = on


func spawn_butterflies(count: int) -> void:
	var colors := [Color(1.0, 0.85, 0.4), Color(0.6, 0.8, 1.0), Color(1.0, 0.6, 0.7)]
	for i in range(count):
		var b := Node3D.new()
		add_child(b)
		var mat := Sketch.paper(colors[i % colors.size()])
		mat.set_shader_parameter("glow", 0.2)
		var wings: Array[MeshInstance3D] = []
		for side in [-1.0, 1.0]:
			var q := QuadMesh.new()
			q.size = Vector2(0.18, 0.14)
			var w := Sketch.mesh_node(q, mat, b)
			var m := mat.duplicate() as ShaderMaterial
			w.material_override = m
			(w.material_override as ShaderMaterial).render_priority = 0
			w.position.x = side * 0.09
			w.set_meta("side", side)
			wings.append(w)
		var center := Vector3(_rng.randf_range(-4.5, 4.5), _rng.randf_range(1.6, 2.8), _rng.randf_range(-2.4, 2.4))
		butterflies.append({"node": b, "wings": wings, "center": center, "phase": _rng.randf() * TAU, "r": _rng.randf_range(0.4, 0.9)})


func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(light) and light.visible:
		light.position.y = level.light.y + 0.35 + sin(_time * 2.4) * 0.06
		light.rotation.y += delta
	# The wilted flower droops until a colour drop reaches it.
	var droop := 1.0 - flower_bloom
	flower_head.rotation.x = 1.1 * droop
	flower_head.scale = Vector3.ONE * lerpf(0.7, 1.15, flower_bloom)
	for petal in flower_head.get_children():
		if petal.has_meta("angle"):
			var open := lerpf(0.9, 0.0, flower_bloom)
			(petal as Node3D).rotation = Vector3(0, -float(petal.get_meta("angle")), open + sin(_time * 3.0 + float(petal.get_meta("angle"))) * 0.05 * flower_bloom)
	flower_mat.set_shader_parameter("life", flower_bloom)
	stream_mat.set_shader_parameter("flow", stream_flow)
	switch_top.position.y = lerpf(switch_top.position.y, 0.035 if switch_pressed else 0.075, minf(1.0, delta * 8.0))
	switch_mat.set_shader_parameter("glow", (0.45 if switch_pressed else 0.08 + 0.08 * sin(_time * 3.0)))
	if orb.visible:
		orb.position.y = level.orb.y + 0.55 + sin(_time * 1.8) * 0.08
		orb_mat.set_shader_parameter("glow", 0.8 + 0.3 * sin(_time * 3.0))
	for b in butterflies:
		var t: float = _time * 0.8 + b.phase
		var node: Node3D = b.node
		var c: Vector3 = b.center
		node.position = c + Vector3(cos(t) * b.r, sin(t * 2.3) * 0.25, sin(t * 1.3) * b.r)
		node.rotation.y = -t + PI * 0.5
		for w in b.wings:
			var side: float = w.get_meta("side")
			w.rotation = Vector3(-PI * 0.5, 0, side * (0.3 + absf(sin(_time * 14.0 + b.phase)) * 1.1))
