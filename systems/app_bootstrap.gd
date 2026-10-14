extends Node3D
## Boot sequence: OpenXR + passthrough, studio intro, then hands the frame
## loop to BookWorld. Desktop "--preview" mode fakes the headset so CI can
## render flat screenshots (which prove nothing about the Quest itself).

const IntroClock = preload("res://systems/intro_clock.gd")

var clock = IntroClock.new()
var xr: OpenXRInterface
var origin: XROrigin3D
var head: XRCamera3D
var studio: Sprite3D
var controllers: Array[XRController3D] = []
var aim_controllers: Array[XRController3D] = []
var world: BookWorld
var sun: DirectionalLight3D
var foreground: bool = true
var positioned: bool = false
var rendered: bool = false
var failed: bool = false
var preview: bool = false
var preview_time: float = 0.0
var preview_shots: int = 0
var started: bool = false


func _ready() -> void:
	preview = OS.get_cmdline_user_args().has("--preview") and not OS.has_feature("android")
	get_viewport().transparent_bg = true
	origin = XROrigin3D.new()
	add_child(origin)
	head = XRCamera3D.new()
	head.near = 0.02
	head.far = 40.0
	origin.add_child(head)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 0.95, 0.88)
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	add_child(environment_node)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 35, 0)
	sun.light_energy = 0.7
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 3.0
	add_child(sun)
	studio = Sprite3D.new()
	studio.texture = load("res://assets/ui/studio.png")
	studio.pixel_size = 0.00085
	studio.modulate.a = 0.0
	add_child(studio)
	for i in range(2):
		var controller := XRController3D.new()
		controller.tracker = &"left_hand" if i == 0 else &"right_hand"
		controller.pose = &"grip"
		origin.add_child(controller)
		controllers.append(controller)
		controller.button_pressed.connect(_button.bind(i))
		var aim := XRController3D.new()
		aim.tracker = controller.tracker
		aim.pose = &"aim"
		origin.add_child(aim)
		aim_controllers.append(aim)
	world = BookWorld.new()
	add_child(world)
	world.visible = false
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if preview:
		environment.background_color = Color(0.36, 0.34, 0.31, 1.0)
		get_viewport().transparent_bg = false
		head.position = Vector3(0, 1.2, -0.04)
		head.rotation_degrees.x = -36.0
		aim_controllers[0].position = Vector3(-0.36, 1.0, -0.12)
		aim_controllers[0].rotation_degrees = Vector3(-35, 10, 0)
		aim_controllers[1].position = Vector3(0.36, 1.0, -0.12)
		aim_controllers[1].rotation_degrees = Vector3(-40, -15, 0)
	else:
		if xr == null or (not xr.is_initialized() and not xr.initialize()):
			_stop("تعذر تشغيل OpenXR. أعد تشغيل التطبيق من النظارة.")
			return
		get_viewport().use_xr = true
		if not xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
			_stop("Passthrough غير متاح. اللعبة تتطلب رؤية الغرفة.")
			return
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		xr.pose_recentered.connect(_recenter)
		if xr.get_available_display_refresh_rates().has(72.0):
			xr.display_refresh_rate = 72.0
	RenderingServer.frame_post_draw.connect(_frame_drawn)


func _frame_drawn() -> void:
	rendered = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		foreground = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		foreground = true


func _tracking_ready() -> bool:
	if preview:
		return true
	if xr == null or xr.get_session_state() != OpenXRInterface.SESSION_STATE_FOCUSED:
		return false
	var tracker := XRServer.get_tracker("head") as XRPositionalTracker
	if tracker == null or not tracker.has_pose("default"):
		return false
	var pose := tracker.get_pose("default")
	if not pose.has_tracking_data or pose.tracking_confidence == XRPose.XR_TRACKING_CONFIDENCE_NONE:
		return false
	if not Engine.has_singleton("OpenXRFbPassthroughExtension"):
		return false
	return bool(Engine.get_singleton("OpenXRFbPassthroughExtension").call("is_passthrough_started"))


