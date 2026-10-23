extends RefCounted
## EmpireSim — the whole single-player simulation as pure logic.
## No nodes, no rendering: the game, the dedicated server and the unit tests all drive this.
## Every player action returns {"ok": bool, "msg": String, ...}.

const C = preload("res://scripts/core/catalog.gd")
const Economy = preload("res://scripts/core/economy.gd")
const Market = preload("res://scripts/core/stock_market.gd")

signal notify(text: String, kind: String)   # kind: money, good, bad, info, news, crime, goal
signal hour_passed
signal day_passed(day: int)

var rng := RandomNumberGenerator.new()
var economy: Economy
var market: Market

var player_name := "Player"
var cash := C.START_CASH
var day := 1
var minute := 8.0 * 60.0          # minute of the current day
var jail_until := -1.0            # absolute game minute; -1 = free
var heat := 0

var businesses := {}              # id -> {"level", "workers"}
var properties: Array = []        # [{"id", "reno", "rented", "features": [], "decor": []}]
var home := -1                    # index into properties, -1 = homeless
var vehicles: Array = []          # owned vehicle ids
var active_vehicle := ""
var holdings := {}                # ticker -> {"shares": int, "cost": float}
var projects: Array = []          # completed endgame projects
var company := ""                 # corporation name ("" = solo)

var jobs_done := 0
var crimes_done := 0
var times_caught := 0
var stats := {"jobs": 0.0, "business": 0.0, "rent": 0.0, "stocks": 0.0, "crime": 0.0, "fines": 0.0, "salaries": 0.0}
var milestones: Array = []        # reached net worth milestones
var achievements: Array = []
var networth_history: Array = []  # one point per day
var billionaire_day := -1

# cosmetics / live-ops (never affects money)
var coins := C.START_COINS
var owned_cosmetics: Array = ["skin:default", "paint:factory"]
var skin := "default"
var paint := "factory"
var pass_xp := 0
var pass_premium := false
var pass_claimed: Array = []
var last_daily_claim := 0

var rivals: Array = []            # [{"name", "networth", "color"}]


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	economy = Economy.new(rng)
	market = Market.new(rng)
	for r in C.RIVALS:
		rivals.append({"name": r.name, "networth": 100.0 + rng.randf() * 400.0, "color": r.color, "rate": r.rate})
	networth_history.append(networth())


# ================================================================ time
func total_minutes() -> float:
	return float(day - 1) * 1440.0 + minute


func clock_text() -> String:
	var m := int(minute)
	return "%02d:%02d" % [m / 60, m % 60]


func is_night() -> bool:
	return minute < 6.0 * 60.0 or minute > 20.0 * 60.0


func in_jail() -> bool:
	return jail_until > total_minutes()


func jail_minutes_left() -> float:
	return maxf(0.0, jail_until - total_minutes())


## Advance the simulation by game minutes. Pays income hourly, runs the economy daily.
func advance(game_minutes: float) -> void:
	while game_minutes > 0.0:
		var to_hour := 60.0 - fmod(minute, 60.0)
		if to_hour <= 0.0001:
			to_hour = 60.0
		var step := minf(game_minutes, to_hour)
		minute += step
		game_minutes -= step
		if step >= to_hour - 0.0001:
			minute = roundf(minute)
			_on_hour()
		if minute >= 1440.0:
			minute -= 1440.0
			day += 1
			_on_day()


func _on_hour() -> void:
	market.tick_hour(economy)
	var inc := daily_business_income() / 24.0
	var rent := daily_rent_income() / 24.0
	var sal := daily_salaries() / 24.0
	cash += inc + rent - sal
	stats.business += inc
	stats.rent += rent
	stats.salaries += sal
	_check_milestones()
	hour_passed.emit()


func _on_day() -> void:
	if economy.tick_day(day):
		notify.emit(economy.headlines[0].text, "news")
	var headline: String = market.open_day(economy)
	if headline != "":
		economy.add_headline(day, headline, "stocks")
		notify.emit(headline, "news")
	heat = maxi(0, heat - 1)
	_tick_rivals()
	networth_history.append(networth())
	if networth_history.size() > 365:
		networth_history.pop_front()
	day_passed.emit(day)


