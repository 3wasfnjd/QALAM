class_name BookWorld
extends Node3D
## "The last page" — the flow and rules of stage one. Visuals live in
## StageView / PencilRig / PathView; rules in PageLevel; this file connects
## input, story beats and puzzles.
##
##  PLACING  the closed book follows your gaze; stick ↑↓ = table height;
##           trigger or A/X sets it down
##  INTRO    book shakes, opens, paper dust, world pops up, the tired pencil
##           steps out of the page, looks around, sees a light, walks to the
##           gap, looks at you and points across (A skips)
##  PLAYING  stick walks (push far = run once he has hope), A/X jumps,
##           trigger draws a path, grip + point erases one, B/Y erases last
##  ENDING   the green orb: colour floods out, life returns, the next page
##           flips, "الصفحة الثانية"; A plays the page again

signal haptic(hand: int, amplitude: float, seconds: float)
signal finished

enum Phase { PLACING, INTRO, PLAYING, ENDING }

const SCALE := 0.09
const DEFAULT_TABLE := 0.76
const PLACE_DISTANCE := 0.6
const SIM_HZ := 90.0
const SAMPLE_STEP := 0.06
const ERASE_TIME := 0.45
const BALL_REST_RESET := 2.5
const INTRO_POP_AT := 3.3
const INTRO_EMERGE_AT := 4.9

var phase: int = Phase.PLACING
var head: Node3D
var hands: Array[Node3D] = []
var pens: Array[DrawingPen] = []
var audio: GameAudio
var level: PageLevel
var view: StageView
var hero: PencilBody
var ball: PaperBall
var page: Node3D
var table_height: float = DEFAULT_TABLE
var placed: bool = false
var paths: Dictionary = {}          # id -> PathView
var zones: Dictionary = {}

# Story progress.
var crossed_gap: bool = false
var light_taken: bool = false
var erase_taught: bool = false
var erased_once: bool = false
var ball_caught: bool = false
var gate_t: float = 0.0
var ending_time: float = -1.0
var strokes_failed: int = 0

var _rng := RandomNumberGenerator.new()
var _phase_time: float = 0.0
var _sim_accum: float = 0.0
var _jump_queued: bool = false
var _move := Vector2.ZERO
var _run: bool = false
var _confetti: Confetti
var _strokes: Array = [PackedVector3Array(), PackedVector3Array()]
var _stroke_ink: Array[float] = [0.0, 0.0]
var _stroke_meshes: Array[ImmediateMesh] = []
var _stroke_nodes: Array[MeshInstance3D] = []
var _anchor_marks: Array[MeshInstance3D] = []
var _was_drawing: Array[bool] = [false, false]
var _dry_cued: Array[bool] = [false, false]
var _erase_target: Array[String] = ["", ""]
var _erase_progress: Array[float] = [0.0, 0.0]
var _falling: Array = []
var _hand_prev: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _ball_rest: float = 0.0
var _drop: Node3D
var _drop_t: float = -1.0
var _scribble: AudioStreamPlayer3D
var _rub: AudioStreamPlayer3D
var _intro_beats_queued: bool = false
var _wave_radius: float = 0.0
var _hint_idle: float = 0.0
var _ball_on_switch: bool = false


func build(camera: Node3D, aim_hands: Array[Node3D]) -> void:
	head = camera
	hands = aim_hands
	_rng.seed = 2026
	audio = GameAudio.new()
	add_child(audio)
	for h in hands:
		var pen := DrawingPen.new()
		h.add_child(pen)
		pens.append(pen)
	page = Node3D.new()
	page.scale = Vector3.ONE * SCALE
	add_child(page)
	_scribble = audio.attach_loop("scribble", self, -14.0)
	_rub = audio.attach_loop("rub", self, -12.0)
	new_game()
	_set_phase(Phase.PLACING)
	audio.play_music("calm")


