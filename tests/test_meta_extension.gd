extends SceneTree
func _initialize() -> void:
	if not ClassDB.class_exists("OpenXRFbPassthroughExtension"):
		push_error("The native Meta passthrough extension did not load")
		quit(1)
		return
	print("PASS: native Meta passthrough extension registered")
	quit(0)

var _elapsed := 0.0
func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > 40.0:
		printerr("FAIL: test timed out (an assert above probably failed)")
		quit(1)
	return false
