extends Node

func _ready() -> void:
	_run()

func _run() -> void:
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	var banks := true
	for id in CharacterDB.HERO_IDS:
		player.call("load_voice_bank", id)
		for trigger in ["intro", "multikill", "headshots", "fastclear"]:
			if int(player.call("voice_count", trigger)) != 3:
				banks = false
	player.call("load_voice_bank", "missing")
	var silent: bool = not bool(player.call("cue_line", "intro"))
	var heroes := true
	for id in CharacterDB.HERO_IDS:
		player.call("load_voice_bank", id)
		player.set("_voice_gap_until", 0)
		if not bool(player.call("cue_line", "intro")):
			heroes = false
	seed(7)
	var seen := {}
	for _i in 40:
		seen[CharacterDB.pick_available([])] = true
	var roster: bool = seen.size() == 4
	for id in CharacterDB.HERO_IDS:
		if not seen.has(id):
			roster = false
	player.call("load_voice_bank", "punk")
	player.call("reset_voice_state")
	player.call("note_kill", false)
	player.call("note_kill", false)
	player.call("note_kill", false)
	var multi: bool = _logged(player, "multikill")
	var before := _log(player).size()
	player.call("note_kill", false)
	player.call("note_kill", false)
	player.call("note_kill", false)
	var busy: bool = _log(player).size() == before
	player.call("reset_voice_state")
	player.call("note_kill", true)
	player.call("note_kill", true)
	player.call("note_kill", false)
	var reset: bool = int(player.get("head_streak")) == 0
	player.set("_voice_gap_until", 0)
	player.set("_kill_times", [])
	await get_tree().create_timer(1.1).timeout
	player.call("note_kill", true)
	await get_tree().create_timer(1.1).timeout
	player.call("note_kill", true)
	await get_tree().create_timer(1.1).timeout
	player.set("_voice_gap_until", 0)
	player.call("note_kill", true)
	var heads: bool = _logged(player, "headshots")
	player.set("_voice_gap_until", 0)
	player.set("_round_started_ms", Time.get_ticks_msec() - 10000)
	GameState.round_index = 1
	player.call("score_round_clear")
	var fast: bool = _logged(player, "fastclear")
	var fast_before := _log(player).size()
	player.set("_voice_gap_until", 0)
	player.set("_round_started_ms", Time.get_ticks_msec() - 50000)
	player.call("score_round_clear")
	var slow: bool = _log(player).size() == fast_before
	seed(3)
	player.call("load_voice_bank", "punk_f")
	player.call("reset_voice_state")
	var repeat := false
	var last := -1
	for _i in 6:
		player.set("_voice_gap_until", 0)
		player.call("cue_line", "intro")
		var line := str(_log(player)[-1])
		var pick := int(line.get_slice(":", 1))
		if pick == last:
			repeat = true
		last = pick
	var ok := banks and silent and heroes and roster and multi and busy and reset and heads and fast and slow and not repeat
	print("VOICES banks=%s silent=%s heroes=%s roster=%s multi=%s busy=%s reset=%s heads=%s fast=%s slow=%s repeat=%s seen=%s" % [banks, silent, heroes, roster, multi, busy, reset, heads, fast, slow, repeat, seen.keys()])
	print("VOICES_OK" if ok else "VOICES_FAIL")
	get_tree().quit(0 if ok else 1)

func _log(player: Node) -> Array:
	return player.get("voice_log")

func _logged(player: Node, trigger: String) -> bool:
	for line in _log(player):
		if str(line).begins_with(trigger + ":"):
			return true
	return false