func new_game() -> void:
	for child in page.get_children():
		child.queue_free()
	paths.clear()
	zones.clear()
	_stroke_meshes.clear()
	_stroke_nodes.clear()
	_anchor_marks.clear()
	_falling.clear()
	level = PageLevel.stage_one()
	view = StageView.new()
	page.add_child(view)
	view.build(level, zones)
	_confetti = Confetti.new()
	page.add_child(_confetti)
	for i in range(2):
		var im := ImmediateMesh.new()
		_stroke_meshes.append(im)
		var node := Sketch.mesh_node(im, Sketch.ink(Sketch.GRAPHITE), page)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stroke_nodes.append(node)
		_anchor_marks.append(_make_anchor_mark())
		_strokes[i] = PackedVector3Array()
		_stroke_ink[i] = 0.0
	hero = PencilBody.new()
	page.add_child(hero)
	hero.setup(level, level.spawn)
	hero.make_shadow(page)
	hero.player_head = head
	hero.visible = false
	hero.jumped.connect(func(): cue("jump", hero.global_position, -6.0))
	hero.landed.connect(func(impact: float): cue("land", hero.global_position, -12.0 + impact * 8.0))
	hero.fell.connect(func(at: Vector3):
		cue("poof", at)
		_confetti.burst(hero.position + Vector3(0, 0.3, 0), 22, [Color(0.1, 0.1, 0.12), Sketch.GRAPHITE], 1.6, 2.0))
	hero.redrawn.connect(func(): cue("scribble_in", hero.global_position, -4.0))
	hero.stepped.connect(func(): cue("step", hero.global_position, -16.0))
	ball = PaperBall.new()
	page.add_child(ball)
	ball.setup(level, level.ball_start, page)
	ball.visible = false
	ball.fell.connect(func():
		cue("poof", ball.global_position, -4.0)
		_confetti.burst(ball.position, 14, [OLD_PAPER_COLOR, Sketch.PAPER_DARK], 1.5, 2.0))
	ball.bumped.connect(func(s: float): cue("bump", ball.global_position, -12.0 + minf(s, 5.0)))
	crossed_gap = false
	light_taken = false
	erase_taught = false
	erased_once = false
	ball_caught = false
	gate_t = 0.0
	ending_time = -1.0
	strokes_failed = 0
	_intro_beats_queued = false
	_wave_radius = 0.0
	_drop_t = -1.0
	Sketch.set_wave(Vector3(0, -100, 0), 0.0)
	_apply_zone_life(0.0)


const OLD_PAPER_COLOR := Color(0.92, 0.87, 0.74)


func _make_anchor_mark() -> MeshInstance3D:
	var pts := PackedVector3Array()
	for k in range(17):
		var a := TAU * k / 16.0
		pts.append(Vector3(cos(a) * 0.2, 0.02, sin(a) * 0.2))
	var mark := Sketch.tube(pts, 0.025, Sketch.ink(Color(0.35, 0.62, 0.3)), page)
	mark.visible = false
	return mark


func cue(name: String, at: Vector3, volume_db: float = 0.0) -> void:
	if audio:
		audio.play_cue(name, at, volume_db)


# --- phases --------------------------------------------------------------------------------

func _set_phase(p: int) -> void:
	phase = p
	_phase_time = 0.0
	match p:
		Phase.PLACING:
			view.set_closed(1.0)
			view.pop_progress(-10.0)
			hero.visible = false
			ball.visible = false
		Phase.INTRO:
			cue("rumble", global_position, -2.0)


func place_here() -> void:
	if phase != Phase.PLACING:
		return
	cue("pop", global_position, -6.0)
	if placed and hero.visible:
		phase = Phase.PLAYING  # the open book was only moved
		_phase_time = 0.0
		return
	placed = true
	_set_phase(Phase.INTRO)


func _flat_forward() -> Vector3:
	var f := -head.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _follow_head(delta: float) -> void:
	var fwd := _flat_forward()
	var target := head.global_position + fwd * PLACE_DISTANCE
	target.y = table_height
	var t := minf(1.0, delta * 6.0)
	global_position = global_position.lerp(target, t) if (placed or _phase_time > 0.05) else target
	global_basis = global_basis.slerp(Basis.looking_at(fwd, Vector3.UP), t).orthonormalized()


# --- frame -----------------------------------------------------------------------------------

## Called every frame with the move stick and both triggers and grips.
func tick(delta: float, stick: Vector2, triggers: Array, grips: Array = [0.0, 0.0]) -> void:
	_phase_time += delta
	match phase:
		Phase.PLACING:
			_follow_head(delta)
			if absf(stick.y) > 0.2:
				table_height = clampf(table_height + stick.y * delta * 0.35, 0.2, 1.6)
			if _phase_time > 0.6 and (triggers[0] > 0.8 or triggers[1] > 0.8):
				place_here()
		Phase.INTRO:
			_tick_intro(delta)
			_step_sim(delta, Vector2.ZERO, false)
		Phase.PLAYING:
			_move = _stick_to_page(stick)
			_run = stick.length() > 0.9
			_step_sim(delta, _move, _run)
			_tick_drawing(triggers)
			_tick_erasing(delta, grips)
			_tick_hands(delta)
			_tick_story(delta)
		Phase.ENDING:
			_step_sim(delta, Vector2.ZERO, false)
			_tick_ending(delta)
	for pen in pens:
		pen.ink_fraction = level.ink / PageLevel.INK_MAX
	_tick_drop(delta)
	_tick_falling_strokes(delta)
	if gate_t > 0.0 and gate_t < 1.0:
		gate_t = minf(1.0, gate_t + delta * 0.45)
		view.set_gate_open(gate_t)
	_apply_zone_life(delta)


func _step_sim(delta: float, move: Vector2, run: bool) -> void:
	_sim_accum = minf(_sim_accum + delta, 4.0 / SIM_HZ)
	while _sim_accum >= 1.0 / SIM_HZ:
		_sim_accum -= 1.0 / SIM_HZ
		var jump := _jump_queued
		_jump_queued = false
		var dt := 1.0 / SIM_HZ
		var emerging := phase == Phase.INTRO and not _intro_beats_queued
		if hero.visible and not emerging:
			hero.simulate(dt, move, run, jump)
			_hero_pushes_ball()
		if ball.visible:
			ball.simulate(dt)
			_ball_rules(dt)


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
	return flat.normalized() * clampf((stick.length() - 0.15) / 0.75, 0.0, 1.0)


