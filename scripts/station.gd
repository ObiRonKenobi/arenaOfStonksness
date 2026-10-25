extends StaticBody3D

@export var kind := "wall"
@export var weapon_id := ""
@export var perk_id := ""

func _ready() -> void:
	add_to_group("stations")
	collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.4, 0.25)
	shape.shape = box
	shape.position = Vector3(0, 0.7, 0)
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	mesh.position = shape.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color()
	mesh.material_override = mat
	add_child(mesh)
	var label := Label3D.new()
	label.text = _title()
	label.font_size = 42
	label.position = Vector3(0, 1.7, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 0.95, 0.8)
	label.outline_size = 8
	add_child(label)

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
