extends RefCounted
## Dynamic stock market. Prices follow a geometric random walk whose drift is set
## by the economy phase (scaled by each sector's beta), plus random company news.

const C = preload("res://scripts/core/catalog.gd")
const HISTORY := 96             # hourly points kept for charts (4 days)

var stocks := {}                # ticker -> {name, sector, price, open, vol, beta, history: Array}
var order: Array = []
var rng: RandomNumberGenerator


func _init(p_rng: RandomNumberGenerator = null) -> void:
	rng = p_rng if p_rng else RandomNumberGenerator.new()
	for s in C.STOCKS:
		order.append(s.ticker)
		stocks[s.ticker] = {"name": s.name, "sector": s.sector, "price": s.price, "open": s.price,
			"vol": s.vol, "beta": s.beta, "history": [s.price]}


func price(ticker: String) -> float:
	return float(stocks[ticker].price) if stocks.has(ticker) else 0.0


func day_change_pct(ticker: String) -> float:
	var s: Dictionary = stocks[ticker]
	return (float(s.price) / maxf(0.01, float(s.open)) - 1.0) * 100.0


## One in-game hour of trading.
func tick_hour(econ) -> void:
	var drift: float = econ.phase_info().drift
	for t in order:
		var s: Dictionary = stocks[t]
		var mu: float = drift * float(s.beta) / 24.0
		var sigma: float = float(s.vol) / sqrt(24.0)
		var r: float = mu + rng.randfn(0.0, sigma)
		s.price = clampf(float(s.price) * exp(r), 0.5, 1_000_000.0)
		var h: Array = s.history
		h.append(s.price)
		if h.size() > HISTORY:
			h.pop_front()


## Start of a new trading day: reset opens, maybe fire company news. Returns a headline or "".
func open_day(econ) -> String:
	for t in order:
		stocks[t].open = stocks[t].price
	if econ.phase == "crash":
		for t in order:
			stocks[t].price *= 0.93 - rng.randf() * 0.05
		return ""
	if rng.randf() < 0.18:
		var t: String = order[rng.randi() % order.size()]
		var s: Dictionary = stocks[t]
		var good := rng.randf() < 0.55
		var jump := 0.06 + rng.randf() * 0.14
		s.price *= (1.0 + jump) if good else (1.0 - jump)
		var verb := "soars" if good else "tumbles"
		var why := ["after blowout earnings", "on a surprise partnership", "as analysts upgrade the stock", "on record demand"] if good \
			else ["after a product recall", "on weak guidance", "as the CEO resigns", "amid an accounting probe"]
		return "%s (%s) %s %d%% %s." % [s.name, t, verb, int(round(jump * 100.0)), why[rng.randi() % why.size()]]
	return ""


func to_dict() -> Dictionary:
	var out := {}
	for t in order:
		var s: Dictionary = stocks[t]
		out[t] = {"price": s.price, "open": s.open, "history": s.history.duplicate()}
	return out


func from_dict(d: Dictionary) -> void:
	for t in d:
		if stocks.has(t):
			var src: Dictionary = d[t]
			stocks[t].price = float(src.get("price", stocks[t].price))
			stocks[t].open = float(src.get("open", stocks[t].price))
			var h: Array = []
			for v in src.get("history", []):
				h.append(float(v))
			if h.is_empty():
				h.append(stocks[t].price)
			stocks[t].history = h
