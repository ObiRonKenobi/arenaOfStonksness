extends CanvasLayer

var _health: Label
var _cash: Label
var _ammo: Label
var _ult: Label
var _wave: Label
var _prompt: Label
var _toast: Label
var _menu: Control
var _over: Control
var _over_label: Label
var _toast_time := 0.0
var _hurt := 0.0
var _heal := 0.0
var _supply := 0.0
var _supply_color := Color(0.72, 0.55, 0.08)
var _health_seen := -1.0
var _crosshair: Label
var _hail: Label
var _menu_home: Control
var _menu_page: Control
var _menu_heroes: Control
var _page_title: Label
var _page_body: Label
var _page_open := false
var _heroes_open := false
var _loading := false
var _hero_viewport: SubViewport
var _hero_stage: Node
var _hero_name: Label
var _hero_bio: Label
var _loader: Control
var _load_status: Label
var _load_percent: Label
var _load_fill: ColorRect
var _down_tint: ColorRect
var _heal_tint: ColorRect
var _supply_tint: ColorRect

func _ready() -> void:
	add_to_group("hud")
	layer = 10
	_build_hud()
	_build_menu()
	_build_over()
	_build_loader()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.connect("health_changed", _on_health)
		player.connect("cash_changed", _on_cash)
		player.connect("ammo_changed", func(): _on_ammo(player))
		player.connect("ult_changed", _on_ult)
		player.connect("weapon_changed", func(): _on_ammo(player))
		player.connect("ammo_for_me", _on_my_ammo)
		_on_health(float(player.get("health")), float(player.get("max_health")))
		_on_cash(int(player.get("cash")))
		_on_ammo(player)
		_on_ult(float(player.get("ult")))
	GameState.round_changed.connect(func(index): _wave.text = "Wave %d" % index)
	GameState.toast_requested.connect(show_toast)
	GameState.king_hail.connect(_on_hail)
	GameState.ammo_shared.connect(_on_shared_ammo)
	GameState.game_over.connect(_on_over)

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.text = ""
	var player := get_tree().get_first_node_in_group("player")
	var downed := player != null and bool(player.get("_downed"))
	var amount := 0.0
	if player != null:
		amount = clampf(float(player.get("_down_t")), 0.0, 1.0)
	if _hurt > 0.0:
		_hurt = maxf(0.0, _hurt - delta)
	if _heal > 0.0:
		_heal = maxf(0.0, _heal - delta)
	if _supply > 0.0:
		_supply = maxf(0.0, _supply - delta)
	if _down_tint:
		var flash := 0.5 * _hurt / 0.75
		_down_tint.color = Color(0.42, 0.0, 0.02, maxf(0.55 * amount, flash))
	if _heal_tint:
		_heal_tint.color = Color(0.05, 0.45, 0.12, 0.5 * _heal / 0.75)
	if _supply_tint:
		_supply_tint.color = Color(_supply_color.r, _supply_color.g, _supply_color.b, 0.5 * _supply / 0.75)
	if _crosshair:
		_crosshair.visible = GameState.running and not downed and _menu != null and not _menu.visible

func set_prompt(text: String) -> void:
	_prompt.text = text

func show_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 2.4

func _on_my_ammo() -> void:
	_flash_supply(Color(0.72, 0.55, 0.08))

func _on_shared_ammo() -> void:
	_flash_supply(Color(0.42, 0.12, 0.62))

func _flash_supply(color: Color) -> void:
	_supply = 0.75
	_supply_color = color
	_play_sting("res://assets/audio/ammo_reload.mp3")

func _on_health(current: float, maximum: float) -> void:
	_health.text = "Health %d / %d" % [int(current), int(maximum)]
	if _health_seen >= 0.0 and current < _health_seen:
		_hurt = 0.75
		_play_sting("res://assets/audio/hurt.mp3")
	elif _health_seen >= 0.0 and current > _health_seen:
		_heal = 0.75
		_play_sting("res://assets/audio/healing.mp3")
	_health_seen = current

