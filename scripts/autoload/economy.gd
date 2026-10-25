extends Node

const WEAPONS := {
	"pipe_pistol": {"name": "Pipe Pistol", "damage": 16.0, "rate": 3.2, "mag": 8, "reserve": 48, "pellets": 1, "spread": 0.012, "price": 0, "rank": 1},
	"street_smg": {"name": "Street SMG", "damage": 9.0, "rate": 11.0, "mag": 30, "reserve": 150, "pellets": 1, "spread": 0.03, "price": 900, "rank": 2},
	"debt_shotgun": {"name": "Debt Collector", "damage": 8.0, "rate": 1.05, "mag": 6, "reserve": 36, "pellets": 7, "spread": 0.09, "price": 1400, "rank": 3},
	"rent_rifle": {"name": "Rent Rifle", "damage": 30.0, "rate": 3.4, "mag": 24, "reserve": 144, "pellets": 1, "spread": 0.008, "price": 1800, "rank": 4},
	"pop_junk": {"name": "Laser Pistol", "damage": 5.0, "rate": 6.0, "mag": 12, "reserve": 36, "pellets": 1, "spread": 0.06, "price": 200, "rank": 1},
	"ledger_cannon": {"name": "Ledger Cannon", "damage": 72.0, "rate": 0.7, "mag": 4, "reserve": 20, "pellets": 1, "spread": 0.004, "price": 0, "rank": 5},
}

const PERKS := {
	"thick_skin": {"name": "Thick Skin", "price": 2500, "hint": "More health."},
	"rapid_fire": {"name": "Rapid Fire", "price": 2500, "hint": "Shoots faster."},
	"tin_vest": {"name": "Tin Vest", "price": 2500, "hint": "Take less damage."},
	"mean_streak": {"name": "Mean Streak", "price": 2500, "hint": "Deal more damage."},
}

const CRATE_COST := 950
const PLANK_PACK_COST := 100
const PLANK_PACK_COUNT := 2
const MAX_PERKS := 4
const SMITH_MAX := 3

const CRATE_TABLE := [
	{"id": "pop_junk", "weight": 22},
	{"id": "pipe_pistol", "weight": 18},
	{"id": "street_smg", "weight": 22},
	{"id": "debt_shotgun", "weight": 18},
	{"id": "rent_rifle", "weight": 14},
	{"id": "ledger_cannon", "weight": 6},
]

func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS["pipe_pistol"])

func tier_multiplier(tier: int) -> float:
	match tier:
		2:
			return 1.85
		3:
			return 2.7
		_:
			return 1.0

func tier_label(tier: int) -> String:
	match tier:
		2:
			return "v2"
		3:
			return "v3"
		_:
			return "stock"

func ammo_cost(weapon_id: String) -> int:
	var price := int(weapon(weapon_id).get("price", 0))
	if price <= 0:
		return 100
	return price * 3 / 4

func markup_cost(_weapon_id: String, next_tier: int) -> int:
	if next_tier <= 2:
		return 1500
	return 4000

func smith_cost(level_after: int) -> int:
	return 750 * level_after

func roll_crate() -> String:
	var total := 0
	for row in CRATE_TABLE:
		total += int(row["weight"])
	var roll := randi() % total
	var cursor := 0
	for row in CRATE_TABLE:
		cursor += int(row["weight"])
		if roll < cursor:
			return str(row["id"])
	return "pipe_pistol"

func wall_weapons() -> Array[String]:
	return ["street_smg", "debt_shotgun", "rent_rifle"]