# --- intro ------------------------------------------------------------------------------------

func _tick_intro(_delta: float) -> void:
	var t := _phase_time
	view.shake(clampf(1.0 - absf(t - 0.7) / 0.7, 0.0, 1.0) if t < 1.4 else 0.0)
	var open := clampf((t - 1.3) / 2.0, 0.0, 1.0)
	view.set_closed(1.0 - smoothstep(0.0, 1.0, open))
	if t > 1.3 and t - _delta <= 1.3:
		cue("book_open", global_position)
	if t > 2.4 and t - _delta <= 2.4:
		# Dust of paper and graphite puffs out as it opens.
		_confetti.burst(Vector3(0, 0.6, 0), 60, [Color(0.75, 0.72, 0.66), Color(0.5, 0.5, 0.52), OLD_PAPER_COLOR], 2.2, 2.5)
		cue("dust", global_position, -4.0)
	view.pop_progress((t - INTRO_POP_AT) * 1.4)
	if t > INTRO_POP_AT and int((t - INTRO_POP_AT) * 8.0) != int((t - _delta - INTRO_POP_AT) * 8.0) and t < INTRO_POP_AT + 1.5:
		cue("paper_pop", global_position, -12.0)
	if t >= INTRO_EMERGE_AT and not hero.visible:
		hero.visible = true
		hero.reset_to(level.spawn - Vector3(0, 1.0, 0))
		hero.tired = true
		cue("emerge", page.to_global(level.spawn), -2.0)
	if hero.visible and not _intro_beats_queued:
		# Rising out of the paper.
		var e := clampf((t - INTRO_EMERGE_AT) / 1.0, 0.0, 1.0)
		hero.position = level.spawn - Vector3(0, 1.0 - smoothstep(0.0, 1.0, e), 0)
		hero.velocity = Vector3.ZERO
		if e > 0.0 and int(e * 10.0) % 3 == 0:
			_confetti.burst(level.spawn + Vector3(0, 0.05, 0), 2, [OLD_PAPER_COLOR, Color(0.6, 0.6, 0.6)], 0.8, 1.0)
		if e >= 1.0:
			hero.reset_to(level.spawn)
			ball.visible = true
			_queue_intro_beats()
	if _intro_beats_queued and not hero.scripted():
		_start_playing()


func _queue_intro_beats() -> void:
	_intro_beats_queued = true
	var light_g := page.to_global(level.light + Vector3(0, 0.35, 0))
	var tree_g := page.to_global(level.dead_tree + Vector3(0, 1.0, 0))
	var below_g := page.to_global(Vector3(level.gap_edge.x + 0.8, 0.0, level.gap_edge.z))
	var across_g := page.to_global(Vector3(-1.6, 1.0, level.gap_edge.z))
	hero.queue([
		{"do": "wait", "t": 1.0, "anim": &"tired_idle"},
		{"do": "anim", "anim": &"look_around", "t": 2.2},
		{"do": "face", "face": PencilRig.Face.SAD, "hold": 1.6},
		{"do": "look", "at": tree_g, "t": 1.4},
		{"do": "face", "face": PencilRig.Face.SURPRISED, "hold": 0.8},
		{"do": "look", "at": light_g, "t": 0.8},
		{"do": "face", "face": PencilRig.Face.HOPEFUL, "hold": 2.0},
		{"do": "point", "at": light_g, "t": 1.4},
		{"do": "walk_to", "to": level.gap_edge, "speed": 0.8, "look": light_g},
		{"do": "anim", "anim": &"careful_step", "t": 0.5, "look": below_g},
		{"do": "anim", "anim": &"lose_balance", "t": 0.6, "look": below_g},
		{"do": "walk_to", "to": level.gap_edge - Vector3(0.35, 0, 0), "speed": 0.5, "look": below_g},
		{"do": "turn", "to": head, "t": 0.5},
		{"do": "look", "at": head, "t": 0.9},
		{"do": "point", "at": across_g, "t": 1.6, "look": head},
		{"do": "call", "fn": func(): hero.look_target = head},
	])


func skip_intro() -> void:
	if phase != Phase.INTRO:
		return
	view.shake(0.0)
	view.set_closed(0.0)
	view.pop_progress(100.0)
	hero.visible = true
	hero.clear_script()
	hero.reset_to(level.gap_edge - Vector3(0.35, 0, 0))
	hero.tired = true
	ball.visible = true
	_intro_beats_queued = true
	_start_playing()


func _start_playing() -> void:
	phase = Phase.PLAYING
	_phase_time = 0.0
	for pen in pens:
		pen.hint = DrawingPen.Hint.DRAW


