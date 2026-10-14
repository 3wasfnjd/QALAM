class_name PencilHero
extends Node3D
## The last pencil: a placeholder body built from simple shapes (the real
## model comes later), with a working face, walk / jump / celebrate motion and
## its own small platformer physics against PageLevel. Units: page units,
## feet at the origin, facing -Z.

signal jumped
signal landed(impact: float)
signal fell
signal respawned
signal stepped

enum Face { HOPEFUL, TIRED, HAPPY, SURPRISED, SAD, DETERMINED }

const SPEED := 2.6
const ACCEL := 16.0
const GRAVITY := 36.0
const JUMP_SPEED := 8.8
const RADIUS := 0.2
const HEIGHT := 1.05
const COYOTE := 0.12
const JUMP_BUFFER := 0.14

var level: PageLevel
var velocity := Vector3.ZERO
var grounded: bool = true
var checkpoint := Vector3.ZERO
var face: int = Face.HOPEFUL
var celebrating: bool = false
var frozen: bool = false
var look_target: Node3D

var _coyote: float = 0.0
var _buffer: float = 0.0
var _yaw: float = 0.0
var _phase: float = 0.0
var _squash: float = 0.0
var _idle: float = 0.0
var _blink: float = 2.0
var _face_hold: float = 0.0
var _respawn: float = -1.0
var _time: float = 0.0
var _air_time: float = 0.0
var _last_step_sign: float = 1.0

var _trunk: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth: MeshInstance3D
var _mouth_mesh := ImmediateMesh.new()
var _mouth_o: MeshInstance3D
var _shadow: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_build()
	set_face(Face.HOPEFUL)


func setup(page: PageLevel, start: Vector3) -> void:
	level = page
	checkpoint = start
	position = start
	velocity = Vector3.ZERO
	grounded = true


# --- body ---------------------------------------------------------------------

