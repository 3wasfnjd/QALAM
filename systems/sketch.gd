class_name Sketch
extends RefCounted
## Storybook look, all built in code: toon "paper" material that can be
## drained of colour (life 0 = pencil-grey sketch, 1 = full colour), hand-drawn
## jittered ink edges, tubes, blob shadows. No textures, no imported models.

const INK := Color(0.16, 0.14, 0.13)
const PAPER := Color(0.93, 0.90, 0.82)
const PAPER_DARK := Color(0.80, 0.75, 0.66)
const GRAPHITE := Color(0.24, 0.25, 0.28)
const GRASS := Color(0.47, 0.70, 0.30)
const WOOD := Color(0.62, 0.42, 0.24)
const STONE := Color(0.70, 0.68, 0.64)
const YELLOW := Color(0.97, 0.78, 0.25)
const PINK := Color(0.93, 0.55, 0.58)
const LEATHER := Color(0.48, 0.30, 0.17)
const GOLD := Color(1.0, 0.80, 0.25)

const PAPER_SHADER := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_back;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float life : hint_range(0.0, 1.0) = 1.0;
uniform float grain = 0.07;
uniform float glow = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float wave_mask = 1.0;
global uniform vec3 qalam_wave_center;
global uniform float qalam_wave_radius;
varying vec3 wpos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float d = distance(wpos, qalam_wave_center);
	float wave = qalam_wave_radius > 0.001 ? smoothstep(qalam_wave_radius, qalam_wave_radius - 0.08, d) * wave_mask : 0.0;
	float rim = qalam_wave_radius > 0.001 ? smoothstep(0.05, 0.0, abs(d - qalam_wave_radius)) * wave_mask : 0.0;
	float alive = max(life, wave);
	vec3 c = albedo.rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 sketch = vec3(0.70, 0.68, 0.64) * (0.45 + 0.65 * g);
	c = mix(vec3(g), c, 0.85);               // never fully saturated: storybook
	c = mix(sketch, c, alive);
	float n = hash(floor(wpos * 900.0));
	float streak = sin((wpos.x + wpos.y * 0.7 + wpos.z * 1.3) * 420.0) * 0.5 + 0.5;
	c *= 1.0 - grain * n - grain * 0.6 * streak * (1.0 - alive);
	ALBEDO = c;
	EMISSION = glow_color.rgb * glow + vec3(0.9, 1.0, 0.55) * rim * 0.8;
}
"""

const INK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(0.16, 0.14, 0.13, 1.0);
uniform float alpha_scale = 1.0;
void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a * alpha_scale;
}
"""

static var _paper_shader: Shader
static var _globals_ready: bool = false