func _tick_rivals() -> void:
	var m: float = economy.income_mult()
	for r in rivals:
		var nw: float = r.networth
		# growth slows as fortunes get bigger (log-scaled), like a real player's would
		var rate: float = float(r.rate) * m * (0.7 + rng.randf() * 0.6) / (1.0 + maxf(0.0, log(nw) / log(10.0) - 3.0) * 0.12)
		if economy.phase == "crash":
			rate = -0.05 * rng.randf()
		r.networth = maxf(50.0, nw * (1.0 + rate))


# ================================================================ money
func earn(amount: float, category: String) -> void:
	cash += amount
	if stats.has(category):
		stats[category] += amount
	_check_milestones()


func spend(amount: float) -> bool:
	if amount > cash + 0.0001:
		return false
	cash -= amount
	return true


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}


func _ok(msg: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"ok": true, "msg": msg}
	d.merge(extra)
	return d


# ================================================================ jobs
func job_unlocked(job_id: String) -> bool:
	var j: Dictionary = C.JOBS[job_id]
	return jobs_done >= int(j.get("unlock_jobs", 0))


func job_level() -> int:
	return 1 + int(sqrt(float(jobs_done)))


func job_pay(job_id: String) -> float:
	var j: Dictionary = C.JOBS[job_id]
	var lvl_mult := minf(3.0, 1.0 + 0.08 * float(job_level() - 1))
	var home_mult := 1.0 + (C.HOME_JOB_BONUS if home >= 0 else 0.0)
	return roundf(float(j.pay) * lvl_mult * home_mult * economy.wage_mult())


## quality 0..1.5 (speed bonus / tips). Called by the job runner when a job is finished.
func complete_job(job_id: String, quality: float = 1.0) -> Dictionary:
	if not C.JOBS.has(job_id):
		return _fail("Unknown job.")
	if in_jail():
		return _fail("You're in jail.")
	var pay := roundf(job_pay(job_id) * clampf(quality, 0.3, 1.5))
	earn(pay, "jobs")
	jobs_done += 1
	add_pass_xp(int(C.JOBS[job_id].xp))
	_award("first_paycheck", "First Paycheck")
	if jobs_done == 10:
		notify.emit("Dock Hand job unlocked at the Harbor! ($$$)", "good")
	if jobs_done >= 50:
		_award("hustler", "Hustler — 50 jobs")
	return _ok("+$%s for %s" % [fmt_money(pay), C.JOBS[job_id].name], {"pay": pay})


# ================================================================ businesses
func business_row(id: String) -> Dictionary:
	for b in C.BUSINESSES:
		if b.id == id:
			return b
	return {}


func business_price(id: String) -> float:
	return roundf(float(business_row(id).price) * economy.price_index * economy.asset_mult())


func upgrade_cost(id: String) -> float:
	var lvl: int = businesses[id].level
	return roundf(float(business_row(id).price) * 0.4 * float(lvl) * economy.price_index)


func worker_cost(id: String) -> float:
	return roundf(float(business_row(id).price) * 0.02 * economy.price_index)


func business_income(id: String) -> float:
	if not businesses.has(id):
		return 0.0
	var b: Dictionary = businesses[id]
	var base: float = business_row(id).income
	var lvl_mult := 1.0 + 0.5 * float(int(b.level) - 1)
	var work_mult := 1.0 + C.WORKER_BONUS * float(b.workers)
	return base * lvl_mult * work_mult * economy.income_mult() * economy.price_index


func business_value(id: String) -> float:
	var b: Dictionary = businesses[id]
	return float(business_row(id).price) * (1.0 + 0.4 * float(int(b.level) - 1)) * economy.asset_mult() * economy.price_index


func daily_business_income() -> float:
	var total := 0.0
	for id in businesses:
		total += business_income(id)
	return total


