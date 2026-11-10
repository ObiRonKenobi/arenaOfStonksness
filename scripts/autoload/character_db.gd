extends Node

const HERO_IDS: Array[String] = ["punk_f", "punk", "cowboy", "worker"]

const CAST := {
	"punk": {
		"name": "Reggie",
		"color": Color(0.86, 0.22, 0.24),
		"ult": "Feedback Loop",
		"ult_hint": "Fire rate and speed, then a painful crash.",
		"bio": "He ran packages for a firm that got bought. New management fired him and kept his bike. He works for the Black Market now, cash only, no questions. He thinks the brokers and the spreadsheet are hilarious, and he will still call them bruh while they try to kill him.",
	},
	"cowboy": {
		"name": "Cletus",
		"color": Color(0.62, 0.46, 0.28),
		"ult": "Market Crash",
		"ult_hint": "Slow the horde. Marked kills pay extra.",
		"bio": "He sold crop insurance for twenty years, including on his family's land. When the brokers arrived, the policy paid them and took their land. He knows his cell on the spreadsheet. He is not angry. He is going to bill them for the ammo.",
	},
	"punk_f": {
		"name": "Spike",
		"color": Color(0.72, 0.28, 0.62),
		"ult": "Cloud Cover",
		"ult_hint": "A smoke cloud that softens incoming hits.",
		"bio": "Her uncle's venue was swallowed in the same portfolio buy. The eviction notice came with a thank-you card and a survey. She stayed, boarded the windows the night before the first wave, and annotated the memo. She is not fighting a horde. She is fighting a spreadsheet.",
	},
	"worker": {
		"name": "Rivet",
		"color": Color(0.85, 0.62, 0.18),
		"ult": "Power Nap",
		"ult_hint": "A short nap, then a wake-up shove.",
		"bio": "He built the tower across the street and the lobby that smells like cedar. He was laid off the week before the ribbon cutting and got a letter thanking him for his contribution to the vision. He knows which walls hold the building up. They are clearing squatters off a floor he poured.",
	},
}

func ids() -> Array[String]:
	var out: Array[String] = []
	for key in CAST.keys():
		out.append(str(key))
	return out

func info(id: String) -> Dictionary:
	return CAST.get(id, {})

func display_name(id: String) -> String:
	return str(info(id).get("name", id))

func bio(id: String) -> String:
	return str(info(id).get("bio", ""))

func load_models() -> void:
	for id in HERO_IDS:
		load("res://assets/characters/%s.glb" % id)

func model_scene(id: String) -> PackedScene:
	return load("res://assets/characters/%s.glb" % id) as PackedScene

func pick_available(taken: Array) -> String:
	var open_ids: Array[String] = []
	for id in ids():
		if id not in taken:
			open_ids.append(id)
	if open_ids.is_empty():
		return ""
	return open_ids[randi() % open_ids.size()]
