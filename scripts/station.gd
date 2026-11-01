extends StaticBody3D

const PROP_PATH := {
	"markup": "res://assets/props/markup.glb",
	"smith": "res://assets/props/street_smith.glb",
	"crate": "res://assets/props/mystery_crate.glb",
	"planks": "res://assets/props/planks.glb",
}
const PERK_PATH := {
	"thick_skin": "res://assets/props/thick_skin.glb",
	"rapid_fire": "res://assets/props/rapid_fire.glb",
	"tin_vest": "res://assets/props/tin_vest.glb",
	"mean_streak": "res://assets/props/mean_streak.glb",
}
const WALL_GUN := {
	"street_smg": ["res://assets/weapons/smg_v1.glb", 0.0],
	"debt_shotgun": ["res://assets/weapons/mossberg.glb", 0.0],
	"rent_rifle": ["res://assets/weapons/rifle.glb", -90.0],
	"pop_junk": ["res://assets/weapons/ray_gun.glb", -90.0],
	"ledger_cannon": ["res://assets/weapons/ledger_cannon.glb", 180.0],
}

@export var kind := "wall"
@export var weapon_id := ""
@export var perk_id := ""

var _hit: BoxShape3D
var _shape: CollisionShape3D
var _label: Label3D

func _ready() -> void:
	add_to_group("stations")
	collision_layer = 1
	_shape = CollisionShape3D.new()
	_hit = BoxShape3D.new()
	_hit.size = Vector3(0.8, 1.4, 0.25)
	_shape.shape = _hit
	_shape.position = Vector3(0, 0.7, 0)
	add_child(_shape)
	_label = Label3D.new()
	_label.text = _title()
	_label.font_size = 42
	_label.position = Vector3(0, 1.7, 0.1)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1, 0.95, 0.8)
	_label.outline_size = 8
	add_child(_label)
	if not _mount_model():
		_add_box()

func use(player: Node) -> void:
	match kind:
		"wall":
			_buy_wall(player)
		"perk":
			player.call("add_perk", perk_id)
		"crate":
			_buy_crate(player)
		"smith":
			var stat: String = player.call("next_smith_stat")
			if stat == "":
				GameState.toast("Street Smith has nothing left for this gun.")
				return
			player.call("buy_smith", stat)
		"markup":
			player.call("markup")
		"planks":
			if player.call("try_buy", Economy.PLANK_PACK_COST):
				player.set("planks", int(player.get("planks")) + Economy.PLANK_PACK_COUNT)
				GameState.toast("Planks: %d" % int(player.get("planks")))

func prompt_for(player: Node) -> String:
	match kind:
		"wall":
			var spec: Dictionary = Economy.weapon(weapon_id)
			if player.call("owns_weapon", weapon_id):
				return "E  Ammo for %s  $%d" % [spec.name, Economy.ammo_cost(weapon_id)]
			return "E  Buy %s  $%d" % [spec.name, int(spec.price)]
		"perk":
			var perk: Dictionary = Economy.PERKS[perk_id]
			return "E  %s  $%d" % [perk.name, int(perk.price)]
		"crate":
			return "E  Black Market Crate  $%d" % Economy.CRATE_COST
		"smith":
			var stat: String = str(player.call("next_smith_stat"))
			if stat == "":
				return "Street Smith is maxed"
			var level := int(player.call("_smith_level", stat)) + 1
			return "E  Street Smith %s  $%d" % [stat, Economy.smith_cost(level)]
		"markup":
			var tier := int(player.get("weapon_tier"))
			var held := str(Economy.weapon(str(player.get("weapon_id"))).name)
			if tier >= 3:
				return "%s is v3" % held
			return "E  Upgrade %s to %s  $%d" % [held, Economy.tier_label(tier + 1), Economy.markup_cost(str(player.get("weapon_id")), tier + 1)]
		"planks":
			return "E  Planks x%d  $%d" % [Economy.PLANK_PACK_COUNT, Economy.PLANK_PACK_COST]
	return "E"

func _buy_wall(player: Node) -> void:
	if player.call("owns_weapon", weapon_id):
		if player.call("try_buy", Economy.ammo_cost(weapon_id)):
			player.call("refill_weapon", weapon_id)
			GameState.toast("Ammo refilled.")
		return
	var price := int(Economy.weapon(weapon_id).price)
	if player.call("try_buy", price):
		player.call("give_weapon", weapon_id, 1, false)

