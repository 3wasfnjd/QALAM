extends RefCounted

var elapsed: float = 0.0
var finished: bool = false

func tick(delta: float, visible_and_focused: bool) -> float:
	if not visible_and_focused or finished:
		return opacity()
	elapsed = minf(5.0, elapsed + maxf(delta, 0.0))
	finished = elapsed >= 5.0
	return opacity()

func opacity() -> float:
	if elapsed < 0.4:
		return elapsed / 0.4
	if elapsed <= 4.6:
		return 1.0
	return clampf((5.0 - elapsed) / 0.4, 0.0, 1.0)
