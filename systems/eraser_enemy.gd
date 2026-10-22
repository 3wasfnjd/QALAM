class_name EraserEnemy
extends Node3D
## The Eraser: a grumpy pink rubber that crawls out of the crack and rubs out the
## lines you drew (their graphite comes back to you, the path is gone). It shoves
## the pencil aside when it bumps into him. Draw a closed loop round it to trap it —
## it scribbles away into pink dust; flick it off the table with your hand and it
## climbs back out of the crack a little later. Page units; rules only read
## PageLevel, so the body can be swapped for a real model.

signal rubbed(path_id: String)
signal trapped
signal knocked_off

enum State { HIDDEN, EMERGING, HUNTING, RUBBING, GONE }

const SIZE := Vector3(0.62, 0.34, 0.38)
const SPEED := 0.75
const REACH := 0.4             # rubs a path point this close (xz)
const RUB_TIME := 1.6
const BUMP_RADIUS := 0.55
const RETURN_TIME := 4.0
const GRAVITY := 14.0

var level: PageLevel
var state: int = State.HIDDEN
var velocity := Vector3.ZERO
var home := Vector3.ZERO       # where it climbs out of the crack
var target_id: String = ""
var rub: float = 0.0
var _t: float = 0.0
var _away: float = -1.0
var _body: Node3D
var _sleeve: MeshInstance3D
var _brows: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 77
	_body = Node3D.new()
	add_child(_body)
	var rubber := Sketch.paper(Sketch.PINK)
	var block := Sketch.box(SIZE, rubber, _body)
	block.position.y = SIZE.y * 0.5
	_sleeve = Sketch.box(Vector3(SIZE.x * 0.42, SIZE.y + 0.02, SIZE.z + 0.02), Sketch.paper(Color(0.36, 0.5, 0.82)), _body)
	_sleeve.position = Vector3(-SIZE.x * 0.24, SIZE.y * 0.5, 0)
	Sketch.sketch_box_edges(SIZE, Vector3(0, SIZE.y * 0.5, 0), 0.012, _rng, _body)
	# An angry face on the front (+z): two eyes and slanted brows.
	var ink := Sketch.ink(Sketch.INK)
	for side in [-1.0, 1.0]:
		var eye := Sketch.sphere(0.035, ink, _body, 8, 5)
		eye.position = Vector3(0.12 + side * 0.07, SIZE.y * 0.6, SIZE.z * 0.5 + 0.01)
		var brow := Node3D.new()
		_body.add_child(brow)
		brow.position = Vector3(0.12 + side * 0.07, SIZE.y * 0.78, SIZE.z * 0.5 + 0.012)
		Sketch.tube(PackedVector3Array([Vector3(-0.05, side * 0.02, 0), Vector3(0.05, -side * 0.02, 0)]), 0.012, ink, brow)
		_brows.append(brow)
	visible = false


func setup(page: PageLevel, crack_at: Vector3) -> void:
	level = page
	home = crack_at


func active() -> bool:
	return state == State.HUNTING or state == State.RUBBING or state == State.EMERGING


## Climb out of the crack and start hunting lines.
func emerge() -> void:
	state = State.EMERGING
	_t = 0.0
	position = home - Vector3(0, SIZE.y, 0)
	velocity = Vector3.ZERO
	visible = true


func push(v: Vector3) -> void:
	if not active():
		return
	velocity += v
	state = State.HUNTING
	rub = 0.0


func trap() -> void:
	if state == State.GONE:
		return
	state = State.GONE
	visible = false
	trapped.emit()


func base() -> Vector3:
	return position


func _ground(p: Vector3) -> float:
	# It crawls over everything: the highest surface under it, from the page up.
	return level.ground_height(Vector3(p.x, 50.0, p.z), SIZE.z * 0.4)


## The nearest point of any drawn path: {id, point} or {}.
func _nearest_path_point() -> Dictionary:
	var best := {}
	var best_d := INF
	for path in level.paths:
		var pts: PackedVector3Array = path.points
		for k in range(0, pts.size(), 2):
			var d := Vector2(pts[k].x - position.x, pts[k].z - position.z).length()
			if d < best_d:
				best_d = d
				best = {"id": path.id, "point": pts[k], "distance": d}
	return best