# --- drawing ------------------------------------------------------------------------------------

func _tick_drawing(triggers: Array) -> void:
	var any := false
	for i in range(mini(pens.size(), triggers.size())):
		var down: bool = triggers[i] > 0.6
		pens[i].drawing = down
		var tip := page.to_local(pens[i].tip_global())
		if down and _erase_target[i] == "":
			any = true
			_draw_point(i, tip)
			_show_anchor(_anchor_marks[i], tip)
		elif _was_drawing[i]:
			finish_stroke(i)
			_anchor_marks[i].visible = false
		else:
			_show_anchor(_anchor_marks[i], tip, true)
		_was_drawing[i] = down and _erase_target[i] == ""
	if _scribble:
		if any and not _scribble.playing:
			_scribble.play()
		elif not any and _scribble.playing:
			_scribble.stop()


## Adds a sample to stroke `i`, spending graphite as the line grows.
func _draw_point(i: int, tip: Vector3) -> void:
	var pts: PackedVector3Array = _strokes[i]
	if pts.is_empty():
		pts.append(tip)
		_strokes[i] = pts
		_dry_cued[i] = false
		return
	var last := pts[pts.size() - 1]
	var d := last.distance_to(tip)
	if d < SAMPLE_STEP:
		return
	var used := level.spend_ink(d)
	if used <= 0.0001:
		if not _dry_cued[i]:
			_dry_cued[i] = true
			cue("dry", pens[i].tip_global(), -4.0)
			haptic.emit(i, 0.5, 0.15)
		return
	pts.append(last.move_toward(tip, used))
	_strokes[i] = pts
	_stroke_ink[i] += used
	Sketch.build_tube(_stroke_meshes[i], pts, 0.05, 5)
	haptic.emit(i, 0.1, 0.02)
	if _rng.randf() < 0.5:
		_confetti.burst(pts[pts.size() - 1], 1, [Color(0.15, 0.15, 0.17), Sketch.GRAPHITE], 0.4, 0.3)


func _show_anchor(mark: MeshInstance3D, tip: Vector3, hover_only: bool = false) -> void:
	var s := level.support(tip)
	mark.visible = s != Vector3.INF and (not hover_only or tip.distance_to(s) < 1.0)
	if mark.visible:
		mark.position = s
		mark.scale = Vector3.ONE * (1.0 + sin(_phase_time * 8.0) * 0.12)


## Releasing the trigger: the line becomes a walkable path, or crumbles.
func finish_stroke(i: int) -> Dictionary:
	var pts: PackedVector3Array = _strokes[i]
	var spent: float = _stroke_ink[i]
	_strokes[i] = PackedVector3Array()
	_stroke_ink[i] = 0.0
	_stroke_meshes[i].clear_surfaces()
	level.refund_ink(spent)
	var result := commit_path(pts)
	haptic.emit(i, 0.6 if result.ok else 0.3, 0.12 if result.ok else 0.2)
	return result


## Turns raw points into a path (public for tests and the preview). Spends ink.
func commit_path(raw: PackedVector3Array) -> Dictionary:
	if raw.size() < 2 or PageLevel.polyline_length(raw) < PageLevel.MIN_PATH:
		strokes_failed += 1
		if raw.size() >= 2:
			_crumble(raw)
		return {"ok": false, "reason": "short"}
	var pts := level.clean_path(raw)
	var length := PageLevel.polyline_length(pts)
	if length > level.ink + 0.001:
		# Not enough graphite for the cleaned line: keep what fits.
		var keep := PackedVector3Array([pts[0]])
		var left := level.ink
		for k in range(1, pts.size()):
			var seg := pts[k - 1].distance_to(pts[k])
			if seg > left:
				keep.append(pts[k - 1].move_toward(pts[k], left))
				break
			left -= seg
			keep.append(pts[k])
		pts = keep
		length = PageLevel.polyline_length(pts)
		if length < PageLevel.MIN_PATH:
			strokes_failed += 1
			_crumble(raw)
			return {"ok": false, "reason": "ink"}
	level.spend_ink(length)
	var path := level.add_path(pts)
	var pv := PathView.new()
	page.add_child(pv)
	pv.build(path.id, pts, _rng)
	paths[path.id] = pv
	cue("pencil_line", page.to_global(pts[pts.size() / 2]), -2.0)
	for k in range(0, pts.size(), 2):
		_confetti.burst(pts[k], 1, [Sketch.GRAPHITE, Color(0.2, 0.2, 0.22)], 0.6, 0.6)
	for pen in pens:
		if pen.hint == DrawingPen.Hint.DRAW:
			pen.hint = DrawingPen.Hint.NONE
	_on_path_created(path)
	return {"ok": true, "id": path.id, "length": length, "points": pts}


func _crumble(raw: PackedVector3Array) -> void:
	var im := ImmediateMesh.new()
	var node := Sketch.mesh_node(im, Sketch.ink(Color(0.24, 0.25, 0.28, 1.0), true), page)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_falling.append({"points": raw.duplicate(), "node": node, "life": 0.0, "vel": 0.0})
	cue("crumble", page.to_global(raw[raw.size() / 2]), -4.0)


