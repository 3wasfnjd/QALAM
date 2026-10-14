class_name PageLevel
extends RefCounted
## Pure layout + collision for one sketchbook page, in "page units"
## (1 unit ≈ one paper block; the whole book is scaled down in the room).
## Blocks are axis-aligned boxes, drawn bridges are sloped planks. The blank
## page (y = 0) is "unwritten": whatever lands on it is sent back.

const STEP := 0.3
const BOOK_HALF := Vector2(4.4, 2.6)
const PLATE_RADIUS := 0.45
const SUPPORT_REACH := 0.5        # how far past an edge a stroke end may hang
const SUPPORT_HEIGHT := 0.75      # how far above/below a top a stroke end snaps
const MIN_STROKE := 0.9
const MAX_STROKE := 4.6
const MAX_SLOPE := 0.85           # rise / run
const BEAM_HALF_WIDTH := 0.32
const INK_MAX := 6.5

var blocks: Array = []   # {id, min, max, zone, solid}
var beams: Array = []    # {a, b, length}
var spawn := Vector3(-3.3, 1.0, 0.2)
var checkpoints := {}    # block id -> Vector3
var ball_start := Vector3(1.45, 1.32, -0.35)
var plate := Vector3(1.7, 1.0, 1.0)
var goal := Vector3(3.72, 2.0, -0.85)
var gate_open: bool = false
var ink: float = INK_MAX


static func page_one() -> PageLevel:
	var l := PageLevel.new()
	# A — the faded start cliff.
	l.add_block("A", Vector3(-4.0, 0, -1.2), Vector3(-1.5, 1.0, 1.2), 0)
	# B — the middle plateau with the ball and the star plate (gap of 2 to A).
	l.add_block("B", Vector3(0.5, 0, -1.6), Vector3(2.6, 1.0, 1.6), 1)
	# C — the high cliff of life, gate and goal.
	l.add_block("C", Vector3(2.6, 0, -1.6), Vector3(4.1, 2.0, -0.1), 2)
	# The broken gate's rubble blocks the way on C until the plate is pressed.
	l.add_block("gate", Vector3(3.05, 2.0, -1.6), Vector3(3.35, 3.4, -0.1), 2)
	l.checkpoints = {"A": Vector3(-3.3, 1.0, 0.2), "B": Vector3(1.0, 1.0, 0.9), "C": Vector3(2.85, 2.0, -0.85)}
	return l


func add_block(id: String, lo: Vector3, hi: Vector3, zone: int) -> void:
	blocks.append({"id": id, "min": lo, "max": hi, "zone": zone, "solid": true})


func block(id: String) -> Dictionary:
	for b in blocks:
		if b.id == id:
			return b
	return {}


func open_gate() -> void:
	gate_open = true
	block("gate").solid = false


func in_book(p: Vector3) -> bool:
	return absf(p.x) <= BOOK_HALF.x and absf(p.z) <= BOOK_HALF.y


static func _overlaps(b: Dictionary, p: Vector3, radius: float) -> bool:
	return p.x > b.min.x - radius and p.x < b.max.x + radius and p.z > b.min.z - radius and p.z < b.max.z + radius


## Height of the surface under `p` that can be stood on from `p.y` (a step
## of STEP is allowed). Blank page = 0, outside the book = -100.
func ground_height(p: Vector3, radius: float) -> float:
	var best := 0.0 if in_book(p) else -100.0
	for b in blocks:
		if not b.solid:
			continue
		var top: float = b.max.y
		if top <= p.y + STEP and top > best and _overlaps(b, p, radius):
			best = top
	for beam in beams:
		var h := beam_height(beam, p, radius)
		if not is_nan(h) and h <= p.y + STEP and h > best:
			best = h
	return best


## Which block (id) is directly under `p`, or "" (page, bridge, air).
func standing_on(p: Vector3, radius: float) -> String:
	for b in blocks:
		if b.solid and absf(b.max.y - p.y) < 0.05 and _overlaps(b, p, radius):
			return b.id
	return ""


func beam_height(beam: Dictionary, p: Vector3, radius: float) -> float:
	var a: Vector3 = beam.a
	var b: Vector3 = beam.b
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var run := flat.length()
	if run < 0.001:
		return NAN
	var dir := flat / run
	var rel := Vector2(p.x - a.x, p.z - a.z)
	var along := rel.dot(dir)
	var side := absf(rel.x * dir.y - rel.y * dir.x)
	if along < -radius or along > run + radius or side > BEAM_HALF_WIDTH + radius:
		return NAN
	return lerpf(a.y, b.y, clampf(along / run, 0.0, 1.0))


## True when a body standing at `p` (feet) with this radius and height would
## overlap a solid block that is too tall to step onto.
func blocked(p: Vector3, radius: float, height: float) -> bool:
	for b in blocks:
		if not b.solid:
			continue
		if b.max.y > p.y + STEP and b.min.y < p.y + height and _overlaps(b, p, radius):
			return true
	return false


## Snaps a stroke end onto the top of a block it hangs over / near.
func support(point: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for b in blocks:
		if not b.solid or b.id == "gate":
			continue
		if not _overlaps(b, point, SUPPORT_REACH):
			continue
		var d: float = absf(point.y - b.max.y)
		if d < SUPPORT_HEIGHT and d < best_d:
			best_d = d
			best = Vector3(point.x, b.max.y, point.z)
	return best


## Decides whether a drawn line becomes a plank. Returns
## {ok, a, b, length, reason} with reason in: short, long, ink, support, steep.
func validate_stroke(a: Vector3, b: Vector3) -> Dictionary:
	var out := {"ok": false, "a": a, "b": b, "length": a.distance_to(b), "reason": ""}
	var sa := support(a)
	var sb := support(b)
	if sa == Vector3.INF or sb == Vector3.INF:
		out.reason = "support"
		return out
	var length := sa.distance_to(sb)
	out.a = sa
	out.b = sb
	out.length = length
	if length < MIN_STROKE:
		out.reason = "short"
	elif length > MAX_STROKE:
		out.reason = "long"
	elif length > ink + 0.001:
		out.reason = "ink"
	elif absf(sb.y - sa.y) > Vector2(sb.x - sa.x, sb.z - sa.z).length() * MAX_SLOPE:
		out.reason = "steep"
	else:
		out.ok = true
	return out


func add_beam(a: Vector3, b: Vector3) -> Dictionary:
	var beam := {"a": a, "b": b, "length": a.distance_to(b)}
	beams.append(beam)
	ink = maxf(0.0, ink - beam.length)
	return beam


func remove_last_beam() -> Dictionary:
	if beams.is_empty():
		return {}
	var beam: Dictionary = beams.pop_back()
	ink = minf(INK_MAX, ink + beam.length)
	return beam


func on_plate(p: Vector3) -> bool:
	return absf(p.y - plate.y) < 0.12 and Vector2(p.x - plate.x, p.z - plate.z).length() < PLATE_RADIUS


func at_goal(p: Vector3) -> bool:
	return absf(p.y - goal.y) < 0.4 and Vector2(p.x - goal.x, p.z - goal.z).length() < 0.5
