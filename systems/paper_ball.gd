class_name PaperBall
extends Node3D
## A crumpled paper ball with a star: rolls on blocks and drawn planks, can be
## pushed by the pencil or by the player's hand, falls off edges, and comes
## back to its start when it lands on the blank page.

signal fell
signal bumped(strength: float)

const RADIUS := 0.32
const GRAVITY := 30.0
const FRICTION := 1.6
const BOUNCE := 0.35

var level: PageLevel
var velocity := Vector3.ZERO
var grounded: bool = false
var start := Vector3.ZERO
var locked: bool = false     # sits in the plate's socket for good

var _mesh: MeshInstance3D
var _respawn: float = -1.0
var _shadow: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 21
	_mesh = Sketch.crumpled_ball(RADIUS, Sketch.paper(Color(0.95, 0.94, 0.9)), _rng)
	add_child(_mesh)
	# Star drawn on the paper.
	var star := PackedVector3Array()
	for i in range(11):
		var a := PI * 0.5 + TAU * i / 10.0
		var r := 0.13 if i % 2 == 0 else 0.055
		star.append(Vector3(cos(a) * r, sin(a) * r, -RADIUS * 0.98))
	Sketch.tube(star, 0.01, Sketch.ink(), _mesh)


func setup(page: PageLevel, at: Vector3, shadow_parent: Node3D) -> void:
	level = page
	start = at
	position = at
	velocity = Vector3.ZERO
	locked = false
	_respawn = -1.0
	scale = Vector3.ONE
	if _shadow == null:
		_shadow = Sketch.blob_shadow(RADIUS * 1.1, shadow_parent)


func push(v: Vector3) -> void:
	if locked or _respawn >= 0.0:
		return
	velocity.x = v.x
	velocity.z = v.z


func simulate(dt: float) -> void:
	if _respawn >= 0.0:
		_respawn += dt
		if _respawn < 0.3:
			scale = Vector3.ONE * maxf(0.01, 1.0 - _respawn / 0.3)
		elif _respawn < 0.6:
			position = start
			velocity = Vector3.ZERO
			scale = Vector3.ONE * 0.01
		else:
			var t := clampf((_respawn - 0.6) / 0.3, 0.0, 1.0)
			scale = Vector3.ONE * maxf(0.01, t)
			if t >= 1.0:
				_respawn = -1.0
		_place_shadow()
		return
	if locked:
		velocity = Vector3.ZERO
		_place_shadow()
		return
	velocity.y -= GRAVITY * dt
	if grounded:
		var damp := exp(-FRICTION * dt)
		velocity.x *= damp
		velocity.z *= damp
	var feet := position - Vector3(0, RADIUS, 0)
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
	var ny := feet.y + velocity.y * dt
	if velocity.y <= 0.0 and ny <= ground:
		ny = ground
		if velocity.y < -4.0:
			bumped.emit(-velocity.y * 0.5)
		velocity.y = 0.0
		grounded = true
	elif grounded and velocity.y <= 0.0 and feet.y - ground < 0.12:
		ny = ground
		velocity.y = 0.0
	else:
		grounded = false
	feet.y = ny
	var moved := feet + Vector3(0, RADIUS, 0) - position
	position = feet + Vector3(0, RADIUS, 0)
	# Roll.
	var flat := Vector3(moved.x, 0, moved.z)
	if flat.length() > 0.0001:
		var axis := Vector3.UP.cross(flat.normalized())
		_mesh.transform.basis = Basis(axis, flat.length() / RADIUS) * _mesh.transform.basis
		_mesh.transform.basis = _mesh.transform.basis.orthonormalized()
	if grounded and feet.y < 0.05 or position.y < -3.0:
		_respawn = 0.0
		fell.emit()
	_place_shadow()


func is_respawning() -> bool:
	return _respawn >= 0.0


func _place_shadow() -> void:
	if _shadow == null or level == null:
		return
	var g := level.ground_height(position, 0.0)
	_shadow.visible = g > -50.0 and _respawn < 0.0
	_shadow.position = Vector3(position.x, g + 0.011, position.z)
	_shadow.scale = Vector3.ONE * clampf(1.0 - (position.y - RADIUS - g) * 0.25, 0.3, 1.0)