func daily_salaries() -> float:
	var total := 0.0
	for id in businesses:
		total += float(business_row(id).income) * C.WORKER_SALARY * float(businesses[id].workers) * economy.price_index
	return total


func buy_business(id: String) -> Dictionary:
	if business_row(id).is_empty():
		return _fail("Unknown business.")
	if businesses.has(id):
		return _fail("You already own it.")
	var price := business_price(id)
	if not spend(price):
		return _fail("Need $%s." % fmt_money(price))
	businesses[id] = {"level": 1, "workers": 0}
	add_pass_xp(25)
	_award("owner", "Business Owner")
	if businesses.size() >= 5:
		_award("chain", "Chain Builder — 5 businesses")
	return _ok("You now own %s!" % business_row(id).name)


func upgrade_business(id: String) -> Dictionary:
	if not businesses.has(id):
		return _fail("You don't own that.")
	if int(businesses[id].level) >= C.MAX_BUSINESS_LEVEL:
		return _fail("Already max level.")
	var cost := upgrade_cost(id)
	if not spend(cost):
		return _fail("Need $%s." % fmt_money(cost))
	businesses[id].level = int(businesses[id].level) + 1
	add_pass_xp(15)
	return _ok("%s upgraded to level %d." % [business_row(id).name, businesses[id].level])


func hire_worker(id: String) -> Dictionary:
	if not businesses.has(id):
		return _fail("You don't own that.")
	if int(businesses[id].workers) >= C.MAX_WORKERS:
		return _fail("Fully staffed.")
	var cost := worker_cost(id)
	if not spend(cost):
		return _fail("Need $%s signing bonus." % fmt_money(cost))
	businesses[id].workers = int(businesses[id].workers) + 1
	return _ok("Hired a worker at %s (+10%% income)." % business_row(id).name)


func sell_business(id: String) -> Dictionary:
	if not businesses.has(id):
		return _fail("You don't own that.")
	var v := roundf(business_value(id) * 0.8)
	businesses.erase(id)
	earn(v, "")
	return _ok("Sold for $%s." % fmt_money(v))


func maxed_businesses() -> int:
	var n := 0
	for id in businesses:
		if int(businesses[id].level) >= C.MAX_BUSINESS_LEVEL:
			n += 1
	return n


# ================================================================ real estate
func property_row(id: String) -> Dictionary:
	for p in C.PROPERTIES:
		if p.id == id:
			return p
	return {}


func property_market_price(id: String) -> float:
	var row := property_row(id)
	return roundf(float(row.price) * float(economy.district_index[row.district]) * economy.asset_mult())


func property_value(idx: int) -> float:
	var p: Dictionary = properties[idx]
	var row := property_row(p.id)
	var v := property_market_price(p.id)
	if p.reno:
		v *= 1.0 + C.RENOVATE_GAIN
	for f in p.features:
		v += float(row.price) * float(C.MANSION_FEATURES[f].pct) * C.FEATURE_VALUE_RETURN * economy.price_index
	return v


func property_rent(idx: int) -> float:
	var p: Dictionary = properties[idx]
	if not p.rented:
		return 0.0
	var row := property_row(p.id)
	var r: float = float(row.rent) * economy.price_index * economy.income_mult()
	if p.reno:
		r *= 1.2
	return r


func daily_rent_income() -> float:
	var t := 0.0
	for i in properties.size():
		t += property_rent(i)
	return t


func owned_count(id: String) -> int:
	var n := 0
	for p in properties:
		if p.id == id:
			n += 1
	return n


func buy_property(id: String) -> Dictionary:
	var row := property_row(id)
	if row.is_empty():
		return _fail("Unknown property.")
	if owned_count(id) >= int(row.max):
		return _fail("You own the maximum of these.")
	var price := property_market_price(id)
	if not spend(price):
		return _fail("Need $%s." % fmt_money(price))
	properties.append({"id": id, "reno": false, "rented": false, "features": [], "decor": []})
	if home < 0:
		home = properties.size() - 1
		notify.emit("You moved in! No longer homeless (+10% job pay).", "good")
	add_pass_xp(20)
	_award("landlord", "First Property")
	if row.kind == "mansion":
		_award("mansion", "Mansion Owner")
	if id == "island":
		_award("island", "Island Owner")
	return _ok("Bought %s." % row.name)


