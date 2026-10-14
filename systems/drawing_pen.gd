class_name DrawingPen
extends Node3D
## The pencil the player holds in each hand (room scale, metres), pointing
## along the controller's aim. Its painted body shortens as the graphite runs
## low (blinking when nearly empty), so the ink meter needs no words. A small
## floating icon above the hand teaches drawing (pencil) or erasing (eraser).

enum Hint { NONE, DRAW, ERASE }

var ink_fraction: float = 1.0
var drawing: bool = false
var erasing: bool = false
var hint: int = Hint.NONE

var _holder: Node3D
var _body: MeshInstance3D
var _body_mat: ShaderMaterial
var _cone: Node3D
var _lead: Node3D
var _tip_node: Node3D
var _eraser: MeshInstance3D
var _eraser_mat: ShaderMaterial
var _glow: MeshInstance3D
var _icon_draw: Node3D
var _icon_erase: Node3D
var _time: float = 0.0


func _ready() -> void:
	_holder = Node3D.new()
	_holder.rotation.x = -PI / 2.0  # cylinders run along Y; point them along -Z
	add_child(_holder)
	_eraser_mat = Sketch.paper(Sketch.PINK)
	_eraser = Sketch.cylinder(0.0095, 0.0095, 0.018, _eraser_mat, _holder, 6)
	_eraser.position.y = -0.009
	var ferrule := Sketch.cylinder(0.01, 0.01, 0.014, Sketch.paper(Color(0.74, 0.75, 0.78)), _holder, 6)
	ferrule.position.y = 0.007
	_body_mat = Sketch.paper(Sketch.YELLOW)
	_body = Sketch.cylinder(0.0095, 0.0095, 1.0, _body_mat, _holder, 6)
	_cone = Sketch.cylinder(0.0025, 0.0095, 0.022, Sketch.paper(Color(0.93, 0.78, 0.58)), _holder, 6)
	_lead = Sketch.cylinder(0.0, 0.0025, 0.008, Sketch.paper(Sketch.GRAPHITE), _holder, 6)
	_tip_node = Node3D.new()
	add_child(_tip_node)
	_glow = Sketch.sphere(0.006, Sketch.ink(Color(0.25, 0.25, 0.3, 0.6), true), self, 8, 4)
	_icon_draw = _make_icon(false)
	_icon_erase = _make_icon(true)
	_set_length(1.0)


## A tiny floating badge: a ring with a pencil (or an eraser) inside.
func _make_icon(eraser: bool) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, 0.055, 0.02)
	add_child(root)
	var ring := PackedVector3Array()
	for i in range(25):
		var a := TAU * i / 24.0
		ring.append(Vector3(cos(a) * 0.02, sin(a) * 0.02, 0))
	Sketch.tube(ring, 0.0016, Sketch.ink(Color(0.15, 0.15, 0.18)), root)
	var disc := Sketch.cylinder(0.019, 0.019, 0.001, Sketch.paper(Color(0.97, 0.95, 0.88)), root, 16)
	disc.rotation.x = PI / 2.0
	if eraser:
		var e := Sketch.box(Vector3(0.022, 0.012, 0.004), Sketch.paper(Sketch.PINK), root)
		e.rotation.z = 0.5
		e.position.z = 0.003
		var band := Sketch.box(Vector3(0.006, 0.0125, 0.0045), Sketch.paper(Color(0.4, 0.55, 0.85)), root)
		band.rotation.z = 0.5
		band.position = Vector3(-0.004, -0.002, 0.003)
	else:
		var b := Sketch.box(Vector3(0.024, 0.006, 0.004), Sketch.paper(Sketch.YELLOW), root)
		b.rotation.z = 0.7
		b.position.z = 0.003
		var t := Sketch.box(Vector3(0.006, 0.004, 0.004), Sketch.paper(Sketch.GRAPHITE), root)
		t.rotation.z = 0.7
		t.position = Vector3(0.011, 0.01, 0.003)
	root.visible = false
	return root


func _set_length(fraction: float) -> void:
	var body_len := 0.025 + 0.1 * clampf(fraction, 0.0, 1.0)
	_body.scale = Vector3(1, body_len, 1)
	_body.position.y = 0.014 + body_len * 0.5
	_cone.position.y = 0.014 + body_len + 0.011
	_lead.position.y = 0.014 + body_len + 0.026
	_tip_node.position = Vector3(0, 0, -(0.014 + body_len + 0.03))
	_glow.position = _tip_node.position


func tip_global() -> Vector3:
	return _tip_node.global_position


func forward_global() -> Vector3:
	return -global_basis.z.normalized()


func _process(delta: float) -> void:
	_time += delta
	_set_length(ink_fraction)
	_glow.visible = drawing
	_glow.scale = Vector3.ONE * (1.0 + sin(_time * 20.0) * 0.2)
	var low := ink_fraction < 0.2
	_body_mat.set_shader_parameter("glow", (0.5 + 0.5 * sin(_time * 9.0)) * 0.6 if low else 0.0)
	_body_mat.set_shader_parameter("glow_color", Color(1.0, 0.3, 0.2))
	_eraser_mat.set_shader_parameter("glow", 0.6 if erasing else 0.0)
	_eraser_mat.set_shader_parameter("glow_color", Color(1.0, 0.6, 0.7))
	for pair in [[_icon_draw, Hint.DRAW], [_icon_erase, Hint.ERASE]]:
		var icon: Node3D = pair[0]
		icon.visible = hint == pair[1]
		if icon.visible:
			var cam := get_viewport().get_camera_3d()
			if cam:
				icon.look_at(cam.global_position, Vector3.UP, true)
			icon.scale = Vector3.ONE * (1.0 + sin(_time * 5.0) * 0.12)
