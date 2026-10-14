class_name PencilBody
extends Node3D
## The pencil's BEHAVIOUR: platformer physics on PageLevel, safe-point
## respawn (as a scribble that gets redrawn), edge teetering, sliding on steep
## lines, pushing, and a small action queue for wordless story beats. All the
## look lives in `rig` (PencilRig), which can be swapped for a GLB later.
## Units: page units, feet at the origin, facing -Z.

signal jumped
signal landed(impact: float)
signal fell(at: Vector3)
signal redrawn
signal stepped
signal action_done(tag: String)

const WALK_SPEED := 2.2
const RUN_SPEED := 3.2
const TIRED_SPEED := 1.25
const ACCEL := 14.0
const GRAVITY := 36.0
const JUMP_SPEED := 8.0
const RADIUS := 0.2
const HEIGHT := 1.05
const COYOTE := 0.1
const JUMP_BUFFER := 0.14
const TEETER_TIME := 0.4

var level: PageLevel
var rig: PencilRig
var velocity := Vector3.ZERO
var grounded: bool = true
var safe_point := Vector3.ZERO
var tired: bool = true
var pushing: bool = false
var celebrating: bool = false
var holding: bool = false
var look_target: Variant = null      # Node3D, Vector3 (global) or null
var player_head: Node3D

var _yaw: float = 0.0
var _coyote: float = 0.0
var _buffer: float = 0.0
var _teeter: float = 0.0
var _sliding: bool = false
var _respawn: float = -1.0
var _idle: float = 0.0
var _face_hold: float = 0.0
var _anim_hold: float = 0.0
var _held_anim: StringName = &""
var _fresh_path: String = ""
var _fresh_time: float = 0.0
var _known_paths: Dictionary = {}
var _actions: Array = []
var _action_time: float = 0.0
var _last_step: float = 0.0
var _shadow: MeshInstance3D


func _ready() -> void:
	rig = PencilRig.new()
	add_child(rig)


func setup(page: PageLevel, at: Vector3) -> void:
	level = page
	position = at
	safe_point = at
	velocity = Vector3.ZERO
	grounded = true


func make_shadow(parent: Node3D) -> void:
	_shadow = Sketch.blob_shadow(0.24, parent)


# --- story beats ----------------------------------------------------------------------

## Queue wordless actions; player input is ignored while any are pending.
## {do: walk_to|wait|look|point|turn|face|anim|call, ...} — see _run_action.
func queue(actions: Array) -> void:
	_actions.append_array(actions)


func scripted() -> bool:
	return not _actions.is_empty()


func clear_script() -> void:
	_actions.clear()
	rig.point_at(Vector3.INF)


func face(f: int, hold: float = 1.2) -> void:
	_face_hold = hold
	rig.set_face(f)


func emote(anim: StringName, seconds: float) -> void:
	_held_anim = anim
	_anim_hold = seconds


func _run_action(dt: float) -> Vector2:
	var a: Dictionary = _actions[0]
	_action_time += dt
	var move := Vector2.ZERO
	var done := false
	if a.has("look"):
		look_target = a.look
	match a.do:
		"walk_to":
			var to: Vector3 = a.to
			var d := Vector2(to.x - position.x, to.z - position.z)
			if d.length() < 0.08 or _action_time > a.get("timeout", 8.0):
				done = true
			else:
				move = d.normalized() * float(a.get("speed", 1.0))
				if a.has("anim"):
					_held_anim = a.anim
					_anim_hold = 0.1
		"wait":
			if a.has("anim"):
				_held_anim = a.anim
				_anim_hold = 0.1
			done = _action_time >= a.t
		"look":
			look_target = a.at
			done = _action_time >= a.t
		"point":
			look_target = a.at
			rig.point_at(_global_of(a.at))
			done = _action_time >= a.t
			if done:
				rig.point_at(Vector3.INF)
		"turn":
			var target := _global_of(a.to)
			var local := (get_parent() as Node3D).to_local(target) - position
			_yaw = lerp_angle(_yaw, atan2(-local.x, -local.z), minf(1.0, dt * 6.0))
			done = _action_time >= a.get("t", 0.4)
		"face":
			face(a.face, a.get("hold", 1.5))
			done = true
		"anim":
			_held_anim = a.anim
			_anim_hold = a.t
			done = _action_time >= a.t
		"call":
			(a.fn as Callable).call()
			done = true
	if done:
		_actions.pop_front()
		_action_time = 0.0
		if a.has("tag"):
			action_done.emit(a.tag)
	return move


func _global_of(v: Variant) -> Vector3:
	if v is Node3D:
		return (v as Node3D).global_position
	if v is Vector3:
		return v
	return Vector3.INF


