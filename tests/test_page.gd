extends SceneTree
## Headless: page collision rules, stroke → bridge validation, pencil physics,
## and a full solve of page one through the real BookWorld (place → open →
## draw bridge → cross → push ball onto plate → gate → jump → star → win).
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_level_rules()
	await _hero_physics()
	await _full_solve()
	if _failures > 0:
		printerr("FAIL: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS: page one — collision, strokes, ink, fall & respawn, bridge, ball & plate, gate, jump, win, replay")
	quit(0)


func _level_rules() -> void:
	var l := PageLevel.page_one()
	_check(l.ground_height(Vector3(-3, 1.0, 0), 0.1) == 1.0, "stand on A")
	_check(l.ground_height(Vector3(-0.5, 1.0, 0), 0.1) == 0.0, "the gap drops to the blank page")
	_check(l.ground_height(Vector3(9, 1.0, 0), 0.1) < -50.0, "outside the book is nothing")
	_check(l.blocked(Vector3(2.5, 1.0, -0.8), 0.2, 1.0), "C is a wall from B")
	_check(not l.blocked(Vector3(2.5, 1.8, -0.8), 0.2, 1.0), "but not once you jumped high enough")
	_check(l.blocked(Vector3(3.0, 2.0, -0.8), 0.2, 1.0), "rubble blocks the gate")
	# Strokes.
	_check(l.validate_stroke(Vector3(-1.7, 1.1, 0), Vector3(-0.5, 1.1, 0)).reason == "support", "must land on something")
	_check(l.validate_stroke(Vector3(-1.7, 1.1, 0), Vector3(-1.4, 1.1, 0)).reason == "short")
	var steep := l.validate_stroke(Vector3(2.3, 1.0, -0.8), Vector3(2.8, 2.0, -0.8))
	_check(steep.reason == "steep", "too steep: %s" % steep.reason)
	var ok := l.validate_stroke(Vector3(-1.7, 1.3, 0.2), Vector3(0.8, 0.8, 0.2))
	_check(ok.ok and ok.a.y == 1.0 and ok.b.y == 1.0, "ends snap onto both tops")
	l.add_beam(ok.a, ok.b)
	_check(is_equal_approx(l.ink, PageLevel.INK_MAX - ok.length))
	_check(l.ground_height(Vector3(-0.5, 1.0, 0.2), 0.1) == 1.0, "the bridge carries you over the gap")
	_check(l.ground_height(Vector3(-0.5, 1.0, 1.2), 0.1) == 0.0, "but only where it is")
	var ramp := l.validate_stroke(Vector3(1.0, 1.0, -0.8), Vector3(3.0, 2.0, -0.8))
	_check(ramp.ok, "a ramp up to C is allowed: %s" % ramp.reason)
	l.ink = 0.5
	_check(l.validate_stroke(Vector3(-1.7, 1.3, -0.5), Vector3(0.8, 0.8, -0.5)).reason == "ink", "out of ink")
	l.remove_last_beam()
	_check(l.beams.is_empty() and l.ink > 2.0, "rubbing out gives the ink back")
	_check(l.on_plate(l.plate) and not l.on_plate(l.plate + Vector3(0.6, 0, 0)))
	l.open_gate()
	_check(not l.blocked(Vector3(3.0, 2.0, -0.8), 0.2, 1.0), "open gate lets you through")


func _hero_physics() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var l := PageLevel.page_one()
	var hero := PencilHero.new()
	root.add_child(hero)
	hero.setup(l, Vector3(-2.0, 1.0, 0.2))
	await process_frame
	# Walk right off the edge of A: falls onto the blank page and comes back.
	var flags := {"fell": false, "back": false}
	hero.fell.connect(func(): flags["fell"] = true)
	hero.respawned.connect(func(): flags["back"] = true)
	for i in range(400):
		hero.simulate(1.0 / 90.0, Vector2(1, 0), false)
		if flags["back"]:
			break
	_check(flags["fell"] and flags["back"], "fell into the gap and respawned")
	_check(hero.position.distance_to(l.checkpoints["A"]) < 0.01, "back at A's checkpoint")
	# A running jump cannot clear the gap.
	hero.reset_to(Vector3(-1.75, 1.0, 0.2))
	var best_x := -10.0
	for i in range(200):
		hero.simulate(1.0 / 90.0, Vector2(1, 0), i == 0)
		if hero.position.y > 0.9:
			best_x = maxf(best_x, hero.position.x)
		if hero.is_respawning():
			break
	_check(best_x < 0.5, "jump distance %0.2f is short of B" % best_x)
	# From B a jump reaches C's top.
	hero.reset_to(Vector3(2.1, 1.0, -0.8))
	for i in range(160):
		hero.simulate(1.0 / 90.0, Vector2(1, 0), i == 8)
	_check(hero.position.y == 2.0 and hero.grounded, "jumped up onto C (y=%0.2f)" % hero.position.y)
	_check(hero.checkpoint == l.checkpoints["C"])
	root.queue_free()
	await process_frame


