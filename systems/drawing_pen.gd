class_name DrawingPen
extends Node3D
## The pencil the player holds in each hand (room scale, metres). Points
## forward along the controller's aim; its painted body shortens as the
## page's ink runs out, so the "ink meter" needs no numbers or words.

const LENGTH := 0.16
const TIP := Vector3(0, 0, -0.17)

var _body: MeshInstance3D
var _glow: MeshInstance3D
var _tip_node: Node3D
var ink_fraction: float = 1.0
var drawing: bool = false
var _time: float = 0.0


func _ready() -> void:
	var holder := Node3D.new()
	holder.rotation.x = -PI / 2.0  # cylinders are along Y; point them along -Z
	add_child(holder)
	var eraser := Sketch.cylinder(0.0095, 0.0095, 0.018, Sketch.paper(Sketch.PINK), holder, 6)
	eraser.position.y = -0.009
	var ferrule := Sketch.cylinder(0.01, 0.01, 0.014, Sketch.paper(Color(0.74, 0.75, 0.78)), holder, 6)
	ferrule.position.y = 0.007
	_body = Sketch.cylinder(0.0095, 0.0095, 1.0, Sketch.paper(Sketch.YELLOW), holder, 6)
	var cone := Sketch.cylinder(0.0025, 0.0095, 0.022, Sketch.paper(Color(0.93, 0.78, 0.58)), holder, 6)
	cone.name = "Cone"
	var lead := Sketch.cylinder(0.0, 0.0025, 0.008, Sketch.paper(Sketch.GRAPHITE), holder, 6)
	lead.name = "Lead"
	_tip_node = Node3D.new()
	add_child(_tip_node)
	_glow = Sketch.sphere(0.006, Sketch.ink(Color(0.25, 0.25, 0.3, 0.6), true), self, 8, 4)
	_set_length(1.0)


func _set_length(fraction: float) -> void:
	var body_len := 0.03 + 0.1 * clampf(fraction, 0.0, 1.0)
	var holder := _body.get_parent() as Node3D
	_body.scale = Vector3(1, body_len, 1)
	_body.position.y = 0.014 + body_len * 0.5
	var cone := holder.get_node("Cone") as Node3D
	cone.position.y = 0.014 + body_len + 0.011
	var lead := holder.get_node("Lead") as Node3D
	lead.position.y = 0.014 + body_len + 0.026
	_tip_node.position = Vector3(0, 0, -(0.014 + body_len + 0.03))
	_glow.position = _tip_node.position


func tip_global() -> Vector3:
	return _tip_node.global_position


func _process(delta: float) -> void:
	_time += delta
	_set_length(ink_fraction)
	_glow.visible = drawing
	_glow.scale = Vector3.ONE * (1.0 + sin(_time * 20.0) * 0.2)
