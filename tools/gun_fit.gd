extends Node

const HIP_GUN := Vector3(0.24, -0.2, -0.42)
const ADS_GUN := Vector3(0.0, -0.11, -0.5)
const AKIMBO_HIP := Vector3(0.0, -0.14, -0.30)
const HIP_FOV := 75.0
const ADS_FOV := 60.0
const ADS_FOV_LONG := 50.0
const VIEW_W := 1280
const VIEW_H := 720
const CELL := 0.03
const GAP_BAND := 0.01
const BORE_LIMIT := 3.0
const SCALE_LIMIT := 1.02
const CLIP_PAD := 0.005
const ROLL_LIMIT := 45.0
const COLLAPSE_LIMIT := 0.02

const ROWS := [
	["pipe_pistol", 1], ["pipe_pistol", 2], ["pipe_pistol", 3],
	["street_smg", 1], ["street_smg", 2], ["street_smg", 3],
	["debt_shotgun", 1], ["debt_shotgun", 2], ["debt_shotgun", 3],
	["rent_rifle", 1], ["rent_rifle", 2], ["rent_rifle", 3],
	["pop_junk", 1], ["ledger_cannon", 1],
]

const PARTS := ["palm", "index", "middle", "thumb"]
const BONES := {
	"r": {
		"palm": ["Hand.R.001"],
		"index": ["Index.R.001", "IndexTip.R.001"],
		"middle": ["DoubleFingers.R.001", "DoubleFingersTip.R.001"],
		"thumb": ["Thumb.R.001", "ThumbTip.R.001"],
	},
	"l": {
		"palm": ["Hand.L"],
		"index": ["Index.L", "IndexTip.L"],
		"middle": ["DoubleFingers.L", "DoubleFingersTip.L"],
		"thumb": ["Thumb.L", "ThumbTip.L"],
	},
}
const PART_COLOR := {
	"palm": Color(1.0, 0.86, 0.1),
	"index": Color(1.0, 0.22, 0.18),
	"middle": Color(0.2, 0.95, 0.35),
	"thumb": Color(0.35, 0.55, 1.0),
}

var _player: CharacterBody3D
var _camera: Camera3D
var _mount: Node3D
var _vp: SubViewport
var _cam: Camera3D
var _label: Label
var _only := ""
var _save := false
var _shot_dir := ""
var _near := 0.05
var _hips: Array[Image] = []
var _hit_d := 0.0
var _hit_s := 1.0
var _hit_p := Vector3.ZERO
var _project_checked := false
var _epoch := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--save-baseline":
			_save = true
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	_shot_dir = OS.get_environment("TEMP")
	if _shot_dir == "":
		_shot_dir = OS.get_environment("TMP")
	_shot_dir += "\\stonks_shots\\guns\\"
	_boot()
	call_deferred("_run")