func _process(delta: float) -> void:
	if failed:
		return
	var ready := foreground and _tracking_ready()
	if ready and not positioned:
		_recenter()
		positioned = true
		rendered = false
		return
	studio.modulate.a = clock.tick(delta, ready and positioned and rendered)
	studio.visible = not clock.finished and ready
	if clock.finished and not started:
		started = true
		var hands: Array[Node3D] = []
		for a in aim_controllers:
			hands.append(a)
		world.build(head, hands)
		world.visible = true
		world.haptic.connect(func(hand: int, amplitude: float, seconds: float):
			if not preview and hand < controllers.size():
				controllers[hand].trigger_haptic_pulse(&"haptic", 0.0, amplitude, seconds, 0.0))
	if not started or not ready:
		return
	var triggers := [0.0, 0.0]
	var grips := [0.0, 0.0]
	var stick := Vector2.ZERO
	if preview:
		stick = _preview_input(delta, triggers)
	else:
		for i in range(2):
			triggers[i] = controllers[i].get_float("trigger")
			grips[i] = controllers[i].get_float("grip")
			aim_controllers[i].visible = controllers[i].get_is_active()
		var left := controllers[0].get_vector2("thumbstick")
		var right := controllers[1].get_vector2("thumbstick")
		stick = left if left.length() >= right.length() else right
	world.tick(delta, stick, triggers, grips)


func _button(action: StringName, hand_index: int) -> void:
	if not clock.finished or not foreground or world == null or not started:
		return
	world.on_button(action, hand_index)


func _recenter() -> void:
	var forward := -head.global_basis.z
	forward.y = 0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	studio.global_position = head.global_position + forward * 1.6
	studio.look_at(head.global_position, Vector3.UP, true)


## Scripted desktop demo through the real game code (flat screenshots for
## CI; they prove nothing about the headset): placing, the intro, drawing,
## the colour drop, erasing, the ramp and ball, the gate, stairs, the ending.
var _pv_step: int = 0
var _pv_t: float = 0.0
var _pv_steps: Array = []


func _preview_input(delta: float, _triggers: Array) -> Vector2:
	if _pv_steps.is_empty():
		_pv_steps = _preview_plan()
	_pv_t += delta
	var stick := Vector2.ZERO
	if _pv_step >= _pv_steps.size():
		get_tree().quit()
		return stick
	var step: Dictionary = _pv_steps[_pv_step]
	if step.has("stick"):
		stick = step.stick
	if step.has("until") and not (step.until as Callable).call():
		if _pv_t < step.get("max", 20.0):
			return stick
	elif _pv_t < step.get("t", 0.0):
		return stick
	if step.has("then"):
		(step.then as Callable).call()
	if step.has("shot"):
		_capture(step.shot)
	_pv_step += 1
	_pv_t = 0.0
	return stick