func sell_property(idx: int) -> Dictionary:
	if idx < 0 or idx >= properties.size():
		return _fail("No such property.")
	var v := roundf(property_value(idx))
	var name: String = property_row(properties[idx].id).name
	properties.remove_at(idx)
	if home == idx:
		home = -1
	elif home > idx:
		home -= 1
	earn(v, "")
	return _ok("Sold %s for $%s." % [name, fmt_money(v)])


func renovate_property(idx: int) -> Dictionary:
	if idx < 0 or idx >= properties.size():
		return _fail("No such property.")
	var p: Dictionary = properties[idx]
	if p.reno:
		return _fail("Already renovated.")
	var cost := roundf(property_market_price(p.id) * C.RENOVATE_COST)
	if not spend(cost):
		return _fail("Need $%s." % fmt_money(cost))
	p.reno = true
	return _ok("Renovated! Value +25%, rent +20%. Flip it or keep it.")


func toggle_rent(idx: int) -> Dictionary:
	if idx < 0 or idx >= properties.size():
		return _fail("No such property.")
	var p: Dictionary = properties[idx]
	if idx == home and not p.rented:
		return _fail("You live here. Move out first (set another home).")
	p.rented = not p.rented
	return _ok("Now renting out." if p.rented else "Tenants moved out.")


func set_home(idx: int) -> Dictionary:
	if idx < 0 or idx >= properties.size():
		return _fail("No such property.")
	properties[idx].rented = false
	home = idx
	return _ok("Moved into %s." % property_row(properties[idx].id).name)


func add_feature(idx: int, feature: String) -> Dictionary:
	if idx < 0 or idx >= properties.size() or not C.MANSION_FEATURES.has(feature):
		return _fail("Invalid.")
	var p: Dictionary = properties[idx]
	var row := property_row(p.id)
	if row.kind != "mansion" and row.kind != "island":
		return _fail("Only mansions get luxury features.")
	if feature in p.features:
		return _fail("Already installed.")
	var cost := roundf(float(row.price) * float(C.MANSION_FEATURES[feature].pct) * economy.price_index)
	if not spend(cost):
		return _fail("Need $%s." % fmt_money(cost))
	p.features.append(feature)
	add_pass_xp(20)
	return _ok("Installed %s." % C.MANSION_FEATURES[feature].name)


func feature_cost(idx: int, feature: String) -> float:
	var row := property_row(properties[idx].id)
	return roundf(float(row.price) * float(C.MANSION_FEATURES[feature].pct) * economy.price_index)


# ================================================================ vehicles
func vehicle_row(id: String) -> Dictionary:
	for v in C.VEHICLES:
		if v.id == id:
			return v
	return {}


func vehicle_price(id: String) -> float:
	return roundf(float(vehicle_row(id).price) * economy.price_index)


func buy_vehicle(id: String) -> Dictionary:
	var row := vehicle_row(id)
	if row.is_empty():
		return _fail("Unknown vehicle.")
	if id in vehicles:
		return _fail("Already in your garage.")
	var price := vehicle_price(id)
	if not spend(price):
		return _fail("Need $%s." % fmt_money(price))
	vehicles.append(id)
	if float(row.speed) > 0.0 and (active_vehicle == "" or float(row.speed) > float(vehicle_row(active_vehicle).speed)):
		active_vehicle = id
	add_pass_xp(15)
	if id == "hyper":
		_award("hyper", "Hypercar Club")
	return _ok("%s purchased!" % row.name)


func sell_vehicle(id: String) -> Dictionary:
	if not id in vehicles:
		return _fail("Not yours.")
	var v := roundf(vehicle_price(id) * C.VEHICLE_RESALE)
	vehicles.erase(id)
	if active_vehicle == id:
		active_vehicle = best_vehicle()
	earn(v, "")
	return _ok("Sold for $%s." % fmt_money(v))


