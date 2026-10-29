extends Node

const CAST := {
	"punk": {
		"name": "Male Punk",
		"color": Color(0.86, 0.22, 0.24),
		"ult": "Feedback Loop",
		"ult_hint": "Fire rate and speed, then a painful crash.",
	},
	"cowboy": {
		"name": "Cowboy",
		"color": Color(0.62, 0.46, 0.28),
		"ult": "Market Crash",
		"ult_hint": "Slow the horde. Marked kills pay extra.",
	},
	"punk_f": {
		"name": "Female Punk",
		"color": Color(0.72, 0.28, 0.62),
		"ult": "Cloud Cover",
		"ult_hint": "A smoke cloud that softens incoming hits.",
	},
	"worker": {
		"name": "Construction Worker",
		"color": Color(0.85, 0.62, 0.18),
		"ult": "Power Nap",
		"ult_hint": "A short nap, then a wake-up shove.",
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

func pick_available(taken: Array) -> String:
	var open_ids: Array[String] = []
	for id in ids():
		if id not in taken:
			open_ids.append(id)
	if open_ids.is_empty():
		return ""
	return open_ids[randi() % open_ids.size()]
