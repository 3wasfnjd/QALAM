class_name BridgeView
extends Node3D
## What a successful pencil stroke turns into: a little plank bridge with
## posts and rope lines, popping in plank by plank. Page units.

const PLANK_STEP := 0.27

var beam: Dictionary
var _planks: Array[Node3D] = []
var _time: float = 0.0
var _leaving: float = -1.0
var _ropes: Array[MeshInstance3D] = []


func build(b: Dictionary, rng: RandomNumberGenerator) -> void:
	beam = b
	var a: Vector3 = b.a
	var e: Vector3 = b.b
	var dir := (e - a).normalized()
	var across := Vector3(-dir.z, 0, dir.x).normalized()
	if across.length() < 0.1:
		across = Vector3.RIGHT
	var up := dir.cross(across).normalized()
	if up.y < 0.0:
		up = -up
		across = -across
	var length: float = b.length
	var n := maxi(2, int(ceil(length / PLANK_STEP)))
	var wood := Sketch.paper(Sketch.WOOD)
	var dark_wood := Sketch.paper(Sketch.WOOD.darkened(0.25))
	for i in range(n):
		var t := (i + 0.5) / n
		var plank := Node3D.new()
		add_child(plank)
		plank.position = a.lerp(e, t) - up * 0.04
		plank.basis = Basis(dir, up, -across).orthonormalized().rotated(up, rng.randf_range(-0.06, 0.06))
		var board := Sketch.box(Vector3(length / n * 0.86, 0.07, PageLevel.BEAM_HALF_WIDTH * 2.1), wood if i % 2 == 0 else dark_wood, plank)
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		Sketch.sketch_box_edges(Vector3(length / n * 0.86, 0.07, PageLevel.BEAM_HALF_WIDTH * 2.1), Vector3.ZERO, 0.008, rng, plank)
		plank.scale = Vector3.ONE * 0.01
		_planks.append(plank)
	# Posts at both ends and two sagging rope lines.
	var post_mat := Sketch.paper(Sketch.WOOD.darkened(0.35))
	for end in [a, e]:
		for side in [-1.0, 1.0]:
			var post := Sketch.cylinder(0.035, 0.04, 0.42, post_mat, self, 6)
			post.position = end + across * side * (PageLevel.BEAM_HALF_WIDTH + 0.04) + Vector3(0, 0.17, 0)
	var rope_mat := Sketch.ink(Color(0.4, 0.3, 0.2))
	for side in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		for k in range(12):
			var t := k / 11.0
			pts.append(a.lerp(e, t) + across * side * (PageLevel.BEAM_HALF_WIDTH + 0.04) + Vector3(0, 0.36 - sin(t * PI) * 0.14, 0))
		var rope := Sketch.tube(pts, 0.012, rope_mat, self)
		rope.visible = false
		_ropes.append(rope)


func remove() -> void:
	_leaving = 0.0


func _process(delta: float) -> void:
	_time += delta
	if _leaving >= 0.0:
		_leaving += delta
		for i in range(_planks.size()):
			var t := clampf(_leaving * 4.0 - i * 0.15, 0.0, 1.0)
			_planks[i].scale = Vector3.ONE * maxf(0.01, 1.0 - t)
		scale = Vector3.ONE
		if _leaving > 0.6 + _planks.size() * 0.04:
			queue_free()
		return
	for i in range(_planks.size()):
		var t := clampf((_time - i * 0.05) / 0.22, 0.0, 1.0)
		var pop := 1.0 + sin(t * PI) * 0.35
		_planks[i].scale = Vector3.ONE * maxf(0.01, t * pop)
	for r in _ropes:
		r.visible = _time > _planks.size() * 0.05