func _tick_falling_strokes(delta: float) -> void:
	for k in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[k]
		f.life += delta
		f.vel += 12.0 * delta
		var pts: PackedVector3Array = f.points
		for j in range(pts.size()):
			pts[j] += Vector3(sin(j * 3.1) * 0.4 * delta, -f.vel * delta * (0.6 + 0.4 * sin(j * 1.7)), 0)
		f.points = pts
		var node: MeshInstance3D = f.node
		Sketch.build_tube(node.mesh as ImmediateMesh, pts, 0.05 * maxf(0.05, 1.0 - f.life * 1.4), 5)
		(node.material_override as ShaderMaterial).set_shader_parameter("alpha_scale", clampf(1.0 - f.life * 1.6, 0.0, 1.0))
		if f.life > 0.65:
			node.queue_free()
			_falling.remove_at(k)


# --- erasing ----------------------------------------------------------------------------------------

func _tick_erasing(delta: float, grips: Array) -> void:
	var rubbing := false
	for pv in paths.values():
		(pv as PathView).targeted = false
	for i in range(mini(pens.size(), grips.size())):
		var held: bool = grips[i] > 0.6
		pens[i].erasing = held
		if not held:
			_erase_target[i] = ""
			_erase_progress[i] = 0.0
			continue
		var origin := page.to_local(pens[i].tip_global())
		var dir := (page.global_basis.inverse() * pens[i].forward_global()).normalized()
		var hit := level.path_near_ray(origin, dir, 0.7)
		var id: String = hit.get("id", "")
		if id != _erase_target[i]:
			_erase_target[i] = id
			_erase_progress[i] = 0.0
		if id == "" or not paths.has(id):
			continue
		var pv: PathView = paths[id]
		pv.targeted = true
		rubbing = true
		_erase_progress[i] += delta / ERASE_TIME
		pv.erase_amount = clampf(_erase_progress[i], 0.0, 1.0)
		if _rng.randf() < 0.6:
			var spot := pv.points[_rng.randi() % pv.points.size()]
			_confetti.burst(spot + Vector3(0, 0.05, 0), 1, [Color(0.98, 0.75, 0.78), Color(0.95, 0.93, 0.9), Sketch.GRAPHITE], 0.8, 0.8)
		haptic.emit(i, 0.15, 0.03)
		if _erase_progress[i] >= 1.0:
			erase_path(id)
			_erase_target[i] = ""
			_erase_progress[i] = 0.0
			haptic.emit(i, 0.5, 0.12)
	if _rub:
		if rubbing and not _rub.playing:
			_rub.play()
		elif not rubbing and _rub.playing:
			_rub.stop()


## Rubs a path out and gives its graphite back.
func erase_path(id: String) -> void:
	if not paths.has(id):
		return
	var pv: PathView = paths[id]
	paths.erase(id)
	level.remove_path(id)
	for k in range(pv.points.size()):
		_confetti.burst(pv.points[k] + Vector3(0, 0.05, 0), 3, [Color(0.98, 0.75, 0.78), Color(0.97, 0.95, 0.9), Sketch.GRAPHITE], 1.2, 1.4)
	pv.remove()
	cue("erase", page.to_global(pv.points[pv.points.size() / 2]))
	erased_once = true
	for pen in pens:
		if pen.hint == DrawingPen.Hint.ERASE:
			pen.hint = DrawingPen.Hint.NONE


func erase_last() -> void:
	if level.paths.is_empty():
		return
	erase_path(level.paths[level.paths.size() - 1].id)


# --- ball, hands, story -------------------------------------------------------------------------------

func _hero_pushes_ball() -> void:
	hero.pushing = false
	if ball.locked or ball.is_respawning() or hero.is_respawning():
		return
	var to := ball.position - hero.position
	var flat := Vector2(to.x, to.z)
	var reach := PencilBody.RADIUS + PaperBall.RADIUS
	if flat.length() >= reach or to.y < -0.2 or to.y > PencilBody.HEIGHT:
		return
	var dir := flat.normalized() if flat.length() > 0.001 else Vector2(0, -1)
	var overlap := reach - flat.length()
	var hv := Vector2(hero.velocity.x, hero.velocity.z)
	var along := maxf(hv.dot(dir), 0.0)
	hero.position -= Vector3(dir.x, 0, dir.y) * overlap * 0.5
	ball.push(Vector3(dir.x, 0, dir.y) * maxf(Vector2(ball.velocity.x, ball.velocity.z).dot(dir), along * 1.1 + 0.3))
	hero.pushing = along > 0.3


