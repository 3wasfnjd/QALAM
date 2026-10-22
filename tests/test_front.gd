extends SceneTree
## Headless checks for the front line: placing the area on the floor, the pencil
## colouring the floor and pushing the line into the Eraser's side, the Eraser
## rubbing it back, a crayon stroke from the hand, the lasso that freezes the
## Eraser, its bump that knocks the pencil over, and the end of the round.
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var root := Node3D.new()
	get_root().add_child(root)
	var head := Node3D.new()
	head.position = Vector3(0, 1.5, 0.3)
	head.rotation_degrees.x = -40.0
	root.add_child(head)
	var hands: Array[Node3D] = []
	for i in range(2):
		var h := Node3D.new()
		h.position = Vector3(-0.3 if i == 0 else 0.3, 1.0, 0.0)
		root.add_child(h)
		hands.append(h)
	var w := FrontWorld.new()
	root.add_child(w)
	w.build(head, hands)
	await process_frame
	var dt := 1.0 / 72.0
	_check(w.phase == FrontWorld.Phase.PLACING)
	for i in range(72):
		w.tick(dt, Vector2.ZERO, [0.0, 1.0])
	_check(w.phase == FrontWorld.Phase.PLAYING, "trigger set the area down")
	_check(absf(w.global_position.y) < 0.001, "the area lies on the floor")
	_check(absf(w.pencil_share - 0.5) < 0.05, "the line starts in the middle (%.2f)" % w.pencil_share)
	# The pencil runs into the Eraser's side: the line moves.
	w.freeze = 100.0     # keep the Eraser still for this part
	var before := w.pencil_share
	w.pencil_pos = Vector3(0.1, 0, 0.6)
	for i in range(72 * 2):
		w.tick(dt, Vector2(1, 0), [0.0, 0.0])
	_check(w.pencil_share > before + 0.02, "running colours the floor and pushes the line (%.2f → %.2f)" % [before, w.pencil_share])
	_check(w.value_at(w.pencil_pos) > 0.5, "the floor under him is the pencil's")
	# A crayon stroke where the hand points.
	var p := Vector3(-0.5, 0, 0.9)
	var gp := w.to_global(p)
	hands[1].global_position = gp + Vector3(0, 0.8, 0.2)
	hands[1].look_at(gp, Vector3.UP)
	var ink0 := w.ink
	for k in range(20):
		hands[1].global_position = w.to_global(Vector3(-0.5 + k * 0.04, 0, 0.9)) + Vector3(0, 0.8, 0.2)
		hands[1].look_at(w.to_global(Vector3(-0.5 + k * 0.04, 0, 0.9)), Vector3.UP)
		w.tick(dt, Vector2.ZERO, [0.0, 1.0])
	w.tick(dt, Vector2.ZERO, [0.0, 0.0])
	_check(w.ink < ink0, "drawing spends graphite (%.2f → %.2f)" % [ink0, w.ink])
	# The Eraser rubs the pencil's floor back to grey.
	w.freeze = 0.0
	w.pencil_pos = Vector3(-1.0, 0, -1.0)
	var spot := Vector3(-0.4, 0, -0.5)
	w.paint(spot, 0.3, 2.0, 1.0)
	w.eraser_pos = spot
	var share0 := w.pencil_share
	for i in range(72 * 3):
		w.tick(dt, Vector2.ZERO, [0.0, 0.0])
	_check(w.pencil_share < share0, "the Eraser takes the floor back (%.2f → %.2f)" % [share0, w.pencil_share])
	# A loop round it freezes it; one elsewhere does not.
	var miss := w.commit_stroke(FrontWorld._loop_points(w.eraser_pos + Vector3(0.7, 0, 0), 0.2, 0.01))
	_check(not miss.frozen, "a loop elsewhere does nothing")
	var hit := w.commit_stroke(FrontWorld._loop_points(w.eraser_pos, 0.25, 0.01))
	_check(hit.frozen and w.freeze > 2.5, "a loop round the Eraser freezes it")
	var at := w.eraser_pos
	for i in range(72):
		w.tick(dt, Vector2.ZERO, [0.0, 0.0])
	_check(w.eraser_pos.distance_to(at) < 0.01, "frozen: it does not move")
	# Its bump knocks the pencil over.
	w.freeze = 0.0
	w.pencil_pos = w.eraser_pos + Vector3(0.2, 0, 0)
	w.tick(dt, Vector2.ZERO, [0.0, 0.0])
	_check(w.stun > 0.0, "the Eraser knocked the pencil over")
	# The round ends: the side with more floor wins and floods the area.
	w.time_left = 0.01
	w.tick(dt, Vector2.ZERO, [0.0, 0.0])
	_check(w.phase == FrontWorld.Phase.OVER and w.winner != "", "the round ended (%s)" % w.winner)
	for i in range(72 * 4):
		w.tick(dt, Vector2.ZERO, [0.0, 0.0])
	_check(w.pencil_share > 0.99 or w.pencil_share < 0.01, "the winner's side floods the floor")
	w.on_button(&"ax_button", 0)
	_check(w.phase == FrontWorld.Phase.PLAYING and absf(w.pencil_share - 0.5) < 0.05 and is_equal_approx(w.time_left, FrontWorld.ROUND_TIME), "A plays again")
	root.queue_free()
	await process_frame
	if _failures > 0:
		printerr("FAIL: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS: front line — placing on the floor, pencil pushes the line, crayon stroke, Eraser rubs back, lasso freeze, bump, round end, replay")
	quit(0)


var _failures := 0
func _check(ok: bool, message: String = "") -> void:
	if not ok:
		_failures += 1
		printerr("CHECK FAILED: " + message)