# --- physics ----------------------------------------------------------------------------

## One physics tick. `move` = wanted direction in page space (x, z), length
## 0..1. Returns true on the tick it jumped.
func simulate(dt: float, move: Vector2, run: bool, jump_pressed: bool) -> bool:
	_face_hold = maxf(0.0, _face_hold - dt)
	_anim_hold = maxf(0.0, _anim_hold - dt)
	if _respawn >= 0.0:
		_tick_respawn(dt)
		_animate(dt, 0.0)
		return false
	if level == null:
		return false
	if scripted():
		move = _run_action(dt)
		run = false
		jump_pressed = false
	if move.length() > 1.0:
		move = move.normalized()
	var top_speed := TIRED_SPEED if tired else (RUN_SPEED if run else WALK_SPEED)
	if _fresh_path != "":
		top_speed = minf(top_speed, 1.1)  # careful on a line he hasn't trusted yet
	var want := Vector3(move.x, 0, move.y) * top_speed
	var accel := ACCEL if grounded else ACCEL * 0.5
	velocity.x = move_toward(velocity.x, want.x, accel * dt)
	velocity.z = move_toward(velocity.z, want.z, accel * dt)
	if jump_pressed:
		_buffer = JUMP_BUFFER
	_buffer = maxf(0.0, _buffer - dt)
	_coyote = COYOTE if grounded else maxf(0.0, _coyote - dt)
	var did_jump := false
	if _buffer > 0.0 and _coyote > 0.0 and not _sliding:
		velocity.y = JUMP_SPEED * (0.85 if tired else 1.0)
		grounded = false
		_coyote = 0.0
		_buffer = 0.0
		did_jump = true
		jumped.emit()
	# Sliding down a line that is too steep.
	_sliding = false
	if grounded and level.on_path(position, 0.05) != "":
		var g := level.slope_at(position)
		if g.length() > PageLevel.SLIDE_SLOPE:
			_sliding = true
			var down := -g.normalized()
			velocity.x += down.x * 9.0 * dt
			velocity.z += down.y * 9.0 * dt
	velocity.y -= GRAVITY * dt
	var p := position
	var step := Vector3(velocity.x * dt, 0, velocity.z * dt)
	var candidate := _try_axis(p, Vector3(step.x, 0, 0))
	candidate = _try_axis(candidate, Vector3(0, 0, step.z))
	# Edge teeter: stepping off a drop needs a moment of insistence.
	var teetering := false
	if grounded and not _sliding and not did_jump and move.length() > 0.1:
		var ahead := level.ground_height(candidate + Vector3(0, 0.01, 0), RADIUS * 0.3)
		if ahead < p.y - 0.45:
			_teeter += dt
			if _teeter < TEETER_TIME and not scripted():
				candidate = p
				velocity.x = 0.0
				velocity.z = 0.0
				teetering = true
		else:
			_teeter = 0.0
	else:
		_teeter = 0.0
	p = candidate
	var ground := level.ground_height(p, RADIUS * 0.55)
	var ny := p.y + velocity.y * dt
	if velocity.y <= 0.0 and ny <= ground:
		if not grounded:
			var impact := clampf(-velocity.y / 14.0, 0.0, 1.0)
			landed.emit(impact)
		ny = ground
		velocity.y = 0.0
		grounded = true
	elif grounded and velocity.y <= 0.0 and p.y - ground < 0.16 + Vector2(step.x, step.z).length() * 1.3:
		ny = ground  # walk down slopes without hopping
		velocity.y = 0.0
	else:
		grounded = false
	p.y = ny
	position = p
	if grounded:
		var on := level.standing_on(p, 0.0)
		if on != "" and level.edge_distance(p) > 0.3:
			safe_point = p
		var path_id := level.on_path(p, 0.05)
		if path_id != "" and not _known_paths.has(path_id):
			_known_paths[path_id] = true
			_fresh_path = path_id
			_fresh_time = 0.0
		if p.y < 0.05:
			_start_respawn()
	elif p.y < -3.0:
		_start_respawn()
	if _fresh_path != "":
		_fresh_time += dt
		if _fresh_time > 1.2 or level.on_path(p, 0.05) != _fresh_path:
			_fresh_path = ""
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.25:
		_yaw = lerp_angle(_yaw, atan2(-velocity.x, -velocity.z), minf(1.0, dt * 12.0))
		_idle = 0.0
	else:
		_idle += dt
	rotation = Vector3(0, _yaw, 0)
	if grounded and speed > 0.3:
		_last_step += dt * speed
		if _last_step > 0.32:
			_last_step = 0.0
			stepped.emit()
	_animate(dt, speed, teetering)
	return did_jump


