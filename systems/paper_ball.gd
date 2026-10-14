class_name PaperBall
extends Node3D
## Crumpled paper ball with a star. Rolls down drawn slopes (gravity along the
## surface), slows on rough paper, flies off the end of a steep ramp, can be
## pushed by the pencil or flicked by the player's hand, and comes back to its
## start when it lands on the blank page.

signal fell
signal bumped(strength: float)

const RADIUS := 0.3
const GRAVITY := 14.0
const ROLL := 0.71               # solid-ish sphere rolling: 5/7 of g along a slope
const RESIST_PATH := 2.0         # rolling resistance (units/s²) on graphite
const RESIST_PAPER := 3.6        # … and on paper blocks
const BOUNCE := 0.35

var level: PageLevel
var velocity := Vector3.ZERO
var grounded: bool = false
var start := Vector3.ZERO        # base point (where it touches the ground)
var locked: bool = false

var _mesh: MeshInstance3D
var _respawn: float = -1.0
var _shadow: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 21
	_mesh = Sketch.crumpled_ball(RADIUS, Sketch.paper(Color(0.95, 0.93, 0.86)), _rng)
	add_child(_mesh)
	var star := PackedVector3Array()
	for i in range(11):
		var a := PI * 0.5 + TAU * i / 10.0
		var r := 0.12 if i % 2 == 0 else 0.05
		star.append(Vector3(cos(a) * r, sin(a) * r, -RADIUS * 0.98))
	Sketch.tube(star, 0.01, Sketch.ink(), _mesh)


func setup(page: PageLevel, base: Vector3, shadow_parent: Node3D) -> void:
	level = page
	start = base
	position = base + Vector3(0, RADIUS, 0)
	velocity = Vector3.ZERO
	locked = false
	grounded = true
	_respawn = -1.0
	scale = Vector3.ONE
	if _shadow == null:
		_shadow = Sketch.blob_shadow(RADIUS * 1.1, shadow_parent)


func base() -> Vector3:
	return position - Vector3(0, RADIUS, 0)


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func push(v: Vector3) -> void:
	if locked or _respawn >= 0.0:
		return
	velocity.x = v.x
	velocity.z = v.z


func is_respawning() -> bool:
	return _respawn >= 0.0


func simulate(dt: float) -> void:
	if _respawn >= 0.0:
		_tick_respawn(dt)
		return
	if locked:
		velocity = Vector3.ZERO
		_place_shadow()
		return
	var feet := base()
	if grounded:
		var g := level.slope_at(feet)
		var slope_len := g.length()
		if slope_len > 0.001:
			# Gravity along the slope: g·sinθ toward downhill.
			var sin_t := slope_len / sqrt(1.0 + slope_len * slope_len)
			var down := -g / slope_len
			velocity.x += down.x * GRAVITY * ROLL * sin_t * dt
			velocity.z += down.y * GRAVITY * ROLL * sin_t * dt
		var resist := RESIST_PATH if level.on_path(feet, 0.0) != "" else RESIST_PAPER
		var flat := Vector2(velocity.x, velocity.z)
		var s := flat.length()
		if s > 0.0:
			var ns := maxf(0.0, s - resist * dt) * exp(-0.25 * dt)
			velocity.x *= ns / s
			velocity.z *= ns / s
	else:
		velocity.y -= GRAVITY * dt
	var nx := feet + Vector3(velocity.x * dt, 0, 0)
	if level.blocked(nx, RADIUS * 0.85, RADIUS * 2.0):
		if absf(velocity.x) > 1.0:
			bumped.emit(absf(velocity.x))
		velocity.x *= -BOUNCE
	else:
		feet = nx
	var nz := feet + Vector3(0, 0, velocity.z * dt)
	if level.blocked(nz, RADIUS * 0.85, RADIUS * 2.0):
		if absf(velocity.z) > 1.0:
			bumped.emit(absf(velocity.z))
		velocity.z *= -BOUNCE
	else:
		feet = nz
	var ground := level.ground_height(feet, 0.0)
	var old_y := feet.y
	var horiz := Vector2(velocity.x, velocity.z).length() * dt
	if grounded and feet.y - ground <= 0.06 + horiz * 2.2 and velocity.y <= 0.5:
		# Stay on the surface (rolling down a slope keeps contact).
		feet.y = ground
		velocity.y = (feet.y - old_y) / dt if dt > 0.0 else 0.0
	else:
		var ny := feet.y + velocity.y * dt
		if velocity.y <= 0.0 and ny <= ground:
			if velocity.y < -4.0:
				bumped.emit(-velocity.y * 0.5)
			ny = ground
			velocity.y = 0.0
			grounded = true
		else:
			grounded = false
		feet.y = ny
	if grounded:
		grounded = absf(feet.y - ground) < 0.001
	var moved := feet + Vector3(0, RADIUS, 0) - position
	position = feet + Vector3(0, RADIUS, 0)
	var flat_move := Vector3(moved.x, 0, moved.z)
	if _mesh and flat_move.length() > 0.0001:
		var axis := Vector3.UP.cross(flat_move.normalized())
		_mesh.transform.basis = (Basis(axis, flat_move.length() / RADIUS) * _mesh.transform.basis).orthonormalized()
	if (grounded and feet.y < 0.05) or position.y < -3.0:
		_respawn = 0.0
		fell.emit()
	_place_shadow()


func _tick_respawn(dt: float) -> void:
	_respawn += dt
	if _respawn < 0.3:
		scale = Vector3.ONE * maxf(0.01, 1.0 - _respawn / 0.3)
	elif _respawn < 0.7:
		position = start + Vector3(0, RADIUS, 0)
		velocity = Vector3.ZERO
		grounded = true
		scale = Vector3.ONE * 0.01
	else:
		var t := clampf((_respawn - 0.7) / 0.3, 0.0, 1.0)
		scale = Vector3.ONE * maxf(0.01, t)
		if t >= 1.0:
			_respawn = -1.0
	_place_shadow()


func _place_shadow() -> void:
	if _shadow == null or level == null:
		return
	var g := level.ground_height(position, 0.0)
	_shadow.visible = g > -50.0 and _respawn < 0.0
	_shadow.position = Vector3(position.x, g + 0.011, position.z)
	_shadow.scale = Vector3.ONE * clampf(1.0 - (position.y - RADIUS - g) * 0.25, 0.3, 1.0)
