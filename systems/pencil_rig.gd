class_name PencilRig
extends Node3D
## The pencil's LOOK, built from simple shapes for now. Game logic never
## touches these meshes; it only calls the small contract below, so a real
## GLB model (with an AnimationPlayer playing clips of the same names) can
## replace this file later without changing PencilBody or the stage.
##
## Contract:
##   play(anim)                    one of ANIMS
##   set_face(face)                PencilRig.Face
##   set_locomotion(speed01, vertical_speed)
##   look_at_point(global_point)   Vector3.INF = look straight ahead
##   point_at(global_point)        Vector3.INF = stop pointing
##   set_glow(amount)              colour drop / orb pulsing through the body
##   set_hidden_for_scribble(on)   fall effect

enum Face { HOPEFUL, TIRED, HAPPY, SURPRISED, SAD, DETERMINED }

const ANIMS := [&"idle", &"tired_idle", &"walk", &"run", &"jump", &"careful_step", &"lose_balance",
	&"fall", &"recover", &"push", &"celebrate", &"hold", &"sad", &"look_around", &"shake_head"]

var anim: StringName = &"idle"
var face: int = Face.HOPEFUL
var speed01: float = 0.0
var vertical: float = 0.0

var _anim_time: float = 0.0
var _time: float = 0.0
var _phase: float = 0.0
var _blink: float = 2.0
var _look := Vector3.INF
var _point := Vector3.INF
var _glow: float = 0.0
var _rng := RandomNumberGenerator.new()

var _trunk: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth: MeshInstance3D
var _mouth_mesh := ImmediateMesh.new()
var _mouth_o: MeshInstance3D
var _body_mat: ShaderMaterial
var _scribble: MeshInstance3D
var _parts: Array[Node3D] = []


func _ready() -> void:
	_rng.seed = 7
	_build()
	set_face(Face.TIRED)


# --- contract ---------------------------------------------------------------------

func play(new_anim: StringName) -> void:
	if new_anim != anim:
		anim = new_anim
		_anim_time = 0.0


func set_locomotion(speed: float, vertical_speed: float) -> void:
	speed01 = clampf(speed, 0.0, 1.5)
	vertical = vertical_speed


func look_at_point(p: Vector3) -> void:
	_look = p


func point_at(p: Vector3) -> void:
	_point = p


func set_glow(amount: float) -> void:
	_glow = amount


func set_hidden_for_scribble(on: bool) -> void:
	for p in _parts:
		p.visible = not on
	_scribble.visible = on


func set_face(f: int) -> void:
	face = f
	if _brows.is_empty():
		return
	var brow_tilt := 0.0
	var brow_y := 0.615
	var eye_open := 1.0
	var smile := 0.6
	var open_mouth := false
	match f:
		Face.HOPEFUL:
			brow_tilt = -0.15
		Face.TIRED:
			brow_tilt = 0.35
			brow_y = 0.6
			eye_open = 0.55
			smile = 0.1
		Face.HAPPY:
			brow_y = 0.63
			eye_open = 0.8
			smile = 1.0
		Face.SURPRISED:
			brow_y = 0.645
			eye_open = 1.2
			open_mouth = true
		Face.SAD:
			brow_tilt = 0.45
			eye_open = 0.85
			smile = -0.6
		Face.DETERMINED:
			brow_tilt = -0.45
			brow_y = 0.6
			eye_open = 0.9
			smile = 0.25
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		_brows[i].position.y = brow_y
		_brows[i].rotation.z = -brow_tilt * side
		_eyes[i].set_meta("open", eye_open)
	_mouth.visible = not open_mouth
	_mouth_o.visible = open_mouth
	var pts := PackedVector3Array()
	for k in range(7):
		var t := k / 6.0 * 2.0 - 1.0
		pts.append(Vector3(t * 0.045, 0.45 - smile * 0.022 * (1.0 - t * t), -0.142 - 0.006 * (1.0 - t * t)))
	Sketch.build_tube(_mouth_mesh, pts, 0.007, 5)