func _preview_plan() -> Array:
	var w := world
	var P := BookWorld.Phase
	return [
		{"t": 0.5, "shot": "01_placing"},
		{"t": 0.2, "then": func(): w.place_here()},
		{"t": 0.8, "shot": "02_shake"},
		{"t": 1.6, "shot": "03_opening_dust"},
		{"t": 1.6, "shot": "04_popup"},
		{"until": func(): return w._intro_beats_queued, "max": 4.0, "shot": "05_emerge"},
		{"t": 4.0, "shot": "06_look_tree"},
		{"until": func(): return w.phase == P.PLAYING, "max": 30.0},
		{"t": 0.3, "shot": "07_points_across"},
		{"t": 0.2, "then": func():
			var pts := PackedVector3Array()
			for k in range(14):
				var u := k / 13.0
				pts.append(Vector3(lerpf(-3.55, -2.4, u), 1.12 + sin(u * PI) * 0.12, 1.6 + sin(u * 4.0) * 0.05))
			w._strokes[1] = pts
			Sketch.build_tube(w._stroke_meshes[1], pts, 0.05, 5)
			w.pens[1].drawing = true
			aim_controllers[1].global_position = w.page.to_global(pts[pts.size() - 1]) + Vector3(0.02, 0.0, 0.14), "shot": "08_drawing"},
		{"t": 0.3, "then": func():
			w._strokes[1] = PackedVector3Array()
			w._stroke_meshes[1].clear_surfaces()
			w.pens[1].drawing = false
			var raw := PackedVector3Array()
			for k in range(20):
				var u := k / 19.0
				raw.append(Vector3(lerpf(-3.55, -1.65, u), 1.08 + sin(u * PI) * 0.1, 1.6 + sin(u * 4.0) * 0.05))
			w.commit_path(raw)},
		{"t": 1.6, "shot": "09_careful_step"},
		{"until": func(): return not w.hero.scripted(), "max": 6.0},
		{"until": func(): return w.light_taken, "max": 8.0, "stick": Vector2(1, 0)},
		{"t": 0.6, "shot": "10_colour_drop"},
		{"t": 2.0, "shot": "11_flower_blooms"},
		{"until": func(): return w.hero.position.x > -0.3, "max": 6.0, "stick": Vector2(1, 0)},
		{"t": 2.6, "shot": "12_erase_hint"},
		{"t": 0.1, "then": func():
			var id: String = w.level.paths[0].id
			(w.paths[id] as PathView).erase_amount = 0.6
			(w.paths[id] as PathView).targeted = true, "shot": "13_erasing"},
		{"t": 0.3, "then": func(): w.erase_path(w.level.paths[0].id)},
		{"t": 0.8, "then": func():
			var raw := PackedVector3Array()
			for k in range(24):
				var u := k / 23.0
				var x := lerpf(-1.0, 1.8, u)
				raw.append(Vector3(x, lerpf(2.2, 1.0, smoothstep(0.0, 1.0, u)), -1.15 - u * 0.1))
			w.commit_path(raw), "shot": "14_ramp_drawn"},
		{"t": 1.0, "shot": "15_ball_rolls"},
		{"until": func(): return w.ball_caught, "max": 5.0},
		{"t": 1.8, "shot": "16_gate_opens"},
		{"t": 0.2, "then": func():
			w.erase_path(w.level.paths[0].id)
			w.hero.reset_to(Vector3(2.05, 1.0, 2.0))
			var raw := PackedVector3Array()
			for k in range(16):
				var u := k / 15.0
				raw.append(Vector3(lerpf(2.1, 3.95, u), lerpf(1.0, 1.5, u) + sin(u * PI) * 0.1, 2.0))
			w.commit_path(raw)},
		{"t": 1.2, "stick": Vector2(1, 0), "shot": "17_stairs"},
		{"t": 0.1, "then": func():
			w.hero.reset_to(Vector3(4.0, 2.5, -2.8))},
		{"until": func(): return w.phase == P.ENDING, "max": 4.0, "stick": Vector2(1, 0)},
		{"t": 1.4, "shot": "18_holds_orb"},
		{"t": 3.0, "shot": "19_colour_wave"},
		{"t": 3.0, "shot": "20_life_returns"},
		{"t": 1.6, "shot": "21_next_page"},
		{"t": 4.0, "shot": "22_page_two"},
	]


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	get_viewport().get_texture().get_image().save_png("res://build/previews/%s.png" % shot_name)
	print("preview shot %s: phase=%d hero=%s ink=%.2f paths=%d ball=%s caught=%s" % [shot_name, world.phase, str(world.hero.position.snapped(Vector3.ONE * 0.01)), world.level.ink, world.level.paths.size(), str(world.ball.position.snapped(Vector3.ONE * 0.01)), str(world.ball_caught)])


func _stop(message: String) -> void:
	failed = true
	push_error(message)
	OS.alert(message, "QALAM")
	get_tree().quit(1)
