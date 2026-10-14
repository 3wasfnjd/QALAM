class_name BookWorld
extends Node3D
## The sketchbook on your table and everything in it.
##  PLACING  the closed book follows your gaze; left stick ↑↓ sets the table
##           height; A / X / trigger puts it down
##  OPENING  the cover swings open, the paper world pops up, the pencil lands
##  PLAYING  stick walks the pencil, A / X jumps, a trigger draws with that
##           hand, B / Y rubs out the last bridge
##  WON      colour floods back, the pencil celebrates; A plays again
## Room scale is metres; everything inside `page` is in page units.

signal won
signal haptic(hand: int, amplitude: float, seconds: float)

enum Phase { PLACING, OPENING, PLAYING, WON }

const SCALE := 0.11
const DEFAULT_TABLE := 0.78
const PLACE_DISTANCE := 0.62
const SIM_HZ := 90.0
const OPEN_TIME := 1.1
const POP_TIME := 1.6
const SAMPLE_STEP := 0.07     # page units between stroke points

var phase: int = Phase.PLACING
var head: Node3D
var hands: Array[Node3D] = []      # aim-pose controllers (room space)
var pens: Array[DrawingPen] = []
var audio: GameAudio
var level: PageLevel
var hero: PencilHero
var ball: PaperBall
var page: Node3D
var table_height: float = DEFAULT_TABLE
var placed: bool = false
var gate_restored: bool = false
var zones: Dictionary = {}           # zone -> Array[ShaderMaterial]
var zone_life: Dictionary = {0: 0.0, 1: 0.0, 2: 0.0}
var zone_target: Dictionary = {0: 0.0, 1: 0.0, 2: 0.0}
var bridges: Array[BridgeView] = []
var strokes_failed: int = 0

var _rng := RandomNumberGenerator.new()
var _left_half: Node3D
var _popups: Array = []              # {node, delay}
var _phase_time: float = 0.0
var _sim_accum: float = 0.0
var _jump_queued: bool = false
var _move := Vector2.ZERO
var _confetti: Confetti
var _plate: Node3D
var _plate_top: MeshInstance3D
var _plate_mat: ShaderMaterial
var _goal: Node3D
var _gate_pieces: Array = []         # {node, broken: Transform3D, fixed: Transform3D}
var _rubble: Array[Node3D] = []
var _vines: Array[Node3D] = []
var _tree_leaves: Array[Node3D] = []
var _flowers: Array[Node3D] = []
var _guide: MeshInstance3D
var _guide_mat: ShaderMaterial
var _replay: Node3D
var _hand_prev: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _was_drawing: Array[bool] = [false, false]
var _stroke_points: Array = [PackedVector3Array(), PackedVector3Array()]
var _stroke_meshes: Array[ImmediateMesh] = []
var _stroke_nodes: Array[MeshInstance3D] = []
var _anchor_marks: Array[MeshInstance3D] = []
var _falling_strokes: Array = []     # {node, mesh, points, vel, life}
var _won_time: float = 0.0
var _scribble: AudioStreamPlayer3D
var _step_cooldown: float = 0.0


func build(camera: Node3D, aim_hands: Array[Node3D]) -> void:
	head = camera
	hands = aim_hands
	_rng.seed = 1405
	audio = GameAudio.new()
	add_child(audio)
	for h in hands:
		var pen := DrawingPen.new()
		h.add_child(pen)
		pens.append(pen)
	page = Node3D.new()
	page.scale = Vector3.ONE * SCALE
	add_child(page)
	_confetti = Confetti.new()
	page.add_child(_confetti)
	for i in range(2):
		var im := ImmediateMesh.new()
		_stroke_meshes.append(im)
		var node := Sketch.mesh_node(im, Sketch.ink(Sketch.GRAPHITE), page)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stroke_nodes.append(node)
		var mark := _make_anchor_mark()
		_anchor_marks.append(mark)
	_scribble = audio.attach_loop("scribble", self, -14.0)
	_build_book()
	new_game()
	_set_phase(Phase.PLACING)
	audio.play_music("calm")


# --- book & world ----------------------------------------------------------------

