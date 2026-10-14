extends SceneTree
const Clock = preload("res://systems/intro_clock.gd")
func _initialize() -> void:
	var c = Clock.new()
	c.tick(0.4,true)
	_check(is_equal_approx(c.opacity(),1.0))
	c.tick(30,false)
	_check(is_equal_approx(c.elapsed,0.4))
	c.tick(4.2,true)
	_check(not c.finished)
	_check(is_equal_approx(c.opacity(),1.0))
	c.tick(0.4,true)
	_check(c.finished and is_zero_approx(c.opacity()))
	if _failures > 0:
		printerr("FAIL: %d check(s) failed" % _failures)
		quit(1)
		return
	print("PASS: intro 5.0 s, focus pause, fade intervals")
	quit(0)

var _failures := 0
func _check(ok: bool) -> void:
	if not ok:
		_failures += 1
		printerr("CHECK FAILED")

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
