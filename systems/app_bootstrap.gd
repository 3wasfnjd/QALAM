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
		head.position = Vector3(0, 1.32, 0.02)
		head.rotation_degrees.x = -38.0
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
	var stick := Vector2.ZERO
	if preview:
		stick = _preview_input(delta, triggers)
	else:
		for i in range(2):
			triggers[i] = controllers[i].get_float("trigger")
			aim_controllers[i].visible = controllers[i].get_is_active()
		var left := controllers[0].get_vector2("thumbstick")
		var right := controllers[1].get_vector2("thumbstick")
		stick = left if left.length() >= right.length() else right
	world.tick(delta, stick, triggers)


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


## Scripted desktop demo through the real game code: place the book, watch it
## open, draw a bridge, cross, push the ball onto the plate, reach the star.
func _preview_input(delta: float, triggers: Array) -> Vector2:
	preview_time += delta
	var t := preview_time
	var stick := Vector2.ZERO
	var hero := world.hero
	if t > 0.6 and world.phase == BookWorld.Phase.PLACING:
		world.place_here()
	if t > 5.0 and t - delta <= 5.0:
		hero.reset_to(Vector3(-1.95, 1.0, 0.2))
		var pts := PackedVector3Array()
		for k in range(12):
			var u := k / 11.0
			pts.append(Vector3(lerpf(-1.65, 0.0, u), 1.15 + sin(u * PI) * 0.1, 0.2 + sin(u * 5.0) * 0.03))
		world._stroke_points[1] = pts
		Sketch.build_tube(world._stroke_meshes[1], pts, 0.045, 5)
		world.pens[1].drawing = true
		aim_controllers[1].global_position = world.page.to_global(pts[pts.size() - 1]) + Vector3(0.02, 0.0, 0.12)
	if t > 5.8 and t - delta <= 5.8:
		world._stroke_points[1] = PackedVector3Array()
		world._stroke_meshes[1].clear_surfaces()
		world.pens[1].drawing = false
		world.try_bridge(Vector3(-1.65, 1.1, 0.2), Vector3(0.85, 1.1, 0.2))
	if t > 6.0 and t < 7.0:
		stick = Vector2(1, 0)
	if t > 7.4 and t - delta <= 7.4:
		var ball_p := world.level.ball_start
		var d := Vector2(world.level.plate.x - ball_p.x, world.level.plate.z - ball_p.z).normalized()
		hero.reset_to(Vector3(ball_p.x - d.x * 0.6, 1.0, ball_p.z - d.y * 0.6))
	if t > 7.4 and t < 9.2 and not world.gate_restored:
		var to_plate := Vector2(world.level.plate.x - world.ball.position.x, world.level.plate.z - world.ball.position.z).normalized()
		stick = Vector2(to_plate.x, -to_plate.y)  # page +z is toward the camera
	if t > 9.6 and t - delta <= 9.6:
		hero.reset_to(Vector3(2.8, 2.0, -0.85))
	if t > 9.8 and t < 11.5:
		stick = Vector2(1, 0)
	var shots := [[0.4, "placing"], [2.3, "opening"], [4.7, "start"], [5.5, "drawing"], [6.6, "bridge"], [8.0, "push"], [9.4, "gate"], [11.0, "goal"], [12.6, "win"], [14.0, "replay"]]
	if preview_shots < shots.size() and t >= shots[preview_shots][0]:
		var shot_name: String = shots[preview_shots][1]
		preview_shots += 1
		_capture(shot_name)
	return stick


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/previews")
	get_viewport().get_texture().get_image().save_png("res://build/previews/%s.png" % shot_name)
	print("preview shot %s: phase=%d hero=%s ball=%s gate=%s bridges=%d" % [shot_name, world.phase, str(world.hero.position.snapped(Vector3.ONE * 0.01)), str(world.ball.position.snapped(Vector3.ONE * 0.01)), str(world.gate_restored), world.bridges.size()])
	if preview_shots >= 10:
		get_tree().quit()


func _stop(message: String) -> void:
	failed = true
	push_error(message)
	OS.alert(message, "QALAM")
	get_tree().quit(1)