# --- build --------------------------------------------------------------------------

func _build() -> void:
	_body_mat = Sketch.paper(Color(0.93, 0.76, 0.32))
	var wood := Sketch.paper(Color(0.9, 0.76, 0.58))
	var lead := Sketch.paper(Sketch.GRAPHITE)
	var metal := Sketch.paper(Color(0.68, 0.68, 0.7))
	var pink := Sketch.paper(Color(0.86, 0.56, 0.56))
	var dark := Sketch.paper(Color(0.12, 0.1, 0.1))
	var white := Sketch.paper(Color(0.97, 0.95, 0.9))
	var leather := Sketch.paper(Sketch.LEATHER)
	var shoe := Sketch.paper(Color(0.42, 0.27, 0.16))
	var patch := Sketch.paper(Color(0.55, 0.38, 0.22))

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.07, 0.25, 0)
		add_child(hip)
		var leg := Sketch.cylinder(0.022, 0.022, 0.2, dark, hip, 6)
		leg.position.y = -0.1
		var boot := Sketch.sphere(0.07, shoe, hip, 10, 6)
		boot.scale = Vector3(1.0, 0.65, 1.35)
		boot.position = Vector3(0, -0.215, -0.03)
		var p := Sketch.sphere(0.025, patch, hip, 6, 4)
		p.position = Vector3(side * 0.05, -0.2, -0.06)
		p.scale = Vector3(0.5, 1, 1)
		_legs.append(hip)
		_parts.append(hip)

	_trunk = Node3D.new()
	_trunk.position.y = 0.22
	add_child(_trunk)
	_parts.append(_trunk)
	# Worn eraser (chewed rim), dented ferrule, faded hexagonal body.
	var eraser := Sketch.cylinder(0.13, 0.12, 0.1, pink, _trunk, 6)
	eraser.position.y = 0.06
	var chew := Sketch.sphere(0.04, pink, _trunk, 6, 4)
	chew.position = Vector3(0.1, 0.02, -0.06)
	chew.scale = Vector3(1, 0.5, 1)
	var ferrule := Sketch.cylinder(0.155, 0.155, 0.08, metal, _trunk, 6)
	ferrule.position.y = 0.15
	var dent := Sketch.sphere(0.03, Sketch.paper(Color(0.5, 0.5, 0.52)), _trunk, 6, 4)
	dent.position = Vector3(-0.13, 0.15, -0.07)
	dent.scale = Vector3(0.4, 1.0, 1.0)
	for y in [0.125, 0.175]:
		var ring := Sketch.cylinder(0.159, 0.159, 0.008, Sketch.paper(Color(0.5, 0.5, 0.54)), _trunk, 6)
		ring.position.y = y
	var body := Sketch.cylinder(0.15, 0.15, 0.48, _body_mat, _trunk, 6)
	body.position.y = 0.43
	body.rotation.y = PI / 6.0
	var cone := Sketch.cylinder(0.045, 0.15, 0.16, wood, _trunk, 6)
	cone.position.y = 0.75
	cone.rotation.y = PI / 6.0
	var tip := Sketch.cylinder(0.012, 0.045, 0.06, lead, _trunk, 6)  # blunt, worn tip
	tip.position.y = 0.86
	var chip := Sketch.box(Vector3(0.05, 0.04, 0.03), wood, _trunk)
	chip.position = Vector3(0.09, 0.73, -0.08)
	chip.rotation = Vector3(0.4, 0.3, 0.6)
	# Scratches and bite marks on the paint (kept off the face).
	var scratch := Sketch.ink(Color(0.5, 0.36, 0.14))
	for i in range(7):
		var a := _rng.randf_range(0.75, 1.7) * (1.0 if i % 2 == 0 else -1.0)
		var y := _rng.randf_range(0.22, 0.64)
		var p := Vector3(sin(a) * 0.152, y, -cos(a) * 0.152)
		Sketch.tube(PackedVector3Array([p, p + Vector3(_rng.randf_range(-0.03, 0.03), 0.04, 0)]), 0.004, scratch, _trunk)
	for i in range(3):
		var a := PI + _rng.randf_range(-0.8, 0.8)
		var nick := Sketch.sphere(0.022, Sketch.paper(Color(0.85, 0.7, 0.5)), _trunk, 6, 4)
		nick.position = Vector3(sin(a) * 0.148, _rng.randf_range(0.3, 0.6), -cos(a) * 0.148)
		nick.scale = Vector3(1, 0.6, 0.4)

	# Face.
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(side * 0.058, 0.53, -0.128)
		_trunk.add_child(eye)
		var white_ball := Sketch.sphere(0.05, white, eye, 12, 8)
		white_ball.scale = Vector3(0.9, 1.15, 0.55)
		var pupil := Node3D.new()
		eye.add_child(pupil)
		var dot := Sketch.sphere(0.03, dark, pupil, 10, 6)
		dot.scale = Vector3(1, 1.15, 0.6)
		dot.position = Vector3(0, -0.008, -0.022)
		var shine := Sketch.sphere(0.009, white, pupil, 6, 4)
		shine.position = Vector3(0.008, 0.01, -0.04)
		_pupils.append(pupil)
		_eyes.append(eye)
		var brow := Sketch.box(Vector3(0.065, 0.016, 0.014), dark, _trunk)
		brow.position = Vector3(side * 0.06, 0.615, -0.14)
		_brows.append(brow)
		var cheek := Sketch.sphere(0.022, Sketch.paper(Color(0.95, 0.6, 0.55)), _trunk, 8, 4)
		cheek.scale = Vector3(1.2, 0.7, 0.4)
		cheek.position = Vector3(side * 0.1, 0.47, -0.13)
	_mouth = Sketch.mesh_node(_mouth_mesh, Sketch.ink(Color(0.25, 0.08, 0.07)), _trunk)
	_mouth_o = Sketch.sphere(0.024, Sketch.paper(Color(0.35, 0.08, 0.08)), _trunk, 8, 6)
	_mouth_o.scale = Vector3(0.9, 1.2, 0.4)
	_mouth_o.position = Vector3(0, 0.445, -0.142)

	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.16, 0.42, 0)
		_trunk.add_child(shoulder)
		var arm := Sketch.cylinder(0.018, 0.018, 0.2, dark, shoulder, 6)
		arm.position.y = -0.1
		var glove := Sketch.sphere(0.048, white, shoulder, 10, 6)
		glove.position.y = -0.215
		_arms.append(shoulder)
	# Small worn satchel with a torn flap.
	var bag := Sketch.box(Vector3(0.05, 0.1, 0.13), leather, _trunk)
	bag.position = Vector3(0.18, 0.22, 0.0)
	var flap := Sketch.box(Vector3(0.054, 0.045, 0.1), Sketch.paper(Color(0.38, 0.23, 0.13)), _trunk)
	flap.position = Vector3(0.18, 0.255, -0.015)
	flap.rotation.x = 0.15
	var strap := PackedVector3Array()
	for i in range(9):
		var t := i / 8.0
		var ang := lerpf(-0.3, PI + 0.5, t)
		strap.append(Vector3(cos(ang) * 0.158, lerpf(0.27, 0.6, sin(t * PI) * 0.9 + t * 0.1), sin(ang) * 0.158))
	Sketch.tube(strap, 0.012, Sketch.ink(Color(0.36, 0.22, 0.12)), _trunk)
	# The scribble that replaces him for a moment when he falls.
	var tangle := PackedVector3Array()
	for i in range(60):
		var t := i / 59.0
		tangle.append(Vector3(sin(t * 37.0) * 0.22 * (1.0 - t * 0.3), 0.3 + cos(t * 23.0) * 0.22, cos(t * 41.0) * 0.18))
	_scribble = Sketch.tube(tangle, 0.018, Sketch.ink(Color(0.08, 0.08, 0.1)), self)
	_scribble.visible = false


