class_name FrontWorld
extends Node3D
## "The front line" — prototype. Nothing in your room but the pencil and the Eraser.
## A black, hand-drawn front line splits a patch of your real floor: behind the
## pencil everything is rainbow crayon, behind the Eraser grey scribble. Each pushes
## the line into the other's side; whoever holds more floor when time runs out wins.
## Metres, floor at y = 0 (stage space), this node at the centre of the play area.
##
##  PLACING  the area's four corner marks follow your gaze on the floor; trigger
##           or A sets it down
##  PLAYING  stick runs the pencil (it colours where it goes); trigger draws
##           crayon on the floor where your hand points (graphite runs out and
##           slowly comes back); a closed loop round the Eraser freezes it; a
##           flick of the hand shoves it away
##  OVER     the winner's side floods the area; A plays again

signal haptic(hand: int, amplitude: float, seconds: float)
signal finished

enum Phase { PLACING, PLAYING, OVER }

const HALF := 1.2                 # the area is 2.4 m × 2.4 m
const CELLS := 48                 # territory grid (5 cm cells)
const ROUND_TIME := 120.0
const PLACE_DISTANCE := 1.5
const PENCIL_SCALE := 0.62        # ~35 cm tall on your floor
const ERASER_SCALE := 0.55        # ~19 cm tall, ~34 cm long
const PENCIL_SPEED := 1.1         # m/s
const PENCIL_PAINT_R := 0.22
const PENCIL_PAINT_RATE := 7.0    # field units / s at the centre (flips the floor as he runs over it)
const ERASER_SPEED := 0.75
const ERASER_SPEED_GAIN := 0.25   # extra m/s by the end of the round
const ERASER_R := 0.26
const ERASER_RATE := 3.2
const STROKE_R := 0.12
const STROKE_STRENGTH := 1.6
const INK_MAX := 3.0              # metres of crayon
const INK_REFILL := 0.22          # m/s
const SAMPLE_STEP := 0.04
const LASSO_CLOSE := 0.3
const FREEZE_TIME := 3.0
const BUMP_RADIUS := 0.3
const STUN_TIME := 1.2

var phase: int = Phase.PLACING
var head: Node3D
var hands: Array[Node3D] = []
var pens: Array[DrawingPen] = []
var audio: GameAudio
var field := PackedFloat32Array()     # +1 pencil … −1 Eraser, CELLS×CELLS
var time_left: float = ROUND_TIME
var ink: float = INK_MAX
var pencil_share: float = 0.5

var pencil_root: Node3D
var rig: PencilRig
var pencil_pos := Vector3(-0.6, 0, 0)
var pencil_vel := Vector3.ZERO
var stun: float = 0.0
var eraser_root: Node3D
var eraser: EraserEnemy
var eraser_pos := Vector3(0.6, 0, 0)
var eraser_vel := Vector3.ZERO
var freeze: float = 0.0
var winner: String = ""

var _image: Image
var _texture: ImageTexture
var _floor_mat: ShaderMaterial
var _hud: Label3D
var _bar_pencil: MeshInstance3D
var _bar_eraser: MeshInstance3D
var _corners: Node3D
var _confetti: Confetti
var _doodles: Array = []          # {node, life}
var _doodle_t: float = 0.0
var _strokes: Array = [PackedVector3Array(), PackedVector3Array()]
var _stroke_meshes: Array[ImmediateMesh] = []
var _was_drawing: Array[bool] = [false, false]
var _hand_prev: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _ice: MeshInstance3D
var _scribble: AudioStreamPlayer3D
var _rub: AudioStreamPlayer3D
var _phase_time: float = 0.0
var _rng := RandomNumberGenerator.new()


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
	_build_floor()
	_build_hud()
	_confetti = Confetti.new()
	add_child(_confetti)
	pencil_root = Node3D.new()
	pencil_root.scale = Vector3.ONE * PENCIL_SCALE
	add_child(pencil_root)
	rig = PencilRig.new()
	pencil_root.add_child(rig)
	var ps := Sketch.blob_shadow(0.35, pencil_root)
	ps.position.y = 0.01
	eraser_root = Node3D.new()
	eraser_root.scale = Vector3.ONE * ERASER_SCALE
	add_child(eraser_root)
	eraser = EraserEnemy.new()
	eraser_root.add_child(eraser)
	var es := Sketch.blob_shadow(0.45, eraser_root)
	es.position.y = 0.01
	_ice = Sketch.tube(_loop_points(Vector3.ZERO, 0.42, 0.06), 0.025, Sketch.ink(Sketch.GRAPHITE), eraser_root)
	_ice.visible = false
	for i in range(2):
		var im := ImmediateMesh.new()
		_stroke_meshes.append(im)
		var n := Sketch.mesh_node(im, Sketch.ink(Sketch.GRAPHITE), self)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scribble = audio.attach_loop("scribble", self, -14.0)
	_rub = audio.attach_loop("rub", eraser_root, -12.0)
	new_round()
	phase = Phase.PLACING
	audio.play_music("bright")


