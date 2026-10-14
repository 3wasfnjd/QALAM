class_name PageLevel
extends RefCounted
## Gameplay data and rules for "the last page", in page units (1 unit ≈ one
## paper block; the book is scaled down into the room). No visuals here, so any
## visual can be swapped for a real 3D model without touching the rules.
##
## Layout (x → right, z → toward the player, y up; blank page at y = 0):
##   P1 start cliff ─ gap ─ P2 long platform (light, wilted flower, stream, gate)
##   R  ball tower behind P2            S  switch island behind P2
##   past the gate: T1 → T2 → T3 stairs with gaps too wide to jump; green orb on T3
## Drawn paths are free-hand polylines you can walk and roll on.

const STEP := 0.3
const BOOK_HALF := Vector2(5.5, 3.3)
const PATH_HALF_WIDTH := 0.3
const SUPPORT_REACH := 0.55      # a path end this close to a top snaps onto it
const SUPPORT_HEIGHT := 0.8
const MIN_PATH := 0.6
const INK_MAX := 3.1
const MAX_WALK_SLOPE := 0.95     # rise / run the pencil can still walk up
const SLIDE_SLOPE := 1.15        # steeper than this and the pencil slides down
const SWITCH_RADIUS := 0.42
const SWITCH_CATCH_SPEED := 2.6  # faster than this and the ball rolls over it
const RESAMPLE := 0.22

var blocks: Array = []    # {id, min, max, zone, solid}
var paths: Array = []     # {id, points: PackedVector3Array, length}
var ink: float = INK_MAX
var gate_open: bool = false
var switch_pressed: bool = false
var _next_path_id: int = 1

var spawn := Vector3(-4.35, 1.0, 1.6)
var gap_edge := Vector3(-3.62, 1.0, 1.6)
var light := Vector3(-1.25, 1.0, 1.6)
var flower := Vector3(-0.55, 1.0, 2.3)
var ball_start := Vector3(-0.42, 2.2, -1.15)     # ball base point on R
var switch_pos := Vector3(2.3, 1.0, -1.3)
var gate := Vector3(1.65, 1.0, 1.6)
var orb := Vector3(4.55, 2.5, -2.85)
var dead_tree := Vector3(-4.75, 1.0, 1.0)


static func stage_one() -> PageLevel:
	var l := PageLevel.new()
	l.add_block("P1", Vector3(-5.2, 0, 0.6), Vector3(-3.4, 1.0, 2.6), 0)
	l.add_block("P2", Vector3(-1.8, 0, 0.6), Vector3(2.2, 1.0, 2.6), 1)
	l.add_block("R", Vector3(-1.2, 0, -1.7), Vector3(-0.2, 2.2, -0.6), 2)
	l.add_block("S", Vector3(1.6, 0, -2.0), Vector3(3.2, 1.0, -0.6), 2)
	l.add_block("gate", Vector3(1.5, 1.0, 0.6), Vector3(1.8, 2.6, 2.6), 2)
	l.add_block("T1", Vector3(3.8, 0, 1.3), Vector3(5.2, 1.5, 2.6), 3)
	l.add_block("T2", Vector3(3.8, 0, -1.0), Vector3(5.2, 2.0, -0.25), 3)
	l.add_block("T3", Vector3(3.6, 0, -3.25), Vector3(5.2, 2.5, -2.45), 3)
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


# --- surfaces -----------------------------------------------------------------------

## Highest surface under `p` reachable from `p.y` (stepping up at most STEP).
## Blank page = 0, outside the book = -100.
func ground_height(p: Vector3, radius: float) -> float:
	var best := 0.0 if in_book(p) else -100.0
	for b in blocks:
		if not b.solid:
			continue
		var top: float = b.max.y
		if top <= p.y + STEP and top > best and _overlaps(b, p, radius):
			best = top
	for path in paths:
		var h := path_height(path, p, radius)
		if not is_nan(h) and h <= p.y + STEP and h > best:
			best = h
	return best


## Surface height of one path under `p` (NAN if not over it).
func path_height(path: Dictionary, p: Vector3, radius: float) -> float:
	var pts: PackedVector3Array = path.points
	var best := NAN
	for i in range(pts.size() - 1):
		var h := _segment_height(pts[i], pts[i + 1], p, radius)
		if not is_nan(h) and h <= p.y + STEP and (is_nan(best) or h > best):
			best = h
	return best


static func _segment_height(a: Vector3, b: Vector3, p: Vector3, radius: float) -> float:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var run := flat.length()
	var rel := Vector2(p.x - a.x, p.z - a.z)
	if run < 0.0001:
		return a.y if rel.length() < PATH_HALF_WIDTH + radius else NAN
	var dir := flat / run
	var along := rel.dot(dir)
	var side := absf(rel.x * dir.y - rel.y * dir.x)
	if along < -radius or along > run + radius or side > PATH_HALF_WIDTH + radius:
		return NAN
	return lerpf(a.y, b.y, clampf(along / run, 0.0, 1.0))