# --- animation ------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


func tick(dt: float) -> void:
	_time += dt
	_anim_time += dt
	var t := _anim_time
	var k := clampf(speed01, 0.0, 1.0)
	var breathe := sin(_time * (1.6 if anim == &"tired_idle" else 2.4)) * 0.015
	# Defaults: neutral pose, then each animation overrides.
	var trunk_pos := Vector3(0, 0.22, 0)
	var trunk_rot := Vector3.ZERO
	var trunk_scale := Vector3.ONE * (1.0 + breathe * 0.5)
	var leg_rot: Array = [Vector3.ZERO, Vector3.ZERO]
	var arm_rot: Array = [Vector3(0, 0, -0.18), Vector3(0, 0, 0.18)]
	match anim:
		&"idle":
			arm_rot = [Vector3(0, 0, -0.18 - breathe * 2.0), Vector3(0, 0, 0.18 + breathe * 2.0)]
		&"tired_idle", &"sad":
			trunk_rot.x = 0.16 + breathe
			trunk_pos.y = 0.2
			arm_rot = [Vector3(0.1, 0, -0.06), Vector3(0.1, 0, 0.06)]
		&"walk", &"careful_step", &"run":
			var run := anim == &"run"
			var careful := anim == &"careful_step"
			_phase += dt * (3.0 if careful else (4.0 + k * 5.0))
			var swing := sin(_phase) * (0.45 if careful else (0.95 if run else 0.7)) * maxf(k, 0.35)
			leg_rot = [Vector3(swing, 0, 0), Vector3(-swing, 0, 0)]
			if careful:
				arm_rot = [Vector3(0, 0, -1.1 + sin(_time * 3.0) * 0.15), Vector3(0, 0, 1.1 - sin(_time * 3.0) * 0.15)]
				trunk_rot.x = 0.12
				leg_rot[0].x -= maxf(0.0, sin(_phase)) * 0.5
				leg_rot[1].x -= maxf(0.0, -sin(_phase)) * 0.5
			else:
				arm_rot = [Vector3(-swing * 0.9, 0, -0.2), Vector3(swing * 0.9, 0, 0.2)]
				trunk_rot.x = -(0.22 if run else 0.1) * k
			trunk_pos.y = 0.22 + absf(sin(_phase)) * (0.05 if run else 0.03) * maxf(k, 0.4)
		&"jump":
			var rising := vertical > 0.0
			leg_rot = [Vector3(0.5, 0, 0), Vector3(-0.35, 0, 0)]
			arm_rot = [Vector3(0, 0, -(2.2 if rising else 1.3)), Vector3(0, 0, 2.2 if rising else 1.3)]
			trunk_scale = Vector3(0.94, 1.1, 0.94) if rising else Vector3(1.0, 1.0, 1.0)
		&"lose_balance":
			var w := sin(_time * 16.0)
			arm_rot = [Vector3(w * 1.2, 0, -1.6 + w * 0.6), Vector3(-w * 1.2, 0, 1.6 + w * 0.6)]
			trunk_rot = Vector3(0.25 + sin(_time * 9.0) * 0.12, 0, sin(_time * 7.0) * 0.18)
			leg_rot = [Vector3(-0.4, 0, 0), Vector3(0.1, 0, 0)]
		&"push":
			trunk_rot.x = -0.32
			arm_rot = [Vector3(-1.45, 0, -0.1), Vector3(-1.45, 0, 0.1)]
			_phase += dt * 5.0
			var s := sin(_phase) * 0.5
			leg_rot = [Vector3(s + 0.3, 0, 0), Vector3(-s + 0.3, 0, 0)]
		&"recover", &"shake_head":
			trunk_rot.y = sin(t * 18.0) * 0.35 * maxf(0.0, 1.0 - t / 0.8)
			arm_rot = [Vector3(-0.6 - sin(t * 14.0) * 0.4, 0, -0.3), Vector3(0, 0, 0.18)]
			var squash := maxf(0.0, 1.0 - t * 2.0)
			trunk_scale = Vector3(1.0 + squash * 0.15, 1.0 - squash * 0.2, 1.0 + squash * 0.15)
		&"celebrate":
			var hop := absf(sin(_time * 5.5))
			trunk_pos.y = 0.22 + hop * 0.22
			arm_rot = [Vector3(0, 0, -(2.5 + sin(_time * 11.0) * 0.35)), Vector3(0, 0, 2.5 + sin(_time * 11.0 + 1.0) * 0.35)]
			leg_rot = [Vector3(-0.3 * hop, 0, 0), Vector3(-0.3 * hop, 0, 0)]
		&"hold":
			arm_rot = [Vector3(-2.0, 0, -0.45), Vector3(-2.0, 0, 0.45)]
			trunk_rot.x = -0.12
		&"look_around":
			trunk_rot.y = sin(t * 1.6) * 0.7
		&"fall":
			pass
	# Looking: lean the trunk toward the target and move the pupils.
	var pupil := Vector2.ZERO
	if _look != Vector3.INF and is_inside_tree():
		var local := to_local(_look) - Vector3(0, 0.75, 0)
		var flat := Vector2(local.x, -local.z)
		var yaw := clampf(atan2(-local.x, -local.z), -0.7, 0.7) if flat.length() > 0.01 else 0.0
		var pitch := clampf(atan2(local.y, maxf(flat.length(), 0.05)), -0.6, 0.6)
		if anim in [&"idle", &"tired_idle", &"sad", &"hold", &"walk", &"careful_step"]:
			trunk_rot.y += yaw * 0.6
			trunk_rot.x += -pitch * 0.35
		pupil = Vector2(clampf(-local.x * 2.0, -1, 1) if flat.length() > 0.01 else 0.0, clampf(pitch, -1, 1))
	# Pointing: right arm aims at the target.
	if _point != Vector3.INF and is_inside_tree() and anim != &"celebrate":
		var shoulder := _arms[1]
		var parent := shoulder.get_parent() as Node3D
		var local_dir := parent.global_basis.inverse() * (_point - shoulder.global_position)
		if local_dir.length() > 0.001:
			var q := Quaternion(Vector3.DOWN, local_dir.normalized())
			arm_rot[1] = q.get_euler()
	# Apply with smoothing.
	var s := minf(1.0, dt * 12.0)
	_trunk.position = _trunk.position.lerp(trunk_pos, s)
	_trunk.rotation = _trunk.rotation.lerp(trunk_rot, s)
	_trunk.scale = _trunk.scale.lerp(trunk_scale, s)
	for i in range(2):
		_legs[i].rotation = _legs[i].rotation.lerp(leg_rot[i], s)
		_arms[i].rotation = _arms[i].rotation.lerp(arm_rot[i], s)
	for i in range(2):
		_pupils[i].position = _pupils[i].position.lerp(Vector3(pupil.x * 0.012, pupil.y * 0.012, 0), s)
	# Blink.
	_blink -= dt
	var blink_amount := 0.1 if _blink < 0.12 else 1.0
	if _blink < 0.0:
		_blink = _rng.randf_range(2.0, 4.5)
	for e in _eyes:
		var open: float = e.get_meta("open", 1.0)
		e.scale = Vector3(1.0, maxf(0.08, open * blink_amount), 1.0)
	_body_mat.set_shader_parameter("glow", _glow)
	if _scribble.visible:
		_scribble.rotation.y += dt * 12.0
		_scribble.scale = Vector3.ONE * (1.0 + sin(_time * 30.0) * 0.08)