func _build() -> void:
	var yellow := Sketch.paper(Sketch.YELLOW)
	var wood := Sketch.paper(Color(0.93, 0.78, 0.58))
	var lead := Sketch.paper(Sketch.GRAPHITE)
	var metal := Sketch.paper(Color(0.74, 0.75, 0.78))
	var pink := Sketch.paper(Sketch.PINK)
	var dark := Sketch.paper(Color(0.12, 0.1, 0.1))
	var white := Sketch.paper(Color(0.98, 0.97, 0.94))
	var leather := Sketch.paper(Sketch.LEATHER)
	var shoe := Sketch.paper(Color(0.42, 0.27, 0.16))

	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.07, 0.25, 0)
		add_child(hip)
		var leg := Sketch.cylinder(0.022, 0.022, 0.2, dark, hip, 6)
		leg.position.y = -0.1
		var boot := Sketch.sphere(0.07, shoe, hip, 10, 6)
		boot.scale = Vector3(1.0, 0.65, 1.35)
		boot.position = Vector3(0, -0.215, -0.03)
		_legs.append(hip)

	_trunk = Node3D.new()
	_trunk.position.y = 0.22
	add_child(_trunk)
	var eraser := Sketch.cylinder(0.14, 0.13, 0.11, pink, _trunk, 6)
	eraser.position.y = 0.055
	var ferrule := Sketch.cylinder(0.155, 0.155, 0.08, metal, _trunk, 6)
	ferrule.position.y = 0.15
	for y in [0.125, 0.175]:
		var ring := Sketch.cylinder(0.159, 0.159, 0.008, Sketch.paper(Color(0.55, 0.56, 0.6)), _trunk, 6)
		ring.position.y = y
	var body := Sketch.cylinder(0.15, 0.15, 0.48, yellow, _trunk, 6)
	body.position.y = 0.43
	body.rotation.y = PI / 6.0
	var cone := Sketch.cylinder(0.04, 0.15, 0.17, wood, _trunk, 6)
	cone.position.y = 0.755
	cone.rotation.y = PI / 6.0
	var tip := Sketch.cylinder(0.0, 0.04, 0.07, lead, _trunk, 6)
	tip.position.y = 0.875
	# Worn scratches on the paint.
	var ink_mat := Sketch.ink(Color(0.55, 0.4, 0.15))
	for i in range(5):
		var a := _rng.randf_range(0.75, 1.6) * (1.0 if i % 2 == 0 else -1.0)
		var y := _rng.randf_range(0.25, 0.62)
		var p := Vector3(sin(a) * 0.152, y, -cos(a) * 0.152)
		Sketch.tube(PackedVector3Array([p, p + Vector3(_rng.randf_range(-0.03, 0.03), 0.04, 0)]), 0.004, ink_mat, _trunk)

	# Face.
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(side * 0.058, 0.53, -0.128)
		_trunk.add_child(eye)
		var white_ball := Sketch.sphere(0.05, white, eye, 12, 8)
		white_ball.scale = Vector3(0.9, 1.15, 0.55)
		var pupil := Sketch.sphere(0.03, dark, eye, 10, 6)
		pupil.scale = Vector3(1, 1.15, 0.6)
		pupil.position = Vector3(side * -0.006, -0.008, -0.022)
		var shine := Sketch.sphere(0.009, white, eye, 6, 4)
		shine.position = Vector3(0.008, 0.01, -0.04)
		_eyes.append(eye)
		var brow := Sketch.box(Vector3(0.065, 0.016, 0.014), dark, _trunk)
		brow.position = Vector3(side * 0.06, 0.615, -0.14)
		_brows.append(brow)
		var cheek := Sketch.sphere(0.022, Sketch.paper(Color(0.98, 0.6, 0.55)), _trunk, 8, 4)
		cheek.scale = Vector3(1.2, 0.7, 0.4)
		cheek.position = Vector3(side * 0.1, 0.47, -0.13)
	_mouth = Sketch.mesh_node(_mouth_mesh, Sketch.ink(Color(0.25, 0.08, 0.07)), _trunk)
	_mouth_o = Sketch.sphere(0.024, Sketch.paper(Color(0.35, 0.08, 0.08)), _trunk, 8, 6)
	_mouth_o.scale = Vector3(0.9, 1.2, 0.4)
	_mouth_o.position = Vector3(0, 0.445, -0.142)

	# Arms with cartoon gloves.
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.16, 0.42, 0)
		_trunk.add_child(shoulder)
		var arm := Sketch.cylinder(0.018, 0.018, 0.2, dark, shoulder, 6)
		arm.position.y = -0.1
		var glove := Sketch.sphere(0.048, white, shoulder, 10, 6)
		glove.position.y = -0.215
		_arms.append(shoulder)
	# Old satchel on the right hip with a strap across the body.
	var bag := Sketch.box(Vector3(0.05, 0.1, 0.13), leather, _trunk)
	bag.position = Vector3(0.18, 0.22, 0.0)
	var flap := Sketch.box(Vector3(0.054, 0.045, 0.134), Sketch.paper(Color(0.38, 0.23, 0.13)), _trunk)
	flap.position = Vector3(0.18, 0.255, 0.0)
	var strap := PackedVector3Array()
	for i in range(9):
		var t := i / 8.0
		var ang := lerpf(-0.3, PI + 0.5, t)
		strap.append(Vector3(cos(ang) * 0.158, lerpf(0.27, 0.6, sin(t * PI) * 0.9 + t * 0.1), sin(ang) * 0.158))
	Sketch.tube(strap, 0.012, Sketch.ink(Color(0.36, 0.22, 0.12)), _trunk)


func make_shadow(parent: Node3D) -> void:
	_shadow = Sketch.blob_shadow(0.24, parent)


# --- face -----------------------------------------------------------------------

func set_face(f: int, hold: float = 0.0) -> void:
	if _face_hold > 0.0 and hold <= 0.0:
		return
	_face_hold = hold
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
			smile = 0.15
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


# --- physics --------------------------------------------------------------------