## Downhill gradient (dh/dx, dh/dz) of whatever surface is under `p`.
func slope_at(p: Vector3) -> Vector2:
	var e := 0.08
	var h0 := ground_height(p, 0.0)
	var hx := ground_height(Vector3(p.x + e, h0 + 0.05, p.z), 0.0)
	var hz := ground_height(Vector3(p.x, h0 + 0.05, p.z + e), 0.0)
	var hx2 := ground_height(Vector3(p.x - e, h0 + 0.05, p.z), 0.0)
	var hz2 := ground_height(Vector3(p.x, h0 + 0.05, p.z - e), 0.0)
	# Ignore cliffs (an edge is not a slope).
	var gx := (hx - hx2) / (2.0 * e) if absf(hx - hx2) < 0.6 else 0.0
	var gz := (hz - hz2) / (2.0 * e) if absf(hz - hz2) < 0.6 else 0.0
	return Vector2(gx, gz)


func on_path(p: Vector3, radius: float = 0.1) -> String:
	for path in paths:
		var h := path_height(path, p, radius)
		if not is_nan(h) and absf(h - p.y) < 0.06:
			return path.id
	return ""


## Solid block id under `p` ("" for paths / page / air).
func standing_on(p: Vector3, radius: float) -> String:
	for b in blocks:
		if b.solid and absf(b.max.y - p.y) < 0.05 and _overlaps(b, p, radius):
			return b.id
	return ""


## True when a block too tall to step onto overlaps a body at `p`.
func blocked(p: Vector3, radius: float, height: float) -> bool:
	for b in blocks:
		if not b.solid:
			continue
		if b.max.y > p.y + STEP and b.min.y < p.y + height and _overlaps(b, p, radius):
			return true
	return false


## Distance from `p` to the nearest edge of the block it stands on (for
## remembering safe spots).
func edge_distance(p: Vector3) -> float:
	var id := standing_on(p, 0.0)
	if id == "":
		return 0.0
	var b := block(id)
	return minf(minf(p.x - b.min.x, b.max.x - p.x), minf(p.z - b.min.z, b.max.z - p.z))


# --- drawing ------------------------------------------------------------------------

## Snaps a path end onto a block top it hangs over / near (or INF).
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
			# Pull the end onto the top so the path really touches the cliff.
			best = Vector3(clampf(point.x, b.min.x + 0.06, b.max.x - 0.06), b.max.y, clampf(point.z, b.min.z + 0.06, b.max.z - 0.06))
	return best


static func polyline_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


## Raw hand samples → an evenly spaced, lightly smoothed path whose ends snap
## onto nearby tops so a bridge meets its cliffs.
func clean_path(raw: PackedVector3Array) -> PackedVector3Array:
	if raw.size() < 2:
		return raw
	var out := PackedVector3Array([raw[0]])
	var carry := 0.0
	for i in range(1, raw.size()):
		var a := out[out.size() - 1]
		var b := raw[i]
		var seg := a.distance_to(b)
		carry = seg
		while carry >= RESAMPLE:
			a = a.move_toward(b, RESAMPLE)
			out.append(a)
			carry = a.distance_to(b)
	if out[out.size() - 1].distance_to(raw[raw.size() - 1]) > RESAMPLE * 0.3:
		out.append(raw[raw.size() - 1])
	# One smoothing pass, ends kept.
	var smooth := out.duplicate()
	for i in range(1, out.size() - 1):
		smooth[i] = out[i - 1] * 0.25 + out[i] * 0.5 + out[i + 1] * 0.25
	for end in [0, smooth.size() - 1]:
		var s := support(smooth[end])
		if s != Vector3.INF:
			smooth[end] = s
	return smooth


## Adds a drawn path (ink is spent while drawing, see spend_ink).
func add_path(points: PackedVector3Array) -> Dictionary:
	var path := {"id": "path%d" % _next_path_id, "points": points, "length": polyline_length(points)}
	_next_path_id += 1
	paths.append(path)
	return path


func remove_path(id: String) -> Dictionary:
	for i in range(paths.size()):
		if paths[i].id == id:
			var path: Dictionary = paths[i]
			paths.remove_at(i)
			ink = minf(INK_MAX, ink + path.length)
			return path
	return {}


func path_by_id(id: String) -> Dictionary:
	for p in paths:
		if p.id == id:
			return p
	return {}


## Takes up to `amount` ink; returns what was actually available.
func spend_ink(amount: float) -> float:
	var used := minf(amount, ink)
	ink -= used
	return used


func refund_ink(amount: float) -> void:
	ink = minf(INK_MAX, ink + amount)


## Nearest path to a ray (for the eraser): {id, distance} or {}.
func path_near_ray(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var best := {}
	var best_d := max_distance
	for path in paths:
		var pts: PackedVector3Array = path.points
		for i in range(pts.size()):
			var to := pts[i] - origin
			var along := to.dot(direction)
			if along < -0.3 or along > 12.0:
				continue
			var d := (origin + direction * maxf(along, 0.0)).distance_to(pts[i])
			if d < best_d:
				best_d = d
				best = {"id": path.id, "distance": d}
	return best


# --- puzzle points ---------------------------------------------------------------------

func on_switch(base: Vector3) -> bool:
	return absf(base.y - switch_pos.y) < 0.12 and Vector2(base.x - switch_pos.x, base.z - switch_pos.z).length() < SWITCH_RADIUS


func near(p: Vector3, target: Vector3, radius: float) -> bool:
	return absf(p.y - target.y) < 0.5 and Vector2(p.x - target.x, p.z - target.z).length() < radius
