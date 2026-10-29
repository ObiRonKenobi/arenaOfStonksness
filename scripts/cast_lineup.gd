extends Node3D

const CAST := ["punk", "cowboy", "worker", "punk_f"]

func _ready() -> void:
	for i in CAST.size():
		_place(CAST[i], -2.7 + float(i) * 1.8)

func _place(id: String, x: float) -> void:
	var path := "res://assets/characters/%s.glb" % id
	var packed := load(path) as PackedScene
	if packed == null:
		if "--smoke" in OS.get_cmdline_user_args():
			print("LINEUP ", id, " MISSING")
		return
	var model := packed.instantiate()
	model.name = id
	model.position = Vector3(x, 0.0, 4.8)
	model.rotation.y = PI
	add_child(model)
	_ink(model)
	var playing := false
	var players: Array = model.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		var anim := players[0] as AnimationPlayer
		var clip := _idle_clip(anim)
		if clip != "":
			var animation := anim.get_animation(clip)
			if animation:
				animation.loop_mode = Animation.LOOP_LINEAR
			anim.play(clip)
			playing = anim.is_playing()
	if "--smoke" in OS.get_cmdline_user_args():
		print("LINEUP ", id, " ", "Idle" if playing else "MISSING")

func _idle_clip(anim: AnimationPlayer) -> String:
	if anim.has_animation("Idle"):
		return "Idle"
	for name in anim.get_animation_list():
		if "idle" in String(name).to_lower():
			return String(name)
	return ""

func _ink(node: Node) -> void:
	for child in node.get_children():
		_ink(child)
	if not node is MeshInstance3D:
		return
	var mesh_inst := node as MeshInstance3D
	if mesh_inst.mesh == null:
		return
	mesh_inst.material_override = null
	for surface in mesh_inst.mesh.get_surface_count():
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var source := mesh_inst.get_active_material(surface)
		if source is BaseMaterial3D:
			var base := source as BaseMaterial3D
			flat.albedo_color = base.albedo_color
			flat.albedo_texture = base.albedo_texture
			flat.vertex_color_use_as_albedo = base.vertex_color_use_as_albedo
		mesh_inst.set_surface_override_material(surface, flat)
