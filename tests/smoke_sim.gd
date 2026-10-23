extends SceneTree
## Balance smoke test: a simple bot plays Money Empire from $100 and must reach $1 Billion.
## It works jobs at a realistic pace (one job per ~45 real seconds), reinvests greedily in the
## best-payback business/upgrade, buys a home and a car, and parks spare cash in stocks.
##   godot --headless --path . -s tests/smoke_sim.gd

const C = preload("res://scripts/core/catalog.gd")
const Sim = preload("res://scripts/core/empire_sim.gd")

const JOB_GAME_MINUTES := 45.0 * 1440.0 / C.DAY_SECONDS   # 45 real seconds per job at 1x
const MAX_DAYS := 160


func _init() -> void:
	var results := []
	for seed_value in [1, 2, 3]:
		results.append(play(seed_value))
	var ok := true
	for r in results:
		print("seed %d: $1k day %s · $1M day %s · $1B day %s · final %s on day %d · jobs %d" % [r.seed, r.d1k, r.d1m, r.d1b, Sim.fmt_money(r.final), r.day, r.jobs])
		if r.d1b < 0 or r.d1b > 120:
			ok = false
		if r.d1k < 0 or r.d1k > 3:
			ok = false
	print("SMOKE OK" if ok else "SMOKE FAIL: balance out of range")
	quit(0 if ok else 1)


func play(seed_value: int) -> Dictionary:
	var s := Sim.new(seed_value)
	var marks := {"d1k": -1, "d1m": -1, "d1b": -1}
	while s.day <= MAX_DAYS:
		# work while jobs are still a meaningful share of income
		if s.daily_business_income() + s.daily_rent_income() < s.job_pay("food") * 40.0:
			var job := "dockhand" if s.job_unlocked("dockhand") else ("food" if s.jobs_done % 2 == 0 else "package")
			s.advance(JOB_GAME_MINUTES * (0.6 if s.speed_mult() > 2.0 else 1.0))
			s.complete_job(job, 1.2)
		else:
			s.advance(120.0)
		_invest(s)
		var nw := s.networth()
		if nw >= 1e3 and marks.d1k < 0: marks.d1k = s.day
		if nw >= 1e6 and marks.d1m < 0: marks.d1m = s.day
		if nw >= 1e9 and marks.d1b < 0:
			marks.d1b = s.day
			break
	return {"seed": seed_value, "d1k": marks.d1k, "d1m": marks.d1m, "d1b": marks.d1b, "final": s.networth(), "day": s.day, "jobs": s.jobs_done}


func _invest(s) -> void:
	if s.vehicles.is_empty() and s.cash >= s.vehicle_price("bike"):
		s.buy_vehicle("bike")
	if s.home < 0 and s.cash >= s.property_market_price("studio") * 1.5:
		s.buy_property("studio")
	if not "sedan" in s.vehicles and s.cash >= s.vehicle_price("sedan") * 3.0:
		s.buy_vehicle("sedan")
	# greedy: repeatedly take the option with the best payback until nothing fits
	for guard in 40:
		var best := ""
		var best_kind := ""
		var best_payback := 45.0
		for row in C.BUSINESSES:
			var id: String = row.id
			if not s.businesses.has(id):
				var price: float = s.business_price(id)
				var pb: float = price / (float(row.income) * s.economy.income_mult() * s.economy.price_index)
				if price <= s.cash and pb < best_payback:
					best = id; best_kind = "buy"; best_payback = pb
			elif int(s.businesses[id].level) < C.MAX_BUSINESS_LEVEL:
				var cost: float = s.upgrade_cost(id)
				var gain: float = float(row.income) * 0.5 * s.economy.income_mult() * s.economy.price_index
				var pb2: float = cost / gain
				if cost <= s.cash and pb2 < best_payback:
					best = id; best_kind = "up"; best_payback = pb2
			if s.businesses.has(id) and int(s.businesses[id].workers) < C.MAX_WORKERS:
				var wc: float = s.worker_cost(id)
				var net: float = float(row.income) * (C.WORKER_BONUS - C.WORKER_SALARY) * s.economy.price_index
				if wc <= s.cash and wc / maxf(1.0, net) < best_payback:
					best = id; best_kind = "hire"; best_payback = wc / maxf(1.0, net)
		if best == "":
			break
		match best_kind:
			"buy": s.buy_business(best)
			"up": s.upgrade_business(best)
			"hire": s.hire_worker(best)
	# rental properties with spare cash
	if s.cash > 50_000.0:
		for row in C.PROPERTIES:
			if s.owned_count(row.id) < int(row.max) and s.property_market_price(row.id) < s.cash * 0.1:
				var r: Dictionary = s.buy_property(row.id)
				if r.ok:
					s.toggle_rent(s.properties.size() - 1)
	# keep a slice in the market
	if s.cash > 200_000.0 and s.portfolio_value() < s.networth() * 0.08:
		s.buy_shares("BYTE", int(s.cash * 0.05 / s.market.price("BYTE")))