## The ball starts down a freshly drawn path that passes under it; it is
## caught by the switch only if it arrives gently; a ball that stops anywhere
## useless goes back to its tower.
func _ball_rules(dt: float) -> void:
	if ball.locked or ball.is_respawning():
		return
	var b := ball.base()
	var at_start := b.distance_to(level.ball_start) < 0.25
	if at_start and ball.speed() < 0.1:
		for path in level.paths:
			var pts: PackedVector3Array = path.points
			for k in range(pts.size()):
				if Vector2(pts[k].x - b.x, pts[k].z - b.z).length() < 0.5 and absf(pts[k].y - b.y) < 0.35:
					var nxt := pts[mini(k + 1, pts.size() - 1)]
					var prv := pts[maxi(k - 1, 0)]
					var dir := (nxt - prv)
					# Roll the way the path goes down.
					if nxt.y > prv.y:
						dir = -dir
					dir.y = 0.0
					if dir.length() > 0.001:
						ball.push(dir.normalized() * 1.5)
						cue("crumple", ball.global_position, -6.0)
						hero.look_target = ball
					return
	# The switch only keeps a ball that arrives gently; a fast one rolls over.
	var on_switch := ball.grounded and level.on_switch(b)
	if on_switch and not _ball_on_switch:
		_ball_on_switch = true
		if ball.speed() < PageLevel.SWITCH_CATCH_SPEED:
			_catch_ball()
			return
		cue("click", page.to_global(level.switch_pos), -8.0)
	elif not on_switch:
		_ball_on_switch = false
	# Stuck somewhere useless → back to the tower.
	if ball.grounded and ball.speed() < 0.05 and not at_start:
		_ball_rest += dt
		if _ball_rest > BALL_REST_RESET:
			_ball_rest = 0.0
			ball.position = ball.position  # stays visible while poofing
			ball.velocity = Vector3.ZERO
			ball._respawn = 0.0
			cue("poof", ball.global_position, -6.0)
			_confetti.burst(ball.position, 12, [OLD_PAPER_COLOR, Sketch.PAPER_DARK], 1.2, 1.5)
	else:
		_ball_rest = 0.0


func _catch_ball() -> void:
	ball_caught = true
	level.switch_pressed = true
	ball.locked = true
	ball.position = level.switch_pos + Vector3(0, PaperBall.RADIUS + 0.04, 0)
	view.set_switch_pressed(true)
	cue("click", page.to_global(level.switch_pos), 2.0)
	cue("gate", page.to_global(level.gate + Vector3(0, 1.0, 0)), 2.0)
	_confetti.burst(level.switch_pos + Vector3(0, 0.2, 0), 18, [Sketch.GOLD, OLD_PAPER_COLOR], 1.8, 2.2)
	level.open_gate()
	gate_t = 0.01
	for k in range(14):
		_confetti.burst(level.gate + Vector3(0, 2.6, _rng.randf_range(-0.9, 0.9)), 2, [Color(0.75, 0.72, 0.66), Color(0.6, 0.58, 0.55)], 0.3, 0.2)
	zone_life_target[2] = 0.35
	hero.face(PencilRig.Face.HAPPY, 2.0)
	hero.look_target = page.to_global(level.gate + Vector3(0, 1.0, 0))


## The player's hands can flick the ball directly.
func _tick_hands(delta: float) -> void:
	for i in range(hands.size()):
		var p := page.to_local(pens[i].tip_global())
		var prev := _hand_prev[i]
		_hand_prev[i] = p
		if prev == Vector3.INF or delta <= 0.0 or ball.locked:
			continue
		var v := (p - prev) / delta
		if (ball.position - p).length() < PaperBall.RADIUS + 0.3 and Vector2(v.x, v.z).length() > 0.8:
			var flat := Vector2(v.x, v.z).limit_length(5.0)
			ball.push(Vector3(flat.x, 0, flat.y))
			cue("crumple", ball.global_position, -6.0)


func _on_path_created(path: Dictionary) -> void:
	# First line over the gap: he looks at it and tries it, carefully.
	if not crossed_gap and hero.position.x < level.block("P1").max.x + 0.1 and not hero.scripted():
		var pts: PackedVector3Array = path.points
		var first := pts[0] if pts[0].x < pts[pts.size() - 1].x else pts[pts.size() - 1]
		if absf(first.y - 1.0) < 0.2 and first.x > level.block("P1").max.x - 0.6:
			var mid := page.to_global(pts[pts.size() / 2])
			var onto := first.move_toward(pts[pts.size() / 2], 0.35)
			var id: String = path.id
			hero.queue([
				{"do": "look", "at": mid, "t": 0.7},
				{"do": "walk_to", "to": Vector3(first.x - 0.15, 1.0, first.z), "speed": 0.5, "look": mid, "timeout": 2.0},
				{"do": "walk_to", "to": onto, "speed": 0.4, "anim": &"careful_step", "timeout": 2.0},
				{"do": "call", "fn": func():
					if paths.has(id):
						(paths[id] as PathView).wobble()
						cue("wobble", page.to_global(onto), -4.0)},
				{"do": "wait", "t": 0.4, "anim": &"careful_step"},
			])


var zone_life: Dictionary = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0}
var zone_life_target: Dictionary = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0}


