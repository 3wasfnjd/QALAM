class_name Confetti
extends Node3D
## Short bursts of paper bits (colour returning, a poof when something falls
## onto the blank page). One MultiMesh, simple ballistic motion. Page units.

const MAX := 160

var _mm: MultiMesh
var _bits: Array = []


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.06)
	_mm.mesh = q
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func burst(at: Vector3, count: int, colors: Array, speed: float = 3.0, up: float = 3.0) -> void:
	for i in range(count):
		if _bits.size() >= MAX:
			_bits.pop_front()
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_bits.append({
			"p": at + Vector3(randf_range(-0.1, 0.1), randf_range(0, 0.1), randf_range(-0.1, 0.1)),
			"v": dir * randf_range(0.3, 1.0) * speed + Vector3(0, randf_range(0.5, 1.0) * up, 0),
			"spin": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)),
			"rot": Vector3(randf() * TAU, randf() * TAU, 0),
			"c": colors[randi() % colors.size()],
			"life": 0.0,
			"max": randf_range(0.9, 1.6),
		})


func _process(delta: float) -> void:
	for i in range(_bits.size() - 1, -1, -1):
		var b: Dictionary = _bits[i]
		b.life += delta
		if b.life > b.max:
			_bits.remove_at(i)
			continue
		b.v.y -= 7.0 * delta
		b.v *= exp(-1.8 * delta)
		b.p += b.v * delta
		b.rot += b.spin * delta
	_mm.visible_instance_count = _bits.size()
	for i in range(_bits.size()):
		var b: Dictionary = _bits[i]
		var s := clampf((b.max - b.life) * 3.0, 0.0, 1.0)
		var basis := Basis.from_euler(b.rot).scaled(Vector3.ONE * maxf(s, 0.01))
		_mm.set_instance_transform(i, Transform3D(basis, b.p))
		_mm.set_instance_color(i, b.c)