static func _loop_points(c: Vector3, r: float, y: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in range(25):
		var a := TAU * k / 24.0
		pts.append(c + Vector3(cos(a) * r * (1.0 + 0.06 * sin(k * 2.7)), y, sin(a) * r))
	return pts


# --- the floor ------------------------------------------------------------------------------

func _build_floor() -> void:
	field.resize(CELLS * CELLS)
	_image = Image.create(CELLS, CELLS, false, Image.FORMAT_L8)
	_texture = ImageTexture.create_from_image(_image)
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF * 2.0, HALF * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = 0.004
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	_floor_mat.shader = sh
	_floor_mat.set_shader_parameter("field", _texture)
	mi.material_override = _floor_mat
	add_child(mi)
	_corners = Node3D.new()
	add_child(_corners)
	var ink_mat := Sketch.ink(Color(0.08, 0.08, 0.09, 0.85), true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * HALF, 0.012, sz * HALF)
			Sketch.tube(PackedVector3Array([c - Vector3(sx * 0.25, 0, 0), c, c - Vector3(0, 0, sz * 0.25)]), 0.008, ink_mat, _corners)


## Rainbow crayon on the pencil's side, grey scribble on the Eraser's, and a
## wobbly black hand-drawn line where they meet. The field is +1 … −1 (L8).
const FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D field : filter_linear, repeat_disable;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV;
	float v = texture(field, uv).r * 2.0 - 1.0;
	float s = v + (noise(uv * 34.0) - 0.5) * 0.18 + (noise(uv * 90.0) - 0.5) * 0.06;
	float grain = noise(uv * 260.0);
	// crayon: rainbow bands that swirl a little, waxy grain, paper showing through
	float band = uv.x * 1.6 + uv.y * 0.7 + noise(uv * 3.0) * 0.9;
	vec3 rainbow = 0.6 + 0.4 * cos(6.2831 * (band * 0.5 + vec3(0.0, 0.33, 0.67)));
	vec3 crayon = rainbow * (0.85 + 0.25 * grain);
	float wax = smoothstep(0.3, 0.8, noise(vec2(uv.x * 120.0 + uv.y * 30.0, uv.y * 10.0)));
	float ca = smoothstep(0.0, 0.18, s) * (0.32 + 0.3 * wax);
	// the Eraser's side: rubbed-out grey with hard scribbles and crumbs
	float scrib = abs(sin(uv.x * 55.0 + uv.y * 22.0 + noise(uv * 7.0) * 6.0));
	float crumbs = step(0.95, hash(floor(uv * 180.0)));
	vec3 grey = vec3(0.66 + 0.2 * grain) * mix(0.72, 1.0, smoothstep(0.05, 0.5, scrib)) - crumbs * 0.35;
	float ga = smoothstep(0.0, 0.18, -s) * (0.5 + 0.18 * (1.0 - scrib) + crumbs * 0.3);
	// the front line: a thick hand-drawn black stroke along s = 0
	float w = fwidth(s);
	float line = 1.0 - smoothstep(w * 1.2 + 0.035, w * 2.2 + 0.07, abs(s));
	vec3 c = s >= 0.0 ? crayon : grey;
	float a = max(ca, ga);
	c = mix(c, vec3(0.03, 0.03, 0.035), line);
	a = max(a, line * 0.96);
	vec2 e = min(uv, 1.0 - uv);
	a *= smoothstep(0.0, 0.025, min(e.x, e.y));
	ALBEDO = c;
	ALPHA = a;
}
"""


func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x + HALF) / (HALF * 2.0) * CELLS), 0, CELLS - 1), clampi(int((z + HALF) / (HALF * 2.0) * CELLS), 0, CELLS - 1))


func value_at(p: Vector3) -> float:
	var c := _cell(p.x, p.z)
	return field[c.y * CELLS + c.x]


## Pushes the field towards `target` (+1 / −1) round `p` (local metres).
func paint(p: Vector3, radius: float, amount: float, target: float) -> void:
	var cs := HALF * 2.0 / CELLS
	var c0 := _cell(p.x - radius, p.z - radius)
	var c1 := _cell(p.x + radius, p.z + radius)
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var cx := -HALF + (i + 0.5) * cs
			var cz := -HALF + (j + 0.5) * cs
			var d := Vector2(cx - p.x, cz - p.z).length()
			if d > radius:
				continue
			var k := j * CELLS + i
			var f := 1.0 - d / radius
			field[k] = move_toward(field[k], target, amount * f)


func _upload_field() -> void:
	var share := 0
	for j in range(CELLS):
		for i in range(CELLS):
			var v := field[j * CELLS + i]
			if v > 0.0:
				share += 1
			_image.set_pixel(i, j, Color(v * 0.5 + 0.5, 0, 0))
	pencil_share = float(share) / (CELLS * CELLS)
	_texture.update(_image)


func in_area(p: Vector3, margin: float = 0.0) -> bool:
	return absf(p.x) <= HALF - margin and absf(p.z) <= HALF - margin


# --- HUD ---------------------------------------------------------------------------------------

func _build_hud() -> void:
	var root := Node3D.new()
	root.position = Vector3(0, 0.55, -HALF - 0.15)
	add_child(root)
	_hud = Label3D.new()
	_hud.font = load("res://assets/fonts/BalooBhaijaan2-Arabic.ttf")
	_hud.font_size = 64
	_hud.pixel_size = 0.0016
	_hud.modulate = Color(0.12, 0.11, 0.1)
	_hud.outline_size = 14
	_hud.outline_modulate = Color(0.98, 0.96, 0.9)
	_hud.position.y = 0.12
	root.add_child(_hud)
	var frame := Sketch.box(Vector3(1.04, 0.07, 0.02), Sketch.paper(Color(0.08, 0.08, 0.09)), root)
	frame.position.z = -0.005
	_bar_pencil = Sketch.box(Vector3(1.0, 0.05, 0.02), Sketch.paper(Sketch.YELLOW), root)
	_bar_eraser = Sketch.box(Vector3(1.0, 0.05, 0.02), Sketch.paper(Color(0.6, 0.6, 0.6)), root)
	root.set_meta("hud", true)
	_hud.set_meta("root", root)


func _tick_hud() -> void:
	var p := clampf(pencil_share, 0.0, 1.0)
	# The pencil's colour fills from the left, the Eraser's grey from the right.
	_bar_pencil.scale.x = maxf(0.001, p)
	_bar_pencil.position.x = -0.5 + p * 0.5
	_bar_eraser.scale.x = maxf(0.001, 1.0 - p)
	_bar_eraser.position.x = 0.5 - (1.0 - p) * 0.5
	var secs := int(ceil(time_left))
	var text := "القلم %d٪   %d:%02d   %d٪ الممحاة" % [int(round(p * 100.0)), secs / 60, secs % 60, int(round((1.0 - p) * 100.0))]
	if phase == Phase.PLACING:
		text = "اختر مكانًا على الأرض واضغط الزناد"
	elif phase == Phase.OVER:
		text = ("فاز القلم!" if winner == "pencil" else "فازت الممحاة!") + "   A للإعادة"
	_hud.text = text
	var root: Node3D = _hud.get_meta("root")
	if head:
		var to := head.global_position - root.global_position
		to.y = 0.0
		if to.length() > 0.01:
			root.global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)


# --- round -------------------------------------------------------------------------------------

func new_round() -> void:
	for k in range(CELLS * CELLS):
		var i := k % CELLS
		var j := k / CELLS
		var x := (i + 0.5) / CELLS * 2.0 - 1.0
		var z := (j + 0.5) / CELLS * 2.0 - 1.0
		# Left half the pencil's, right half the Eraser's, along a gentle wave.
		var edge := sin(z * 3.2) * 0.08
		field[k] = clampf((edge - x) * 6.0, -1.0, 1.0)
	_upload_field()
	time_left = ROUND_TIME
	ink = INK_MAX
	winner = ""
	stun = 0.0
	freeze = 0.0
	pencil_pos = Vector3(-0.6, 0, 0.2)
	pencil_vel = Vector3.ZERO
	eraser_pos = Vector3(0.6, 0, -0.2)
	eraser_vel = Vector3.ZERO
	pencil_root.position = pencil_pos
	eraser_root.position = eraser_pos
	eraser.visible = true
	eraser.state = EraserEnemy.State.HUNTING
	_ice.visible = false
	rig.play(&"idle")
	rig.set_face(PencilRig.Face.DETERMINED)
	for d in _doodles:
		(d.node as Node3D).queue_free()
	_doodles.clear()


func _flat_forward() -> Vector3:
	var f := -head.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func place_here() -> void:
	if phase != Phase.PLACING:
		return
	phase = Phase.PLAYING
	_phase_time = 0.0
	audio.play_cue("pop", global_position, -4.0)
	for pen in pens:
		pen.hint = DrawingPen.Hint.DRAW


func tick(delta: float, stick: Vector2, triggers: Array, grips: Array = [0.0, 0.0]) -> void:
	_phase_time += delta
	match phase:
		Phase.PLACING:
			var fwd := _flat_forward()
			var target := head.global_position + fwd * PLACE_DISTANCE
			target.y = 0.0
			var t := minf(1.0, delta * 6.0) if _phase_time > 0.05 else 1.0
			global_position = global_position.lerp(target, t)
			# The pencil's side is on your left, the Eraser's on your right.
			global_basis = global_basis.slerp(Basis.looking_at(fwd, Vector3.UP), t).orthonormalized()
			if _phase_time > 0.6 and (triggers[0] > 0.8 or triggers[1] > 0.8):
				place_here()
		Phase.PLAYING:
			time_left = maxf(0.0, time_left - delta)
			_tick_pencil(delta, stick)
			_tick_eraser(delta)
			_tick_drawing(delta, triggers)
			_tick_hands(delta)
			_tick_doodles(delta)
			if time_left <= 0.0:
				_end_round()
		Phase.OVER:
			_tick_doodles(delta)
			var target := 1.0 if winner == "pencil" else -1.0
			for k in range(field.size()):
				field[k] = move_toward(field[k], target, delta * 0.8)
	for pen in pens:
		pen.ink_fraction = ink / INK_MAX
	_upload_field()
	_tick_hud()


func _stick_to_floor(stick: Vector2) -> Vector3:
	if stick.length() < 0.15:
		return Vector3.ZERO
	var fwd := _flat_forward()
	var right := fwd.cross(Vector3.UP)
	var world := right * stick.x + fwd * stick.y
	var local := global_basis.inverse() * world
	local.y = 0.0
	return local.normalized() * clampf((stick.length() - 0.15) / 0.75, 0.0, 1.0)


func _tick_pencil(delta: float, stick: Vector2) -> void:
	var want := _stick_to_floor(stick) * PENCIL_SPEED
	if stun > 0.0:
		stun -= delta
		want = Vector3.ZERO
	pencil_vel = pencil_vel.move_toward(want, delta * 6.0)
	pencil_pos += pencil_vel * delta
	pencil_pos.x = clampf(pencil_pos.x, -HALF + 0.08, HALF - 0.08)
	pencil_pos.z = clampf(pencil_pos.z, -HALF + 0.08, HALF - 0.08)
	pencil_root.position = pencil_pos
	var speed := Vector2(pencil_vel.x, pencil_vel.z).length()
	if speed > 0.05:
		pencil_root.rotation.y = lerp_angle(pencil_root.rotation.y, atan2(-pencil_vel.x, -pencil_vel.z), minf(1.0, delta * 10.0))
		# Wherever he runs, colour pours out round his tip.
		paint(pencil_pos, PENCIL_PAINT_R, PENCIL_PAINT_RATE * delta * clampf(speed / PENCIL_SPEED, 0.4, 1.0), 1.0)
		_doodle_t += delta
		if _doodle_t > 0.35:
			_doodle_t = 0.0
			_spawn_doodle(pencil_pos + Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)))
	rig.set_locomotion(speed / 0.5, 0.0)
	if stun > 0.0:
		rig.play(&"fall")
	elif winner == "pencil":
		rig.play(&"celebrate")
	else:
		rig.play(&"run" if speed > PENCIL_SPEED * 0.75 else (&"walk" if speed > 0.08 else &"idle"))


## The Eraser goes for the coloured floor nearest the front line (or for the pencil
## when he is close), rubbing it grey; it shoves the pencil over when it hits him.
func _tick_eraser(delta: float) -> void:
	eraser._t += delta
	if freeze > 0.0:
		freeze -= delta
		_ice.visible = freeze > 0.0
		eraser._animate(delta, 0.0)
		if _rub.playing:
			_rub.stop()
		return
	var target := _eraser_target()
	var to := target - eraser_pos
	to.y = 0.0
	var speed := ERASER_SPEED + ERASER_SPEED_GAIN * (1.0 - time_left / ROUND_TIME)
	var want := to.normalized() * speed if to.length() > 0.05 else Vector3.ZERO
	eraser_vel = eraser_vel.move_toward(want, delta * 3.0)
	eraser_pos += eraser_vel * delta
	eraser_pos.x = clampf(eraser_pos.x, -HALF + 0.1, HALF - 0.1)
	eraser_pos.z = clampf(eraser_pos.z, -HALF + 0.1, HALF - 0.1)
	eraser_root.position = eraser_pos
	if Vector2(eraser_vel.x, eraser_vel.z).length() > 0.05:
		eraser_root.rotation.y = lerp_angle(eraser_root.rotation.y, atan2(eraser_vel.x, eraser_vel.z), minf(1.0, delta * 6.0))
	var rubbing := value_at(eraser_pos) > -0.9
	paint(eraser_pos, ERASER_R, ERASER_RATE * delta, -1.0)
	eraser._animate(delta, 1.0 if rubbing else 0.0)
	if rubbing and _rng.randf() < 0.3:
		_confetti.burst(eraser_pos + Vector3(0, 0.03, 0), 1, [Color(0.85, 0.85, 0.85), Color(0.4, 0.4, 0.42)], 0.4, 0.4)
	if rubbing and not _rub.playing:
		_rub.play()
	elif not rubbing and _rub.playing:
		_rub.stop()
	# Hitting the pencil knocks him over.
	var d := Vector2(pencil_pos.x - eraser_pos.x, pencil_pos.z - eraser_pos.z)
	if d.length() < BUMP_RADIUS and stun <= 0.0:
		var n := d.normalized() if d.length() > 0.001 else Vector2(-1, 0)
		pencil_vel = Vector3(n.x, 0, n.y) * 1.6
		stun = STUN_TIME
		rig.set_face(PencilRig.Face.SURPRISED)
		audio.play_cue("bump", pencil_root.global_position, -2.0)
		_confetti.burst(pencil_pos + Vector3(0, 0.15, 0), 10, [Sketch.YELLOW, Color(0.3, 0.3, 0.32)], 0.8, 1.0)
		haptic.emit(0, 0.5, 0.1)
		haptic.emit(1, 0.5, 0.1)


func _eraser_target() -> Vector3:
	var to_pencil := Vector2(pencil_pos.x - eraser_pos.x, pencil_pos.z - eraser_pos.z)
	if to_pencil.length() < 0.6 and stun <= 0.0:
		return pencil_pos
	# The nearest coloured cell (searched coarsely), weighted towards the line.
	var best := pencil_pos
	var best_score := INF
	var cs := HALF * 2.0 / CELLS
	for j in range(0, CELLS, 2):
		for i in range(0, CELLS, 2):
			var v := field[j * CELLS + i]
			if v <= 0.05:
				continue
			var p := Vector3(-HALF + (i + 0.5) * cs, 0, -HALF + (j + 0.5) * cs)
			var score := p.distance_to(eraser_pos) + v * 0.6
			if score < best_score:
				best_score = score
				best = p
	return best


# --- drawing on the floor ------------------------------------------------------------------------

## Where hand `i` points on the floor (local), or INF.
func _floor_hit(i: int) -> Vector3:
	var o := to_local(pens[i].tip_global())
	var dir := (global_basis.inverse() * pens[i].forward_global()).normalized()
	if dir.y > -0.05:
		return Vector3.INF
	var t := -o.y / dir.y
	if t < 0.0 or t > 6.0:
		return Vector3.INF
	var p := o + dir * t
	return p if in_area(p) else Vector3.INF


func _tick_drawing(delta: float, triggers: Array) -> void:
	ink = minf(INK_MAX, ink + INK_REFILL * delta)
	var any := false
	for i in range(mini(pens.size(), triggers.size())):
		var down: bool = triggers[i] > 0.6
		pens[i].drawing = down
		var hit := _floor_hit(i)
		if down and hit != Vector3.INF:
			any = true
			_draw_point(i, hit)
		elif _was_drawing[i]:
			finish_stroke(i)
		_was_drawing[i] = down and hit != Vector3.INF
	if _scribble:
		if any and not _scribble.playing:
			_scribble.play()
		elif not any and _scribble.playing:
			_scribble.stop()


func _draw_point(i: int, p: Vector3) -> void:
	var pts: PackedVector3Array = _strokes[i]
	if not pts.is_empty():
		var d := pts[pts.size() - 1].distance_to(p)
		if d < SAMPLE_STEP:
			return
		if ink < d:
			return
		ink -= d
	pts.append(p + Vector3(0, 0.01, 0))
	_strokes[i] = pts
	# Crayon goes straight onto the floor as you draw.
	paint(p, STROKE_R, STROKE_STRENGTH, 1.0)
	if pts.size() >= 2:
		Sketch.build_tube(_stroke_meshes[i], pts, 0.012, 4)
	haptic.emit(i, 0.08, 0.02)
	if _rng.randf() < 0.25:
		_spawn_doodle(p)


## Releasing the trigger: a closed loop round the Eraser freezes it.
func finish_stroke(i: int) -> Dictionary:
	var pts: PackedVector3Array = _strokes[i]
	_strokes[i] = PackedVector3Array()
	_stroke_meshes[i].clear_surfaces()
	return commit_stroke(pts)


func commit_stroke(pts: PackedVector3Array) -> Dictionary:
	if pts.size() >= 6 and pts[0].distance_to(pts[pts.size() - 1]) < LASSO_CLOSE and _inside(pts, eraser_pos):
		freeze = FREEZE_TIME
		_ice.visible = true
		eraser_vel = Vector3.ZERO
		audio.play_cue("scribble", eraser_root.global_position, 0.0)
		_confetti.burst(eraser_pos + Vector3(0, 0.2, 0), 18, [Sketch.GRAPHITE, Color(0.2, 0.2, 0.22)], 1.0, 1.2)
		rig.set_face(PencilRig.Face.HAPPY)
		return {"frozen": true}
	return {"frozen": false}


static func _inside(pts: PackedVector3Array, p: Vector3) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in range(pts.size()):
		var a := pts[i]
		var b := pts[j]
		if (a.z > p.z) != (b.z > p.z):
			var x := a.x + (p.z - a.z) / (b.z - a.z) * (b.x - a.x)
			if p.x < x:
				inside = not inside
		j = i
	return inside


## A flick of the hand near the Eraser shoves it away.
func _tick_hands(delta: float) -> void:
	for i in range(hands.size()):
		var p := to_local(pens[i].tip_global())
		var prev := _hand_prev[i]
		_hand_prev[i] = p
		if prev == Vector3.INF or delta <= 0.0:
			continue
		var v := (p - prev) / delta
		if (eraser_pos + Vector3(0, 0.12, 0) - p).length() < 0.25 and Vector2(v.x, v.z).length() > 1.2:
			var fl := Vector2(v.x, v.z).limit_length(4.0)
			eraser_vel = Vector3(fl.x, 0, fl.y)
			audio.play_cue("bump", eraser_root.global_position, -4.0)
			haptic.emit(i, 0.5, 0.08)


# --- crayon doodles ---------------------------------------------------------------------------------

## A little star, heart or flower scribbled on the coloured floor; it pops in and
## fades out after a while.
func _spawn_doodle(at: Vector3) -> void:
	if not in_area(at, 0.05) or value_at(at) <= 0.0:
		return
	if _doodles.size() > 40:
		var old: Dictionary = _doodles.pop_front()
		(old.node as Node3D).queue_free()
	var colors := [Color(0.95, 0.2, 0.25), Color(1.0, 0.75, 0.1), Color(0.2, 0.55, 1.0), Color(0.6, 0.3, 0.9), Color(1.0, 0.45, 0.75), Color(0.25, 0.8, 0.4)]
	var col: Color = colors[_rng.randi() % colors.size()]
	var pts := PackedVector3Array()
	var kind := _rng.randi() % 3
	var r := _rng.randf_range(0.035, 0.06)
	match kind:
		0:   # star
			for k in range(11):
				var a := PI * 0.5 + TAU * k / 10.0
				var rr := r if k % 2 == 0 else r * 0.45
				pts.append(Vector3(cos(a) * rr, 0, sin(a) * rr))
		1:   # heart
			for k in range(21):
				var t := TAU * k / 20.0
				pts.append(Vector3(16.0 * pow(sin(t), 3.0), 0, -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * r / 16.0)
		_:   # flower
			for k in range(31):
				var a := TAU * k / 30.0
				var rr := r * (0.55 + 0.45 * absf(cos(a * 2.5)))
				pts.append(Vector3(cos(a) * rr, 0, sin(a) * rr))
	var node := Sketch.tube(pts, 0.004, Sketch.ink(col), self)
	node.position = at + Vector3(0, 0.008, 0)
	node.rotation.y = _rng.randf() * TAU
	node.scale = Vector3.ONE * 0.01
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_doodles.append({"node": node, "life": 0.0})


func _tick_doodles(delta: float) -> void:
	for k in range(_doodles.size() - 1, -1, -1):
		var d: Dictionary = _doodles[k]
		d.life += delta
		var node: Node3D = d.node
		node.scale = Vector3.ONE * minf(1.0, d.life * 6.0)
		# Rubbed out where the Eraser has taken the floor back.
		if d.life > 8.0 or value_at(node.position) < -0.2:
			node.queue_free()
			_doodles.remove_at(k)


# --- end -------------------------------------------------------------------------------------------

func _end_round() -> void:
	phase = Phase.OVER
	_phase_time = 0.0
	winner = "pencil" if pencil_share >= 0.5 else "eraser"
	if winner == "pencil":
		rig.play(&"celebrate")
		rig.set_face(PencilRig.Face.HAPPY)
		audio.play_cue("restore", pencil_root.global_position, 2.0)
		for k in range(12):
			_confetti.burst(pencil_pos + Vector3(0, 0.3, 0), 3, [Color(0.95, 0.2, 0.25), Color(1.0, 0.75, 0.1), Color(0.2, 0.55, 1.0)], 1.6, 2.0)
	else:
		rig.play(&"sad")
		rig.set_face(PencilRig.Face.SAD)
		audio.play_cue("poof", eraser_root.global_position, 0.0)
	if _rub.playing:
		_rub.stop()
	finished.emit()


func on_button(action: StringName, _hand: int) -> void:
	match action:
		&"ax_button":
			match phase:
				Phase.PLACING:
					place_here()
				Phase.OVER:
					new_round()
					phase = Phase.PLAYING
		&"thumbstick_click":
			if phase == Phase.PLAYING:
				phase = Phase.PLACING
				_phase_time = 0.0
