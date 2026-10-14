extends SceneTree
## Headless checks for "the last page": surfaces and drawn paths, ink that is
## spent while drawing and returned by erasing, slopes the pencil can or cannot
## walk, the ball's three ramp outcomes, the stairs that force erase-and-redraw,
## and a full run through BookWorld from placing the book to the ending.
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_rules()
	await _pencil()
	await _ramp_outcomes()
	await _full_run()
	if _failures > 0:
		printerr("FAIL: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS: last page — paths, ink, erase, slopes, teeter, scribble respawn, ramp (good/steep/flat), stairs loop, intro, light, gate, orb ending, replay")
	quit(0)


func _line(a: Vector3, b: Vector3, n: int = 20, arch: float = 0.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in range(n):
		var u := k / float(n - 1)
		pts.append(a.lerp(b, u) + Vector3(0, sin(u * PI) * arch, 0))
	return pts


func _rules() -> void:
	var l := PageLevel.stage_one()
	_check(l.ground_height(Vector3(-4.3, 1.0, 1.6), 0.1) == 1.0, "stand on P1")
	_check(l.ground_height(Vector3(-2.6, 1.0, 1.6), 0.1) == 0.0, "the gap drops to the blank page")
	_check(l.blocked(Vector3(1.65, 1.0, 1.6), 0.2, 1.0), "the closed gate blocks P2")
	# A free-hand line over the gap snaps its ends onto both cliffs.
	var pts := l.clean_path(_line(Vector3(-3.6, 1.2, 1.6), Vector3(-1.6, 1.3, 1.6), 20, 0.1))
	_check(absf(pts[0].y - 1.0) < 0.001 and absf(pts[pts.size() - 1].y - 1.0) < 0.001, "ends snap onto the tops")
	_check(pts[0].x <= -3.45 and pts[pts.size() - 1].x >= -1.75, "ends pulled onto the cliffs")
	var length := PageLevel.polyline_length(pts)
	_check(l.spend_ink(length) == length)
	var path := l.add_path(pts)
	_check(l.ground_height(Vector3(-2.6, 1.3, 1.6), 0.1) > 1.0, "the drawn path carries you over the gap")
	_check(l.on_path(Vector3(-2.6, l.ground_height(Vector3(-2.6, 1.3, 1.6), 0.0), 1.6)) == path.id)
	_check(l.ink < PageLevel.INK_MAX - 1.6, "a gap bridge costs most of the graphite")
	# Not enough left for the ramp (R → S needs > 2.1).
	_check(l.ink < 2.1, "ink left %.2f cannot make the ramp" % l.ink)
	l.remove_path(path.id)
	_check(is_equal_approx(l.ink, PageLevel.INK_MAX), "erasing returns the graphite")
	# The stairs: one bridge fits, two do not.
	_check(PageLevel.INK_MAX < 1.6 * 2.0, "two stair bridges cannot exist at once")
	# Eraser ray finds a path it points at.
	l.add_path(l.clean_path(_line(Vector3(-3.6, 1.0, 1.6), Vector3(-1.6, 1.0, 1.6))))
	var hit := l.path_near_ray(Vector3(-2.6, 3.0, 3.0), Vector3(0, -2.0, -1.4).normalized(), 0.7)
	_check(hit.get("id", "") != "", "eraser ray finds the path")
	_check(l.path_near_ray(Vector3(2.0, 3.0, 3.0), Vector3(0, -2.0, -1.4).normalized(), 0.7).is_empty(), "…and not when pointing elsewhere")


func _pencil() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var l := PageLevel.stage_one()
	var hero := PencilBody.new()
	root.add_child(hero)
	hero.setup(l, Vector3(-4.0, 1.0, 1.6))
	hero.tired = false
	await process_frame
	# Walking at the edge: he teeters first, and only falls if you insist.
	hero.reset_to(Vector3(-3.6, 1.0, 1.6))
	var teetered := false
	for i in range(60):
		hero.simulate(1.0 / 90.0, Vector2(1, 0), false, false)
		if hero.rig.anim == &"lose_balance":
			teetered = hero.grounded and hero.position.x < -3.3
			break
	_check(teetered, "teeters at the edge (%s, %s)" % [str(hero.position), hero.rig.anim])
	var flags := {"fell": false, "back": false}
	hero.fell.connect(func(_at): flags["fell"] = true)
	hero.redrawn.connect(func(): flags["back"] = true)
	for i in range(400):
		hero.simulate(1.0 / 90.0, Vector2(1, 0), false, false)
		if flags["back"]:
			break
	_check(flags["fell"] and flags["back"], "fell into the gap and was redrawn")
	_check(hero.position.x <= -3.55 and absf(hero.position.y - 1.0) < 0.01, "redrawn at a safe spot on P1: %s" % str(hero.position))
	# A running jump cannot clear the gap.
	hero.reset_to(Vector3(-3.5, 1.0, 1.6))
	var best_x := -10.0
	for i in range(160):
		hero.simulate(1.0 / 90.0, Vector2(1, 0), true, i == 0)
		if hero.position.y > 0.9:
			best_x = maxf(best_x, hero.position.x)
		if hero.is_respawning():
			break
	_check(best_x < -1.8, "jump reaches %.2f, short of P2" % best_x)
	# Too steep a line: he stops at the bottom instead of walking up.
	var steep := l.clean_path(_line(Vector3(-2.0, 1.0, 0.9), Vector3(-1.2, 2.4, 0.9)))
	l.add_path(steep)
	hero.reset_to(Vector3(-2.5, 1.0, 0.9))
	hero.position = Vector3(-1.6, 1.0, 0.9)
	for i in range(180):
		hero.simulate(1.0 / 90.0, Vector2(1, 0), false, false)
	_check(hero.position.y < 1.4, "cannot climb a 60° line (y=%.2f)" % hero.position.y)
	root.queue_free()
	await process_frame


func _ramp_outcomes() -> void:
	var results := {}
	var specs := {
		"good": _ramp(Vector3(-1.0, 2.2, -1.15), Vector3(1.75, 1.0, -1.25), true),
		"steep": _ramp(Vector3(-0.3, 2.2, -1.15), Vector3(1.75, 1.0, -1.25), false),
		"flat": _ramp(Vector3(-0.3, 2.2, -1.15), Vector3(1.2, 2.05, -1.2), false),
	}
	for key in specs.keys():
		var l := PageLevel.stage_one()
		l.add_path(l.clean_path(specs[key]))
		var holder := Node3D.new()
		get_root().add_child(holder)
		var b := PaperBall.new()
		holder.add_child(b)
		await process_frame
		b.setup(l, l.ball_start, holder)
		var p0: PackedVector3Array = l.paths[0].points
		var d := p0[1] - p0[0]
		d.y = 0.0
		b.push(d.normalized() * 1.5)
		var outcome := "stopped"
		var was_on := false
		for i in range(90 * 6):
			b.simulate(1.0 / 90.0)
			var on := b.grounded and l.on_switch(b.base())
			if on and not was_on:
				if b.speed() < PageLevel.SWITCH_CATCH_SPEED:
					outcome = "caught"
					break
				outcome = "rolled_over"
			was_on = on
			if b.is_respawning():
				outcome = "fell" if outcome != "rolled_over" else "rolled_over"
				break
		results[key] = outcome
		holder.queue_free()
	_check(results["good"] == "caught", "a well-made ramp delivers the ball: %s" % results["good"])
	_check(results["steep"] == "rolled_over", "a steep ramp flings it past the switch: %s" % results["steep"])
	_check(results["flat"] == "stopped", "a flat ramp leaves it halfway: %s" % results["flat"])
	await process_frame


func _ramp(a: Vector3, b: Vector3, ease_out: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in range(24):
		var u := k / 23.0
		var y := lerpf(a.y, b.y, smoothstep(0.0, 1.0, u) if ease_out else u)
		pts.append(Vector3(lerpf(a.x, b.x, u), y, lerpf(a.z, b.z, u)))
	return pts


func _full_run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var head := Node3D.new()
	head.position = Vector3(0, 1.3, 0.05)
	head.rotation_degrees.x = -38.0
	root.add_child(head)
	var hands: Array[Node3D] = []
	for i in range(2):
		var h := Node3D.new()
		h.position = Vector3(-0.3 if i == 0 else 0.3, 0.95, -0.1)
		root.add_child(h)
		hands.append(h)
	var w := BookWorld.new()
	root.add_child(w)
	w.build(head, hands)
	await process_frame
	var dt := 1.0 / 72.0
	var tick := func(seconds: float, stick: Vector2 = Vector2.ZERO, trig: Array = [0.0, 0.0], grip: Array = [0.0, 0.0]) -> void:
		for i in range(int(seconds * 72.0)):
			w.tick(dt, stick, trig, grip)
	_check(w.phase == BookWorld.Phase.PLACING)
	tick.call(1.0, Vector2.ZERO, [0.0, 1.0])
	_check(w.phase == BookWorld.Phase.INTRO, "trigger set the book down")
	# Let the intro play to the end (no skipping).
	for i in range(72 * 30):
		w.tick(dt, Vector2.ZERO, [0.0, 0.0], [0.0, 0.0])
		if w.phase == BookWorld.Phase.PLAYING:
			break
	_check(w.phase == BookWorld.Phase.PLAYING, "the intro ends with control")
	var hero := w.hero
	_check(hero.position.distance_to(w.level.gap_edge) < 0.6 and hero.tired, "he waits at the gap, tired")
	_check(w.pens[0].hint == DrawingPen.Hint.DRAW, "pencil icon on the hand")
	# Draw across the gap with the right hand through the real input path.
	var right := hands[1]
	var a := Vector3(-3.6, 1.15, 1.6)
	var b := Vector3(-1.6, 1.2, 1.6)
	for k in range(36):
		var p := a.lerp(b, k / 35.0) + Vector3(0, sin(k / 35.0 * PI) * 0.1, 0)
		right.global_position += w.page.to_global(p) - w.pens[1].tip_global()
		w.tick(dt, Vector2.ZERO, [0.0, 1.0], [0.0, 0.0])
	w.tick(dt, Vector2.ZERO, [0.0, 0.0], [0.0, 0.0])
	_check(w.level.paths.size() == 1, "the line became a path")
	_check(w.pens[0].hint == DrawingPen.Hint.NONE)
	var ink_after_bridge := w.level.ink
	tick.call(4.0)  # he tries it carefully
	# Walk over, take the light, the flower blooms, he gets his energy back.
	for i in range(72 * 6):
		w.tick(dt, Vector2(1, 0), [0.0, 0.0], [0.0, 0.0])
		if w.light_taken:
			break
	_check(w.crossed_gap and w.light_taken, "crossed and took the light: %s scripted=%s" % [str(hero.position), str(hero.scripted())])
	tick.call(3.0)
	_check(w.view.flower_bloom > 0.9 and not hero.tired, "the flower opened and he is no longer tired")
	# Further along, low graphite: he looks back and the eraser icon appears.
	for i in range(72 * 4):
		w.tick(dt, Vector2(1, 0), [0.0, 0.0], [0.0, 0.0])
		if hero.position.x > -0.3:
			break
	tick.call(3.0)
	_check(w.erase_taught and w.pens[1].hint == DrawingPen.Hint.ERASE, "erase lesson shown")
	# Grip + point at the bridge erases it and returns the graphite.
	var bridge_mid: Vector3 = w.level.paths[0].points[w.level.paths[0].points.size() / 2]
	var mid_g := w.page.to_global(bridge_mid)
	right.global_position = mid_g + Vector3(0, 0.2, 0.2)
	right.look_at(mid_g, Vector3.UP)
	tick.call(0.8, Vector2.ZERO, [0.0, 0.0], [0.0, 1.0])
	_check(w.level.paths.is_empty() and w.level.ink > ink_after_bridge + 1.0 and w.erased_once, "grip-erase returned the graphite (ink %.2f)" % w.level.ink)
	_check(w.pens[1].hint == DrawingPen.Hint.NONE)
	right.rotation = Vector3.ZERO
	# A steep ramp: the ball rolls over the switch and comes back.
	var steep := w.commit_path(_ramp(Vector3(-0.3, 2.2, -1.15), Vector3(1.75, 1.0, -1.25), false))
	_check(steep.ok)
	tick.call(4.0)
	_check(not w.ball_caught, "too steep: missed the switch")
	tick.call(4.0)
	w.erase_path(steep.id)
	var home := false
	for i in range(72 * 8):
		w.tick(dt, Vector2.ZERO, [0.0, 0.0], [0.0, 0.0])
		if not w.ball.is_respawning() and w.ball.base().distance_to(w.level.ball_start) < 0.3 and w.ball.speed() < 0.05:
			home = true
			break
	_check(home, "the ball returned to its tower: %s" % str(w.ball.base()))
	# A good ramp: caught, the gate opens.
	var good := w.commit_path(_ramp(Vector3(-1.0, 2.2, -1.15), Vector3(1.75, 1.0, -1.25), true))
	_check(good.ok)
	for i in range(72 * 6):
		w.tick(dt, Vector2.ZERO, [0.0, 0.0], [0.0, 0.0])
		if w.ball_caught:
			break
	_check(w.ball_caught and w.level.gate_open, "ball on the switch opens the gate")
	tick.call(2.5)
	# Stairs: bridge, cross, erase behind, bridge again — three times.
	w.erase_path(good.id)
	hero.reset_to(Vector3(2.0, 1.0, 2.0))
	var stairs := [
		[Vector3(2.15, 1.05, 2.0), Vector3(3.9, 1.55, 2.0), Vector2(1, 0), "T1"],
		[Vector3(4.5, 1.55, 1.38), Vector3(4.5, 2.05, -0.3), Vector2(0, 1), "T2"],
		[Vector3(4.5, 2.05, -0.95), Vector3(4.5, 2.55, -2.55), Vector2(0, 1), "T3"],
	]
	var previous := ""
	for step in stairs:
		var r := w.commit_path(_line(step[0], step[1], 18, 0.08))
		if not r.ok and previous != "":
			_check(true)
		_check(r.ok, "bridge to %s drawn (ink %.2f)" % [step[3], w.level.ink])
		for i in range(72 * 5):
			w.tick(dt, step[2], [0.0, 0.0], [0.0, 0.0])
			if w.level.standing_on(hero.position, 0.0) == step[3] and w.level.edge_distance(hero.position) > 0.35:
				break
		_check(w.level.standing_on(hero.position, 0.0) == step[3], "reached %s: %s" % [step[3], str(hero.position)])
		# Not enough graphite for the next one until the old bridge is erased.
		if step[3] != "T3":
			_check(w.level.ink < 1.6, "must erase before the next bridge (ink %.2f)" % w.level.ink)
		w.erase_path(r.id)
		previous = r.id
	# The orb.
	for i in range(72 * 4):
		w.tick(dt, Vector2(-0.3, 0.2), [0.0, 0.0], [0.0, 0.0])
		if w.phase == BookWorld.Phase.ENDING:
			break
	_check(w.phase == BookWorld.Phase.ENDING, "touching the green orb ends the page: %s" % str(hero.position))
	tick.call(14.0)
	_check(w.zone_life[0] > 0.9 and w.view.stream_flow > 0.9, "life and the stream returned")
	_check(w.view.page_two_label.modulate.a > 0.9, "'الصفحة الثانية' is shown")
	w.on_button(&"ax_button", 0)
	_check(w.phase == BookWorld.Phase.INTRO and w.level.paths.is_empty() and not w.ball_caught, "A plays the page again")
	root.queue_free()
	await process_frame


var _failures := 0
func _check(ok: bool, message: String = "") -> void:
	if not ok:
		_failures += 1
		printerr("CHECK FAILED: " + message)


var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 120.0:
		printerr("FAIL: test timed out")
		quit(1)
	return false