## One physics tick. `move` is the wanted direction in page space (x, z),
## length 0..1. Returns true on the frame it jumped.
func simulate(dt: float, move: Vector2, jump_pressed: bool) -> bool:
	_time += dt
	if _respawn >= 0.0:
		_tick_respawn(dt)
		return false
	if frozen or level == null:
		velocity = Vector3.ZERO
		_animate(dt, 0.0)
		return false
	if move.length() > 1.0:
		move = move.normalized()
	var want := Vector3(move.x, 0, move.y) * SPEED
	var accel := ACCEL if grounded else ACCEL * 0.55
	velocity.x = move_toward(velocity.x, want.x, accel * dt)
	velocity.z = move_toward(velocity.z, want.z, accel * dt)
	if jump_pressed:
		_buffer = JUMP_BUFFER
	_buffer = maxf(0.0, _buffer - dt)
	_coyote = COYOTE if grounded else maxf(0.0, _coyote - dt)
	var did_jump := false
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_SPEED
		grounded = false
		_coyote = 0.0
		_buffer = 0.0
		_squash = -0.6
		did_jump = true
		jumped.emit()
	velocity.y -= GRAVITY * dt
	var p := position
	var nx := p + Vector3(velocity.x * dt, 0, 0)
	if level.blocked(nx, RADIUS, HEIGHT):
		velocity.x = 0.0
	else:
		p = nx
	var nz := p + Vector3(0, 0, velocity.z * dt)
	if level.blocked(nz, RADIUS, HEIGHT):
		velocity.z = 0.0
	else:
		p = nz
	var ground := level.ground_height(p, RADIUS * 0.55)
	var ny := p.y + velocity.y * dt
	var was_grounded := grounded
	if velocity.y <= 0.0 and ny <= ground:
		if not was_grounded:
			var impact := clampf(-velocity.y / 14.0, 0.0, 1.0)
			_squash = 0.4 + impact * 0.6
			landed.emit(impact)
		ny = ground
		velocity.y = 0.0
		grounded = true
	elif was_grounded and velocity.y <= 0.0 and p.y - ground < 0.16:
		ny = ground  # walk down a gentle plank
		velocity.y = 0.0
	else:
		grounded = false
	p.y = ny
	position = p
	_air_time = 0.0 if grounded else _air_time + dt
	if grounded:
		var on := level.standing_on(p, RADIUS * 0.55)
		if on != "" and level.checkpoints.has(on) and on != "gate":
			checkpoint = level.checkpoints[on]
		if p.y < 0.05:
			_start_respawn()
	elif p.y < -3.0:
		_start_respawn()
	_animate(dt, Vector2(velocity.x, velocity.z).length())
	return did_jump


func _start_respawn() -> void:
	_respawn = 0.0
	velocity = Vector3.ZERO
	set_face(Face.SURPRISED, 0.6)
	fell.emit()


func _tick_respawn(dt: float) -> void:
	_respawn += dt
	if _respawn < 0.35:
		scale = Vector3.ONE * maxf(0.01, 1.0 - _respawn / 0.35)
		return
	if _respawn < 0.45:
		position = checkpoint
		scale = Vector3.ONE * 0.01
		return
	var t := clampf((_respawn - 0.45) / 0.35, 0.0, 1.0)
	scale = Vector3.ONE * maxf(0.01, t + sin(t * PI) * 0.2)
	if t >= 1.0:
		scale = Vector3.ONE
		_respawn = -1.0
		grounded = true
		set_face(Face.SAD, 0.9)
		respawned.emit()


func is_respawning() -> bool:
	return _respawn >= 0.0


## Snaps back to the checkpoint without the poof (used by tests / restart).
func reset_to(p: Vector3) -> void:
	position = p
	checkpoint = p
	velocity = Vector3.ZERO
	grounded = true
	_respawn = -1.0
	scale = Vector3.ONE


# --- animation ------------------------------------------------------------------