func _boot() -> void:
	seed(1)
	OS.set_low_processor_usage_mode(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.visible = false
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	GameState.begin_match()
	get_node("/root/RoundDirector").call("_stop")
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.velocity = Vector3.ZERO
	_player.set("_aim", 0.0)
	_player.global_position = Vector3(0.0, 60.0, 0.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.free()
	_camera = _player.get_node("Head/Camera3D") as Camera3D
	_mount = _player.get("_gun_mount") as Node3D
	_near = _camera.near
	_make_view()

func _make_view() -> void:
	_vp = SubViewport.new()
	_vp.name = "GunFitView"
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.own_world_3d = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	_vp.disable_3d = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.name = "FitCamera"
	_cam.current = true
	_cam.fov = HIP_FOV
	_cam.near = _near
	_cam.far = _camera.far
	_cam.keep_aspect = _camera.keep_aspect
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	_cam.environment = env
	_vp.add_child(_cam)
	var layer := CanvasLayer.new()
	_vp.add_child(layer)
	var back := ColorRect.new()
	back.position = Vector2(12, VIEW_H - 64)
	back.size = Vector2(980, 48)
	back.color = Color(0, 0, 0, 0.45)
	layer.add_child(back)
	_label = Label.new()
	_label.position = Vector2(24, VIEW_H - 58)
	_label.size = Vector2(960, 40)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)

func _run() -> void:
	if not _self_check():
		print("GUNFIT_FAIL self_check")
		get_tree().quit(1)
		return
	if _player == null or _mount == null:
		print("GUNFIT_FAIL no_player")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: Array = []
	for spec in ROWS:
		var id := String(spec[0])
		var tier := int(spec[1])
		if not _include(id, tier):
			continue
		print("GUNFIT_WORK %s t%d" % [id, tier])
		var row: Dictionary = await _measure_weapon(id, tier)
		if _picture(id, tier):
			await _shoot(row)
		rows.append(row)
	var pistol_ref := _find_row(rows, "pipe_pistol", 1)
	var rifle_ref := _find_row(rows, "rent_rifle", 2)
	for row in rows:
		var ref: Dictionary = rifle_ref if row.rifle else pistol_ref
		_fill_ratios(row, ref)
		row.reasons = _reasons(row, ref)
	_print_refs(pistol_ref, rifle_ref)
	var baseline: Dictionary = {}
	var have_base := false
	if not _save and FileAccess.file_exists(_baseline_path()):
		baseline = _read_baseline()
		have_base = not baseline.is_empty() or FileAccess.file_exists(_baseline_path())
		if baseline.is_empty():
			print("GUNFIT_BASELINE unreadable")
			have_base = false
	for row in rows:
		_print_row(row)
		if have_base:
			_print_compare(row, baseline)
	if _save and _only == "":
		_write_baseline(rows)
		print("GUNFIT_BASELINE %s" % _baseline_path())
	elif _save:
		print("GUNFIT_BASELINE skipped partial")
	_write_overview()
	print("GUNFIT_SHOTS %s" % _shot_dir)
	print("GUNFIT_DONE")
	get_tree().quit(0)

func _tokens() -> PackedStringArray:
	var out := PackedStringArray()
	if _only == "":
		return out
	for part in _only.split(","):
		var token := part.strip_edges()
		if token != "":
			out.append(token)
	return out

func _include(id: String, tier: int) -> bool:
	var tokens := _tokens()
	if tokens.is_empty():
		return true
	var key := "%s:%d" % [id, tier]
	var need_rifle := false
	var need_pistol := false
	for token in tokens:
		if token == key:
			return true
		var bits := token.split(":")
		if bits.size() < 2:
			continue
		if _rifle(bits[0], int(bits[1])):
			need_rifle = true
		else:
			need_pistol = true
	if need_rifle and id == "rent_rifle" and tier == 2:
		return true
	if need_pistol and id == "pipe_pistol" and tier == 1:
		return true
	return false

func _picture(id: String, tier: int) -> bool:
	var tokens := _tokens()
	if tokens.is_empty():
		return true
	return ("%s:%d" % [id, tier]) in tokens

func _rifle(id: String, tier: int) -> bool:
	return id in ["debt_shotgun", "rent_rifle", "ledger_cannon"] or (id == "street_smg" and tier >= 3)

func _akimbo(id: String, tier: int) -> bool:
	return id == "pipe_pistol" and tier >= 3

func _ads_fov(id: String) -> float:
	if id in ["debt_shotgun", "rent_rifle", "ledger_cannon"]:
		return ADS_FOV_LONG
	return ADS_FOV

func _hip_of(id: String, tier: int) -> Vector3:
	if _akimbo(id, tier):
		return AKIMBO_HIP
	return HIP_GUN

func _apply_hip(id: String, tier: int) -> void:
	_mount.position = _hip_of(id, tier)
	_mount.rotation = Vector3.ZERO
	_camera.fov = HIP_FOV

func _apply_ads(id: String, tier: int) -> void:
	if _akimbo(id, tier):
		_apply_hip(id, tier)
		return
	_mount.position = _hip_of(id, tier).lerp(ADS_GUN, 1.0)
	_mount.rotation = Vector3.ZERO
	_camera.fov = _ads_fov(id)

func _measure_weapon(id: String, tier: int) -> Dictionary:
	_player.set("weapon_id", id)
	_player.set("weapon_tier", tier)
	_player.call("_show_gun")
	await get_tree().process_frame
	var length := _idle_length()
	var times: Array[float] = [0.0]
	if length > 0.05:
		times.append(length * 0.5)
	var samples: Array = []
	for t in times:
		samples.append(await _measure_at(id, tier, t))
	var pic := 0
	if samples.size() > 1 and float(samples[1].score) > float(samples[0].score):
		pic = 1
	var merged: Dictionary = _merge_weapon(samples[0], samples[samples.size() - 1] if samples.size() > 1 else samples[0])
	merged.id = id
	merged.tier = tier
	merged.rifle = _rifle(id, tier)
	merged.akimbo = _akimbo(id, tier)
	merged.markers = samples[pic].markers
	merged.frame = samples[pic].frame
	merged.picture_time = samples[pic].time
	merged.length = samples[pic].length
	merged.thick_r = samples[pic].thick_r
	merged.thick_l = samples[pic].thick_l
	merged.thick_r2 = samples[pic].thick_r2
	merged.caption = "%s %s" % [str(Economy.weapon(id).name), str(Economy.tier_label(tier))]
	await _pose(samples[pic].time)
	_apply_hip(id, tier)
	return merged

func _measure_at(id: String, tier: int, time: float) -> Dictionary:
	await _pose(time)
	_apply_hip(id, tier)
	var sides := 2 if _akimbo(id, tier) else 1
	var parts: Array = []
	for side in sides:
		parts.append(_measure_side(side, false))
	var shift := Vector3.ZERO
	if not _akimbo(id, tier):
		var before: Vector3 = _mount.global_position
		_apply_ads(id, tier)
		shift = _mount.global_position - before
		for side in sides:
			_ads_pass(parts[side], side, shift)
		_apply_hip(id, tier)
	return _pack_time(id, tier, time, parts)

func _measure_side(side: int, ads: bool) -> Dictionary:
	var rig := _rig_for(side)
	var out := {
		"ok": rig != null,
		"gaps_r": _blank_gaps(),
		"gaps_l": _blank_gaps(),
		"markers": [],
		"frame_r": [],
		"frame_l": [],
		"off_right": 0.0,
		"off_up": 0.0,
		"palm_l": Vector3.ZERO,
		"palm_l_ok": false,
		"thick_r": Vector2.ZERO,
		"thick_l": Vector2.ZERO,
		"length": 0.0,
		"scale_ratio": 1.0,
		"up_deg": 0.0,
		"up_dot": 1.0,
		"left_extent": 0.0,
		"arm_scale": 1.0,
		"bore_deg": 180.0,
		"miss_pct": 100.0,
		"muzzle_z": 1.0,
		"depth": 0.0,
		"bore": -_camera.global_transform.basis.z,
		"gun_verts": PackedVector3Array(),
		"arm_verts": PackedVector3Array(),
	}
	if rig == null:
		return out
	var skel := _arm_skeleton(rig)
	var arm_pose := _read_meshes(_arm_meshes(rig), true)
	var gun_pose := _read_meshes(_gun_meshes(rig), false)
	out.arm_verts = arm_pose.verts
	out.gun_verts = gun_pose.verts
	out.arm_scale = _arm_scale(skel)
	out.left_extent = _left_extent(skel, arm_pose)
	var tip: Vector3 = _player.call("_barrel_tip", side)
	var pca := _pca_axis(gun_pose.verts)
	var bore: Vector3 = pca.axis
	if bore.dot(tip - pca.c) < 0.0:
		bore = -bore
	out.bore = bore
	out.length = _longest(gun_pose.verts)
	var root := _gun_root(rig)
	if root != null:
		var scale := root.global_transform.basis.get_scale()
		out.scale_ratio = _ratio_of(absf(scale.x), absf(scale.y), absf(scale.z))
		var up := root.global_transform.basis.y
		if up.length_squared() > 1e-8:
			up = up.normalized()
		else:
			up = Vector3.UP
		var dot := up.dot(_camera.global_transform.basis.y)
		out.up_dot = dot
		out.up_deg = rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
	_sync_cam()
	out.bore_deg = _bore_angle(bore, tip)
	out.miss_pct = _bore_miss(bore, tip)
	out.muzzle_z = (_camera.to_local(tip)).z
	out.depth = _min_depth(gun_pose.verts, arm_pose.verts, Vector3.ZERO)
	if side == 0 and _player.get("weapon_tier") == 1 and str(_player.get("weapon_id")) == "pipe_pistol":
		var root_basis := Basis()
		if root != null:
			root_basis = root.global_transform.basis
		var cam_up := _camera.global_transform.basis.y
		var sc := Vector3.ONE
		if root != null:
			sc = root.global_transform.basis.get_scale()
		var skel_y := 0.0
		if skel != null:
			skel_y = skel.global_transform.basis.orthonormalized().y.dot(cam_up)
		printerr("GUNFIT dbg scale %s lens %.2f %.2f %.2f skel_y %.3f behind %s" % [
			sc, root_basis.x.length(), root_basis.y.length(), root_basis.z.length(), skel_y, _behind_bones(skel, arm_pose),
		])
	if skel != null:
		_hand_metrics(out, skel, arm_pose, gun_pose, bore, pca.c, ads)
	return out

func _ads_pass(side_row: Dictionary, side: int, shift: Vector3) -> void:
	var tip: Vector3 = _player.call("_barrel_tip", side)
	var bore: Vector3 = side_row.bore
	_sync_cam()
	side_row.bore_ads = _bore_angle(bore, tip)
	side_row.miss_ads = _bore_miss(bore, tip)
	side_row.mz_ads = (_camera.to_local(tip)).z
	side_row.depth_ads = _min_depth(side_row.gun_verts, side_row.arm_verts, shift)
	side_row.bore_deg = side_row.bore_deg
	side_row.miss_pct = side_row.miss_pct
	side_row.muzzle_z = side_row.muzzle_z

func _hand_metrics(out: Dictionary, skel: Skeleton3D, arm_pose: Dictionary, gun_pose: Dictionary, bore: Vector3, centroid: Vector3, _ads: bool) -> void:
	var bins := _build_bins(gun_pose.verts, gun_pose.indices)
	var stamp := PackedInt32Array()
	stamp.resize(gun_pose.indices.size() / 3)
	var gun_mn := Vector3.ZERO
	var gun_mx := Vector3.ZERO
	if not gun_pose.verts.is_empty():
		gun_mn = gun_pose.verts[0]
		gun_mx = gun_pose.verts[0]
		for v in gun_pose.verts:
			gun_mn = gun_mn.min(v)
			gun_mx = gun_mx.max(v)
	var axes := _bore_axes(bore)
	for hand in ["r", "l"]:
		var gaps: Dictionary = _blank_gaps()
		var palm := Vector3.ZERO
		var palm_n := 0
		var frame: Array[Vector3] = []
		for part in PARTS:
			var ids := _part_ids(skel, hand, part)
			var which: Array[int] = []
			for i in arm_pose.bones.size():
				if ids.has(int(arm_pose.bones[i])):
					which.append(i)
			if not which.is_empty():
				var center := Vector3.ZERO
				for i in which:
					center += arm_pose.verts[i]
					if part == "palm":
						palm += arm_pose.verts[i]
						palm_n += 1
				center /= float(which.size())
				frame.append(center)
			var gap := _gap(which, arm_pose.verts, gun_pose, bins, stamp, gun_mn, gun_mx)
			gaps[part] = gap.gap
			if gap.ok:
				out.markers.append({
					"hand": gap.hand,
					"gun": gap.gun,
					"color": PART_COLOR[part],
					"side": hand,
					"part": part,
				})
		if palm_n > 0:
			palm /= float(palm_n)
			frame.append(palm)
			frame.append(centroid + bore * bore.dot(palm - centroid))
			frame.append(centroid + bore * (bore.dot(palm - centroid) + 0.1))
		if hand == "r":
			out.gaps_r = gaps
			out.frame_r = frame
			if palm_n > 0:
				out.thick_r = _section(gun_pose.verts, centroid, bore, bore.dot(palm - centroid), axes.right, axes.up)
		else:
			out.gaps_l = gaps
			out.frame_l = frame
			if palm_n > 0:
				out.palm_l = palm
				out.palm_l_ok = true
				out.thick_l = _section(gun_pose.verts, centroid, bore, bore.dot(palm - centroid), axes.right, axes.up)
				var on_bore: Vector3 = centroid + bore * bore.dot(palm - centroid)
				var delta := palm - on_bore
				out.off_right = _camera.global_transform.basis.x.dot(delta)
				out.off_up = _camera.global_transform.basis.y.dot(delta)

func _pack_time(id: String, tier: int, time: float, parts: Array) -> Dictionary:
	var a: Dictionary = parts[0]
	var row := {
		"time": time,
		"bore_hip": a.bore_deg,
		"miss_hip": a.miss_pct,
		"mz_hip": a.muzzle_z,
		"bore_ads": a.get("bore_ads", a.bore_deg),
		"miss_ads": a.get("miss_ads", a.miss_pct),
		"mz_ads": a.get("mz_ads", a.muzzle_z),
		"depth_hip": a.depth,
		"depth_ads": a.get("depth_ads", a.depth),
		"gaps_r": a.gaps_r,
		"gaps_l": a.gaps_l,
		"off_right": a.off_right,
		"off_up": a.off_up,
		"length": a.length,
		"scale_ratio": a.scale_ratio,
		"up_deg": a.up_deg,
		"up_dot": a.up_dot,
		"thick_r": a.thick_r,
		"thick_l": a.thick_l,
		"thick_r2": Vector2.ZERO,
		"gaps_r2": _blank_gaps(),
		"left_extent": a.left_extent,
		"arm_scale": a.arm_scale,
		"markers": a.markers.duplicate(),
		"frame": a.frame_l if not a.frame_l.is_empty() else a.frame_r,
		"bore_hip2": 0.0,
		"miss_hip2": 0.0,
		"mz_hip2": 0.0,
	}
	if parts.size() > 1:
		var b: Dictionary = parts[1]
		row.bore_hip2 = b.bore_deg
		row.miss_hip2 = b.miss_pct
		row.mz_hip2 = b.muzzle_z
		row.depth_hip = minf(float(a.depth), float(b.depth))
		row.gaps_r2 = b.gaps_r
		row.thick_r2 = b.thick_r
		row.length = maxf(float(a.length), float(b.length))
		row.scale_ratio = maxf(float(a.scale_ratio), float(b.scale_ratio))
		if float(b.up_dot) < float(a.up_dot):
			row.up_dot = b.up_dot
			row.up_deg = b.up_deg
		row.left_extent = maxf(float(a.left_extent), float(b.left_extent))
		row.arm_scale = maxf(float(a.arm_scale), float(b.arm_scale))
		row.markers.append_array(b.markers)
		row.frame = a.frame_r.duplicate()
		row.frame.append_array(b.frame_r)
	row.score = _score(row, _akimbo(id, tier))
	return row

func _score(sample: Dictionary, akimbo: bool) -> float:
	var score := 0.0
	if akimbo:
		score = maxf(absf(sample.bore_hip), absf(sample.bore_hip2))
	else:
		for part in PARTS:
			var g = sample.gaps_l[part]
			if g != null:
				score = maxf(score, absf(float(g)))
		score = maxf(score, absf(sample.bore_hip) * 0.001)
	return score

func _merge_weapon(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := a.duplicate(true)
	o.bore_hip = maxf(float(a.bore_hip), float(b.bore_hip))
	o.miss_hip = maxf(float(a.miss_hip), float(b.miss_hip))
	o.mz_hip = maxf(float(a.mz_hip), float(b.mz_hip))
	o.bore_ads = maxf(float(a.bore_ads), float(b.bore_ads))
	o.miss_ads = maxf(float(a.miss_ads), float(b.miss_ads))
	o.mz_ads = maxf(float(a.mz_ads), float(b.mz_ads))
	o.bore_hip2 = maxf(float(a.bore_hip2), float(b.bore_hip2))
	o.miss_hip2 = maxf(float(a.miss_hip2), float(b.miss_hip2))
	o.mz_hip2 = maxf(float(a.mz_hip2), float(b.mz_hip2))
	o.depth_hip = minf(float(a.depth_hip), float(b.depth_hip))
	o.depth_ads = minf(float(a.depth_ads), float(b.depth_ads))
	o.gaps_r = _merge_gaps(a.gaps_r, b.gaps_r)
	o.gaps_l = _merge_gaps(a.gaps_l, b.gaps_l)
	o.gaps_r2 = _merge_gaps(a.gaps_r2, b.gaps_r2)
	o.off_right = _worse_abs(float(a.off_right), float(b.off_right))
	o.off_up = _worse_abs(float(a.off_up), float(b.off_up))
	o.scale_ratio = maxf(float(a.scale_ratio), float(b.scale_ratio))
	o.left_extent = maxf(float(a.left_extent), float(b.left_extent))
	o.arm_scale = maxf(float(a.arm_scale), float(b.arm_scale))
	if float(a.up_dot) <= float(b.up_dot):
		o.up_dot = a.up_dot
		o.up_deg = a.up_deg
	else:
		o.up_dot = b.up_dot
		o.up_deg = b.up_deg
	return o

func _merge_gaps(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := {}
	for part in PARTS:
		o[part] = _merge_gap(a[part], b[part])
	return o

func _merge_gap(a, b):
	if a == null:
		return b
	if b == null:
		return a
	if absf(float(a)) >= absf(float(b)):
		return a
	return b

func _worse_abs(a: float, b: float) -> float:
	if absf(a) >= absf(b):
		return a
	return b

func _blank_gaps() -> Dictionary:
	return {"palm": null, "index": null, "middle": null, "thumb": null}

func _fill_ratios(row: Dictionary, ref: Dictionary) -> void:
	if ref.is_empty():
		row.ratio_r_w = 0.0
		row.ratio_r_h = 0.0
		row.ratio_l_w = 0.0
		row.ratio_l_h = 0.0
		row.ratio_r2_w = 0.0
		row.ratio_r2_h = 0.0
		return
	var tr: Vector2 = row.thick_r
	var rr: Vector2 = ref.thick_r
	row.ratio_r_w = _safe_div(tr.x, rr.x)
	row.ratio_r_h = _safe_div(tr.y, rr.y)
	var tl: Vector2 = row.thick_l
	var rl: Vector2 = ref.thick_l
	row.ratio_l_w = _safe_div(tl.x, rl.x)
	row.ratio_l_h = _safe_div(tl.y, rl.y)
	var t2: Vector2 = row.thick_r2
	row.ratio_r2_w = _safe_div(t2.x, rr.x)
	row.ratio_r2_h = _safe_div(t2.y, rr.y)

func _safe_div(v: float, ref: float) -> float:
	if absf(ref) < 0.0001:
		return 0.0
	return v / ref

func _reasons(row: Dictionary, ref: Dictionary) -> Array:
	var why: Array = []
	_bore_flags(why, "hip", row.bore_hip, row.mz_hip)
	if row.akimbo:
		_bore_flags(why, "hip2", row.bore_hip2, row.mz_hip2)
		if float(row.left_extent) > COLLAPSE_LIMIT:
			why.append("collapsed_arm")
	else:
		_bore_flags(why, "ads", row.bore_ads, row.mz_ads)
	if float(row.scale_ratio) > SCALE_LIMIT:
		why.append("scale")
	if float(row.up_dot) < 0.0:
		why.append("upside_down")
	elif float(row.up_deg) > ROLL_LIMIT:
		why.append("rolled")
	if float(row.depth_hip) < _near + CLIP_PAD:
		why.append("clip_hip")
	if not row.akimbo and float(row.depth_ads) < _near + CLIP_PAD:
		why.append("clip_ads")
	_gap_flags(why, "r", row.gaps_r, ref, "r")
	if row.akimbo:
		_gap_flags(why, "r2", row.gaps_r2, ref, "r")
	else:
		_gap_flags(why, "l", row.gaps_l, ref, "l")
	why.sort()
	return why

func _bore_flags(why: Array, tag: String, angle: float, mz: float) -> void:
	if angle > BORE_LIMIT:
		why.append("bore_" + tag)
	if mz >= 0.0:
		why.append("muzzle_" + tag)

func _gap_flags(why: Array, tag: String, gaps: Dictionary, ref: Dictionary, ref_hand: String) -> void:
	var ref_gaps: Dictionary = {}
	if not ref.is_empty():
		ref_gaps = ref.gaps_l if ref_hand == "l" else ref.gaps_r
	for part in PARTS:
		var g = gaps[part]
		if g == null:
			why.append("missing_%s_%s" % [tag, part])
			continue
		if ref_gaps.is_empty() or ref_gaps.get(part) == null:
			continue
		var base := float(ref_gaps[part])
		var got := float(g)
		if got >= base + GAP_BAND:
			why.append("float_%s_%s" % [tag, part])
		elif got <= base - GAP_BAND:
			why.append("bury_%s_%s" % [tag, part])

func _print_refs(pistol_ref: Dictionary, rifle_ref: Dictionary) -> void:
	if not pistol_ref.is_empty():
		print("GUNFIT_REF pistol %s" % _gap_text(pistol_ref))
	if not rifle_ref.is_empty():
		print("GUNFIT_REF rifle %s" % _gap_text(rifle_ref))

func _gap_text(row: Dictionary) -> String:
	var bits: PackedStringArray = PackedStringArray()
	for hand in [["R", row.gaps_r], ["L", row.gaps_l]]:
		for part in PARTS:
			bits.append("%s%s=%s" % [hand[0], part, _g(hand[1][part])])
	return " ".join(bits)

func _print_row(row: Dictionary) -> void:
	var reasons: Array = row.reasons
	var head := "GUNFIT %s t%d %s" % [row.id, row.tier, "OK" if reasons.is_empty() else "FLAG"]
	if not reasons.is_empty():
		head += " " + " ".join(reasons)
	print(head)
	print("\trig %s  shot t=%.3f" % ["rifle" if row.rifle else "pistol", row.picture_time])
	print("\thip bore %s deg  miss %s%%  z %s" % [_n(row.bore_hip), _n(row.miss_hip), _n(row.mz_hip)])
	if row.akimbo:
		print("\thip2 bore %s deg  miss %s%%  z %s" % [_n(row.bore_hip2), _n(row.miss_hip2), _n(row.mz_hip2)])
	else:
		print("\tads bore %s deg  miss %s%%  z %s" % [_n(row.bore_ads), _n(row.miss_ads), _n(row.mz_ads)])
	print("\tR %s" % _hand_line(row.gaps_r))
	if row.akimbo:
		print("\tR2 %s" % _hand_line(row.gaps_r2))
		print("\tL collapsed extent %s  arm_scale %s" % [_n(row.left_extent), _n(row.arm_scale)])
	else:
		print("\tL %s" % _hand_line(row.gaps_l))
		print("\toffset right %s  up %s" % [_n(row.off_right), _n(row.off_up)])
	print("\tlen %s  scale %s  up %s deg  dot %s" % [_n(row.length), _n(row.scale_ratio), _n(row.up_deg), _n(row.up_dot)])
	if row.akimbo:
		print("\tdepth hip %s  near %s" % [_n(row.depth_hip), _n(_near)])
	else:
		print("\tdepth hip %s  ads %s  near %s" % [_n(row.depth_hip), _n(row.depth_ads), _n(_near)])
	var tr: Vector2 = row.thick_r
	print("\tthick R w %s h %s  ratio w %s h %s" % [_n(tr.x), _n(tr.y), _n(row.ratio_r_w), _n(row.ratio_r_h)])
	if row.akimbo:
		var t2: Vector2 = row.thick_r2
		print("\tthick R2 w %s h %s  ratio w %s h %s" % [_n(t2.x), _n(t2.y), _n(row.ratio_r2_w), _n(row.ratio_r2_h)])
	else:
		var tl: Vector2 = row.thick_l
		print("\tthick L w %s h %s  ratio w %s h %s" % [_n(tl.x), _n(tl.y), _n(row.ratio_l_w), _n(row.ratio_l_h)])

func _hand_line(gaps: Dictionary) -> String:
	return "palm %s  index %s  middle %s  thumb %s" % [_g(gaps.palm), _g(gaps.index), _g(gaps.middle), _g(gaps.thumb)]

func _n(v: float) -> String:
	return "%.4f" % v

func _g(v) -> String:
	if v == null:
		return "missing"
	return "%.4f" % float(v)

func _metrics(row: Dictionary) -> Dictionary:
	var m := {}
	m.bore_hip_deg = row.bore_hip
	m.miss_hip_pct = row.miss_hip
	m.muzzle_z_hip = row.mz_hip
	m.gap_r_palm = row.gaps_r.palm
	m.gap_r_index = row.gaps_r.index
	m.gap_r_middle = row.gaps_r.middle
	m.gap_r_thumb = row.gaps_r.thumb
	m.length = row.length
	m.scale_ratio = row.scale_ratio
	m.up_deg = row.up_deg
	m.up_dot = row.up_dot
	m.depth_hip = row.depth_hip
	m.near = _near
	m.arm_scale = row.arm_scale
	m.left_extent = row.left_extent
	var tr: Vector2 = row.thick_r
	m.thick_r_w = tr.x
	m.thick_r_h = tr.y
	m.ratio_r_w = row.ratio_r_w
	m.ratio_r_h = row.ratio_r_h
	if row.akimbo:
		m.bore_hip2_deg = row.bore_hip2
		m.miss_hip2_pct = row.miss_hip2
		m.muzzle_z_hip2 = row.mz_hip2
		m.gap_r2_palm = row.gaps_r2.palm
		m.gap_r2_index = row.gaps_r2.index
		m.gap_r2_middle = row.gaps_r2.middle
		m.gap_r2_thumb = row.gaps_r2.thumb
		var t2: Vector2 = row.thick_r2
		m.thick_r2_w = t2.x
		m.thick_r2_h = t2.y
		m.ratio_r2_w = row.ratio_r2_w
		m.ratio_r2_h = row.ratio_r2_h
	else:
		m.bore_ads_deg = row.bore_ads
		m.miss_ads_pct = row.miss_ads
		m.muzzle_z_ads = row.mz_ads
		m.depth_ads = row.depth_ads
		m.gap_l_palm = row.gaps_l.palm
		m.gap_l_index = row.gaps_l.index
		m.gap_l_middle = row.gaps_l.middle
		m.gap_l_thumb = row.gaps_l.thumb
		m.off_right = row.off_right
		m.off_up = row.off_up
		var tl: Vector2 = row.thick_l
		m.thick_l_w = tl.x
		m.thick_l_h = tl.y
		m.ratio_l_w = row.ratio_l_w
		m.ratio_l_h = row.ratio_l_h
	return m

func _baseline_path() -> String:
	return ProjectSettings.globalize_path("res://tools/baseline.json")

func _write_baseline(rows: Array) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("{")
	for i in rows.size():
		var row: Dictionary = rows[i]
		var key := "%s:%d" % [row.id, row.tier]
		lines.append("\t\"%s\": {" % key)
		var metrics := _metrics(row)
		var keys: Array = metrics.keys()
		keys.sort()
		for k in keys.size():
			var name := String(keys[k])
			var val = metrics[name]
			var comma := "," if k < keys.size() - 1 else ""
			if val == null:
				lines.append("\t\t\"%s\": null%s" % [name, comma])
			else:
				lines.append("\t\t\"%s\": %s%s" % [name, _f4(float(val)), comma])
		var tail := "," if i < rows.size() - 1 else ""
		lines.append("\t}%s" % tail)
	lines.append("}")
	lines.append("")
	var file := FileAccess.open(_baseline_path(), FileAccess.WRITE)
	if file == null:
		print("GUNFIT_FAIL baseline_write %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string("\n".join(lines))
	file.close()

func _read_baseline() -> Dictionary:
	var file := FileAccess.open(_baseline_path(), FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}

func _print_compare(row: Dictionary, baseline: Dictionary) -> void:
	var key := "%s:%d" % [row.id, row.tier]
	if not baseline.has(key):
		print("\tbaseline MISSING")
		return
	var was: Dictionary = baseline[key]
	var now := _metrics(row)
	var changed: Array = []
	var keys: Array = []
	for k in was.keys():
		if not keys.has(k):
			keys.append(k)
	for k in now.keys():
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	for k in keys:
		var a = was.get(k, null)
		var b = now.get(k, null)
		if not _num_same(a, b):
			changed.append(String(k))
	if changed.is_empty():
		print("\tbaseline SAME")
	else:
		print("\tbaseline CHANGED %s" % " ".join(changed))

func _num_same(a, b) -> bool:
	if a == null or b == null:
		return a == null and b == null
	return _f4(float(a)) == _f4(float(b))

func _f4(v: float) -> String:
	if is_nan(v) or is_inf(v):
		return "null"
	var n: float = round(v * 10000.0) / 10000.0
	if absf(n) < 0.00005:
		n = 0.0
	return "%.4f" % n

func _find_row(rows: Array, id: String, tier: int) -> Dictionary:
	for row in rows:
		if row.id == id and int(row.tier) == tier:
			return row
	return {}

func _shoot(row: Dictionary) -> void:
	_label.text = "%s  hip" % row.caption
	_apply_hip(row.id, row.tier)
	_sync_cam()
	_check_project()
	var hip := await _grab()
	_crosshair(hip)
	var second: Image
	if row.akimbo:
		_label.text = "%s  hip side" % row.caption
		_place_side()
		second = await _grab()
		_crosshair(second)
	else:
		_label.text = "%s  aim" % row.caption
		_apply_ads(row.id, row.tier)
		_sync_cam()
		second = await _grab()
		_crosshair(second)
		_apply_hip(row.id, row.tier)
	_label.text = "%s  support below" % row.caption
	_place_close(row, false)
	var below := await _grab()
	_draw_markers(below, row.markers)
	_label.text = "%s  support top" % row.caption
	_place_close(row, true)
	var top := await _grab()
	_draw_markers(top, row.markers)
	var sheet := Image.create(VIEW_W * 2, VIEW_H * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	_blit(sheet, hip, 0, 0)
	_blit(sheet, second, VIEW_W, 0)
	_blit(sheet, below, 0, VIEW_H)
	_blit(sheet, top, VIEW_W, VIEW_H)
	var path := _shot_dir + "%s_t%d.png" % [row.id, row.tier]
	var err := sheet.save_png(path)
	if err != OK:
		print("GUNFIT_FAIL shot %s %s" % [path, error_string(err)])
	_hips.append(hip)

func _write_overview() -> void:
	if _hips.is_empty():
		return
	var cols := 7
	var tw := 640
	var th := 360
	var rows := int(ceil(float(_hips.size()) / float(cols)))
	var sheet := Image.create(cols * tw, rows * th, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.12))
	for i in _hips.size():
		var thumb := _hips[i].duplicate()
		thumb.convert(Image.FORMAT_RGBA8)
		thumb.resize(tw, th, Image.INTERPOLATE_LANCZOS)
		_blit_rect(sheet, thumb, (i % cols) * tw, int(i / cols) * th)
	var err := sheet.save_png(_shot_dir + "overview.png")
	if err != OK:
		print("GUNFIT_FAIL overview %s" % error_string(err))

func _blit(dest: Image, src: Image, x: int, y: int) -> void:
	var tile := src.duplicate()
	tile.convert(Image.FORMAT_RGBA8)
	if tile.get_width() != VIEW_W or tile.get_height() != VIEW_H:
		tile.resize(VIEW_W, VIEW_H, Image.INTERPOLATE_BILINEAR)
	dest.blit_rect(tile, Rect2i(0, 0, VIEW_W, VIEW_H), Vector2i(x, y))

func _blit_rect(dest: Image, src: Image, x: int, y: int) -> void:
	dest.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(x, y))

func _sync_cam() -> void:
	_cam.global_transform = _camera.global_transform
	_cam.fov = _camera.fov
	_cam.near = _camera.near
	_cam.far = _camera.far

func _check_project() -> void:
	if _project_checked:
		return
	_project_checked = true
	var ahead: Vector3 = _camera.global_position + (-_camera.global_transform.basis.z) * 5.0
	var px: Vector2 = _cam.unproject_position(ahead)
	printerr("GUNFIT project ", px, " center ", VIEW_W * 0.5, " ", VIEW_H * 0.5)

func _place_side() -> void:
	var basis := _camera.global_transform.basis
	var origin := _camera.global_position
	var focus: Vector3 = origin + (-basis.z) * 0.55 + basis.y * -0.16
	_cam.fov = 62.0
	_cam.near = _near
	_cam.far = _camera.far
	_cam.global_position = origin + basis.x * 0.32 + basis.y * 0.04
	_cam.look_at(focus, basis.y)

func _place_close(row: Dictionary, top: bool) -> void:
	var pts: Array[Vector3] = []
	var side := Vector3.ZERO
	var side_n := 0
	var want := "r" if row.akimbo else "l"
	if row.get("frame", []).is_empty():
		for marker in row.markers:
			if String(marker.get("side", "")) != want:
				continue
			pts.append(marker.hand)
			pts.append(marker.gun)
	else:
		for p in row.frame:
			pts.append(p)
	for marker in row.markers:
		if String(marker.get("side", "")) != want:
			continue
		pts.append(marker.hand)
		pts.append(marker.gun)
		if String(marker.get("part", "")) == "palm":
			side += marker.hand - marker.gun
			side_n += 1
	if pts.is_empty():
		var tip: Vector3 = _player.call("_barrel_tip", 0)
		pts.append(tip)
	var center := Vector3.ZERO
	for p in pts:
		center += p
	center /= float(pts.size())
	var basis := _camera.global_transform.basis
	var right := basis.x
	var up := basis.y
	var forward := -basis.z
	var max_r := 0.07
	var max_u := 0.07
	var max_f := 0.07
	for p in pts:
		var d := p - center
		max_r = maxf(max_r, absf(d.dot(right)))
		max_u = maxf(max_u, absf(d.dot(up)))
		max_f = maxf(max_f, absf(d.dot(forward)))
	var fov := deg_to_rad(42.0)
	_cam.fov = 42.0
	_cam.near = 0.01
	_cam.far = 20.0
	if top:
		var half := maxf(max_r, max_f) * 1.7 + 0.03
		var dist := maxf(half / tan(fov * 0.5), max_u + 0.12)
		_cam.global_position = center + up * dist
		_cam.look_at(center, forward)
		return
	if side_n > 0:
		side /= float(side_n)
		side = side - up * side.dot(up)
	if side.length_squared() < 0.0001:
		side = -right if not row.akimbo else right
	side = side.normalized()
	var half2 := maxf(max_r, maxf(max_u, max_f)) * 1.7 + 0.03
	var dist2 := maxf(half2 / tan(fov * 0.5), 0.22)
	var out_dir := (-up * 0.7 + side * 0.62 - forward * 0.22).normalized()
	_cam.global_position = center + out_dir * dist2
	_cam.look_at(center, up)

func _grab() -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img == null or img.get_width() == 0:
		await RenderingServer.frame_post_draw
		img = _vp.get_texture().get_image()
	if img == null or img.get_width() == 0:
		img = Image.create(VIEW_W, VIEW_H, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
	else:
		img = img.duplicate()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

func _crosshair(img: Image) -> void:
	var cx := int(img.get_width() / 2.0)
	var cy := int(img.get_height() / 2.0)
	for i in range(-14, 15):
		if absi(i) < 3:
			continue
		_px(img, cx + i, cy, Color.WHITE)
		_px(img, cx + i, cy + 1, Color.BLACK)
		_px(img, cx, cy + i, Color.WHITE)
		_px(img, cx + 1, cy + i, Color.BLACK)

func _draw_markers(img: Image, markers: Array) -> void:
	for marker in markers:
		var a = _project_point(marker.hand)
		var b = _project_point(marker.gun)
		if a != null and b != null:
			_line(img, a, b, Color(1, 1, 1, 0.85))
		if b != null:
			_dot(img, b, Color(1.0, 0.15, 0.85), 4)
		if a != null:
			_dot(img, a, marker.color, 5)

func _project_point(world: Vector3):
	var local: Vector3 = _cam.global_transform.affine_inverse() * world
	if -local.z <= 0.02:
		return null
	return _cam.unproject_position(world)

func _dot(img: Image, p: Vector2, color: Color, radius: int) -> void:
	var cx := int(round(p.x))
	var cy := int(round(p.y))
	for y in range(-radius - 1, radius + 2):
		for x in range(-radius - 1, radius + 2):
			var d2 := x * x + y * y
			if d2 > (radius + 1) * (radius + 1):
				continue
			if d2 >= radius * radius:
				_px(img, cx + x, cy + y, Color.BLACK)
			else:
				_px(img, cx + x, cy + y, color)

func _line(img: Image, a: Vector2, b: Vector2, color: Color) -> void:
	var x0 := int(round(a.x))
	var y0 := int(round(a.y))
	var x1 := int(round(b.x))
	var y1 := int(round(b.y))
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	for _i in 800:
		_px(img, x0, y0, color)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

func _px(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, color)

func _pose(time: float) -> void:
	var players: Array = []
	var view = _player.get("_view_anims")
	var off = _player.get("_offhand_anims")
	if view != null:
		players.append_array(view)
	if off != null:
		players.append_array(off)
	for anim in players:
		var ap := anim as AnimationPlayer
		if ap == null:
			continue
		var clip := String(_player.call("_view_clip", ap, "idle"))
		if clip == "":
			continue
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		ap.speed_scale = 1.0
		if ap.current_animation != clip:
			ap.play(clip)
		var length := ap.get_animation(clip).length
		var at := clampf(time, 0.0, maxf(length - 0.001, 0.0))
		ap.seek(at, true)
		ap.pause()
		ap.seek(at, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_squash_modifiers()

func _squash_modifiers() -> void:
	var guns = _player.get("_muzzle_guns")
	if guns == null:
		return
	for rig in guns:
		if rig == null or not is_instance_valid(rig):
			continue
		for node in rig.find_children("*", "Skeleton3D", true, false):
			var skel := node as Skeleton3D
			for child in skel.get_children():
				if child is SkeletonModifier3D:
					child.call("_process_modification")
			skel.force_update_all_bone_transforms()

func _idle_length() -> float:
	var view = _player.get("_view_anims")
	if view == null:
		return 0.0
	for anim in view:
		var ap := anim as AnimationPlayer
		var clip := String(_player.call("_view_clip", ap, "idle"))
		if clip == "":
			continue
		return ap.get_animation(clip).length
	return 0.0

func _rig_for(side: int) -> Node3D:
	var guns = _player.get("_muzzle_guns")
	if guns == null or guns.is_empty():
		return null
	var idx := 0
	if bool(_player.call("_akimbo")) and guns.size() > 1:
		idx = 0 if side == 1 else 1
	if idx >= guns.size():
		idx = 0
	return guns[idx] as Node3D

func _arm_skeleton(rig: Node) -> Skeleton3D:
	for node in rig.find_children("*", "Skeleton3D", true, false):
		var skel := node as Skeleton3D
		if skel.find_bone("Hand.R.001") >= 0:
			return skel
	return null

func _arm_meshes(rig: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		if "arm" in String(mi.name).to_lower():
			out.append(mi)
	return out

func _gun_meshes(rig: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var held := rig.find_child("HeldGun", true, false)
	var root: Node = held if held != null else rig
	var nodes: Array = []
	if root is MeshInstance3D:
		nodes.append(root)
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		if String(mi.name) == "MuzzleFlash":
			continue
		var n := String(mi.name).to_lower()
		if "arm" in n or "hand" in n:
			continue
		if held == null and not ("glock" in n or "akm" in n):
			continue
		out.append(mi)
	return out

func _gun_root(rig: Node) -> Node3D:
	var held := rig.find_child("HeldGun", true, false)
	if held != null and held.get_child_count() > 0:
		return held.get_child(0) as Node3D
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var n := String(node.name).to_lower()
		if "glock" in n or "akm" in n:
			return node as Node3D
	return null

func _read_meshes(meshes: Array[MeshInstance3D], want_bones: bool) -> Dictionary:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var bones := PackedInt32Array()
	for mi in meshes:
		_append_mesh(mi, verts, indices, bones, want_bones)
	return {"verts": verts, "indices": indices, "bones": bones}

func _append_mesh(mi: MeshInstance3D, verts: PackedVector3Array, indices: PackedInt32Array, bones: PackedInt32Array, want_bones: bool) -> void:
	var mesh := mi.mesh
	var skel: Skeleton3D = null
	var posed: Array[Transform3D] = []
	var skinned := false
	if mi.skin != null and mi.skeleton != NodePath():
		skel = mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if skel != null:
			skinned = true
			posed = _posed_binds(mi.skin, skel)
	var xf := mi.global_transform
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var local: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if local.is_empty():
			continue
		var idx := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			idx = arrays[Mesh.ARRAY_INDEX]
		var normals := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] != null:
			normals = arrays[Mesh.ARRAY_NORMAL]
		var flip := _winding_flip(local, idx, normals)
		var base := verts.size()
		if skinned:
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := 4
			if weights.size() % local.size() == 0:
				var maybe := int(weights.size() / local.size())
				if maybe == 8 or maybe == 4:
					stride = maybe
			var bind_map := _bind_map(mi.skin, skel)
			for i in local.size():
				var bx := Vector3.ZERO
				var by := Vector3.ZERO
				var bz := Vector3.ZERO
				var origin := Vector3.ZERO
				var best_w := -1.0
				var best_bone := -1
				for k in stride:
					var w := weights[i * stride + k]
					if w < 0.001:
						continue
					var bind := int(joints[i * stride + k])
					if bind < 0 or bind >= posed.size():
						continue
					if w > best_w:
						best_w = w
						best_bone = bind_map[bind] if bind < bind_map.size() else -1
					var bone_xf: Transform3D = posed[bind]
					bx += bone_xf.basis.x * w
					by += bone_xf.basis.y * w
					bz += bone_xf.basis.z * w
					origin += bone_xf.origin * w
				verts.append(skel.global_transform * (Basis(bx, by, bz) * local[i] + origin))
				if want_bones:
					bones.append(best_bone)
		else:
			for v in local:
				verts.append(xf * v)
				if want_bones:
					bones.append(-1)
		if idx.is_empty():
			for i in range(0, local.size() - 2, 3):
				_add_tri(indices, base, i, i + 1, i + 2, flip, local.size())
		else:
			for i in range(0, idx.size() - 2, 3):
				_add_tri(indices, base, idx[i], idx[i + 1], idx[i + 2], flip, local.size())

func _add_tri(indices: PackedInt32Array, base: int, i0: int, i1: int, i2: int, flip: bool, count: int) -> void:
	if i0 < 0 or i1 < 0 or i2 < 0 or i0 >= count or i1 >= count or i2 >= count:
		return
	indices.append(base + i0)
	if flip:
		indices.append(base + i2)
		indices.append(base + i1)
	else:
		indices.append(base + i1)
		indices.append(base + i2)

func _winding_flip(local: PackedVector3Array, idx: PackedInt32Array, normals: PackedVector3Array) -> bool:
	if normals.is_empty():
		return false
	var count := int(local.size() / 3) if idx.is_empty() else int(idx.size() / 3)
	var step := maxi(1, int(count / 240.0))
	var agree := 0.0
	var t := 0
	while t < count:
		var i0: int
		var i1: int
		var i2: int
		if idx.is_empty():
			i0 = t * 3
			i1 = i0 + 1
			i2 = i0 + 2
		else:
			i0 = idx[t * 3]
			i1 = idx[t * 3 + 1]
			i2 = idx[t * 3 + 2]
		if i0 < local.size() and i1 < local.size() and i2 < local.size() and i0 < normals.size() and i1 < normals.size() and i2 < normals.size():
			var gn := (local[i1] - local[i0]).cross(local[i2] - local[i0])
			var an: Vector3 = normals[i0] + normals[i1] + normals[i2]
			agree += gn.dot(an)
		t += step
	return agree < 0.0

func _bind_map(skin: Skin, skel: Skeleton3D) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(skin.get_bind_count())
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(i))
		map[i] = bone
	return map

func _posed_binds(skin: Skin, skel: Skeleton3D) -> Array[Transform3D]:
	var globals := _bone_globals(skel)
	var map := _bind_map(skin, skel)
	var posed: Array[Transform3D] = []
	posed.resize(map.size())
	for i in map.size():
		var bone := int(map[i])
		if bone < 0 or bone >= globals.size():
			posed[i] = Transform3D()
		else:
			posed[i] = globals[bone] * skin.get_bind_pose(i)
	return posed

func _bone_globals(skel: Skeleton3D) -> Array[Transform3D]:
	skel.force_update_all_bone_transforms()
	var out: Array[Transform3D] = []
	var count := skel.get_bone_count()
	out.resize(count)
	for i in count:
		out[i] = skel.get_bone_global_pose(i)
	var arm := skel.find_bone("UpperArm.L")
	if arm >= 0:
		var scale := skel.get_bone_pose_scale(arm)
		if scale.x < 0.05 and scale.y < 0.05 and scale.z < 0.05:
			var posed := out[arm].basis.get_scale()
			if posed.x > 0.05 or posed.y > 0.05 or posed.z > 0.05:
				return _manual_globals(skel)
	return out

func _manual_globals(skel: Skeleton3D) -> Array[Transform3D]:
	var count := skel.get_bone_count()
	var globals: Array[Transform3D] = []
	globals.resize(count)
	var ready := PackedByteArray()
	ready.resize(count)
	for _pass in count:
		var progressed := false
		for i in count:
			if ready[i] != 0:
				continue
			var parent := skel.get_bone_parent(i)
			if parent >= 0 and ready[parent] == 0:
				continue
			var local := skel.get_bone_pose(i)
			globals[i] = local if parent < 0 else globals[parent] * local
			ready[i] = 1
			progressed = true
		if not progressed:
			break
	return globals

func _behind_bones(skel: Skeleton3D, arm_pose: Dictionary) -> String:
	if skel == null:
		return ""
	var counts := {}
	var inv := _camera.global_transform.affine_inverse()
	for i in arm_pose.verts.size():
		if -(inv * arm_pose.verts[i]).z >= 0.0:
			continue
		var bone := int(arm_pose.bones[i])
		var name := "none" if bone < 0 else String(skel.get_bone_name(bone))
		counts[name] = int(counts.get(name, 0)) + 1
	return str(counts)

func _arm_scale(skel: Skeleton3D) -> float:
	if skel == null:
		return 1.0
	var arm := skel.find_bone("UpperArm.L")
	if arm < 0:
		return 1.0
	var s := skel.get_bone_pose_scale(arm)
	return maxf(s.x, maxf(s.y, s.z))

func _left_extent(skel: Skeleton3D, arm_pose: Dictionary) -> float:
	if skel == null or arm_pose.verts.is_empty():
		return 0.0
	var ids := {}
	var arm := skel.find_bone("UpperArm.L")
	if arm < 0:
		return 0.0
	var stack: Array[int] = [arm]
	while not stack.is_empty():
		var bone: int = stack.pop_back()
		ids[bone] = true
		for child in skel.get_bone_children(bone):
			stack.append(int(child))
	var any := false
	var mn := Vector3.ZERO
	var mx := Vector3.ZERO
	for i in arm_pose.bones.size():
		if not ids.has(int(arm_pose.bones[i])):
			continue
		var p: Vector3 = arm_pose.verts[i]
		if not any:
			mn = p
			mx = p
			any = true
		else:
			mn = mn.min(p)
			mx = mx.max(p)
	if not any:
		return 0.0
	var size := mx - mn
	return maxf(size.x, maxf(size.y, size.z))

func _part_ids(skel: Skeleton3D, hand: String, part: String) -> Dictionary:
	var ids := {}
	for bname in BONES[hand][part]:
		var idx := skel.find_bone(bname)
		if idx >= 0:
			ids[idx] = true
	return ids

func _pca_axis(verts: PackedVector3Array) -> Dictionary:
	var fallback := -_camera.global_transform.basis.z
	if verts.size() < 3:
		return {"c": Vector3.ZERO, "axis": fallback}
	var c := Vector3.ZERO
	for v in verts:
		c += v
	c /= float(verts.size())
	var xx := 0.0
	var xy := 0.0
	var xz := 0.0
	var yy := 0.0
	var yz := 0.0
	var zz := 0.0
	for v in verts:
		var d := v - c
		xx += d.x * d.x
		xy += d.x * d.y
		xz += d.x * d.z
		yy += d.y * d.y
		yz += d.y * d.z
		zz += d.z * d.z
	var axis := fallback.normalized()
	for _i in 24:
		var mv := Vector3(
			xx * axis.x + xy * axis.y + xz * axis.z,
			xy * axis.x + yy * axis.y + yz * axis.z,
			xz * axis.x + yz * axis.y + zz * axis.z
		)
		if mv.length_squared() < 1e-12:
			break
		axis = mv.normalized()
	return {"c": c, "axis": axis}

func _longest(verts: PackedVector3Array) -> float:
	if verts.is_empty():
		return 0.0
	var mn := verts[0]
	var mx := verts[0]
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	var size := mx - mn
	return maxf(size.x, maxf(size.y, size.z))

func _ratio_of(x: float, y: float, z: float) -> float:
	var mn := minf(x, minf(y, z))
	var mx := maxf(x, maxf(y, z))
	if mn < 1e-6:
		return 999.0
	return mx / mn

func _bore_axes(bore: Vector3) -> Dictionary:
	var cam_up := _camera.global_transform.basis.y
	var cam_right := _camera.global_transform.basis.x
	var right := cam_right - bore * bore.dot(cam_right)
	if right.length_squared() < 1e-8:
		right = cam_up.cross(bore)
	right = right.normalized()
	var up := bore.cross(right)
	if up.dot(cam_up) < 0.0:
		up = -up
		right = -right
	return {"right": right, "up": up.normalized()}

func _section(verts: PackedVector3Array, centroid: Vector3, bore: Vector3, station: float, right: Vector3, up: Vector3) -> Vector2:
	var slab := 0.015
	for pass_i in 3:
		var min_r := 1e9
		var max_r := -1e9
		var min_u := 1e9
		var max_u := -1e9
		var n := 0
		for v in verts:
			if absf(bore.dot(v - centroid) - station) > slab:
				continue
			var r := right.dot(v)
			var u := up.dot(v)
			min_r = minf(min_r, r)
			max_r = maxf(max_r, r)
			min_u = minf(min_u, u)
			max_u = maxf(max_u, u)
			n += 1
		if n >= 8 or pass_i == 2:
			if n > 0:
				return Vector2(max_r - min_r, max_u - min_u)
			return Vector2.ZERO
		slab *= 2.0
	return Vector2.ZERO

func _bore_angle(bore: Vector3, muzzle: Vector3) -> float:
	var aim := (_camera.global_position - _camera.global_transform.basis.z * 40.0) - muzzle
	if aim.length_squared() < 1e-8 or bore.length_squared() < 1e-8:
		return 180.0
	return rad_to_deg(bore.normalized().angle_to(aim.normalized()))

func _bore_miss(bore: Vector3, muzzle: Vector3) -> float:
	var far: Vector3 = muzzle + bore.normalized() * 20.0
	var la: Vector3 = _cam.global_transform.affine_inverse() * muzzle
	var lb: Vector3 = _cam.global_transform.affine_inverse() * far
	var size := _cam.get_viewport().get_visible_rect().size
	if size.y < 2.0:
		size = Vector2(VIEW_W, VIEW_H)
	if -la.z <= 0.02 or -lb.z <= 0.02:
		return 100.0
	var a := _cam.unproject_position(muzzle)
	var b := _cam.unproject_position(far)
	var center := size * 0.5
	var ab := b - a
	var span := ab.length()
	var dist: float
	if span < 0.001:
		dist = a.distance_to(center)
	else:
		var cross := (center.x - a.x) * ab.y - (center.y - a.y) * ab.x
		dist = absf(cross) / span
	return dist / size.y * 100.0

func _min_depth(gun_verts: PackedVector3Array, arm_verts: PackedVector3Array, shift: Vector3) -> float:
	var inv := _camera.global_transform.affine_inverse()
	var best := 1e9
	for v in gun_verts:
		best = minf(best, -(inv * (v + shift)).z)
	for v in arm_verts:
		best = minf(best, -(inv * (v + shift)).z)
	if best > 1e8:
		return 0.0
	return best

func _build_bins(verts: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var bins := {}
	var tris := int(indices.size() / 3)
	for t in tris:
		var a := verts[indices[t * 3]]
		var b := verts[indices[t * 3 + 1]]
		var c := verts[indices[t * 3 + 2]]
		var mn := a.min(b).min(c)
		var mx := a.max(b).max(c)
		var i0 := _cell(mn)
		var i1 := _cell(mx)
		for z in range(i0.z, i1.z + 1):
			for y in range(i0.y, i1.y + 1):
				for x in range(i0.x, i1.x + 1):
					var key := Vector3i(x, y, z)
					if not bins.has(key):
						bins[key] = []
					bins[key].append(t)
	return bins

func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))

func _gap(which: Array[int], arm_verts: PackedVector3Array, gun_pose: Dictionary, bins: Dictionary, stamp: PackedInt32Array, gun_mn: Vector3, gun_mx: Vector3) -> Dictionary:
	if which.is_empty() or gun_pose.indices.is_empty():
		return {"gap": null, "hand": Vector3.ZERO, "gun": Vector3.ZERO, "ok": false}
	var order: Array[int] = which.duplicate()
	var gun_c := (gun_mn + gun_mx) * 0.5
	order.sort_custom(func(i, j):
		return arm_verts[i].distance_squared_to(gun_c) < arm_verts[j].distance_squared_to(gun_c)
	)
	var mn := arm_verts[order[0]]
	var mx := mn
	for i in order:
		var p: Vector3 = arm_verts[i]
		mn = mn.min(p)
		mx = mx.max(p)
	var margin := 0.08
	var best_signed := 1e9
	var hand := mn
	var gun_p := mn
	var indices: PackedInt32Array = gun_pose.indices
	var gverts: PackedVector3Array = gun_pose.verts
	while margin <= 0.64:
		var cand := _tris_touching(bins, stamp, mn, mx, margin, int(indices.size() / 3))
		best_signed = 1e9
		var need_more := cand.is_empty()
		for i in order:
			var p: Vector3 = arm_verts[i]
			var outside := _aabb_dist(p, gun_mn, gun_mx)
			if best_signed < 1e8 and outside > maxf(best_signed, 0.0) + 0.002:
				continue
			var absd := 1e9
			var sgn := 1.0
			var cp := p
			for t in cand:
				var i0 := int(t) * 3
				var box := _tri_box_dist(p, gverts[indices[i0]], gverts[indices[i0 + 1]], gverts[indices[i0 + 2]])
				if box >= absd:
					continue
				_point_tri(p, gverts[indices[i0]], gverts[indices[i0 + 1]], gverts[indices[i0 + 2]])
				if _hit_d < absd:
					absd = _hit_d
					sgn = _hit_s
					cp = _hit_p
			if absd >= margin - 0.001:
				need_more = true
			var signed := sgn * absd
			if signed < best_signed:
				best_signed = signed
				hand = p
				gun_p = cp
		if not need_more or margin >= 0.64:
			break
		margin *= 2.0
	if best_signed > 1e8:
		return {"gap": null, "hand": Vector3.ZERO, "gun": Vector3.ZERO, "ok": false}
	return {"gap": best_signed, "hand": hand, "gun": gun_p, "ok": true}

func _tris_touching(bins: Dictionary, stamp: PackedInt32Array, mn: Vector3, mx: Vector3, margin: float, tri_count: int) -> Array:
	if stamp.is_empty():
		return []
	_epoch += 1
	if _epoch > 2000000000:
		stamp.fill(0)
		_epoch = 1
	var pad := Vector3(margin, margin, margin)
	var a := _cell(mn - pad)
	var b := _cell(mx + pad)
	var result: Array = []
	if b.x - a.x > 48 or b.y - a.y > 48 or b.z - a.z > 48:
		for t in tri_count:
			result.append(t)
		return result
	for z in range(a.z, b.z + 1):
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				var key := Vector3i(x, y, z)
				if not bins.has(key):
					continue
				for t in bins[key]:
					var ti := int(t)
					if ti < 0 or ti >= stamp.size():
						continue
					if stamp[ti] == _epoch:
						continue
					stamp[ti] = _epoch
					result.append(ti)
	return result

func _aabb_dist(p: Vector3, mn: Vector3, mx: Vector3) -> float:
	var q := Vector3(clampf(p.x, mn.x, mx.x), clampf(p.y, mn.y, mx.y), clampf(p.z, mn.z, mx.z))
	return p.distance_to(q)

func _tri_box_dist(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var mn := a.min(b).min(c)
	var mx := a.max(b).max(c)
	return _aabb_dist(p, mn, mx)

func _point_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	var ab := b - a
	var ac := c - a
	var normal := ab.cross(ac)
	var nlen2 := normal.length_squared()
	if nlen2 < 1e-16:
		_closest_degenerate(p, a, b, c)
		return
	var n := normal / sqrt(nlen2)
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	var closest := a
	if d1 <= 0.0 and d2 <= 0.0:
		closest = a
	else:
		var bp := p - b
		var d3 := ab.dot(bp)
		var d4 := ac.dot(bp)
		if d3 >= 0.0 and d4 <= d3:
			closest = b
		else:
			var vc := d1 * d4 - d3 * d2
			if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
				var v := d1 / (d1 - d3)
				closest = a + ab * v
			else:
				var cp := p - c
				var d5 := ab.dot(cp)
				var d6 := ac.dot(cp)
				if d6 >= 0.0 and d5 <= d6:
					closest = c
				else:
					var vb := d5 * d2 - d1 * d6
					if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
						var w := d2 / (d2 - d6)
						closest = a + ac * w
					else:
						var va := d3 * d6 - d5 * d4
						var edge := (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0
						if va <= 0.0 and edge:
							var denom_edge := (d4 - d3) + (d5 - d6)
							var w2 := 0.0 if absf(denom_edge) < 1e-12 else (d4 - d3) / denom_edge
							closest = b + (c - b) * w2
						else:
							var denom := va + vb + vc
							if absf(denom) < 1e-12:
								closest = a
							else:
								var v2 := vb / denom
								var w3 := vc / denom
								closest = a + ab * v2 + ac * w3
	var delta := p - closest
	_hit_d = delta.length()
	_hit_p = closest
	_hit_s = -1.0 if delta.dot(n) < 0.0 else 1.0

func _closest_degenerate(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	var best := a
	var best_d := p.distance_squared_to(a)
	for seg in [[a, b], [b, c], [c, a]]:
		var q := _closest_seg(p, seg[0], seg[1])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = q
	_hit_p = best
	_hit_d = sqrt(best_d)
	_hit_s = 1.0

func _closest_seg(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var den := ab.length_squared()
	if den < 1e-12:
		return a
	var t := clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return a + ab * t

func _self_check() -> bool:
	_point_tri(Vector3(0.2, 0.2, 0.5), Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0))
	if absf(_hit_d - 0.5) > 1e-4 or _hit_s < 0.0:
		return false
	_point_tri(Vector3(0.2, 0.2, -0.25), Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0))
	if absf(_hit_d - 0.25) > 1e-4 or _hit_s > 0.0:
		return false
	_point_tri(Vector3(2, 0, 0), Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0))
	if absf(_hit_d - 1.0) > 1e-4 or _hit_p.distance_to(Vector3(1, 0, 0)) > 1e-4:
		return false
	return true