func _build_book() -> void:
	var cover := Sketch.paper(Color(0.45, 0.28, 0.18))
	var paper := Sketch.paper(Sketch.PAPER)
	var edge := Sketch.paper(Sketch.PAPER_DARK)
	# Right half sits still; the left half hinges on the spine (x = 0).
	var right := Node3D.new()
	page.add_child(right)
	Sketch.box(Vector3(4.6, 0.12, 5.6), cover, right).position = Vector3(2.3, -0.5, 0)
	Sketch.box(Vector3(4.4, 0.36, 5.3), edge, right).position = Vector3(2.2, -0.2, 0)
	Sketch.box(Vector3(4.4, 0.02, 5.3), paper, right).position = Vector3(2.2, -0.01, 0)
	_left_half = Node3D.new()
	page.add_child(_left_half)
	Sketch.box(Vector3(4.6, 0.12, 5.6), cover, _left_half).position = Vector3(-2.3, -0.5, 0)
	Sketch.box(Vector3(4.4, 0.36, 5.3), edge, _left_half).position = Vector3(-2.2, -0.2, 0)
	Sketch.box(Vector3(4.4, 0.02, 5.3), paper, _left_half).position = Vector3(-2.2, -0.01, 0)
	# Spine and a few doodles on the blank pages.
	Sketch.cylinder(0.14, 0.14, 5.6, cover, page).rotation.x = PI / 2.0
	var doodle := Sketch.ink(Color(0.55, 0.52, 0.48))
	for i in range(14):
		var x := _rng.randf_range(-4.2, 4.2)
		var z := _rng.randf_range(-2.4, 2.4)
		if absf(x) < 0.3:
			continue
		var pts := PackedVector3Array()
		var ang := _rng.randf() * TAU
		for k in range(6):
			pts.append(Vector3(x + cos(ang) * k * 0.08, 0.005, z + sin(ang) * k * 0.08 + sin(k * 1.7) * 0.04))
		Sketch.tube(pts, 0.012, doodle, _left_half if x < 0.0 else right)
	# Ruled lines.
	var ruled := Sketch.ink(Color(0.72, 0.78, 0.86))
	for i in range(9):
		var z := -2.3 + i * 0.58
		Sketch.tube(PackedVector3Array([Vector3(-4.3, 0.004, z), Vector3(-0.3, 0.004, z)]), 0.008, ruled, _left_half)
		Sketch.tube(PackedVector3Array([Vector3(0.3, 0.004, z), Vector3(4.3, 0.004, z)]), 0.008, ruled, right)


func new_game() -> void:
	# Clear everything that lives on the page.
	for n in _popups:
		if is_instance_valid(n.node):
			n.node.queue_free()
	_popups.clear()
	for b in bridges:
		if is_instance_valid(b):
			b.queue_free()
	bridges.clear()
	if hero:
		hero.queue_free()
	if ball:
		ball.queue_free()
	if _replay:
		_replay.queue_free()
		_replay = null
	_gate_pieces.clear()
	_rubble.clear()
	_vines.clear()
	_tree_leaves.clear()
	_flowers.clear()
	zones.clear()
	level = PageLevel.page_one()
	gate_restored = false
	strokes_failed = 0
	for z in [0, 1, 2]:
		zone_life[z] = 0.0
		zone_target[z] = 0.0
	_build_terrain()
	_build_props()
	hero = PencilHero.new()
	page.add_child(hero)
	hero.setup(level, level.spawn)
	hero.make_shadow(page)
	hero.look_target = head
	hero.visible = false
	hero.jumped.connect(func(): cue("jump", hero.global_position))
	hero.landed.connect(func(impact: float): cue("land", hero.global_position, -8.0 + impact * 8.0))
	hero.fell.connect(func():
		cue("poof", hero.global_position)
		_confetti.burst(hero.position + Vector3(0, 0.3, 0), 18, [Sketch.PAPER, Sketch.PAPER_DARK, Sketch.YELLOW], 1.5, 2.0))
	hero.respawned.connect(func(): cue("pop", hero.global_position, -4.0))
	hero.stepped.connect(func():
		if _step_cooldown <= 0.0:
			_step_cooldown = 0.12
			cue("step", hero.global_position, -14.0))
	ball = PaperBall.new()
	page.add_child(ball)
	ball.setup(level, level.ball_start, page)
	ball.visible = false
	ball.fell.connect(func():
		cue("poof", ball.global_position, -3.0)
		_confetti.burst(ball.position, 14, [Sketch.PAPER, Sketch.PAPER_DARK], 1.5, 2.0))
	ball.bumped.connect(func(s: float): cue("bump", ball.global_position, -10.0 + minf(s, 5.0)))
	_apply_zone_life()


func _pop(node: Node3D, delay: float) -> void:
	node.scale = Vector3(1, 0.01, 1)
	_popups.append({"node": node, "delay": delay})


func _build_terrain() -> void:
	var colors := {
		"A": [Color(0.80, 0.72, 0.60), Sketch.GRASS.darkened(0.12)],
		"B": [Color(0.86, 0.80, 0.66), Sketch.GRASS],
		"C": [Color(0.84, 0.78, 0.66), Sketch.GRASS.lightened(0.1)],
	}
	for b in level.blocks:
		if b.id == "gate":
			continue
		var root := Node3D.new()
		page.add_child(root)
		var size: Vector3 = b.max - b.min
		var center: Vector3 = (b.max + b.min) * 0.5
		var zone: int = b.zone
		var cliff := Sketch.box(size - Vector3(0, 0.1, 0), Sketch.paper(colors[b.id][0], zone, zones), root)
		cliff.position = center - Vector3(0, 0.05, 0)
		var top := Sketch.box(Vector3(size.x + 0.06, 0.12, size.z + 0.06), Sketch.paper(colors[b.id][1], zone, zones), root)
		top.position = Vector3(center.x, b.max.y - 0.06, center.z)
		Sketch.sketch_box_edges(size, center, 0.018, _rng, root)
		# Paper-cut strata lines on the cliff faces.
		var strata := Sketch.ink(Color(0.5, 0.45, 0.38))
		for k in range(int(size.y * 3.0)):
			var y: float = b.min.y + 0.25 + k * 0.33
			if y > b.max.y - 0.2:
				break
			var zf: float = b.max.z + 0.005
			var pts := PackedVector3Array()
			for s in range(8):
				var t := s / 7.0
				pts.append(Vector3(lerpf(b.min.x + 0.1, b.max.x - 0.1, t), y + sin(t * 9.0 + k) * 0.04, zf))
			Sketch.tube(pts, 0.01, strata, root)
		_pop(root, 0.15 + (center.x + 4.0) * 0.12)


