extends Node3D

const WALL_H := 3.0
const UPPER_Y := 3.0
const ROOM_TONE := preload("res://assets/audio/interior_night.wav")
const BRICK := preload("res://assets/textures/brick.png")
const PLANKS := preload("res://assets/textures/planks.png")

func _ready() -> void:
	add_to_group("map")
	_box(Vector3(0, -0.15, 0), Vector3(18, 0.3, 14), Color.WHITE, true, PLANKS)
	_box(Vector3(0, -0.15, -9.6), Vector3(18, 0.3, 6.0), Color.WHITE, true, PLANKS)
	_upper_floor()
	_box(Vector3(0, UPPER_Y + 3.0, 0), Vector3(18, 0.2, 14), Color.WHITE, true, PLANKS)
	_walls()
	_stairs()
	_doors()
	_window_blocks()
	_stations()
	_cast_lineup()
	_light()
	_room_tone()

func _upper_floor() -> void:
	# Rectangular hole for the stairs: x 5.6..8.8, z 0.6..4.8. Every edge runs with the walls.
	_box(Vector3(-1.7, UPPER_Y, 0.0), Vector3(14.6, 0.25, 14.0), Color.WHITE, true, PLANKS)
	_box(Vector3(7.2, UPPER_Y, -3.2), Vector3(3.2, 0.25, 7.6), Color.WHITE, true, PLANKS)
	_box(Vector3(7.2, UPPER_Y, 5.9), Vector3(3.2, 0.25, 2.2), Color.WHITE, true, PLANKS)