func _buy_crate(player: Node) -> void:
	if not player.call("try_buy", Economy.CRATE_COST):
		return
	var rolled := Economy.roll_crate()
	player.call("give_weapon", rolled, 1, false)

func _title() -> String:
	match kind:
		"wall":
			return Economy.weapon(weapon_id).name
		"perk":
			return Economy.PERKS[perk_id].name
		"crate":
			return "Black Market"
		"smith":
			return "Street Smith"
		"markup":
			return "The Markup"
		"planks":
			return "Planks"
	return kind

func _model_path() -> Array:
	if kind == "wall" and WALL_GUN.has(weapon_id):
		return WALL_GUN[weapon_id]
	if kind == "perk" and PERK_PATH.has(perk_id):
		return [PERK_PATH[perk_id], 0.0]
	if PROP_PATH.has(kind):
		return [PROP_PATH[kind], 0.0]
	return []

func _mount_model() -> bool:
	var spec := _model_path()
	if spec.is_empty():
		return false
	var packed := load(str(spec[0])) as PackedScene
	if packed == null:
		return false
	var hang := kind == "wall"
	var holder := Node3D.new()
	add_child(holder)
	var model := packed.instantiate() as Node3D
	model.rotation_degrees.y = float(spec[1])
	holder.add_child(model)
	var bounds := _bounds_under(holder)
	if not hang:
		_use_texture_color(model)
	if not hang and bounds.size.y < maxf(bounds.size.x, bounds.size.z) * 0.35:
		model.rotation_degrees = Vector3(-90.0, float(spec[1]) + 180.0, 0.0)
		bounds = _bounds_under(holder)
	var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if span < 0.001:
		holder.queue_free()
		return false
	var target := 1.05 if hang else 1.2
	var fitted := target / span
	model.scale *= fitted
	var center := bounds.get_center() * fitted
	var ext := bounds.size * fitted
	model.position = -center
	if hang:
		holder.position = Vector3(0, 1.15, -0.08)
		_set_hit(Vector3(maxf(ext.x, 0.7), maxf(ext.y, 0.35) + 0.2, 0.28), Vector3(0, 1.15, 0.02))
		_label.position = Vector3(0, 1.15 + ext.y * 0.5 + 0.22, 0.05)
	else:
		holder.position = Vector3(0, ext.y * 0.5, ext.z * 0.5 + 0.08)
		_set_hit(Vector3(maxf(ext.x, 0.55), ext.y, maxf(ext.z, 0.35)), Vector3(0, ext.y * 0.5, ext.z * 0.35))
		_label.position = Vector3(0, ext.y + 0.28, ext.z * 0.2)
	return true

func _use_texture_color(root: Node) -> void:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		var source := mesh_node.get_active_material(0) as StandardMaterial3D
		if source == null:
			continue
		var mat := source.duplicate() as StandardMaterial3D
		mat.metallic = 0.0
		mat.roughness = 0.72
		mesh_node.material_override = mat

func _bounds_under(root: Node3D) -> AABB:
	var box := AABB()
	var started := false
	var inv := root.global_transform.affine_inverse()
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	for mesh_node in meshes:
		if mesh_node.mesh == null:
			continue
		var local := mesh_node.mesh.get_aabb()
		var to_root := inv * mesh_node.global_transform
		for i in 8:
			var point: Vector3 = to_root * local.get_endpoint(i)
			if not started:
				box = AABB(point, Vector3.ZERO)
				started = true
			else:
				box = box.expand(point)
	return box

func _set_hit(size: Vector3, pos: Vector3) -> void:
	_hit.size = size
	_shape.position = pos

func _add_box() -> void:
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = _hit.size
	mesh.mesh = cube
	mesh.position = _shape.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color()
	mesh.material_override = mat
	add_child(mesh)

func _color() -> Color:
	match kind:
		"wall":
			return Color(0.35, 0.38, 0.42)
		"perk":
			return Color(0.15, 0.45, 0.42)
		"crate":
			return Color(0.45, 0.28, 0.1)
		"smith":
			return Color(0.4, 0.4, 0.45)
		"markup":
			return Color(0.55, 0.4, 0.12)
		"planks":
			return Color(0.42, 0.3, 0.18)
	return Color.GRAY