func _tick_story(delta: float) -> void:
	if not crossed_gap and hero.position.x > level.block("P2").min.x - 0.3 and hero.grounded:
		crossed_gap = true
	# The light: a drop of colour → into the pencil → into the wilted flower.
	if not light_taken and hero.grounded and level.near(hero.position, level.light, 0.5):
		light_taken = true
		_drop_t = 0.0
		cue("drop", view.light.global_position)
		view.light.visible = false
	# Teach erasing when the graphite left can't make the next line.
	if light_taken and not erase_taught and not erased_once and hero.position.x > -0.5 and level.ink < 2.0 and not level.paths.is_empty() and not hero.scripted():
		erase_taught = true
		var old: Dictionary = level.paths[0]
		var pts: PackedVector3Array = old.points
		var back := page.to_global(pts[pts.size() / 2])
		hero.queue([
			{"do": "look", "at": back, "t": 1.3},
			{"do": "look", "at": head, "t": 1.0},
			{"do": "call", "fn": func():
				for pen in pens:
					pen.hint = DrawingPen.Hint.ERASE},
		])
	# A gentle reminder later on: low graphite and standing around.
	_hint_idle = _hint_idle + delta if (hero.velocity.length() < 0.1 and level.ink < 1.7 and not level.paths.is_empty()) else 0.0
	if _hint_idle > 6.0 and erased_once:
		for pen in pens:
			if pen.hint == DrawingPen.Hint.NONE:
				pen.hint = DrawingPen.Hint.ERASE
	# Looking up at the ball on its tower when near.
	if not ball_caught and hero.position.x > -1.2 and hero.position.x < 1.2 and not hero.scripted() and hero.look_target == null and hero.velocity.length() < 0.1:
		hero.look_target = ball
	# The green orb ends the page.
	if hero.grounded and level.standing_on(hero.position, 0.0) == "T3" and level.near(hero.position, level.orb, 0.6):
		_start_ending()


func _tick_drop(delta: float) -> void:
	if _drop_t < 0.0:
		return
	if _drop == null:
		_drop = Node3D.new()
		page.add_child(_drop)
		var m := Sketch.paper(Sketch.GOLD)
		m.set_shader_parameter("glow", 1.5)
		Sketch.sphere(0.07, m, _drop, 8, 6)
	_drop_t += delta
	var from := level.light + Vector3(0, 0.35, 0)
	var mid := hero.position + Vector3(0, 0.6, 0)
	var to := level.flower + Vector3(0, 0.35, 0)
	if _drop_t < 0.5:
		var t := _drop_t / 0.5
		_drop.position = from.lerp(mid, t) + Vector3(0, sin(t * PI) * 0.3, 0)
	elif _drop_t < 1.2:
		_drop.visible = false
		hero.rig.set_glow(sin((_drop_t - 0.5) / 0.7 * PI) * 1.2)
		if _drop_t - delta < 0.5:
			hero.face(PencilRig.Face.SURPRISED, 0.8)
			cue("absorb", hero.global_position)
	elif _drop_t < 1.9:
		_drop.visible = true
		hero.rig.set_glow(0.0)
		var t := (_drop_t - 1.2) / 0.7
		_drop.position = mid.lerp(to, t) + Vector3(0, sin(t * PI) * 0.6, 0)
	else:
		_drop.visible = false
		view.flower_bloom = minf(1.0, view.flower_bloom + delta * 1.2)
		if _drop_t - delta < 1.9:
			cue("bloom", page.to_global(level.flower), 2.0)
			_confetti.burst(to, 20, [Sketch.GOLD, Color(1.0, 0.95, 0.6), Sketch.GRASS], 1.4, 1.8)
			hero.tired = false
			var fl := page.to_global(level.flower + Vector3(0, 0.3, 0))
			hero.queue([
				{"do": "look", "at": fl, "t": 0.4},
				{"do": "face", "face": PencilRig.Face.HAPPY, "hold": 2.2},
				{"do": "look", "at": fl, "t": 1.8},
			])
			zone_life_target[1] = maxf(zone_life_target[1], 0.25)
		if view.flower_bloom >= 1.0:
			_drop_t = -1.0


# --- ending -----------------------------------------------------------------------------------------------

func _start_ending() -> void:
	if phase == Phase.ENDING:
		return
	phase = Phase.ENDING
	_phase_time = 0.0
	ending_time = 0.0
	for pen in pens:
		pen.hint = DrawingPen.Hint.NONE
		pen.drawing = false
		pen.erasing = false
	if _scribble and _scribble.playing:
		_scribble.stop()
	hero.clear_script()
	hero.velocity = Vector3.ZERO
	var orb_g := view.orb.global_position
	hero.queue([
		{"do": "turn", "to": orb_g, "t": 0.4},
		{"do": "face", "face": PencilRig.Face.HAPPY, "hold": 3.0},
		{"do": "call", "fn": func(): hero.holding = true},
		{"do": "wait", "t": 2.2},
		{"do": "call", "fn": func(): hero.holding = false},
		{"do": "wait", "t": 2.6, "look": orb_g},
	])
	cue("orb", orb_g, 3.0)
	audio.play_music("bright")