func _walls() -> void:
	_south_rooms()
	_box(Vector3(-9, WALL_H * 0.5, 0), Vector3(0.4, WALL_H, 14), Color.WHITE, true, BRICK)
	_box(Vector3(9, WALL_H * 0.5, 0), Vector3(0.4, WALL_H, 14), Color.WHITE, true, BRICK)
	_box(Vector3(0, WALL_H + 1.5, -7), Vector3(18, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(0, WALL_H + 1.5, 7), Vector3(18, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(-9, WALL_H + 1.5, 0), Vector3(0.4, 3.0, 14), Color.WHITE, true, BRICK)
	_box(Vector3(9, WALL_H + 1.5, 0), Vector3(0.4, 3.0, 14), Color.WHITE, true, BRICK)
	_north_piers()

func _north_piers() -> void:
	_box(Vector3(-7.05, 1.5, -7), Vector3(3.9, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(-2.1, 1.5, -7), Vector3(2.4, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(2.1, 1.5, -7), Vector3(2.4, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(7.05, 1.5, -7), Vector3(3.9, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(-4.2, 2.7, -7), Vector3(1.8, 0.6, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(0.0, 2.7, -7), Vector3(1.8, 0.6, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(4.2, 2.7, -7), Vector3(1.8, 0.6, 0.4), Color.WHITE, true, BRICK)
	_window_frames()

func _window_frames() -> void:
	var sill := Color(0.34, 0.31, 0.29)
	var frame := Color(0.2, 0.14, 0.11)
	var glass := Color(1, 1, 1, 0)
	for x in [-4.2, 0.0, 4.2]:
		_box(Vector3(x, 0.525, -7), Vector3(1.78, 1.05, 0.4), sill, true)
		_box(Vector3(x - 0.84, 1.72, -7), Vector3(0.1, 1.3, 0.4), frame, true)
		_box(Vector3(x + 0.84, 1.72, -7), Vector3(0.1, 1.3, 0.4), frame, true)
		_pane(Vector3(x, 1.75, -7.0), Vector3(1.5, 1.15, 0.04), glass, 0.0)

func _south_rooms() -> void:
	# Ground-floor south wall, split around doorways at x = -6, 0, and 6.
	_box(Vector3(-7.85, 1.5, 7), Vector3(2.3, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(-3.0, 1.5, 7), Vector3(4.6, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(3.0, 1.5, 7), Vector3(4.6, 3.0, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(7.85, 1.5, 7), Vector3(2.3, 3.0, 0.4), Color.WHITE, true, BRICK)
	for x in [-6.0, 0.0, 6.0]:
		_box(Vector3(x, 2.7, 7), Vector3(1.4, 0.6, 0.4), Color.WHITE, true, BRICK)
	_box(Vector3(0, -0.15, 9.625), Vector3(18, 0.3, 5.55), Color.WHITE, true, PLANKS)
	_box(Vector3(0, UPPER_Y, 9.6), Vector3(18.4, 0.25, 5.6), Color.WHITE, true, PLANKS)
	_box(Vector3(-9, 1.5, 9.6), Vector3(0.4, 3.0, 5.6), Color.WHITE, true, BRICK)
	_box(Vector3(9, 1.5, 9.6), Vector3(0.4, 3.0, 5.6), Color.WHITE, true, BRICK)
	_box(Vector3(-3, 1.5, 9.6), Vector3(0.4, 3.0, 5.2), Color.WHITE, true, BRICK)
	_box(Vector3(3, 1.5, 9.6), Vector3(0.4, 3.0, 5.2), Color.WHITE, true, BRICK)
	_box(Vector3(0, 1.5, 12.2), Vector3(18.4, 3.0, 0.4), Color.WHITE, true, BRICK)
	_gate("Street Smith", 400, Vector3(-6, 0, 7), -1.55)
	_gate("The Markup", 800, Vector3(0, 0, 7), 1.55)
	_gate("Black Market", 500, Vector3(6, 0, 7), 1.55)

func _gate(room_name: String, price: int, pos: Vector3, slide: float) -> void:
	var gate := StaticBody3D.new()
	gate.set_script(load("res://scripts/gate.gd"))
	gate.title = room_name
	gate.price = price
	gate.slide = slide
	gate.position = pos
	add_child(gate)

func _doors() -> void:
	_door(Vector3(-4.2, 1.05, -7), Vector3(0, 0, -2.2))
	_door(Vector3(0, 1.05, -7), Vector3(0, 0, -2.2))
	_door(Vector3(4.2, 1.05, -7), Vector3(0, 0, -2.2))

func _window_blocks() -> void:
	_player_block(Vector3(-4.2, 1.72, -6.72))
	_player_block(Vector3(0.0, 1.72, -6.72))
	_player_block(Vector3(4.2, 1.72, -6.72))

func _player_block(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.55, 1.4, 0.22)
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _door(pos: Vector3, outside: Vector3) -> void:
	var door := StaticBody3D.new()
	door.set_script(load("res://scripts/barricade.gd"))
	door.position = pos
	door.boards = 6
	add_child(door)
	door.set_outside(outside)

func _stairs() -> void:
	var marker := Marker3D.new()
	marker.name = "StairBase"
	marker.position = Vector3(7.2, 0.2, 4.7)
	marker.add_to_group("stairs")
	add_child(marker)
	var landing := Marker3D.new()
	landing.name = "StairTop"
	landing.position = Vector3(7.2, 3.2, 0.75)
	landing.add_to_group("stair_top")
	add_child(landing)
	var tread := 0.32
	var rise_step := 0.25
	for i in 12:
		var top := rise_step * float(i + 1)
		var z := 4.55 - float(i) * tread
		var step := _box(Vector3(7.2, top - rise_step * 0.5, z), Vector3(2.6, rise_step, tread), Color.WHITE, true, PLANKS)
		step.add_to_group("stair_steps")
	_box(Vector3(7.2, UPPER_Y, 0.85), Vector3(2.6, 0.25, 0.7), Color.WHITE, true, PLANKS)

func _stations() -> void:
	_station("wall", Vector3(-7.85, 0, 6.2), "street_smg", "", 180)
	_station("wall", Vector3(-3, 0, 6.2), "debt_shotgun", "", 180)
	_station("wall", Vector3(1.6, 0, 6.2), "rent_rifle", "", 180)
	_station("perk", Vector3(3, 0, 6.2), "", "thick_skin", 180)
	_station("perk", Vector3(7.85, 0, 6.2), "", "rapid_fire", 180)
	_station("perk", Vector3(-8.4, 0, -2), "", "tin_vest", 90)
	_station("perk", Vector3(-8.4, 0, 1.5), "", "mean_streak", 90)
	_station("planks", Vector3(-8.4, 0, 4), "", "", 90)
	_station("smith", Vector3(-6, 0, 11.6), "", "", 180)
	_station("markup", Vector3(0, 0, 11.6), "", "", 180)
	_station("crate", Vector3(6, 0, 11.6), "", "", 180)
	_station("wall", Vector3(8.4, 0, -2), "pop_junk", "", -90)
	_station("wall", Vector3(8.4, 0, 1.5), "ledger_cannon", "", -90)

func _cast_lineup() -> void:
	var row := Node3D.new()
	row.name = "CastLineup"
	row.set_script(load("res://scripts/cast_lineup.gd"))
	add_child(row)

func _station(kind: String, pos: Vector3, weapon_id: String, perk_id: String, yaw: float) -> void:
	var station := StaticBody3D.new()
	station.set_script(load("res://scripts/station.gd"))
	station.kind = kind
	station.weapon_id = weapon_id
	station.perk_id = perk_id
	station.position = pos
	station.rotation.y = deg_to_rad(yaw)
	add_child(station)

func _pane(pos: Vector3, size: Vector3, color: Color, tilt: float) -> void:
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.position = pos
	mesh.rotation_degrees = Vector3(0, 0, tilt)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	add_child(mesh)

func _box(pos: Vector3, size: Vector3, color: Color, solid: bool, surface: Texture2D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	if solid:
		body.collision_layer = 1
		body.collision_mask = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if surface:
		mesh.mesh = _tiled_box(size, pos)
		mat.albedo_texture = surface
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		var cube := BoxMesh.new()
		cube.size = size
		mesh.mesh = cube
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
	return body

const TILE := 0.5

func _tiled_box(size: Vector3, origin: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	_tile_face(st, origin, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(0, 0, 1))
	_tile_face(st, origin, Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(0, 0, -1))
	_tile_face(st, origin, Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(0, 1, 0))
	_tile_face(st, origin, Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(0, -1, 0))
	_tile_face(st, origin, Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(1, 0, 0))
	_tile_face(st, origin, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-1, 0, 0))
	return st.commit()

func _tile_face(st: SurfaceTool, origin: Vector3, bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3, normal: Vector3) -> void:
	var corners: Array[Vector3] = [bl, br, tr, tl]
	var uvs: Array[Vector2] = []
	for corner in corners:
		uvs.append(_tile_uv(corner + origin, normal))
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])

func _tile_uv(p: Vector3, n: Vector3) -> Vector2:
	if n.y > 0.5:
		return Vector2(p.x, -p.z) * TILE
	if n.y < -0.5:
		return Vector2(p.x, p.z) * TILE
	if n.x > 0.5:
		return Vector2(-p.z, p.y) * TILE
	if n.x < -0.5:
		return Vector2(p.z, p.y) * TILE
	if n.z > 0.5:
		return Vector2(p.x, p.y) * TILE
	return Vector2(-p.x, p.y) * TILE

func _room_tone() -> void:
	var tone := AudioStreamPlayer.new()
	tone.stream = ROOM_TONE
	tone.volume_db = -16.0
	if tone.stream is AudioStreamWAV:
		(tone.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	add_child(tone)
	tone.play()

func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 30, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = false
	add_child(sun)
	var env := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color(0.62, 0.66, 0.7)
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color(0.85, 0.82, 0.76)
	world.ambient_light_energy = 1.1
	env.environment = world
	add_child(env)
