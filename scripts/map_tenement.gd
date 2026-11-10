extends Node3D

const WALL_H := 3.0
const UPPER_Y := 3.0
const WALL_D := 0.4
# Centers are the old lines. Interior faces are 0.2 in from those centers.
const NORTH_C := -7.0
const SOUTH_C := 7.0
const WEST_C := -9.0
const EAST_C := 9.0
const NORTH_IN := NORTH_C + WALL_D * 0.5
const SOUTH_IN := SOUTH_C - WALL_D * 0.5
const WEST_IN := WEST_C + WALL_D * 0.5
const EAST_IN := EAST_C - WALL_D * 0.5
const SOUTH_OUT := SOUTH_C + WALL_D * 0.5
const FLOOR_TOP := 3.125
var _brick: Texture2D
var _planks: Texture2D
var _built := false

func _ready() -> void:
	add_to_group("map")
	if _boot_now():
		build()
		load_audio()

func _boot_now() -> bool:
	var args := OS.get_cmdline_user_args()
	return "--smoke" in args or "--audit" in args or "--gunfit" in args or "--boards" in args or "--ads" in args or _nav_boot(args)

func _nav_boot(args: PackedStringArray) -> bool:
	for arg in args:
		if arg.begins_with("--nav"):
			return true
	return false

func load_textures() -> void:
	if _brick != null:
		return
	_brick = load("res://assets/textures/brick.png")
	_planks = load("res://assets/textures/planks.png")

func build() -> void:
	if _built:
		return
	_built = true
	load_textures()
	# Main floor runs under the south wall to its outer face.
	_box(Vector3(0, -0.15, 0.1), Vector3(18, 0.3, 14.2), Color.WHITE, true, _planks)
	_box(Vector3(0, -0.15, -9.9), Vector3(18, 0.3, 6.6), Color.WHITE, true, _planks)
	_upper_floor()
	_box(Vector3(0, UPPER_Y + 3.0, 0), Vector3(18, 0.2, 14), Color.WHITE, true, _planks)
	_walls()
	_stairs()
	_doors()
	_window_blocks()
	_stations()
	_light()
	_bake_nav()

func _upper_floor() -> void:
	# Hole on the east wall, centered along it: x 5.6..8.8, z -2.1..2.1.
	# The west slab runs past the stair wall so the boards cover its top.
	var cover := 5.72
	var west_x0 := -9.0
	var west_c := (west_x0 + cover) * 0.5
	_box(Vector3(west_c, UPPER_Y, 0.0), Vector3(cover - west_x0, 0.25, 14.0), Color.WHITE, true, _planks)
	# East caps tuck into the east wall so the landing seam stays plank.
	# The north cap's collision starts past the hole so the ramp can meet it without a lip.
	var cap_x0 := 3.8
	var cap_x1 := 9.05
	var cap_c := (cap_x0 + cap_x1) * 0.5
	var cap_w := cap_x1 - cap_x0
	# Caps overlap the main upstairs floor by almost 2 m, and the north cap
	# overlaps the ramp nose, so the bake keeps a path around the hole.
	var north_z0 := -7.0
	var north_z1 := -2.15
	_box(Vector3(cap_c, UPPER_Y, (north_z0 + north_z1) * 0.5), Vector3(cap_w, 0.25, north_z1 - north_z0), Color.WHITE, true, _planks)
	var south_z0 := 2.1
	var south_z1 := 7.0
	_box(Vector3(cap_c, UPPER_Y, (south_z0 + south_z1) * 0.5), Vector3(cap_w, 0.25, south_z1 - south_z0), Color.WHITE, true, _planks)

