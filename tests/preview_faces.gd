extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.9, 0.87, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 0.95, 0.88)
	env.environment.ambient_light_energy = 0.5
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.7
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.6, 2.4)
	cam.fov = 40
	root.add_child(cam)
	cam.look_at(Vector3(0, 0.55, 0))
	var faces := [0, 1, 2, 3, 4, 5]
	var heroes: Array = []
	for i in range(6):
		var h := PencilRig.new()
		root.add_child(h)
		h.position = Vector3((i - 2.5) * 0.42, 0, 0)
		h.rotation.y = PI
		heroes.append(h)
	await process_frame
	for i in range(6):
		heroes[i].set_face(faces[i])
		heroes[i].rotation.y = PI + (i - 2.5) * 0.12
	var anims := [&"idle", &"tired_idle", &"celebrate", &"lose_balance", &"sad", &"push"]
	for i in range(6):
		heroes[i].play(anims[i])
	for k in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://build/previews/hero_faces.png")
	quit(0)