## Moves along one axis unless a wall or a too-steep line is in the way.
func _try_axis(p: Vector3, delta: Vector3) -> Vector3:
	if delta.length() < 0.000001:
		return p
	var c := p + delta
	if level.blocked(c, RADIUS, HEIGHT):
		if absf(delta.x) > 0.0:
			velocity.x = 0.0
		else:
			velocity.z = 0.0
		return p
	if grounded:
		# Compare the surface right under the feet now and after the step.
		var g_here := level.ground_height(p + Vector3(0, 0.02, 0), 0.0)
		var g_new := level.ground_height(Vector3(c.x, g_here + 0.02, c.z), 0.0)
		var rise := g_new - g_here
		if rise > 0.03 and rise > delta.length() * PageLevel.MAX_WALK_SLOPE + 0.02 and rise < PageLevel.STEP + 0.01:
			# Too steep to walk up: he stops at the bottom.
			if absf(delta.x) > 0.0:
				velocity.x = 0.0
			else:
				velocity.z = 0.0
			return p
	return c


func _start_respawn() -> void:
	_respawn = 0.0
	velocity = Vector3.ZERO
	clear_script()
	rig.set_hidden_for_scribble(true)
	rig.set_face(PencilRig.Face.SURPRISED)
	fell.emit(global_position)


func _tick_respawn(dt: float) -> void:
	_respawn += dt
	if _respawn < 0.55:
		rig.scale = Vector3.ONE * (1.0 - _respawn * 0.6)
		return
	if _respawn < 0.65:
		position = safe_point
		rig.set_hidden_for_scribble(false)
		rig.scale = Vector3(1, 0.01, 1)
		_place_shadow()
		return
	var t := clampf((_respawn - 0.65) / 0.45, 0.0, 1.0)
	rig.scale = Vector3(1.0, maxf(0.01, t), 1.0)   # redrawn from the shoes up
	if t >= 1.0:
		rig.scale = Vector3.ONE
		_respawn = -1.0
		grounded = true
		emote(&"recover", 0.9)
		face(PencilRig.Face.SAD, 1.0)
		redrawn.emit()


func is_respawning() -> bool:
	return _respawn >= 0.0


func reset_to(p: Vector3) -> void:
	position = p
	safe_point = p
	velocity = Vector3.ZERO
	grounded = true
	_respawn = -1.0
	rig.scale = Vector3.ONE
	rig.set_hidden_for_scribble(false)


# --- picking the animation -------------------------------------------------------------

func _animate(_dt: float, speed: float, teetering: bool = false) -> void:
	var k := speed / RUN_SPEED
	rig.set_locomotion(speed / WALK_SPEED, velocity.y)
	var anim: StringName = &"idle"
	if _respawn >= 0.0:
		anim = &"fall"
	elif _anim_hold > 0.0 and _held_anim != &"":
		anim = _held_anim
	elif celebrating:
		anim = &"celebrate"
	elif holding:
		anim = &"hold"
	elif not grounded:
		anim = &"jump"
	elif teetering or _sliding:
		anim = &"lose_balance"
	elif pushing and speed > 0.2:
		anim = &"push"
	elif speed > 0.25:
		if _fresh_path != "":
			anim = &"careful_step"
		elif k > 0.8:
			anim = &"run"
		else:
			anim = &"walk"
	elif tired:
		anim = &"tired_idle"
	rig.play(anim)
	# Faces follow what is happening unless a beat is holding one.
	if _face_hold <= 0.0:
		var f := PencilRig.Face.HOPEFUL
		if tired:
			f = PencilRig.Face.TIRED
		if anim in [&"lose_balance", &"fall"] or (not grounded and velocity.y < -6.0):
			f = PencilRig.Face.SURPRISED
		elif anim in [&"walk", &"run", &"push"] and not tired:
			f = PencilRig.Face.DETERMINED
		elif celebrating or holding:
			f = PencilRig.Face.HAPPY
		if f != rig.face:
			rig.set_face(f)
	# Where to look: a beat's target, else the player after standing still.
	var look: Vector3 = _global_of(look_target) if look_target != null else Vector3.INF
	if look == Vector3.INF and _idle > 2.0 and player_head:
		look = player_head.global_position
	rig.look_at_point(look)
	if look_target != null and _actions.is_empty() and _idle > 3.0:
		look_target = null
	_place_shadow()


func _place_shadow() -> void:
	if _shadow == null or level == null:
		return
	var g := level.ground_height(position + Vector3(0, 0.05, 0), 0.0)
	_shadow.visible = g > -50.0 and _respawn < 0.0
	_shadow.position = Vector3(position.x, g + 0.012, position.z)
	_shadow.scale = Vector3.ONE * clampf(1.0 - (position.y - g) * 0.25, 0.35, 1.0)
