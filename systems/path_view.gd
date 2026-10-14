class_name PathView
extends Node3D
## How a drawn path looks: a thick hand-drawn graphite strip that follows the
## stroke, with wobbly pencil edges. It firms up when drawn, trembles when the
## pencil first steps on it, turns pink under the eraser and rubs away.

var path_id: String = ""
var points := PackedVector3Array()
var erase_amount: float = 0.0      # 0..1 while the eraser works on it
var targeted: bool = false

var _strip: MeshInstance3D
var _edges: MeshInstance3D
var _mat: ShaderMaterial
var _edge_mat: ShaderMaterial
var _time: float = 0.0
var _wobble: float = 0.0
var _leaving: float = -1.0
var _built_width: float = -1.0


func build(id: String, pts: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	path_id = id
	points = pts
	_mat = Sketch.paper(Color(0.38, 0.38, 0.42))
	_mat.set_shader_parameter("grain", 0.18)
	_strip = MeshInstance3D.new()
	_strip.material_override = _mat
	add_child(_strip)
	_edge_mat = Sketch.ink(Color(0.1, 0.1, 0.12))
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for pass_i in range(2):
			var line := PackedVector3Array()
			for i in range(pts.size()):
				var across := _across(i)
				var jitter := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.012
				line.append(pts[i] + across * side * (PageLevel.PATH_HALF_WIDTH + 0.01 * pass_i) + Vector3(0, 0.01, 0) + jitter)
			Sketch._append_tube(im, line, 0.016 if pass_i == 0 else 0.009, 4)
	# Cross hatching on the top, like pencil shading.
	for i in range(pts.size() - 1):
		var across := _across(i)
		var a := pts[i] + across * PageLevel.PATH_HALF_WIDTH * 0.8 + Vector3(0, 0.012, 0)
		var b := pts[i + 1] - across * PageLevel.PATH_HALF_WIDTH * 0.8 + Vector3(0, 0.012, 0)
		Sketch._append_tube(im, PackedVector3Array([a, b]), 0.006, 3)
	im.surface_end()
	_edges = Sketch.mesh_node(im, _edge_mat, self)
	_edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild(0.2)


func _across(i: int) -> Vector3:
	var a := points[maxi(i - 1, 0)]
	var b := points[mini(i + 1, points.size() - 1)]
	var d := b - a
	var flat := Vector3(d.x, 0, d.z)
	if flat.length() < 0.0001:
		return Vector3.RIGHT
	return Vector3(-flat.z, 0, flat.x).normalized()


func _rebuild(width_scale: float) -> void:
	if absf(width_scale - _built_width) < 0.01:
		return
	_built_width = width_scale
	var w := PageLevel.PATH_HALF_WIDTH * width_scale
	var thick := 0.07
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var sa := _across(i) * w
		var sb := _across(i + 1) * w
		var up := Vector3(0, 0.005, 0)
		var dn := Vector3(0, -thick, 0)
		var quads := [
			[a - sa + up, a + sa + up, b + sa + up, b - sa + up],   # top
			[a - sa + dn, b - sa + dn, b + sa + dn, a + sa + dn],   # bottom
			[a + sa + up, a + sa + dn, b + sa + dn, b + sa + up],   # side
			[a - sa + up, b - sa + up, b - sa + dn, a - sa + dn],   # other side
		]
		for q in quads:
			st.add_vertex(q[0])
			st.add_vertex(q[1])
			st.add_vertex(q[2])
			st.add_vertex(q[0])
			st.add_vertex(q[2])
			st.add_vertex(q[3])
	st.generate_normals()
	_strip.mesh = st.commit()


func wobble() -> void:
	_wobble = 1.0


func remove() -> void:
	_leaving = 0.0


func _process(delta: float) -> void:
	_time += delta
	if _leaving >= 0.0:
		_leaving += delta
		_rebuild(maxf(0.05, 1.0 - _leaving * 3.0))
		_edge_mat.set_shader_parameter("alpha_scale", maxf(0.0, 1.0 - _leaving * 3.0))
		if _leaving > 0.35:
			queue_free()
		return
	# Firm up from a thin line to the full strip.
	var grow := clampf(_time / 0.25, 0.0, 1.0)
	var width := lerpf(0.2, 1.0, grow) * (1.0 - erase_amount * 0.7)
	_rebuild(snappedf(width, 0.05))
	_wobble = maxf(0.0, _wobble - delta * 1.8)
	position.y = sin(_time * 26.0) * 0.03 * _wobble
	var pink := Color(0.86, 0.55, 0.6)
	var base := Color(0.38, 0.38, 0.42)
	var tint := base.lerp(pink, clampf(erase_amount * 1.4 + (0.35 if targeted else 0.0), 0.0, 1.0))
	_mat.set_shader_parameter("albedo", tint)
	_edge_mat.set_shader_parameter("alpha_scale", 1.0 - erase_amount * 0.8)