func best_vehicle() -> String:
	var best := ""
	var sp := 0.0
	for id in vehicles:
		var s: float = vehicle_row(id).speed
		if s > sp:
			sp = s
			best = id
	return best


func set_vehicle(id: String) -> Dictionary:
	if id != "" and not id in vehicles:
		return _fail("Not yours.")
	if id != "" and float(vehicle_row(id).speed) <= 0.0:
		return _fail("You can't drive that on the street.")
	active_vehicle = id
	return _ok("On foot." if id == "" else "Driving the %s." % vehicle_row(id).name)


func speed_mult() -> float:
	if active_vehicle == "":
		return 1.0
	return float(vehicle_row(active_vehicle).speed)


func has_fast_travel() -> bool:
	return "jet" in vehicles or "heli" in vehicles or "yacht" in vehicles


# ================================================================ stocks
func shares(t: String) -> int:
	return int(holdings[t].shares) if holdings.has(t) else 0


func portfolio_value() -> float:
	var v := 0.0
	for t in holdings:
		v += float(holdings[t].shares) * market.price(t)
	return v


func buy_shares(t: String, n: int) -> Dictionary:
	if n <= 0 or not market.stocks.has(t):
		return _fail("Invalid order.")
	var cost := market.price(t) * n
	if not spend(cost):
		return _fail("Need $%s." % fmt_money(cost))
	if not holdings.has(t):
		holdings[t] = {"shares": 0, "cost": 0.0}
	holdings[t].shares = int(holdings[t].shares) + n
	holdings[t].cost = float(holdings[t].cost) + cost
	_award("investor", "Investor")
	return _ok("Bought %d %s @ $%s" % [n, t, fmt_money(market.price(t), 2)])


func sell_shares(t: String, n: int) -> Dictionary:
	var have := shares(t)
	if n <= 0 or have <= 0:
		return _fail("No shares to sell.")
	n = mini(n, have)
	var avg: float = float(holdings[t].cost) / float(have)
	var proceeds := market.price(t) * n
	var profit := proceeds - avg * n
	holdings[t].shares = have - n
	holdings[t].cost = float(holdings[t].cost) - avg * n
	if int(holdings[t].shares) <= 0:
		holdings.erase(t)
	cash += proceeds
	stats.stocks += profit
	_check_milestones()
	return _ok("Sold %d %s (%s$%s)" % [n, t, "+" if profit >= 0 else "-", fmt_money(absf(profit))], {"profit": profit})


func max_affordable_shares(t: String) -> int:
	var p := market.price(t)
	return int(floor(cash / p)) if p > 0 else 0


# ================================================================ crime (optional)
func crime_chance(id: String) -> float:
	var c: Dictionary = C.CRIMES[id]
	return clampf(float(c.risk) + C.HEAT_RISK * float(heat), 0.05, 0.95)


func crime_available(id: String) -> String:
	var c: Dictionary = C.CRIMES[id]
	if in_jail():
		return "You're in jail."
	if c.has("need_speed") and speed_mult() < float(c.need_speed):
		return "Need a getaway car."
	if c.has("need_networth") and networth() < float(c.need_networth):
		return "Need $%s net worth." % fmt_money(c.need_networth)
	return ""