func _full_solve() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var head := Node3D.new()
	head.position = Vector3(0, 1.5, 0.1)
	head.rotation_degrees.x = -40.0
	root.add_child(head)
	var hands: Array[Node3D] = []
	for i in range(2):
		var h := Node3D.new()
		h.position = Vector3(-0.3 if i == 0 else 0.3, 1.0, -0.1)
		root.add_child(h)
		hands.append(h)
	var world := BookWorld.new()
	root.add_child(world)
	world.build(head, hands)
	await process_frame
	var dt := 1.0 / 72.0
	_check(world.phase == BookWorld.Phase.PLACING)
	world.tick(dt, Vector2(0, 1), [0.0, 0.0])
	_check(world.table_height > BookWorld.DEFAULT_TABLE, "stick up raises the table")
	for i in range(50):
		world.tick(dt, Vector2.ZERO, [0.0, 1.0])
	_check(world.phase == BookWorld.Phase.OPENING, "trigger set the book down")
	_check(absf(world.global_position.y - world.table_height) < 0.01)
	for i in range(72 * 6):
		world.tick(dt, Vector2.ZERO, [0.0, 0.0])
		if world.phase == BookWorld.Phase.PLAYING:
			break
	_check(world.phase == BookWorld.Phase.PLAYING, "book opened")
	for i in range(60):
		world.tick(dt, Vector2.ZERO, [0.0, 0.0])
	var hero := world.hero
	_check(hero.position.distance_to(world.level.spawn) < 0.05 and hero.grounded, "pencil landed at the start")
	# A wild scribble in the air crumbles; a line from A to B becomes a bridge.
	_check(not world.try_bridge(Vector3(-1.0, 3.0, 0), Vector3(-0.5, 3.5, 0)).ok)
	_check(world.strokes_failed == 1)
	# Draw with the right hand through the real input path.
	var right := hands[1]
	var path := [Vector3(-1.7, 1.15, 0.2), Vector3(-0.6, 1.2, 0.2), Vector3(0.85, 1.15, 0.2)]
	for k in range(30):
		var u := k / 29.0
		var p: Vector3 = path[0].lerp(path[2], u)
		right.global_position = world.page.to_global(p) - (world.pens[1].tip_global() - right.global_position)
		world.tick(dt, Vector2.ZERO, [0.0, 1.0])
	world.tick(dt, Vector2.ZERO, [0.0, 0.0])
	_check(world.bridges.size() == 1, "the drawn line became a bridge")
	_check(world.level.ink < PageLevel.INK_MAX)
	right.global_position = Vector3(0.3, 1.0, -0.1)
	# Walk across to B.
	for i in range(72 * 4):
		world.tick(dt, Vector2(1, 0), [0.0, 0.0])
		if hero.position.x > 1.0:
			break
	_check(hero.position.x > 0.6 and absf(hero.position.y - 1.0) < 0.01 and not hero.is_respawning(), "crossed the bridge to B: %s" % str(hero.position))
	# Erase and redraw works and refunds ink.
	var ink_before := world.level.ink
	world.on_button(&"by_button", 1)
	_check(world.bridges.is_empty() and world.level.ink > ink_before)
	# Push the ball onto the star plate by walking into it.
	var guard := 0
	while not world.gate_restored and guard < 72 * 25:
		guard += 1
		var ball_p := Vector2(world.ball.position.x, world.ball.position.z)
		var plate_p := Vector2(world.level.plate.x, world.level.plate.z)
		var to_plate := (plate_p - ball_p).normalized()
		var behind := ball_p - to_plate * 0.6
		var me := Vector2(hero.position.x, hero.position.z)
		var dir: Vector2
		var lined_up := (behind - me).length() < 0.2 or ((ball_p - me).normalized().dot(to_plate) > 0.95 and (ball_p - me).length() < 0.9)
		if lined_up:
			dir = to_plate
		elif (me - ball_p).dot(to_plate) > -0.3 and (me - ball_p).length() < 1.0:
			# On the wrong side: step around the ball first.
			var perp := Vector2(-to_plate.y, to_plate.x)
			if (me - ball_p).dot(perp) < 0.0:
				perp = -perp
			dir = (ball_p + perp * 0.75 - to_plate * 0.3 - me).normalized()
		else:
			dir = (behind - me).normalized()
		world.tick(dt, Vector2(dir.x, -dir.y), [0.0, 0.0])
	_check(world.gate_restored, "ball pushed onto the plate (ball %s)" % str(world.ball.position))
	_check(world.ball.locked and world.level.gate_open)
	# Up onto C with a jump, then to the star.
	hero.reset_to(Vector3(2.0, 1.0, -0.85))
	for i in range(72 * 5):
		if i == 10:
			world.on_button(&"ax_button", 0)
		world.tick(dt, Vector2(1, 0), [0.0, 0.0])
		if world.phase == BookWorld.Phase.WON:
			break
	_check(world.phase == BookWorld.Phase.WON, "reached the star: %s" % str(hero.position))
	_check(hero.celebrating)
	for i in range(72 * 3):
		world.tick(dt, Vector2.ZERO, [0.0, 0.0])
	_check(world.zone_life[2] > 0.9 and world.zone_life[0] > 0.9, "colour came back")
	world.on_button(&"ax_button", 0)
	_check(world.phase == BookWorld.Phase.OPENING and not world.gate_restored and world.bridges.is_empty(), "A plays the page again")
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
	if _elapsed > 90.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