func _animate(dt: float, speed: float) -> void:
	_face_hold = maxf(0.0, _face_hold - dt)
	var moving := speed > 0.25
	if moving:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		_yaw = lerp_angle(_yaw, target_yaw, minf(1.0, dt * 12.0))
		_idle = 0.0
	else:
		_idle += dt
		if look_target and _idle > 1.5 and not celebrating:
			var parent_local := (get_parent() as Node3D).to_local(look_target.global_position) - position
			var target_yaw := atan2(-parent_local.x, -parent_local.z)
			_yaw = lerp_angle(_yaw, target_yaw, minf(1.0, dt * 2.0))
	rotation = Vector3(0, _yaw, 0)
	# Face follows what's happening.
	if _face_hold <= 0.0:
		if celebrating:
			set_face(Face.HAPPY)
		elif not grounded and velocity.y < -6.0:
			set_face(Face.SURPRISED)
		elif moving:
			set_face(Face.DETERMINED)
		elif _idle > 7.0:
			set_face(Face.TIRED)
		elif face != Face.HOPEFUL and _idle > 0.4:
			set_face(Face.HOPEFUL)
	# Walk cycle.
	var k := clampf(speed / SPEED, 0.0, 1.0)
	_phase += dt * (4.0 + speed * 4.2)
	var swing := sin(_phase) * 0.75 * k
	var step_sign := signf(sin(_phase))
	if grounded and moving and step_sign != _last_step_sign:
		stepped.emit()
	_last_step_sign = step_sign
	_squash = move_toward(_squash, 0.0, dt * 4.0)
	var breathe := sin(_time * 2.4) * 0.015 * (1.0 - k)
	var sq := _squash
	if celebrating:
		var hop := absf(sin(_time * 5.5))
		_trunk.position.y = 0.22 + hop * 0.22
		for i in range(2):
			var side := -1.0 if i == 0 else 1.0
			_arms[i].rotation = Vector3(0, 0, side * (2.5 + sin(_time * 11.0 + i) * 0.35))
			_legs[i].rotation = Vector3(-0.3 * hop, 0, 0)
			_legs[i].position.y = 0.25 + hop * 0.22
		_trunk.scale = Vector3(1, 1, 1)
		_update_eyes(dt)
		_place_shadow()
		return
	if grounded:
		for i in range(2):
			var s := swing if i == 0 else -swing
			_legs[i].rotation = Vector3(s, 0, 0)
			_legs[i].position.y = 0.25
			_arms[i].rotation = Vector3(-s * 0.8, 0, (0.18 + breathe * 3.0) * (-1.0 if i == 0 else 1.0))
		_trunk.position.y = 0.22 + absf(sin(_phase)) * 0.035 * k
		_trunk.rotation.x = -0.12 * k
	else:
		var rising := velocity.y > 0.0
		for i in range(2):
			var side := -1.0 if i == 0 else 1.0
			_legs[i].rotation = Vector3(0.5 if i == 0 else -0.35, 0, 0)
			_arms[i].rotation = Vector3(0, 0, side * (2.2 if rising else 1.3))
		_trunk.rotation.x = 0.05
	var stretch := 1.0 - sq * 0.22 + breathe
	_trunk.scale = Vector3(1.0 + sq * 0.14, stretch, 1.0 + sq * 0.14)
	_update_eyes(dt)
	_place_shadow()


func _update_eyes(dt: float) -> void:
	_blink -= dt
	var blink_amount := 1.0
	if _blink < 0.12:
		blink_amount = 0.1
	if _blink < 0.0:
		_blink = _rng.randf_range(2.0, 4.5)
	for e in _eyes:
		var open: float = e.get_meta("open", 1.0)
		e.scale = Vector3(1.0, maxf(0.08, open * blink_amount), 1.0)


func _place_shadow() -> void:
	if _shadow == null or level == null:
		return
	var g := level.ground_height(position + Vector3(0, 0.05, 0), 0.0)
	_shadow.visible = g > -50.0
	_shadow.position = Vector3(position.x, g + 0.012, position.z)
	var h := clampf(position.y - g, 0.0, 3.0)
	_shadow.scale = Vector3.ONE * clampf(1.0 - h * 0.25, 0.35, 1.0) * scale.x