func attempt_crime(id: String) -> Dictionary:
	if not C.CRIMES.has(id):
		return _fail("Unknown.")
	var why := crime_available(id)
	if why != "":
		return _fail(why)
	var c: Dictionary = C.CRIMES[id]
	crimes_done += 1
	var caught := rng.randf() < crime_chance(id)
	heat = mini(C.MAX_HEAT, heat + int(c.heat))
	if not caught:
		var take := roundf(lerpf(float(c.min), float(c.max), rng.randf()) * economy.price_index)
		earn(take, "crime")
		return _ok("Got away with $%s! Heat rising..." % fmt_money(take), {"caught": false, "amount": take})
	times_caught += 1
	var fine := maxf(C.MIN_FINE, roundf(cash * C.FINE_PCT))
	fine = minf(fine, maxf(0.0, cash))
	cash -= fine
	stats.fines += fine
	jail_until = total_minutes() + C.JAIL_MINUTES
	var seized := ""
	if heat >= C.SEIZE_AT_HEAT and properties.size() > 0:
		var cheapest := 0
		for i in properties.size():
			if property_value(i) < property_value(cheapest):
				cheapest = i
		seized = property_row(properties[cheapest].id).name
		properties.remove_at(cheapest)
		if home == cheapest:
			home = -1
		elif home > cheapest:
			home -= 1
	heat = 0
	var msg := "BUSTED! Fined $%s and jailed for %d hours." % [fmt_money(fine), int(C.JAIL_MINUTES / 60.0)]
	if seized != "":
		msg += " Police seized your %s." % seized
	return {"ok": false, "msg": msg, "caught": true, "fine": fine, "seized": seized}


# ================================================================ endgame
func project_available(id: String) -> String:
	var p: Dictionary = C.PROJECTS[id]
	if id in projects:
		return "Done"
	if networth() < C.GOAL and id != "global":
		return "Reach $1B net worth first."
	if p.has("need_maxed") and maxed_businesses() < int(p.need_maxed):
		return "Need %d max-level businesses (%d/%d)." % [p.need_maxed, maxed_businesses(), p.need_maxed]
	return ""


func start_project(id: String) -> Dictionary:
	if not C.PROJECTS.has(id):
		return _fail("Unknown.")
	var why := project_available(id)
	if why != "":
		return _fail(why)
	var cost := roundf(float(C.PROJECTS[id].cost) * economy.price_index)
	if not spend(cost):
		return _fail("Need $%s." % fmt_money(cost))
	projects.append(id)
	_award("project_" + id, C.PROJECTS[id].name)
	return _ok("%s complete! The whole city is talking." % C.PROJECTS[id].name)


func prestige() -> int:
	var p := 0
	for id in vehicles:
		p += int(vehicle_row(id).prestige)
	for prop in properties:
		for f in prop.features:
			p += int(C.MANSION_FEATURES[f].prestige)
	for id in projects:
		p += int(C.PROJECTS[id].prestige)
	for id in businesses:
		p += int(business_row(id).tier) * int(businesses[id].level) * 2
	return p


# ================================================================ net worth & ranking
func networth() -> float:
	var nw := cash + portfolio_value()
	for id in businesses:
		nw += business_value(id)
	for i in properties.size():
		nw += property_value(i)
	for id in vehicles:
		nw += vehicle_price(id) * C.VEHICLE_RESALE
	for id in projects:
		nw += float(C.PROJECTS[id].cost) * 0.5
	return nw


func goal_progress() -> float:
	# log scale: $100 -> 0, $1B -> 1
	var nw := maxf(1.0, networth())
	return clampf((log(nw) - log(100.0)) / (log(C.GOAL) - log(100.0)), 0.0, 1.0)


func leaderboard(online: Array = []) -> Array:
	var rows: Array = []
	rows.append({"name": player_name + " (you)", "networth": networth(), "you": true})
	for r in rivals:
		rows.append({"name": r.name, "networth": r.networth, "you": false})
	for o in online:
		rows.append({"name": str(o.get("name", "?")), "networth": float(o.get("networth", 0.0)), "you": false, "online": true})
	rows.sort_custom(func(a, b): return float(a.networth) > float(b.networth))
	return rows


func rank() -> int:
	var lb := leaderboard()
	for i in lb.size():
		if lb[i].you:
			return i + 1
	return lb.size()


const MILESTONES := [1_000.0, 10_000.0, 100_000.0, 1_000_000.0, 10_000_000.0, 100_000_000.0, 1_000_000_000.0, 10_000_000_000.0, 100_000_000_000.0, 1_000_000_000_000.0]


