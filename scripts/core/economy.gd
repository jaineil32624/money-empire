extends RefCounted
## The living economy: boom / stable / recession / crash cycles, inflation,
## and per-district property price indexes. Shared by every player online.

const C = preload("res://scripts/core/catalog.gd")

var phase := "stable"
var phase_days := 0
var price_index := 1.0          # cumulative inflation (1.0 = day one prices)
var district_index := {}        # district id -> property price multiplier
var headlines: Array = []       # newest first: {"day", "text", "kind"}
var rng: RandomNumberGenerator


func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng else RandomNumberGenerator.new()
	for d in C.DISTRICTS:
		district_index[d] = 1.0


func phase_info() -> Dictionary:
	return C.PHASES[phase]


func income_mult() -> float:
	return phase_info().income


func asset_mult() -> float:
	return phase_info().assets


func wage_mult() -> float:
	return price_index * phase_info().wages


## Advances one in-game day. Returns true if the phase changed.
func tick_day(day: int) -> bool:
	phase_days += 1
	# inflation compounds daily over a 60-day game year
	price_index *= 1.0 + phase_info().inflation / float(C.DAYS_PER_YEAR)
	# property markets random-walk, pulled by the economy
	var drift: float = phase_info().drift * 0.6
	for d in district_index:
		var v: float = district_index[d]
		v *= 1.0 + drift + rng.randfn(0.0, 0.012)
		# gentle mean reversion keeps districts from running away forever
		v += (price_index - v) * 0.01
		district_index[d] = clampf(v, 0.45, 6.0)
	# phase transitions
	var changed := false
	if phase_days >= 3:
		var roll := rng.randf()
		var acc := 0.0
		var table: Dictionary = C.PHASE_TRANSITIONS[phase]
		for target in table:
			acc += float(table[target])
			if roll < acc:
				set_phase(target, day)
				changed = true
				break
	return changed


func set_phase(p: String, day: int) -> void:
	if p == phase or not C.PHASES.has(p):
		return
	var old := phase
	phase = p
	phase_days = 0
	var text := ""
	match p:
		"boom": text = "ECONOMIC BOOM! Consumers are spending — business income up 25%."
		"stable": text = "Markets stabilize. Business as usual."
		"recession": text = "Recession hits. Income and property values are falling."
		"crash": text = "MARKET CRASH! Stocks plunge. Bargain hunters, this is your moment."
	if old == "boom" and p == "crash":
		text = "THE BUBBLE POPS! Market crash after the boom."
	add_headline(day, text, p)


func add_headline(day: int, text: String, kind: String = "news") -> void:
	headlines.push_front({"day": day, "text": text, "kind": kind})
	if headlines.size() > 30:
		headlines.resize(30)


func to_dict() -> Dictionary:
	return {"phase": phase, "phase_days": phase_days, "price_index": price_index,
		"district_index": district_index.duplicate(), "headlines": headlines.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	phase = str(d.get("phase", "stable"))
	if not C.PHASES.has(phase):
		phase = "stable"
	phase_days = int(d.get("phase_days", 0))
	price_index = float(d.get("price_index", 1.0))
	var di: Dictionary = d.get("district_index", {})
	for k in district_index:
		district_index[k] = float(di.get(k, 1.0))
	headlines = d.get("headlines", []).duplicate(true)