func _walls() -> void:
	_south_rooms()
	_box(Vector3(WEST_C, WALL_H * 0.5, 0), Vector3(WALL_D, WALL_H, 14.4), Color.WHITE, true, _brick)
	_box(Vector3(EAST_C, WALL_H * 0.5, 0), Vector3(WALL_D, WALL_H, 14.4), Color.WHITE, true, _brick)
	_box(Vector3(0, WALL_H + 1.5, NORTH_C), Vector3(18.4, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(0, WALL_H + 1.5, SOUTH_C), Vector3(18.4, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(WEST_C, WALL_H + 1.5, 0), Vector3(WALL_D, 3.0, 14.4), Color.WHITE, true, _brick)
	_box(Vector3(EAST_C, WALL_H + 1.5, 0), Vector3(WALL_D, 3.0, 14.4), Color.WHITE, true, _brick)
	_north_piers()

func _north_piers() -> void:
	_box(Vector3(-7.05, 1.5, NORTH_C), Vector3(3.9, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(-2.1, 1.5, NORTH_C), Vector3(2.4, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(2.1, 1.5, NORTH_C), Vector3(2.4, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(7.05, 1.5, NORTH_C), Vector3(3.9, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(-4.2, 2.7, NORTH_C), Vector3(1.8, 0.6, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(0.0, 2.7, NORTH_C), Vector3(1.8, 0.6, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(4.2, 2.7, NORTH_C), Vector3(1.8, 0.6, WALL_D), Color.WHITE, true, _brick)
	_window_frames()

func _window_frames() -> void:
	var frame := Color(0.2, 0.14, 0.11)
	var glass := Color(1, 1, 1, 0)
	# 1.5 m clear opening. Posts sit proud of the brick so the jamb does not z-fight.
	var post_c := 0.93
	var post_w := 0.36
	var sill_y := 1.05
	var head_y := 2.4
	var frame_z := NORTH_C + 0.014
	var frame_d := WALL_D + 0.03
	for x in [-4.2, 0.0, 4.2]:
		_box(Vector3(x, sill_y * 0.5, NORTH_C), Vector3(1.9, sill_y, WALL_D), Color.WHITE, true, _brick)
		_box(Vector3(x - post_c, (sill_y + head_y) * 0.5, frame_z), Vector3(post_w, head_y - sill_y + 0.06, frame_d), frame, true)
		_box(Vector3(x + post_c, (sill_y + head_y) * 0.5, frame_z), Vector3(post_w, head_y - sill_y + 0.06, frame_d), frame, true)
		_box(Vector3(x, (head_y + WALL_H) * 0.5, NORTH_C), Vector3(1.6, WALL_H - head_y, WALL_D), Color.WHITE, true, _brick)
		_pane(Vector3(x, (sill_y + head_y) * 0.5, NORTH_C), Vector3(1.5, head_y - sill_y, 0.04), glass, 0.0)

func _south_rooms() -> void:
	# Ground-floor south wall. Each shop door is a 2 m gap, wide enough after the nav carve.
	_box(Vector3(-8.0, 1.5, SOUTH_C), Vector3(2.0, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(-3.0, 1.5, SOUTH_C), Vector3(4.0, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(3.0, 1.5, SOUTH_C), Vector3(4.0, 3.0, WALL_D), Color.WHITE, true, _brick)
	_box(Vector3(8.0, 1.5, SOUTH_C), Vector3(2.0, 3.0, WALL_D), Color.WHITE, true, _brick)
	for x in [-6.0, 0.0, 6.0]:
		_box(Vector3(x, (2.4 + WALL_H) * 0.5, SOUTH_C), Vector3(2.0, WALL_H - 2.4, WALL_D), Color.WHITE, true, _brick)
	# Shop floors overlap the south wall and the back wall so no seam opens to the sky.
	var shop_z0 := SOUTH_OUT - 0.2
	var shop_z1 := 12.4
	var shop_depth := shop_z1 - shop_z0
	var shop_z := (shop_z0 + shop_z1) * 0.5
	_box(Vector3(0, -0.15, shop_z), Vector3(18, 0.3, shop_depth), Color.WHITE, true, _planks)
	_box(Vector3(0, UPPER_Y, shop_z), Vector3(18.4, 0.25, shop_depth), Color.WHITE, true, _planks)
	_box(Vector3(WEST_C, 1.5, shop_z), Vector3(WALL_D, 3.0, shop_depth), Color.WHITE, true, _brick)
	_box(Vector3(EAST_C, 1.5, shop_z), Vector3(WALL_D, 3.0, shop_depth), Color.WHITE, true, _brick)
	var party_z0 := SOUTH_OUT
	var party_z1 := 12.0
	var party_z := (party_z0 + party_z1) * 0.5
	var party_d := party_z1 - party_z0
	_box(Vector3(-3, 1.5, party_z), Vector3(0.2, 3.0, party_d), Color.WHITE, true, _brick)
	_box(Vector3(3, 1.5, party_z), Vector3(0.2, 3.0, party_d), Color.WHITE, true, _brick)
	_box(Vector3(0, 1.5, 12.2), Vector3(18.4, 3.0, WALL_D), Color.WHITE, true, _brick)
	_gate("Street Smith", 400, Vector3(-6, 0, SOUTH_C), -2.2)
	_gate("The Markup", 800, Vector3(0, 0, SOUTH_C), 2.2)
	_gate("Black Market", 500, Vector3(6, 0, SOUTH_C), 2.2)

func _gate(room_name: String, price: int, pos: Vector3, slide: float) -> void:
	var gate := StaticBody3D.new()
	gate.set_script(load("res://scripts/gate.gd"))
	gate.title = room_name
	gate.price = price
	gate.slide = slide
	gate.position = pos
	add_child(gate)

func _doors() -> void:
	_door(Vector3(-4.2, 1.05, NORTH_C), Vector3(0, 0, -2.2))
	_door(Vector3(0, 1.05, NORTH_C), Vector3(0, 0, -2.2))
	_door(Vector3(4.2, 1.05, NORTH_C), Vector3(0, 0, -2.2))

func _window_blocks() -> void:
	# Room face of the block is the interior plane. The block itself is inside the wall.
	var block_z := NORTH_IN - 0.08
	_player_block(Vector3(-4.2, 1.725, block_z))
	_player_block(Vector3(0.0, 1.725, block_z))
	_player_block(Vector3(4.2, 1.725, block_z))

func _player_block(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.35, 0.16)
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
	# 17 risers to the upstairs floor. The run fills the east-wall hole, bottom toward the south.
	var z_south := 2.1
	var z_north := -2.1
	var rise := FLOOR_TOP / 17.0
	var tread := (z_south - z_north) / 16.0
	var width := EAST_IN - 5.6
	var cx := (5.6 + EAST_IN) * 0.5
	var wood := 0.06
	for i in 16:
		var top := rise * float(i + 1)
		var z := z_south - tread * 0.5 - float(i) * tread
		var brick_h := maxf(top - wood, 0.02)
		_box(Vector3(cx, brick_h * 0.5, z), Vector3(width, brick_h, tread), Color.WHITE, false, _brick)
		var step := _box(Vector3(cx, top - wood * 0.5, z), Vector3(width, wood, tread), Color.WHITE, false, _planks)
		step.add_to_group("stair_steps")
	_stair_ramp(5.6, EAST_IN, z_south, z_north)
	# Brick side wall stops inside the floor slab so the boards cover its top.
	var wall_top := UPPER_Y
	_box(Vector3(5.5, wall_top * 0.5, 0.0), Vector3(0.2, wall_top, z_south - z_north), Color.WHITE, true, _brick)
	_stair_rails()

const STAIR_LANES: Array[float] = [6.25, 7.2, 8.15]

func lane_x(lane: int) -> float:
	return STAIR_LANES[clampi(lane, 0, STAIR_LANES.size() - 1)]

func stair_count() -> int:
	return STAIR_LANES.size()

func stair_entry(lane: int, going_up: bool) -> Vector3:
	var x := _lane_x(lane)
	if going_up:
		return Vector3(x, 0.0, 2.75)
	return Vector3(x, FLOOR_TOP, -3.4)

func stair_exit(lane: int, going_up: bool) -> Vector3:
	var x := _lane_x(lane)
	if going_up:
		return Vector3(x, FLOOR_TOP, -2.5)
	return Vector3(x, 0.0, 2.75)

func stair_through(lane: int) -> Vector3:
	return Vector3(_lane_x(lane), FLOOR_TOP, _clear_z(lane))

func stair_clear(lane: int) -> Vector3:
	return Vector3(5.15, FLOOR_TOP, _clear_z(lane))

func _clear_z(lane: int) -> float:
	return -2.7 - float(clampi(lane, 0, 2)) * 0.9

func _lane_x(lane: int) -> float:
	return STAIR_LANES[clampi(lane, 0, STAIR_LANES.size() - 1)]

func on_ramp(at: Vector3) -> bool:
	return at.x >= 5.6 and at.z >= -2.2 and at.z <= 2.2 and at.y > 0.1 and at.y < 3.05

func floor_level(at: Vector3) -> int:
	return 1 if at.y > 1.8 else 0

func needs_stairs(a: Vector3, b: Vector3) -> bool:
	return floor_level(a) != floor_level(b) and not on_ramp(b)

func _stair_rails() -> void:
	# Enemies only. The player can still drop through the stair hole.
	var rail := StaticBody3D.new()
	rail.collision_layer = 16
	rail.collision_mask = 0
	_rail_box(rail, Vector3(5.68, 3.725, -0.025), Vector3(0.08, 1.2, 4.25))
	_rail_box(rail, Vector3(7.22, 3.725, 1.62), Vector3(3.16, 1.2, 0.08))
	add_child(rail)

func _rail_box(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)

func _stair_ramp(x0: float, x1: float, z_south: float, z_north: float) -> void:
	# One slope from the ground floor to a flat nose under the landing. No risers to bob on.
	var inset := 0.06
	var xa := x0 + inset
	var xb := x1 - inset
	var z_flat := z_north - 2.1
	var y_top := FLOOR_TOP
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("stair_steps")
	body.add_to_group("navmesh")
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.margin = 0.001
	hull.points = PackedVector3Array([
		Vector3(xa, -0.2, z_south), Vector3(xb, -0.2, z_south),
		Vector3(xa, -0.2, z_flat), Vector3(xb, -0.2, z_flat),
		Vector3(xa, 0.0, z_south), Vector3(xb, 0.0, z_south),
		Vector3(xa, y_top, z_north), Vector3(xb, y_top, z_north),
		Vector3(xa, y_top, z_flat), Vector3(xb, y_top, z_flat),
	])
	shape.shape = hull
	body.add_child(shape)
	add_child(body)

var _nav_region: NavigationRegion3D

func _bake_nav() -> void:
	# Group navmesh is floors, walls, ramps, and stations. Gates are not in it.
	# A new stair is any solid slope under the limits below. A new door is another gate.
	var nav := NavigationMesh.new()
	nav.agent_radius = 0.45
	nav.agent_height = 1.75
	nav.agent_max_climb = 0.3
	nav.agent_max_slope = 45.0
	nav.cell_size = 0.1
	nav.cell_height = 0.05
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_collision_mask = 1
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav.geometry_source_group_name = "navmesh"
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	if _nav_region == null:
		_nav_region = NavigationRegion3D.new()
		_nav_region.name = "Nav"
		add_child(_nav_region)
	_nav_region.navigation_mesh = nav

func _stations() -> void:
	# Wall mounts sit on the interior face; shops stay on the floor in their rooms.
	_station("wall", Vector3(-7.85, 0, SOUTH_IN), "street_smg", "", 180)
	_station("wall", Vector3(-3, 0, SOUTH_IN), "debt_shotgun", "", 180)
	_station("wall", Vector3(5.4, 0, 0.0), "rent_rifle", "", -90)
	_station("perk", Vector3(3, 0, SOUTH_IN), "", "thick_skin", 180)
	_station("perk", Vector3(7.85, 0, SOUTH_IN), "", "rapid_fire", 180)
	_station("perk", Vector3(WEST_IN, 0, -2), "", "tin_vest", 90)
	_station("perk", Vector3(WEST_IN, 0, 1.5), "", "mean_streak", 90)
	_station("planks", Vector3(WEST_IN, 0, 4), "", "", 90)
	_station("smith", Vector3(-6, 0, 11.6), "", "", 180)
	_station("markup", Vector3(0, 0, 11.6), "", "", 180)
	_station("crate", Vector3(6, 0, 11.6), "", "", 180)

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
	station.add_to_group("navmesh")
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
		body.add_to_group("navmesh")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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

func load_audio() -> void:
	if has_node("RoomTone"):
		return
	var stream := load("res://assets/audio/interior_night.wav") as AudioStream
	if stream == null:
		return
	var tone := AudioStreamPlayer.new()
	tone.name = "RoomTone"
	tone.stream = stream
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
