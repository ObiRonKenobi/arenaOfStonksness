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
var _crosshair: Label
var _hail: Label
var _menu_home: Control
var _menu_page: Control
var _page_title: Label
var _page_body: Label
var _page_open := false

func _ready() -> void:
	add_to_group("hud")
	layer = 10
	_build_hud()
	_build_menu()
	_build_over()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.connect("health_changed", _on_health)
		player.connect("cash_changed", _on_cash)
		player.connect("ammo_changed", func(): _on_ammo(player))
		player.connect("ult_changed", _on_ult)
		player.connect("weapon_changed", func(): _on_ammo(player))
		_on_health(float(player.get("health")), float(player.get("max_health")))
		_on_cash(int(player.get("cash")))
		_on_ammo(player)
		_on_ult(float(player.get("ult")))
	GameState.round_changed.connect(func(index): _wave.text = "Wave %d" % index)
	GameState.toast_requested.connect(show_toast)
	GameState.king_hail.connect(_on_hail)
	GameState.game_over.connect(_on_over)

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.text = ""

func set_prompt(text: String) -> void:
	_prompt.text = text

func show_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 2.4

func _on_health(current: float, maximum: float) -> void:
	_health.text = "Health %d / %d" % [int(current), int(maximum)]

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
	_page_body.custom_minimum_size = Vector2(520, 0)
	_menu_page.add_child(_page_body)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(220, 40)
	back.pressed.connect(_close_page)
	_menu_page.add_child(back)

func _build_over() -> void:
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

func _open_how() -> void:
	_show_page("How to Play", "WASD move. Mouse look. Space jump.\nLeft click shoots. Right mouse aims. Right click also fires the offhand while holding two pistols.\nR reloads.\nE buys or interacts. Hold E at a window to board it.\nQ uses your ult.\n1 and 2, or the mouse wheel, switch weapons.\nEsc releases the mouse.")

func _open_credits() -> void:
	_show_page("Credits", "An RBYT3R Production\n\nWith Much Thanks To:\nQuaternius\nKenney\nJ-Toastie\nburunduk\nuniversfield\nsound-work")

func _show_page(title: String, body: String) -> void:
	_page_open = true
	_page_title.text = title
	_page_body.text = body
	_menu_home.visible = false
	_menu_page.visible = true

func _close_page() -> void:
	_page_open = false
	_menu_page.visible = false
	_menu_home.visible = true

func _on_hail() -> void:
	_hail.visible = true
	_hail.text = "Hail to the King, Baby!"
	var timer := get_tree().create_timer(2.2)
	timer.timeout.connect(func():
		if is_instance_valid(_hail):
			_hail.visible = false
	)

func _menu_click(event: InputEvent) -> void:
	if _page_open:
		return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_start_solo()

func _unhandled_input(event: InputEvent) -> void:
	if _page_open:
		return
	if _menu.visible and (event.is_action_pressed("ui_accept") or event.is_action_pressed("shoot")):
		_start_solo()

func _start_solo() -> void:
	if not _menu.visible:
		return
	_menu.visible = false
	_crosshair.visible = true
	GameState.begin_match()
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("capture_mouse"):
		player.call("capture_mouse")

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	return label