## The colour wave (centre + radius, world space) is a global shader value so
## every paper surface can bloom back to life as it passes.
static func ensure_globals() -> void:
	if _globals_ready:
		return
	_globals_ready = true
	var names := RenderingServer.global_shader_parameter_get_list()
	if not names.has(&"qalam_wave_center"):
		RenderingServer.global_shader_parameter_add(&"qalam_wave_center", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0, -100, 0))
	if not names.has(&"qalam_wave_radius"):
		RenderingServer.global_shader_parameter_add(&"qalam_wave_radius", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


static func set_wave(center: Vector3, radius: float) -> void:
	ensure_globals()
	RenderingServer.global_shader_parameter_set(&"qalam_wave_center", center)
	RenderingServer.global_shader_parameter_set(&"qalam_wave_radius", radius)
static var _ink_shader: Shader


## A toon paper material. Register it in `zones[zone]` so the world can bring
## that zone's colour back later; zone -1 means always in full colour.
static func paper(color: Color, zone: int = -1, zones: Dictionary = {}) -> ShaderMaterial:
	if _paper_shader == null:
		ensure_globals()
		_paper_shader = Shader.new()
		_paper_shader.code = PAPER_SHADER
	var m := ShaderMaterial.new()
	m.shader = _paper_shader
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("life", 1.0 if zone < 0 else 0.0)
	if zone >= 0:
		if not zones.has(zone):
			zones[zone] = []
		zones[zone].append(m)
	return m


static func ink(color: Color = INK, transparent: bool = false) -> ShaderMaterial:
	if _ink_shader == null:
		_ink_shader = Shader.new()
		_ink_shader.code = INK_SHADER
	var m := ShaderMaterial.new()
	m.shader = _ink_shader
	m.set_shader_parameter("tint", color)
	if transparent:
		m.render_priority = 2
	return m


static func mesh_node(mesh: Mesh, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if parent:
		parent.add_child(mi)
	return mi


static func box(size: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh_node(b, material, parent)


static func sphere(radius: float, material: Material, parent: Node3D = null, segments: int = 14, rings: int = 8) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = rings
	return mesh_node(s, material, parent)


static func cylinder(top: float, bottom: float, height: float, material: Material, parent: Node3D = null, sides: int = 12) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return mesh_node(c, material, parent)


## Writes a round tube along `points` into an ImmediateMesh (for live strokes).
static func build_tube(mesh: ImmediateMesh, points: PackedVector3Array, radius: float, sides: int = 6) -> void:
	mesh.clear_surfaces()
	if points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var prev_side := Vector3.ZERO
	for i in range(points.size()):
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, points.size() - 1)]
		var dir := (b - a)
		dir = dir.normalized() if dir.length() > 0.00001 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		if prev_side != Vector3.ZERO and side.dot(prev_side) < 0.0:
			side = -side
		prev_side = side
		var up := side.cross(dir).normalized()
		var ring: Array = []
		for k in range(sides):
			var ang := TAU * k / sides
			ring.append(points[i] + (side * cos(ang) + up * sin(ang)) * radius)
		rings.append(ring)
	for i in range(rings.size() - 1):
		for k in range(sides):
			var k2 := (k + 1) % sides
			var p00: Vector3 = rings[i][k]
			var p01: Vector3 = rings[i][k2]
			var p10: Vector3 = rings[i + 1][k]
			var p11: Vector3 = rings[i + 1][k2]
			mesh.surface_add_vertex(p00)
			mesh.surface_add_vertex(p10)
			mesh.surface_add_vertex(p11)
			mesh.surface_add_vertex(p00)
			mesh.surface_add_vertex(p11)
			mesh.surface_add_vertex(p01)
	mesh.surface_end()


## A static tube mesh (for ink lines that never change).
static func tube(points: PackedVector3Array, radius: float, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	build_tube(im, points, radius, 5)
	var mi := mesh_node(im, material, parent)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Hand-drawn outline of a box: each edge drawn twice with a little wobble and
## overshoot, like a quick pencil sketch. All edges in one mesh.
static func sketch_box_edges(size: Vector3, center: Vector3, radius: float, rng: RandomNumberGenerator, parent: Node3D, color: Color = INK) -> MeshInstance3D:
	var h := size * 0.5
	var corners := []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				corners.append(center + Vector3(x * h.x, y * h.y, z * h.z))
	var edges := []
	for i in range(8):
		for j in range(i + 1, 8):
			var d: Vector3 = corners[i] - corners[j]
			var axes := int(absf(d.x) > 0.0001) + int(absf(d.y) > 0.0001) + int(absf(d.z) > 0.0001)
			if axes == 1:
				edges.append([corners[i], corners[j]])
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in edges:
		for pass_i in range(2):
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			var dir := (b - a).normalized()
			var over := 0.04 + rng.randf() * 0.05
			a -= dir * over * float(pass_i == 0)
			b += dir * over * float(pass_i == 1)
			var pts := PackedVector3Array()
			var wob := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 1.4
			for k in range(5):
				var t := k / 4.0
				pts.append(a.lerp(b, t) + wob * sin(t * PI))
			_append_tube(im, pts, radius * (1.0 if pass_i == 0 else 0.6), 4)
	im.surface_end()
	var mi := mesh_node(im, ink(color), parent)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _append_tube(im: ImmediateMesh, points: PackedVector3Array, radius: float, sides: int) -> void:
	var rings: Array = []
	for i in range(points.size()):
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, points.size() - 1)]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(dir).normalized()
		var ring: Array = []
		for k in range(sides):
			var ang := TAU * k / sides
			ring.append(points[i] + (side * cos(ang) + up * sin(ang)) * radius)
		rings.append(ring)
	for i in range(rings.size() - 1):
		for k in range(sides):
			var k2 := (k + 1) % sides
			im.surface_add_vertex(rings[i][k])
			im.surface_add_vertex(rings[i + 1][k])
			im.surface_add_vertex(rings[i + 1][k2])
			im.surface_add_vertex(rings[i][k])
			im.surface_add_vertex(rings[i + 1][k2])
			im.surface_add_vertex(rings[i][k2])


## Soft dark disc on the ground under something that jumps.
static func blob_shadow(radius: float, parent: Node3D) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.45;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.12, 0.1, 0.08);
	ALPHA = strength * smoothstep(1.0, 0.2, d);
}
"""
	m.shader = s
	m.render_priority = 1
	var mi := mesh_node(q, m, parent)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A crumpled-paper ball: jittered icosphere, flat shaded.
static func crumpled_ball(radius: float, material: Material, rng: RandomNumberGenerator) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	# One subdivision.
	var cache := {}
	var pts: Array = []
	for v in verts:
		pts.append((v as Vector3).normalized())
	var mid := func(a: int, b: int) -> int:
		var key := mini(a, b) * 1000 + maxi(a, b)
		if cache.has(key):
			return cache[key]
		pts.append(((pts[a] + pts[b]) * 0.5).normalized())
		cache[key] = pts.size() - 1
		return pts.size() - 1
	var tris: Array = []
	for f in faces:
		var a: int = mid.call(f[0], f[1])
		var b: int = mid.call(f[1], f[2])
		var c: int = mid.call(f[2], f[0])
		tris.append_array([[f[0], a, c], [f[1], b, a], [f[2], c, b], [a, b, c]])
	var jitter: Array = []
	for p in pts:
		jitter.append(p * radius * rng.randf_range(0.82, 1.08))
	st.set_smooth_group(-1)
	for tri in tris:
		for idx in tri:
			st.add_vertex(jitter[idx])
	st.generate_normals()
	return mesh_node(st.commit(), material)