func _play_sting(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -4.0
	player.pitch_scale = 1.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _on_cash(amount: int) -> void:
	_cash.text = "$%d" % amount

func _on_ammo(player: Node) -> void:
	if player.has_method("weapon_hud"):
		_ammo.text = str(player.call("weapon_hud"))
	else:
		_ammo.text = "%s   %d / %d" % [str(player.call("weapon_label")), int(player.get("mag")), int(player.get("reserve"))]

func _on_ult(amount: float) -> void:
	_ult.text = "Ult %d" % int(amount)

func _on_over(rounds_survived: int) -> void:
	_over.visible = true
	_over_label.text = "The horde took the rent.\nWaves cleared: %d" % rounds_survived
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_hud() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 16)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_right", 16)
	root.add_theme_constant_override("margin_bottom", 16)
	add_child(root)
	var box := VBoxContainer.new()
	root.add_child(box)
	_wave = _label("Wave 0")
	_health = _label("Health")
	_cash = _label("$0")
	_ammo = _label("Pipe Pistol")
	_ult = _label("Ult 0")
	for item in [_wave, _health, _cash, _ammo, _ult]:
		box.add_child(item)
	_prompt = _label("")
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -80
	_prompt.offset_bottom = -40
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	_toast = _label("")
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 80
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_crosshair = _label("+")
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -12
	_crosshair.offset_top = -16
	_crosshair.offset_right = 12
	_crosshair.offset_bottom = 16
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.add_theme_font_size_override("font_size", 28)
	_crosshair.visible = false
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	_hail = _label("Hail to the King, Baby!")
	_hail.set_anchors_preset(Control.PRESET_CENTER)
	_hail.offset_left = -420
	_hail.offset_top = -40
	_hail.offset_right = 420
	_hail.offset_bottom = 40
	_hail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hail.add_theme_font_size_override("font_size", 42)
	_hail.visible = false
	_hail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hail)

func _build_menu() -> void:
	_menu = ColorRect.new()
	_menu.color = Color(0.05, 0.04, 0.04, 0.82)
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.gui_input.connect(_menu_click)
	add_child(_menu)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(center)
	_menu_home = VBoxContainer.new()
	_menu_home.custom_minimum_size = Vector2(520, 0)
	_menu_home.add_theme_constant_override("separation", 14)
	center.add_child(_menu_home)
	var title := _label("Arena of Stonksness")
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_home.add_child(title)
	var start := Button.new()
	start.text = "Start match"
	start.custom_minimum_size = Vector2(280, 52)
	start.pressed.connect(_start_solo)
	_menu_home.add_child(start)
	var story := Button.new()
	story.text = "Story"
	story.custom_minimum_size = Vector2(220, 40)
	story.pressed.connect(_open_story)
	_menu_home.add_child(story)
	var heroes := Button.new()
	heroes.text = "Heroes"
	heroes.custom_minimum_size = Vector2(220, 40)
	heroes.pressed.connect(_open_heroes)
	_menu_home.add_child(heroes)
	var how := Button.new()
	how.text = "How to Play"
	how.custom_minimum_size = Vector2(220, 40)
	how.pressed.connect(_open_how)
	_menu_home.add_child(how)
	var credits := Button.new()
	credits.text = "Credits"
	credits.custom_minimum_size = Vector2(220, 40)
	credits.pressed.connect(_open_credits)
	_menu_home.add_child(credits)
	_menu_page = VBoxContainer.new()
	_menu_page.custom_minimum_size = Vector2(560, 0)
	_menu_page.add_theme_constant_override("separation", 12)
	_menu_page.visible = false
	center.add_child(_menu_page)
	_page_title = _label("")
	_page_title.add_theme_font_size_override("font_size", 32)
	_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_page.add_child(_page_title)
	_page_body = _label("")
	_page_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_body.custom_minimum_size = Vector2(640, 0)
	_menu_page.add_child(_page_body)
	var back := Button.new()
	back.text = "Main menu"
	back.custom_minimum_size = Vector2(220, 40)
	back.pressed.connect(_close_page)
	_menu_page.add_child(back)
	_build_heroes(center)