func simulate(dt: float, hero: PencilBody) -> void:
	_t += dt
	match state:
		State.HIDDEN, State.GONE:
			if _away >= 0.0:
				_away += dt
				if _away > RETURN_TIME:
					_away = -1.0
					emerge()
			return
		State.EMERGING:
			position = home - Vector3(0, SIZE.y * (1.0 - smoothstep(0.0, 1.0, _t / 1.2)), 0)
			if _t >= 1.2:
				position = home
				state = State.HUNTING
			_animate(dt, 0.0)
			return
	var goal := _nearest_path_point()
	var move := Vector2.ZERO
	if goal.is_empty():
		# No lines to eat: it wanders towards the pencil to bully him.
		if hero and hero.visible:
			var to := Vector2(hero.position.x - position.x, hero.position.z - position.z)
			if to.length() > BUMP_RADIUS * 0.8:
				move = to.normalized() * 0.5
		state = State.HUNTING
		rub = 0.0
	else:
		var p: Vector3 = goal.point
		var to := Vector2(p.x - position.x, p.z - position.z)
		if goal.distance > REACH:
			move = to.normalized()
			state = State.HUNTING
			rub = 0.0
		else:
			if goal.id != target_id:
				target_id = goal.id
				rub = 0.0
			state = State.RUBBING
			rub += dt / RUB_TIME
			if rub >= 1.0:
				rub = 0.0
				rubbed.emit(target_id)
	# Its own push (a flick) decays; walking adds a steady crawl.
	velocity.x = move_toward(velocity.x, move.x * SPEED, dt * 4.0)
	velocity.z = move_toward(velocity.z, move.y * SPEED, dt * 4.0)
	var ground := _ground(position)
	if position.y > ground + 0.02:
		velocity.y -= GRAVITY * dt
	else:
		velocity.y = maxf(velocity.y, 0.0)
	position += velocity * dt
	ground = _ground(position)
	if position.y < ground:
		position.y = ground
		velocity.y = 0.0
	if position.y < -2.0:
		# Fell off the table: gone for a while, then it climbs out again.
		state = State.HIDDEN
		visible = false
		_away = 0.0
		knocked_off.emit()
		return
	if Vector2(velocity.x, velocity.z).length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), minf(1.0, dt * 6.0))
	# Bumping into the pencil shoves him aside.
	if hero and hero.visible and not hero.is_respawning():
		var d := Vector2(hero.position.x - position.x, hero.position.z - position.z)
		if d.length() < BUMP_RADIUS and absf(hero.position.y - position.y) < 0.6:
			var n := d.normalized() if d.length() > 0.001 else Vector2(1, 0)
			hero.velocity += Vector3(n.x, 0.6, n.y) * 2.2
			hero.face(PencilRig.Face.SURPRISED, 0.8)
	_animate(dt, rub if state == State.RUBBING else 0.0)


func _animate(_dt: float, rubbing: float) -> void:
	# Squash while crawling, scrub side to side while rubbing.
	var crawl := sin(_t * 10.0) * 0.06
	_body.scale = Vector3(1.0 + crawl, 1.0 - crawl, 1.0)
	_body.position.x = sin(_t * 26.0) * 0.06 * (1.0 if rubbing > 0.0 else 0.0)
	for b in _brows:
		b.rotation.z = sin(_t * 3.0) * 0.1


## True when the closed loop `pts` (page units) surrounds the eraser on the table.
func inside_loop(pts: PackedVector3Array) -> bool:
	if not active() or pts.size() < 4:
		return false
	var inside := false
	var j := pts.size() - 1
	for i in range(pts.size()):
		var a := pts[i]
		var b := pts[j]
		if (a.z > position.z) != (b.z > position.z):
			var x := a.x + (position.z - a.z) / (b.z - a.z) * (b.x - a.x)
			if position.x < x:
				inside = not inside
		j = i
	return inside
