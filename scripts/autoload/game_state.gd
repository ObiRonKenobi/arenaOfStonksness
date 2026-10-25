extends Node

signal match_started
signal character_assigned(id: String)
signal round_changed(round_index: int)
signal rounds_cleared_changed(count: int)
signal game_over(rounds_survived: int)
signal toast_requested(text: String)

var round_index := 0
var rounds_cleared := 0
var running := false
var over := false
var character_id := ""
var taken: Array[String] = []

func reset() -> void:
	round_index = 0
	rounds_cleared = 0
	running = false
	over = false
	character_id = ""
	taken.clear()

func begin_match(preferred_id: String = "") -> void:
	reset()
	var pick := preferred_id
	if pick == "" or pick in taken:
		pick = CharacterDB.pick_available(taken)
	if pick == "":
		return
	character_id = pick
	taken.append(pick)
	running = true
	character_assigned.emit(pick)
	match_started.emit()

func claim_character(id: String) -> bool:
	if id in taken or not CharacterDB.CAST.has(id):
		return false
	taken.append(id)
	return true

func set_round(index: int) -> void:
	round_index = index
	round_changed.emit(index)

func mark_round_cleared() -> void:
	rounds_cleared += 1
	rounds_cleared_changed.emit(rounds_cleared)

func fail() -> void:
	if over:
		return
	over = true
	running = false
	game_over.emit(rounds_cleared)

func toast(text: String) -> void:
	toast_requested.emit(text)