func _build_over() -> void:
	_down_tint = ColorRect.new()
	_down_tint.color = Color(0.42, 0.0, 0.02, 0.0)
	_down_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_down_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_down_tint)
	_heal_tint = ColorRect.new()
	_heal_tint.color = Color(0.05, 0.45, 0.12, 0.0)
	_heal_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_heal_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heal_tint)
	_supply_tint = ColorRect.new()
	_supply_tint.color = Color(0.72, 0.55, 0.08, 0.0)
	_supply_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_supply_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_supply_tint)
	_over = ColorRect.new()
	_over.visible = false
	_over.color = Color(0.08, 0.02, 0.02, 0.8)
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_over)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	_over_label = _label("Down")
	_over_label.add_theme_font_size_override("font_size", 28)
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_label)
	var again := Button.new()
	again.text = "Try again"
	again.custom_minimum_size = Vector2(220, 48)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	box.add_child(again)

func _open_story() -> void:
	_show_page("The Memo", "The firm bought the block. Buried in the paperwork was one line: clear the building for Q3 site optimization. The brokers read it as an order. They come in suits, on the clock, through the windows, because the memo said clear the building and nobody asked how.\n\nYou live here. The memo calls you a squatter. They already took the work. Now they have come for the rest.\n\nFour people are on the same spreadsheet. Spike annotated the memo. Reggie thinks the whole thing is a joke. Cletus knows his row number and means to invoice them. Rivet poured the floor they are standing on. You board the windows, buy the guns, and survive the next wave. The brokers keep coming. Nobody has read the whole procedure.")

func _open_how() -> void:
	_show_page("How to Play", "WASD move. Left Shift sprint. Space jump. Mouse look.\nLeft click shoots. Right mouse aims. With two pistols, right click fires the offhand.\nR reloads.\nE buys a wall gun, a perk, or a shop door. Hold E at a window to board it.\nQ uses your ult.\n1 and 2, or the mouse wheel, switch weapons.\nEsc releases the mouse.\n\nBrokers drop cash. Spend it before the next wave.")

func _open_credits() -> void:
	_show_page("Credits", "An RBYT3R Production\n\nWith Much Thanks To:\nQuaternius\nKenney\nJ-Toastie\nburunduk\nuniversfield\nsound-work")

func _show_page(title: String, body: String) -> void:
	_close_heroes()
	_page_open = true
	_page_title.text = title
	_page_body.text = body
	_menu_home.visible = false
	_menu_page.visible = true

func _close_page() -> void:
	_page_open = false
	_menu_page.visible = false
	_menu_home.visible = true

func _build_heroes(center: Control) -> void:
	_menu_heroes = VBoxContainer.new()
	_menu_heroes.custom_minimum_size = Vector2(720, 0)
	_menu_heroes.add_theme_constant_override("separation", 10)
	_menu_heroes.visible = false
	center.add_child(_menu_heroes)
	var title := _label("Heroes")
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_heroes.add_child(title)
	var host := SubViewportContainer.new()
	host.custom_minimum_size = Vector2(720, 320)
	host.stretch = true
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_heroes.add_child(host)
	_hero_viewport = SubViewport.new()
	_hero_viewport.transparent_bg = false
	_hero_viewport.size = Vector2i(720, 320)
	_hero_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_hero_viewport.handle_input_locally = false
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.06, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	world.environment = env
	_hero_viewport.world_3d = world
	host.add_child(_hero_viewport)
	_hero_stage = Node3D.new()
	_hero_stage.set_script(load("res://scripts/hero_stage.gd"))
	_hero_viewport.add_child(_hero_stage)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_menu_heroes.add_child(row)
	var left := Button.new()
	left.text = "<"
	left.custom_minimum_size = Vector2(48, 40)
	left.focus_mode = Control.FOCUS_NONE
	left.pressed.connect(func(): _hero_step(-1))
	row.add_child(left)
	_hero_name = _label("")
	_hero_name.add_theme_font_size_override("font_size", 28)
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_name.custom_minimum_size = Vector2(220, 0)
	row.add_child(_hero_name)
	var right := Button.new()
	right.text = ">"
	right.custom_minimum_size = Vector2(48, 40)
	right.focus_mode = Control.FOCUS_NONE
	right.pressed.connect(func(): _hero_step(1))
	row.add_child(right)
	_hero_bio = _label("")
	_hero_bio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_bio.custom_minimum_size = Vector2(680, 0)
	_menu_heroes.add_child(_hero_bio)
	var back := Button.new()
	back.text = "Main menu"
	back.custom_minimum_size = Vector2(220, 40)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_close_heroes)
	_menu_heroes.add_child(back)