func _build_props() -> void:
	var a := level.block("A")
	var c := level.block("C")
	# --- Zone 0: the faded start. Dead tree, fence, the sign.
	var dead := Node3D.new()
	page.add_child(dead)
	dead.position = Vector3(-3.6, 1.0, -0.8)
	var bark := Sketch.paper(Color(0.45, 0.38, 0.3), 0, zones)
	Sketch.cylinder(0.06, 0.1, 1.1, bark, dead, 6).position.y = 0.55
	for i in range(4):
		var ang := i * 1.7
		var pts := PackedVector3Array([Vector3(0, 0.6 + i * 0.12, 0), Vector3(cos(ang) * 0.35, 0.95 + i * 0.1, sin(ang) * 0.35), Vector3(cos(ang) * 0.5, 1.1 + i * 0.1, sin(ang) * 0.5)])
		Sketch.tube(pts, 0.025, Sketch.ink(Color(0.36, 0.3, 0.24)), dead)
	_pop(dead, 0.5)
	var sign := Node3D.new()
	page.add_child(sign)
	sign.position = Vector3(-2.35, 1.0, 0.75)
	sign.rotation.y = 0.35
	var wood := Sketch.paper(Sketch.WOOD, 0, zones)
	Sketch.cylinder(0.035, 0.035, 0.6, wood, sign, 6).position.y = 0.3
	var board := Sketch.box(Vector3(0.9, 0.32, 0.05), wood, sign)
	board.position.y = 0.6
	board.rotation.z = -0.06
	var label := Label3D.new()
	label.text = "ما زال .. هناك أمل"
	label.font = load("res://assets/fonts/BalooBhaijaan2-Arabic.ttf")
	label.font_size = 64
	label.pixel_size = 0.0026
	label.modulate = Color(0.2, 0.15, 0.1)
	label.outline_size = 0
	label.position = Vector3(0, 0.6, 0.03)
	label.rotation.z = -0.06
	label.double_sided = false
	sign.add_child(label)
	_pop(sign, 0.6)
	for i in range(5):
		var rock := Sketch.sphere(_rng.randf_range(0.08, 0.15), Sketch.paper(Sketch.STONE, 0, zones), page, 7, 4)
		rock.position = Vector3(_rng.randf_range(a.min.x + 0.2, a.max.x - 0.2), 1.02, _rng.randf_range(a.min.z + 0.15, a.min.z + 0.5))
		rock.scale.y = 0.6
		_pop(rock, 0.55)
	# --- Zone 1: plate with the star.
	_plate = Node3D.new()
	page.add_child(_plate)
	_plate.position = level.plate
	Sketch.cylinder(PageLevel.PLATE_RADIUS + 0.08, PageLevel.PLATE_RADIUS + 0.1, 0.05, Sketch.paper(Sketch.STONE, 1, zones), _plate, 16).position.y = 0.025
	_plate_mat = Sketch.paper(Color(0.85, 0.82, 0.74), 1, zones)
	_plate_top = Sketch.cylinder(PageLevel.PLATE_RADIUS, PageLevel.PLATE_RADIUS, 0.06, _plate_mat, _plate, 16)
	_plate_top.position.y = 0.06
	var star := PackedVector3Array()
	for i in range(11):
		var ang := PI * 0.5 + TAU * i / 10.0
		var r := 0.3 if i % 2 == 0 else 0.13
		star.append(Vector3(cos(ang) * r, 0.0, sin(ang) * r))
	Sketch.tube(star, 0.018, Sketch.ink(Color(0.45, 0.35, 0.15)), _plate_top).position.y = 0.032
	_pop(_plate, 1.0)
	# Flowers waiting to bloom on B and C.
	for i in range(9):
		var host := level.block("B") if i < 5 else c
		var f := _make_flower(i)
		page.add_child(f)
		var fx := _rng.randf_range(host.min.x + 0.15, host.max.x - 0.15)
		var fz := _rng.randf_range(host.min.z + 0.15, host.max.z - 0.15)
		if host == c and fx > 3.0:
			fx -= 0.5
		f.position = Vector3(fx, host.max.y, fz)
		if Vector2(fx - level.plate.x, fz - level.plate.z).length() < 0.7 or Vector2(fx - level.ball_start.x, fz - level.ball_start.z).length() < 0.6:
			f.position.z = host.min.z + 0.15 if fz > 0 else host.max.z - 0.15
		f.scale = Vector3.ONE * 0.01
		f.set_meta("zone", 1 if host != c else 2)
		_flowers.append(f)
	# --- Zone 2: the tree of life, the broken gate, the goal star.
	var tree := Node3D.new()
	page.add_child(tree)
	tree.position = Vector3(3.85, 2.0, -1.35)
	Sketch.cylinder(0.08, 0.13, 1.0, Sketch.paper(Color(0.5, 0.36, 0.24), 2, zones), tree, 7).position.y = 0.5
	for i in range(4):
		var leaf := Sketch.sphere(0.32 - i * 0.03, Sketch.paper(Color(0.38, 0.62, 0.28).lightened(i * 0.05), 2, zones), tree, 10, 6)
		leaf.position = Vector3(cos(i * 1.9) * 0.22, 1.05 + i * 0.13, sin(i * 1.9) * 0.22)
		leaf.scale = Vector3.ONE * 0.01
		_tree_leaves.append(leaf)
	_pop(tree, 1.1)
	# Gate: two pillars and a lintel, broken; rubble blocks the path.
	var stone := Sketch.paper(Sketch.STONE, 2, zones)
	var gate_x := 3.2
	var fixed_parts := [
		[Vector3(0.24, 1.3, 0.24), Transform3D(Basis(), Vector3(gate_x, 2.65, -1.45))],
		[Vector3(0.24, 1.3, 0.24), Transform3D(Basis(), Vector3(gate_x, 2.65, -0.25))],
		[Vector3(0.3, 0.26, 1.55), Transform3D(Basis(), Vector3(gate_x, 3.42, -0.85))],
	]
	var broken := [
		Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(gate_x, 2.6, -1.45)),
		Transform3D(Basis(Vector3.RIGHT, 1.35).rotated(Vector3.UP, 0.4), Vector3(gate_x + 0.45, 2.12, 0.15)),
		Transform3D(Basis(Vector3.RIGHT, 0.3).rotated(Vector3.FORWARD, 0.25), Vector3(gate_x, 2.3, -0.75)),
	]
	for i in range(fixed_parts.size()):
		var piece := Node3D.new()
		page.add_child(piece)
		Sketch.box(fixed_parts[i][0], stone, piece)
		Sketch.sketch_box_edges(fixed_parts[i][0], Vector3.ZERO, 0.014, _rng, piece)
		piece.transform = broken[i]
		_gate_pieces.append({"node": piece, "broken": broken[i], "fixed": fixed_parts[i][1]})
		_pop(piece, 1.2)
	for i in range(6):
		var r := Sketch.box(Vector3(_rng.randf_range(0.18, 0.3), _rng.randf_range(0.14, 0.24), _rng.randf_range(0.18, 0.3)), stone, page)
		r.position = Vector3(gate_x + _rng.randf_range(-0.12, 0.12), 2.1 + (i / 3) * 0.2, -1.35 + (i % 3) * 0.5 + _rng.randf_range(-0.1, 0.1))
		r.rotation = Vector3(_rng.randf(), _rng.randf(), _rng.randf())
		_rubble.append(r)
		_pop(r, 1.25)
	for side in [-1.45, -0.25]:
		var vine := PackedVector3Array()
		for k in range(10):
			vine.append(Vector3(gate_x + sin(k * 1.3) * 0.15, 2.05 + k * 0.14, side + cos(k * 1.3) * 0.15))
		var v := Sketch.tube(vine, 0.025, Sketch.ink(Color(0.3, 0.55, 0.22)), page)
		v.visible = false
		_vines.append(v)
	_goal = Node3D.new()
	page.add_child(_goal)
	_goal.position = level.goal + Vector3(0, 0.55, 0)
	var star_mesh := _star_mesh(0.28, 0.12, 0.08)
	var gold := Sketch.paper(Sketch.GOLD)
	gold.set_shader_parameter("glow", 0.35)
	Sketch.mesh_node(star_mesh, gold, _goal)
	_goal.scale = Vector3.ONE * 0.01
	# Dotted hint line over the gap — fades once the first bridge stands.
	var guide := PackedVector3Array()
	_guide_mat = Sketch.ink(Color(0.3, 0.3, 0.35, 0.5), true)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(8):
		var t0 := k / 8.0
		var t1 := t0 + 0.06
		var p0 := Vector3(lerpf(-1.75, 0.75, t0), 1.12 - sin(t0 * PI) * 0.12, 0.2)
		var p1 := Vector3(lerpf(-1.75, 0.75, t1), 1.12 - sin(t1 * PI) * 0.12, 0.2)
		guide = PackedVector3Array([p0, p1])
		Sketch._append_tube(im, guide, 0.025, 5)
	im.surface_end()
	_guide = Sketch.mesh_node(im, _guide_mat, page)
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guide.visible = false