func _check_milestones() -> void:
	var nw := networth()
	for m in MILESTONES:
		if nw >= m and not milestones.has(m):
			milestones.append(m)
			coins += 25
			if m >= C.GOAL and billionaire_day < 0:
				billionaire_day = day
				_award("billionaire", "BILLIONAIRE")
				notify.emit("YOU ARE A BILLIONAIRE! Day %d. Endgame projects unlocked." % day, "goal")
			elif m >= C.STRETCH_GOAL:
				_award("trillionaire", "TRILLIONAIRE")
				notify.emit("TRILLIONAIRE! You won the city.", "goal")
			else:
				notify.emit("Milestone: $%s net worth! (+25 coins)" % fmt_money(m), "goal")


func _award(id: String, label: String) -> void:
	if id in achievements:
		return
	achievements.append(id)
	notify.emit("Achievement: " + label, "good")


# ================================================================ cosmetics & season pass
func pass_tier() -> int:
	return mini(C.PASS_TIERS, pass_xp / C.PASS_XP_PER_TIER)


func add_pass_xp(x: int) -> void:
	var before := pass_tier()
	pass_xp += x
	if pass_tier() > before:
		notify.emit("Season Pass tier %d reached! Claim it in the Shop." % pass_tier(), "info")


func pass_reward(tier: int, premium: bool) -> int:
	return (40 if premium else 15) + tier * (4 if premium else 1)


func claim_pass(tier: int, premium: bool) -> Dictionary:
	var key := "%d%s" % [tier, "p" if premium else "f"]
	if tier > pass_tier():
		return _fail("Tier locked.")
	if premium and not pass_premium:
		return _fail("Premium track locked.")
	if key in pass_claimed:
		return _fail("Already claimed.")
	pass_claimed.append(key)
	var c := pass_reward(tier, premium)
	coins += c
	return _ok("+%d coins" % c)


func buy_premium_pass() -> Dictionary:
	if pass_premium:
		return _fail("Already premium.")
	if coins < C.PASS_PREMIUM_COST:
		return _fail("Need %d coins." % C.PASS_PREMIUM_COST)
	coins -= C.PASS_PREMIUM_COST
	pass_premium = true
	return _ok("Premium Season Pass unlocked!")


func claim_daily() -> Dictionary:
	if last_daily_claim == day:
		return _fail("Come back tomorrow.")
	last_daily_claim = day
	coins += C.DAILY_COINS
	return _ok("+%d Empire Coins" % C.DAILY_COINS)


func buy_cosmetic(kind: String, id: String) -> Dictionary:
	var table: Dictionary = {"skin": C.SKINS, "paint": C.PAINTS, "decor": C.DECOR}.get(kind, {})
	if not table.has(id):
		return _fail("Unknown item.")
	var key := kind + ":" + id
	if key in owned_cosmetics:
		return equip(kind, id)
	var cost := int(table[id].cost)
	if coins < cost:
		return _fail("Need %d coins." % cost)
	coins -= cost
	owned_cosmetics.append(key)
	if kind != "decor":
		equip(kind, id)
	return _ok("Unlocked %s!" % table[id].name)


func equip(kind: String, id: String) -> Dictionary:
	if not (kind + ":" + id) in owned_cosmetics:
		return _fail("Not owned.")
	if kind == "skin":
		skin = id
	elif kind == "paint":
		paint = id
	return _ok("Equipped.")


# ================================================================ formatting
static func fmt_money(v: float, decimals: int = 0) -> String:
	var a := absf(v)
	var sgn := "-" if v < 0 else ""
	if a >= 1e12:
		return sgn + "%.2fT" % (a / 1e12)
	if a >= 1e9:
		return sgn + "%.2fB" % (a / 1e9)
	if a >= 1e6:
		return sgn + "%.2fM" % (a / 1e6)
	if decimals > 0 and a < 1000.0:
		return sgn + ("%." + str(decimals) + "f") % a
	var s := str(int(roundf(a)))
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0:
			out = "," + out
	return sgn + out


