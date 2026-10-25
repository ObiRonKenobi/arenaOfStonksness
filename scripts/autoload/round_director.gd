extends Node

signal enemy_count_changed(alive: int, remaining: int)
signal intermission_started(seconds: float)

const INTERMISSION := 10.0
# Waves 1-9, one row per player count from 1 to 4. Later waves use the square formulas.
const EARLY_BUDGET := [
	[6, 8, 13, 18, 24, 27, 28, 28, 29],
	[7, 9, 15, 21, 27, 31, 32, 33, 34],
	[9, 10, 18, 25, 32, 38, 40, 43, 45],
	[10, 12, 21, 29, 37, 45, 49, 52, 56],
]
var _alive := 0
var _alive_cap := 8
var _players := 1
var _budget := 0
var _spawned := 0
var _spawn_wait := 0.0
var _between := 0.0
var _in_round := false

func _ready() -> void:
	GameState.match_started.connect(_on_match_started)
	GameState.game_over.connect(func(_rounds): _stop())

func _process(delta: float) -> void:
	if not GameState.running or GameState.over:
		return
	if not _is_authority():
		return
	if _between > 0.0:
		_between -= delta
		if _between <= 0.0:
			_start_round(GameState.round_index + 1)
		return
	if not _in_round:
		return
	if _spawned < _budget:
		if _alive >= _alive_cap:
			return
		_spawn_wait -= delta
		if _spawn_wait <= 0.0:
			_spawn_one()
			_spawn_wait = maxf(0.6, 1.2 - float(GameState.round_index) * 0.02)
	elif _alive <= 0:
		_in_round = false
		GameState.mark_round_cleared()
		_between = INTERMISSION
		intermission_started.emit(INTERMISSION)
		GameState.toast("Buy time. Next wave in %d seconds." % int(INTERMISSION))

func _on_match_started() -> void:
	_stop()
	_start_round(1)

func _stop() -> void:
	_in_round = false
	_between = 0.0
	_budget = 0
	_spawned = 0
	_alive = 0

func _start_round(index: int) -> void:
	GameState.set_round(index)
	_players = _player_count()
	_alive_cap = 8 + 4 * (_players - 1)
	_budget = _wave_budget(index, _players)
	_spawned = 0
	_alive = 0
	_spawn_wait = 0.4
	_in_round = true
	_emit_counts()
	GameState.toast("Wave %d" % index)

func _spawn_one() -> void:
	var map := get_tree().get_first_node_in_group("map")
	if map == null:
		return
	var barricades: Array = get_tree().get_nodes_in_group("barricades")
	if barricades.is_empty():
		return
	var door = barricades[randi() % barricades.size()]
	var archetype := _roll_archetype()
	var stats := _stats_for(archetype)
	var enemy := preload("res://scenes/enemy.tscn").instantiate()
	map.add_child(enemy)
	enemy.global_position = door.spawn_position()
	enemy.setup(archetype, stats.hp, stats.speed, door)
	enemy.died.connect(_on_enemy_died)
	_spawned += 1
	_alive += 1
	_emit_counts()

func _on_enemy_died() -> void:
	_alive = maxi(0, _alive - 1)
	if _spawned < _budget and _alive < _alive_cap:
		_spawn_wait = 0.0
	_emit_counts()

func _roll_archetype() -> String:
	var round_index := GameState.round_index
	var bag: Array[String] = ["collector"]
	if round_index >= 3:
		bag.append("broker")
		bag.append("broker")
	if round_index >= 5:
		bag.append("king")
	if round_index >= 8:
		bag.append("king")
	return bag[randi() % bag.size()]

func _stats_for(archetype: String) -> Dictionary:
	var round_index := GameState.round_index
	var hp := _base_hp(round_index)
	var speed := 1.35 * (1.0 + float(round_index - 1) * 0.035)
	match archetype:
		"broker":
			hp *= 0.82
			speed *= 1.28
		"king":
			hp *= 2.35
			speed *= 0.82
	return {"hp": hp, "speed": speed}

func _player_count() -> int:
	var count := 1
	if get_tree() != null:
		count = get_tree().get_nodes_in_group("player").size()
	return clampi(count, 1, 4)


func _wave_budget(wave: int, players: int) -> int:
	if wave < 10:
		return int(EARLY_BUDGET[players - 1][wave - 1])
	var square := 0.09 if players == 1 else 0.18 * float(players - 1)
	return 24 + int(floor(square * float(wave * wave)))


func _base_hp(wave: int) -> float:
	if wave <= 9:
		return 40.0 + 10.0 * float(wave - 1)
	return 120.0 * pow(1.08, float(wave - 9))


func _emit_counts() -> void:
	enemy_count_changed.emit(_alive, maxi(0, _budget - _spawned) + _alive)

func _is_authority() -> bool:
	return get_tree() == null or get_tree().get_multiplayer().is_server()