func _make_flower(i: int) -> Node3D:
	var f := Node3D.new()
	var colors := [Color(0.95, 0.4, 0.4), Color(1.0, 0.75, 0.3), Color(0.75, 0.5, 0.95), Color(0.98, 0.6, 0.75)]
	Sketch.cylinder(0.012, 0.012, 0.2, Sketch.paper(Color(0.35, 0.6, 0.25)), f, 4).position.y = 0.1
	var petal_mat := Sketch.paper(colors[i % colors.size()])
	for k in range(5):
		var p := Sketch.sphere(0.04, petal_mat, f, 6, 4)
		p.position = Vector3(cos(k * TAU / 5.0) * 0.045, 0.22, sin(k * TAU / 5.0) * 0.045)
		p.scale.y = 0.5
	Sketch.sphere(0.03, Sketch.paper(Sketch.GOLD), f, 6, 4).position.y = 0.225
	return f


static func _star_mesh(outer: float, inner: float, depth: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rim: Array = []
	for i in range(10):
		var a := PI * 0.5 + TAU * i / 10.0
		var r := outer if i % 2 == 0 else inner
		rim.append(Vector3(cos(a) * r, sin(a) * r, 0))
	for face in [1.0, -1.0]:
		var c := Vector3(0, 0, depth * face)
		for i in range(10):
			var p0: Vector3 = rim[i]
			var p1: Vector3 = rim[(i + 1) % 10]
			if face > 0:
				st.add_vertex(c)
				st.add_vertex(p1)
				st.add_vertex(p0)
			else:
				st.add_vertex(c)
				st.add_vertex(p0)
				st.add_vertex(p1)
	st.generate_normals()
	return st.commit()


func _make_anchor_mark() -> MeshInstance3D:
	var pts := PackedVector3Array()
	for k in range(17):
		var a := TAU * k / 16.0
		pts.append(Vector3(cos(a) * 0.2, 0.02, sin(a) * 0.2))
	var mark := Sketch.tube(pts, 0.025, Sketch.ink(Color(0.35, 0.65, 0.3)), page)
	mark.visible = false
	return mark


# --- phases ----------------------------------------------------------------------

func _set_phase(p: int) -> void:
	phase = p
	_phase_time = 0.0
	match p:
		Phase.PLACING:
			_left_half.rotation.z = -PI
			page.position.x = -2.3 * SCALE
			for n in _popups:
				n.node.visible = false
			hero.visible = false
			ball.visible = false
		Phase.OPENING:
			cue("book_open", global_position)
		Phase.WON:
			_won_time = 0.0


func place_here() -> void:
	if phase != Phase.PLACING:
		return
	cue("pop", global_position)
	if placed and hero.visible:
		phase = Phase.PLAYING  # just moved the open book
		_phase_time = 0.0
		return
	placed = true
	_set_phase(Phase.OPENING)


func cue(name: String, at: Vector3, volume_db: float = 0.0) -> void:
	if audio:
		audio.play_cue(name, at, volume_db)


func _flat_forward() -> Vector3:
	var f := -head.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _follow_head(delta: float) -> void:
	var fwd := _flat_forward()
	var target := head.global_position + fwd * PLACE_DISTANCE
	target.y = table_height
	var t := minf(1.0, delta * 6.0)
	global_position = global_position.lerp(target, t) if placed or _phase_time > 0.05 else target
	var want := Basis.looking_at(fwd, Vector3.UP)
	global_basis = global_basis.slerp(want, t).orthonormalized()


func adjust_height(axis: float, delta: float) -> void:
	if phase == Phase.PLACING and absf(axis) > 0.2:
		table_height = clampf(table_height + axis * delta * 0.35, 0.2, 1.6)


# --- frame -----------------------------------------------------------------------

## Called every frame by the app with the move stick and the two triggers.
func tick(delta: float, stick: Vector2, triggers: Array) -> void:
	_phase_time += delta
	_step_cooldown = maxf(0.0, _step_cooldown - delta)
	match phase:
		Phase.PLACING:
			_follow_head(delta)
			adjust_height(stick.y, delta)
			if _phase_time > 0.6 and (triggers[0] > 0.8 or triggers[1] > 0.8):
				place_here()
		Phase.OPENING:
			_tick_opening()
		Phase.PLAYING, Phase.WON:
			_move = _stick_to_page(stick)
			_sim_accum = minf(_sim_accum + delta, 4.0 / SIM_HZ)
			while _sim_accum >= 1.0 / SIM_HZ:
				_sim_accum -= 1.0 / SIM_HZ
				_simulate(1.0 / SIM_HZ)
			if phase == Phase.PLAYING:
				_tick_drawing(triggers)
				_tick_hands(delta)
			_tick_world(delta)
	for i in range(pens.size()):
		pens[i].ink_fraction = level.ink / PageLevel.INK_MAX
	_tick_falling_strokes(delta)
	_apply_zone_life(delta)


func _tick_opening() -> void:
	var t := clampf(_phase_time / OPEN_TIME, 0.0, 1.0)
	_left_half.rotation.z = -PI * (1.0 - _ease_out_back(t, 0.6)) if t < 1.0 else 0.0
	page.position.x = -2.3 * SCALE * (1.0 - smoothstep(0.0, 1.0, t))
	var pt := _phase_time - OPEN_TIME
	for n in _popups:
		var node: Node3D = n.node
		var k := clampf((pt - n.delay * 0.6) / 0.45, 0.0, 1.0)
		node.visible = k > 0.0
		node.scale = Vector3(1, maxf(0.01, _ease_out_back(k, 1.6)), 1)
		if k > 0.0 and not node.has_meta("popped"):
			node.set_meta("popped", true)
			cue("paper_pop", node.global_position, -10.0)
	if pt > POP_TIME and not hero.visible:
		hero.visible = true
		ball.visible = true
		hero.position = level.spawn + Vector3(0, 3.0, 0)
		hero.grounded = false
		hero.velocity = Vector3.ZERO
		hero.set_face(PencilHero.Face.SURPRISED, 0.9)
		_guide.visible = true
	if hero.visible:
		_simulate_drop(1.0 / 60.0)
	if pt > POP_TIME + 1.2:
		for n in _popups:
			n.node.scale = Vector3.ONE
		_set_phase(Phase.PLAYING)


func _simulate_drop(dt: float) -> void:
	hero.simulate(dt, Vector2.ZERO, false)


static func _ease_out_back(t: float, s: float) -> float:
	var u := t - 1.0
	return 1.0 + u * u * ((s + 1.0) * u + s)


func _stick_to_page(stick: Vector2) -> Vector2:
	if stick.length() < 0.15:
		return Vector2.ZERO
	var fwd := _flat_forward()
	var right := fwd.cross(Vector3.UP)
	var world_dir := right * stick.x + fwd * stick.y
	var local := page.global_basis.inverse() * world_dir
	var flat := Vector2(local.x, local.z)
	if flat.length() < 0.0001:
		return Vector2.ZERO
	return flat.normalized() * clampf((stick.length() - 0.15) / 0.85, 0.0, 1.0)


func _simulate(dt: float) -> void:
	var jump := _jump_queued
	_jump_queued = false
	if phase == Phase.WON:
		hero.simulate(dt, Vector2.ZERO, false)
	else:
		hero.simulate(dt, _move, jump)
		_hero_pushes_ball()
	ball.simulate(dt)
	if phase != Phase.PLAYING:
		return
	if not gate_restored and not ball.is_respawning() and ball.grounded and level.on_plate(ball.position - Vector3(0, PaperBall.RADIUS, 0)):
		_restore_gate()
	if gate_restored and hero.grounded and level.at_goal(hero.position):
		_win()


func _hero_pushes_ball() -> void:
	if ball.locked or ball.is_respawning() or hero.is_respawning():
		return
	var to := ball.position - hero.position
	var flat := Vector2(to.x, to.z)
	var reach := PencilHero.RADIUS + PaperBall.RADIUS
	if flat.length() >= reach or to.y < -0.2 or to.y > PencilHero.HEIGHT:
		return
	var dir := flat.normalized() if flat.length() > 0.001 else Vector2(0, -1)
	var overlap := reach - flat.length()
	var hv := Vector2(hero.velocity.x, hero.velocity.z)
	var along := maxf(hv.dot(dir), 0.0)
	hero.position -= Vector3(dir.x, 0, dir.y) * overlap * 0.5
	var bv := Vector2(ball.velocity.x, ball.velocity.z)
	var speed := maxf(bv.dot(dir), along * 1.15 + 0.4)
	ball.push(Vector3(dir.x, 0, dir.y) * speed)
	if along > 0.5 and _step_cooldown <= 0.0:
		_step_cooldown = 0.25
		cue("crumple", ball.global_position, -10.0)


## The player's hands can nudge the ball directly — a flick sends it rolling.
func _tick_hands(delta: float) -> void:
	for i in range(hands.size()):
		var p := page.to_local(pens[i].tip_global())
		var prev := _hand_prev[i]
		_hand_prev[i] = p
		if prev == Vector3.INF or delta <= 0.0:
			continue
		var v := (p - prev) / delta
		var to := ball.position - p
		if to.length() < PaperBall.RADIUS + 0.3 and Vector2(v.x, v.z).length() > 0.8:
			var flat := Vector2(v.x, v.z)
			if flat.length() > 6.0:
				flat = flat.normalized() * 6.0
			ball.push(Vector3(flat.x, 0, flat.y))
			cue("crumple", ball.global_position, -6.0)


# --- drawing ---------------------------------------------------------------------

func _tick_drawing(triggers: Array) -> void:
	var any_drawing := false
	for i in range(mini(pens.size(), triggers.size())):
		var down: bool = triggers[i] > 0.6
		pens[i].drawing = down
		var tip := page.to_local(pens[i].tip_global())
		if down:
			any_drawing = true
			var pts: PackedVector3Array = _stroke_points[i]
			if pts.is_empty() or pts[pts.size() - 1].distance_to(tip) > SAMPLE_STEP:
				pts.append(tip)
				_stroke_points[i] = pts
				haptic.emit(i, 0.12, 0.02)
				Sketch.build_tube(_stroke_meshes[i], pts, 0.045, 5)
			_show_anchor(_anchor_marks[i], tip)
		elif _was_drawing[i]:
			_finish_stroke(i)
			_anchor_marks[i].visible = false
		else:
			_show_anchor(_anchor_marks[i], tip, true)
		_was_drawing[i] = down
	if _scribble:
		if any_drawing and not _scribble.playing:
			_scribble.play()
		elif not any_drawing and _scribble.playing:
			_scribble.stop()


func _show_anchor(mark: MeshInstance3D, tip: Vector3, hover_only: bool = false) -> void:
	var s := level.support(tip)
	mark.visible = s != Vector3.INF and (not hover_only or tip.distance_to(s) < 0.9)
	if mark.visible:
		mark.position = s
		mark.scale = Vector3.ONE * (1.0 + sin(_phase_time * 8.0) * 0.12)


## Turns stroke `i` into a bridge if it rests on two surfaces; otherwise the
## graphite crumbles and falls.
func _finish_stroke(i: int) -> Dictionary:
	var pts: PackedVector3Array = _stroke_points[i]
	_stroke_points[i] = PackedVector3Array()
	var result := {"ok": false, "reason": "short"}
	if pts.size() >= 2:
		result = try_bridge(pts[0], pts[pts.size() - 1])
		haptic.emit(i, 0.6 if result.ok else 0.3, 0.12 if result.ok else 0.2)
	if not result.ok and pts.size() >= 2:
		_falling_strokes.append({"points": pts.duplicate(), "mesh": _detach_stroke(i), "life": 0.0, "vel": 0.0})
		cue("erase", page.to_global(pts[pts.size() / 2]), -4.0)
	_stroke_meshes[i].clear_surfaces()
	return result


func _detach_stroke(i: int) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var node := Sketch.mesh_node(im, Sketch.ink(Color(0.24, 0.25, 0.28, 1.0), true), page)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _tick_falling_strokes(delta: float) -> void:
	for k in range(_falling_strokes.size() - 1, -1, -1):
		var f: Dictionary = _falling_strokes[k]
		f.life += delta
		f.vel += 12.0 * delta
		var pts: PackedVector3Array = f.points
		for j in range(pts.size()):
			pts[j] += Vector3(sin(j * 3.1) * 0.4 * delta, -f.vel * delta * (0.6 + 0.4 * sin(j * 1.7)), 0)
		f.points = pts
		var node: MeshInstance3D = f.mesh
		Sketch.build_tube(node.mesh as ImmediateMesh, pts, 0.045 * (1.0 - f.life * 1.4), 5)
		(node.material_override as ShaderMaterial).set_shader_parameter("alpha_scale", clampf(1.0 - f.life * 1.6, 0.0, 1.0))
		if f.life > 0.65:
			node.queue_free()
			_falling_strokes.remove_at(k)


## Public so tests and the preview can draw without hands.
func try_bridge(a: Vector3, b: Vector3) -> Dictionary:
	var r := level.validate_stroke(a, b)
	if not r.ok:
		strokes_failed += 1
		return r
	var beam := level.add_beam(r.a, r.b)
	var view := BridgeView.new()
	page.add_child(view)
	view.build(beam, _rng)
	bridges.append(view)
	cue("plank", page.to_global((r.a + r.b) * 0.5))
	_confetti.burst((r.a + r.b) * 0.5, 10, [Sketch.WOOD, Sketch.PAPER], 1.2, 1.5)
	if _guide.visible:
		_guide.visible = false
	if zone_target[0] < 0.35:
		zone_target[0] = 0.35
	return r


func erase_last() -> void:
	if bridges.is_empty():
		return
	var view: BridgeView = bridges.pop_back()
	level.remove_last_beam()
	view.remove()
	cue("erase", page.to_global((view.beam.a + view.beam.b) * 0.5))


# --- progress --------------------------------------------------------------------

func _restore_gate() -> void:
	gate_restored = true
	level.open_gate()
	ball.locked = true
	ball.position = Vector3(level.plate.x, level.plate.y + PaperBall.RADIUS + 0.06, level.plate.z)
	cue("plate", page.to_global(level.plate))
	cue("gate", page.to_global(Vector3(3.2, 2.6, -0.85)), 2.0)
	zone_target[0] = maxf(zone_target[0], 0.5)
	zone_target[1] = 1.0
	_confetti.burst(level.plate + Vector3(0, 0.2, 0), 26, [Sketch.GOLD, Sketch.GRASS, Sketch.PINK], 2.5, 3.0)
	_plate_mat.set_shader_parameter("glow", 0.5)
	hero.set_face(PencilHero.Face.HAPPY, 1.5)


func _win() -> void:
	_set_phase(Phase.WON)
	hero.celebrating = true
	for z in [0, 1, 2]:
		zone_target[z] = 1.0
	cue("win", page.to_global(level.goal))
	_confetti.burst(level.goal + Vector3(0, 0.6, 0), 60, [Sketch.GOLD, Sketch.GRASS, Sketch.PINK, Color(0.5, 0.7, 1.0)], 3.5, 4.5)
	audio.play_music("bright")
	won.emit()


func _tick_world(delta: float) -> void:
	var t := _phase_time
	# Gate pieces fly back together, rubble melts away, vines grow.
	for p in _gate_pieces:
		var node: Node3D = p.node
		var target: Transform3D = p.fixed if gate_restored else p.broken
		node.transform = node.transform.interpolate_with(target, minf(1.0, delta * 3.0))
	for r in _rubble:
		r.scale = r.scale.lerp(Vector3.ONE * (0.01 if gate_restored else 1.0), minf(1.0, delta * 4.0))
	for v in _vines:
		v.visible = gate_restored
	# Plate sinks under the ball.
	_plate_top.position.y = lerpf(_plate_top.position.y, 0.02 if gate_restored else 0.06, minf(1.0, delta * 8.0))
	if not gate_restored:
		_plate_mat.set_shader_parameter("glow", 0.12 + 0.12 * sin(t * 3.0))
	# Goal star appears once the gate is open.
	var goal_scale := 1.0 if gate_restored else 0.01
	_goal.scale = _goal.scale.lerp(Vector3.ONE * goal_scale, minf(1.0, delta * 3.0))
	_goal.rotation.y += delta * 1.6
	_goal.position.y = level.goal.y + 0.55 + sin(t * 2.2) * 0.07
	# Flowers bloom in restored zones; leaves fill the tree at the end.
	for f in _flowers:
		var z: int = f.get_meta("zone")
		var on: bool = zone_life[z] > 0.6
		f.scale = f.scale.lerp(Vector3.ONE * (1.0 if on else 0.01), minf(1.0, delta * 4.0))
	for i in range(_tree_leaves.size()):
		var grow := phase == Phase.WON and _won_time > i * 0.15
		_tree_leaves[i].scale = _tree_leaves[i].scale.lerp(Vector3.ONE * (1.0 if grow else 0.01), minf(1.0, delta * 5.0))
	if _guide.visible:
		_guide_mat.set_shader_parameter("alpha_scale", 0.35 + 0.35 * sin(t * 3.0))
	if phase == Phase.WON:
		_won_time += delta
		if _won_time > 2.5 and _replay == null:
			_replay = _make_replay_icon()
		if _replay:
			_replay.rotation.y += delta * 0.8


func _make_replay_icon() -> Node3D:
	var root := Node3D.new()
	page.add_child(root)
	root.position = Vector3(0, 3.6, 0)
	var arc := PackedVector3Array()
	for i in range(22):
		var a := deg_to_rad(40.0 + i * 14.0)
		arc.append(Vector3(cos(a) * 0.6, sin(a) * 0.6, 0))
	var mat := Sketch.ink(Sketch.GOLD.darkened(0.2))
	Sketch.tube(arc, 0.07, mat, root)
	Sketch.tube(PackedVector3Array([Vector3(0.25, 0.1, 0), Vector3(0.48, 0.42, 0), Vector3(0.8, 0.12, 0)]), 0.07, mat, root)
	cue("pop", root.global_position)
	return root


func _apply_zone_life(delta: float = 1.0) -> void:
	for z in zone_life.keys():
		zone_life[z] = move_toward(zone_life[z], zone_target[z], delta * 0.8)
		if zones.has(z):
			for m in zones[z]:
				(m as ShaderMaterial).set_shader_parameter("life", zone_life[z])


# --- buttons ---------------------------------------------------------------------

func on_button(action: StringName, _hand: int) -> void:
	match action:
		&"ax_button":
			match phase:
				Phase.PLACING:
					place_here()
				Phase.PLAYING:
					_jump_queued = true
				Phase.WON:
					if _won_time > 2.5:
						restart()
		&"by_button":
			if phase == Phase.PLAYING:
				erase_last()
		&"trigger_click":
			if phase == Phase.PLACING:
				place_here()
		&"thumbstick_click":
			if phase == Phase.PLAYING:
				# Pick the book up and set it down somewhere else.
				phase = Phase.PLACING
				_phase_time = 0.0


func restart() -> void:
	new_game()
	audio.play_music("calm")
	_left_half.rotation.z = 0.0
	_phase_time = OPEN_TIME
	for n in _popups:
		n.node.visible = false
	phase = Phase.OPENING
	cue("book_open", global_position)