func _tick_ending(delta: float) -> void:
	var t := _phase_time
	ending_time = t
	# The orb comes down into his hands and fades into him.
	var hands_at := hero.position + Vector3(0, 0.78, 0) - hero.basis.z * 0.3
	if t < 1.6:
		view.orb.position = view.orb.position.lerp(hands_at, minf(1.0, delta * 3.0))
	elif t < 2.6:
		view.orb.scale = Vector3.ONE * maxf(0.01, 1.0 - (t - 1.6))
		hero.rig.set_glow((t - 1.6) * 1.5)
	else:
		view.orb.visible = false
		hero.rig.set_glow(maxf(0.0, 1.5 - (t - 2.6) * 0.8))
	# Colour spreads out from him across the page (world-space wave).
	if t > 2.4:
		_wave_radius = minf(1.25, _wave_radius + delta * 0.32)
		Sketch.set_wave(page.to_global(hero.position + Vector3(0, 0.5, 0)), _wave_radius)
		if t - delta <= 2.4:
			cue("restore", hero.global_position, 2.0)
	var spread := _wave_radius / SCALE   # in page units
	var origin := hero.position
	for leaf in view.leaves:
		_grow_if_reached(leaf, origin, spread, delta)
	for g in view.grass:
		_grow_if_reached(g, origin, spread, delta)
	for b in view.buds:
		_grow_if_reached(b, origin, spread, delta)
	if spread > origin.distance_to(level.flower) - 1.0:
		view.stream_flow = minf(1.0, view.stream_flow + delta * 0.5)
	if t > 4.0 and t - delta <= 4.0:
		view.spawn_butterflies(6)
	if t > 6.0:
		for z in zone_life_target.keys():
			zone_life_target[z] = 1.0
	# Wind, the next page flips, he looks at you and points at it.
	if t > 7.2 and t - delta <= 7.2:
		cue("wind", global_position, 0.0)
		hero.queue([{"do": "look", "at": view.back_pages[1].global_position + Vector3(0, 0.3, 0), "t": 2.0}])
	if t > 7.2 and t < 9.5:
		if int(t * 20.0) != int((t - delta) * 20.0):
			_confetti.burst(Vector3(-5.0, 2.5, _rng.randf_range(-2.5, 2.5)), 2, [OLD_PAPER_COLOR, Color(0.8, 0.78, 0.7)], 0.5, 0.4)
		for bit in _confetti._bits:
			bit.v.x += delta * 6.0
	var flip := 0.0
	if t > 8.0:
		flip = clampf((t - 8.0) / 0.8, 0.0, 1.0) if t < 10.2 else clampf(1.0 - (t - 10.2) / 0.9, 0.0, 1.0)
		if t - delta <= 8.0:
			cue("page_flip", view.back_pages[1].global_position)
	view.flip_page(flip)
	if t > 11.2 and t - delta <= 11.2:
		var pg := view.back_pages[1].global_position + Vector3(0, 0.25, 0)
		hero.queue([
			{"do": "turn", "to": head, "t": 0.5},
			{"do": "look", "at": head, "t": 0.8},
			{"do": "point", "at": pg, "t": 2.4, "look": head},
		])
	if t > 12.2:
		view.show_page_two(clampf((t - 12.2) / 1.2, 0.0, 1.0))
	if t > 13.5 and t - delta <= 13.5:
		finished.emit()


func _grow_if_reached(node: Node3D, origin: Vector3, spread: float, delta: float) -> void:
	if node.position.distance_to(origin) < spread:
		node.visible = true
		node.scale = node.scale.lerp(Vector3.ONE, minf(1.0, delta * 4.0))


func _apply_zone_life(delta: float) -> void:
	for z in zone_life.keys():
		zone_life[z] = move_toward(zone_life[z], zone_life_target[z], delta * 0.6)
		if zones.has(z):
			for m in zones[z]:
				(m as ShaderMaterial).set_shader_parameter("life", zone_life[z])


# --- buttons ------------------------------------------------------------------------------------------------

func on_button(action: StringName, _hand: int) -> void:
	match action:
		&"ax_button":
			match phase:
				Phase.PLACING:
					place_here()
				Phase.INTRO:
					skip_intro()
				Phase.PLAYING:
					_jump_queued = true
				Phase.ENDING:
					if ending_time > 12.5:
						restart()
		&"by_button":
			if phase == Phase.PLAYING:
				erase_last()
		&"thumbstick_click":
			if phase == Phase.PLAYING:
				phase = Phase.PLACING
				_phase_time = 0.0


func restart() -> void:
	new_game()
	audio.play_music("calm")
	view.set_closed(0.0)
	view.pop_progress(100.0)
	phase = Phase.INTRO
	_phase_time = INTRO_EMERGE_AT - 0.5
	cue("book_open", global_position)
