extends RefCounted
## Difficulty levels. main.gd sets `level` from the settings; everything else
## reads the multipliers below. Changing it mid-run applies to enemies that
## spawn afterwards.

static var level := "normal"

const LEVELS := {
	#            enemy dmg  enemy hp/shield  enemy spread  enemy fire delay  wave size  cache refills  drop chance
	"easy":   {"dmg": 0.6, "hp": 0.8, "spread": 1.45, "fire_delay": 1.3, "wave": 0.75, "refills": 4, "drops": 1.3},
	"normal": {"dmg": 1.0, "hp": 1.0, "spread": 1.0, "fire_delay": 1.0, "wave": 1.0, "refills": 3, "drops": 1.0},
	"hard":   {"dmg": 1.4, "hp": 1.25, "spread": 0.75, "fire_delay": 0.82, "wave": 1.3, "refills": 2, "drops": 0.75},
}


static func v(key: String) -> float:
	return float(LEVELS.get(level, LEVELS.normal)[key])


static func refills() -> int:
	return int(v("refills"))