func _open_heroes() -> void:
	_page_open = false
	_menu_page.visible = false
	_heroes_open = true
	_menu_home.visible = false
	_menu_heroes.visible = true
	_hero_stage.call("set_active", true)
	_hero_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	CharacterDB.load_models()
	_hero_stage.call("setup")
	_show_hero()

func _close_heroes() -> void:
	if _hero_stage:
		_hero_stage.call("set_active", false)
	if _hero_viewport:
		_hero_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_heroes_open = false
	if _menu_heroes:
		_menu_heroes.visible = false
	if not _page_open and _menu_home:
		_menu_home.visible = true

func _hero_step(dir: int) -> void:
	if not _heroes_open:
		return
	_hero_stage.call("step", dir)
	_show_hero()

func _show_hero() -> void:
	var id := str(_hero_stage.call("current_id"))
	_hero_name.text = CharacterDB.display_name(id)
	_hero_bio.text = CharacterDB.bio(id)

func _build_loader() -> void:
	_loader = ColorRect.new()
	_loader.color = Color(0.05, 0.04, 0.04, 0.96)
	_loader.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loader.visible = false
	_loader.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_loader)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loader.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_load_status = _label("Loading map")
	_load_status.add_theme_font_size_override("font_size", 28)
	_load_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_load_status)
	var track := ColorRect.new()
	track.custom_minimum_size = Vector2(420, 18)
	track.color = Color(0.2, 0.16, 0.13)
	box.add_child(track)
	_load_fill = ColorRect.new()
	_load_fill.color = Color(0.93, 0.78, 0.42)
	_load_fill.anchor_right = 0.0
	_load_fill.anchor_bottom = 1.0
	_load_fill.offset_right = 0.0
	_load_fill.offset_bottom = 0.0
	track.add_child(_load_fill)
	_load_percent = _label("0%")
	_load_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_load_percent)

func _paint_load(status: String, percent: int) -> void:
	_loader.visible = true
	_load_status.text = status
	_load_percent.text = "%d%%" % percent
	_load_fill.anchor_right = clampf(float(percent) / 100.0, 0.0, 1.0)
	await get_tree().process_frame

func _on_hail() -> void:
	_hail.visible = true
	_hail.text = "Hail to the King, Baby!"
	_play_hail()
	var timer := get_tree().create_timer(2.2)
	timer.timeout.connect(func():
		if is_instance_valid(_hail):
			_hail.visible = false
	)

func _play_hail() -> void:
	var stream := load("res://assets/audio/hail_king.mp3") as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -4.0
	player.pitch_scale = 1.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _menu_click(event: InputEvent) -> void:
	if _page_open or _heroes_open or _loading:
		return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_start_solo()

func _input(event: InputEvent) -> void:
	if not _heroes_open:
		return
	if event.is_action_pressed("ui_left"):
		_hero_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_hero_step(1)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _heroes_open or _page_open or _loading:
		return
	if _menu.visible and (event.is_action_pressed("ui_accept") or event.is_action_pressed("shoot")):
		_start_solo()

func _start_solo() -> void:
	if _loading or _page_open or _heroes_open or not _menu.visible:
		return
	_loading = true
	var map := get_tree().get_first_node_in_group("map")
	var player := get_tree().get_first_node_in_group("player")
	await _paint_load("Loading map", 0)
	if map:
		map.call("build")
	await _paint_load("Loading characters", 20)
	CharacterDB.load_models()
	await _paint_load("Loading guns", 40)
	if player:
		player.call("load_guns")
	await _paint_load("Loading audio", 60)
	if map:
		map.call("load_audio")
	if player:
		player.call("load_audio")
	await _paint_load("Preparing shaders", 80)
	if player:
		player.call("load_shader")
		player.call("finish_boot")
	await get_tree().process_frame
	await get_tree().process_frame
	await _paint_load("Preparing shaders", 100)
	_loader.visible = false
	_menu.visible = false
	_loading = false
	_crosshair.visible = true
	GameState.begin_match()
	if player and player.has_method("capture_mouse"):
		player.call("capture_mouse")

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	return label