# ================================================================ save / load
func to_dict() -> Dictionary:
	return {
		"version": C.VERSION, "player_name": player_name, "cash": cash, "day": day, "minute": minute,
		"jail_until": jail_until, "heat": heat, "businesses": businesses.duplicate(true),
		"properties": properties.duplicate(true), "home": home, "vehicles": vehicles.duplicate(),
		"active_vehicle": active_vehicle, "holdings": holdings.duplicate(true), "projects": projects.duplicate(),
		"company": company, "jobs_done": jobs_done, "crimes_done": crimes_done, "times_caught": times_caught,
		"stats": stats.duplicate(), "milestones": milestones.duplicate(), "achievements": achievements.duplicate(),
		"networth_history": networth_history.duplicate(), "billionaire_day": billionaire_day,
		"coins": coins, "owned_cosmetics": owned_cosmetics.duplicate(), "skin": skin, "paint": paint,
		"pass_xp": pass_xp, "pass_premium": pass_premium, "pass_claimed": pass_claimed.duplicate(),
		"last_daily_claim": last_daily_claim,
		"rivals": rivals.map(func(r): return {"name": r.name, "networth": r.networth}),
		"economy": economy.to_dict(), "market": market.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	player_name = str(d.get("player_name", "Player"))
	cash = float(d.get("cash", C.START_CASH))
	day = int(d.get("day", 1))
	minute = float(d.get("minute", 480.0))
	jail_until = float(d.get("jail_until", -1.0))
	heat = int(d.get("heat", 0))
	businesses = {}
	var bsrc: Dictionary = d.get("businesses", {})
	for id in bsrc:
		if not business_row(id).is_empty():
			businesses[id] = {"level": int(bsrc[id].get("level", 1)), "workers": int(bsrc[id].get("workers", 0))}
	properties = []
	for p in d.get("properties", []):
		if not property_row(str(p.get("id", ""))).is_empty():
			properties.append({"id": str(p.id), "reno": bool(p.get("reno", false)), "rented": bool(p.get("rented", false)),
				"features": Array(p.get("features", [])), "decor": Array(p.get("decor", []))})
	home = clampi(int(d.get("home", -1)), -1, properties.size() - 1)
	vehicles = []
	for v in d.get("vehicles", []):
		if not vehicle_row(str(v)).is_empty():
			vehicles.append(str(v))
	active_vehicle = str(d.get("active_vehicle", ""))
	if active_vehicle != "" and not active_vehicle in vehicles:
		active_vehicle = ""
	holdings = {}
	var hsrc: Dictionary = d.get("holdings", {})
	for t in hsrc:
		holdings[t] = {"shares": int(hsrc[t].get("shares", 0)), "cost": float(hsrc[t].get("cost", 0.0))}
	projects = Array(d.get("projects", []))
	company = str(d.get("company", ""))
	jobs_done = int(d.get("jobs_done", 0))
	crimes_done = int(d.get("crimes_done", 0))
	times_caught = int(d.get("times_caught", 0))
	var st: Dictionary = d.get("stats", {})
	for k in stats:
		stats[k] = float(st.get(k, 0.0))
	milestones = []
	for m in d.get("milestones", []):
		milestones.append(float(m))
	achievements = Array(d.get("achievements", []))
	networth_history = []
	for v in d.get("networth_history", []):
		networth_history.append(float(v))
	billionaire_day = int(d.get("billionaire_day", -1))
	coins = int(d.get("coins", C.START_COINS))
	owned_cosmetics = Array(d.get("owned_cosmetics", ["skin:default", "paint:factory"]))
	skin = str(d.get("skin", "default"))
	paint = str(d.get("paint", "factory"))
	pass_xp = int(d.get("pass_xp", 0))
	pass_premium = bool(d.get("pass_premium", false))
	pass_claimed = Array(d.get("pass_claimed", []))
	last_daily_claim = int(d.get("last_daily_claim", 0))
	var rv: Array = d.get("rivals", [])
	for i in mini(rv.size(), rivals.size()):
		rivals[i].networth = float(rv[i].get("networth", rivals[i].networth))
	economy.from_dict(d.get("economy", {}))
	market.from_dict(d.get("market", {}))
