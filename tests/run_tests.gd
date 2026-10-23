extends SceneTree
## Unit tests for the pure simulation. Run:
##   godot --headless --path . -s tests/run_tests.gd

const C = preload("res://scripts/core/catalog.gd")
const Sim = preload("res://scripts/core/empire_sim.gd")
const Economy = preload("res://scripts/core/economy.gd")
const Market = preload("res://scripts/core/stock_market.gd")

var passed := 0
var failed := 0


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		printerr("  FAIL: ", what)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))


func _init() -> void:
	print("Money Empire unit tests")
	test_start_state()
	test_clock_and_income()
	test_jobs()
	test_businesses()
	test_real_estate()
	test_vehicles()
	test_stocks()
	test_economy()
	test_crime()
	test_endgame()
	test_cosmetics()
	test_formatting()
	test_save_roundtrip()
	test_save_signature()
	test_leaderboard()
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func test_start_state() -> void:
	var s := Sim.new(1)
	check(s.cash == 100.0, "start with $100")
	check(s.properties.is_empty() and s.home == -1, "start homeless")
	check(s.vehicles.is_empty() and s.speed_mult() == 1.0, "start on foot")
	check(s.businesses.is_empty(), "no businesses")
	check(near(s.networth(), 100.0), "net worth = cash at start")
	check(s.goal_progress() == 0.0, "goal progress 0 at start")
	check(s.rivals.size() == C.RIVALS.size(), "rivals seeded")


func test_clock_and_income() -> void:
	var s := Sim.new(2)
	var hours := [0]
	s.hour_passed.connect(func(): hours[0] += 1)
	s.advance(60.0)
	check(hours[0] == 1, "one hour tick after 60 min (got %d)" % hours[0])
	s.advance(30.0)
	s.advance(29.0)
	check(hours[0] == 1, "no tick before the hour")
	s.advance(1.0)
	check(hours[0] == 2, "tick exactly on the hour")
	var days := [0]
	s.day_passed.connect(func(_d): days[0] += 1)
	s.advance(1440.0)
	check(days[0] == 1 and s.day == 2, "a day passes after 1440 minutes")
	check(hours[0] == 26, "24 more hourly ticks")
	# passive income
	var b := Sim.new(3)
	b.cash = 10_000.0
	b.buy_business("taco")
	var before := b.cash
	var expected := b.daily_business_income()
	b.advance(1440.0)
	check(b.cash > before, "business pays passive income")
	check(near(b.cash - before, expected, 0.15), "income ~= daily rate (%.1f vs %.1f)" % [b.cash - before, expected])


func test_jobs() -> void:
	var s := Sim.new(4)
	var pay := s.job_pay("package")
	check(pay >= 40.0 and pay <= 80.0, "starter job pay sensible: %f" % pay)
	var r := s.complete_job("package")
	check(r.ok and s.cash == 100.0 + r.pay, "completing a job pays")
	check(s.jobs_done == 1, "job counter")
	check(not s.job_unlocked("dockhand"), "dock hand locked at start")
	for i in 9:
		s.complete_job("carwash")
	check(s.job_unlocked("dockhand"), "dock hand unlocks after 10 jobs")
	check(s.job_level() > 1, "job level rises")
	var lazy := s.complete_job("food", 0.0)
	check(lazy.pay >= roundf(s.job_pay("food") * 0.3) - 1.0, "quality floor 30%")
	check(not s.complete_job("nope").ok, "unknown job rejected")
	# living in your own home pays more
	var h := Sim.new(5)
	var p0 := h.job_pay("lawn")
	h.cash = 100_000.0
	h.buy_property("studio")
	check(h.job_pay("lawn") > p0, "home bonus increases job pay")


func test_businesses() -> void:
	var s := Sim.new(6)
	check(not s.buy_business("taco").ok, "can't afford taco with $100")
	s.cash = 1_000_000.0
	check(s.buy_business("taco").ok, "buy taco stand")
	check(not s.buy_business("taco").ok, "can't buy twice")
	var inc1 := s.business_income("taco")
	check(s.upgrade_business("taco").ok and s.businesses.taco.level == 2, "upgrade to level 2")
	check(s.business_income("taco") > inc1 * 1.4, "upgrade boosts income")
	var inc2 := s.business_income("taco")
	check(s.hire_worker("taco").ok, "hire worker")
	check(near(s.business_income("taco"), inc2 * 1.1), "worker adds 10%")
	check(s.daily_salaries() > 0.0, "workers cost salary")
	for i in 3:
		s.upgrade_business("taco")
	check(s.businesses.taco.level == C.MAX_BUSINESS_LEVEL, "max level reached")
	check(not s.upgrade_business("taco").ok, "can't exceed max level")
	check(s.maxed_businesses() == 1, "maxed count")
	var cash_before := s.cash
	check(s.sell_business("taco").ok and s.cash > cash_before, "sell business")
	check(not s.businesses.has("taco"), "sold business removed")
	# every catalog business has a sane payback period (3..12 days)
	for row in C.BUSINESSES:
		var payback: float = float(row.price) / float(row.income)
		check(payback >= 3.0 and payback <= 12.0, "%s payback %.1f days" % [row.id, payback])


func test_real_estate() -> void:
	var s := Sim.new(7)
	s.cash = 10_000_000.0
	check(s.buy_property("studio").ok, "buy studio")
	check(s.home == 0, "first property becomes home")
	check(not s.toggle_rent(0).ok, "can't rent out your own home")
	check(s.buy_property("duplex").ok, "buy duplex")
	check(s.toggle_rent(1).ok and s.properties[1].rented, "rent out duplex")
	check(s.daily_rent_income() > 0.0, "rent income")
	var v := s.property_value(1)
	check(s.renovate_property(1).ok, "renovate")
	check(near(s.property_value(1), v * 1.25), "renovation adds 25%")
	check(not s.renovate_property(1).ok, "can't renovate twice")
	check(not s.add_feature(1, "pool").ok, "no pool on a duplex")
	check(s.buy_property("villa").ok, "buy villa")
	var vv := s.property_value(2)
	check(s.add_feature(2, "pool").ok, "add pool to villa")
	check(s.property_value(2) > vv, "pool adds value")
	check(s.prestige() > 0, "prestige from features")
	check(s.set_home(2).ok and s.home == 2, "move into villa")
	var n := s.properties.size()
	check(s.sell_property(0).ok and s.properties.size() == n - 1, "sell studio")
	check(s.home == 1, "home index shifts after selling earlier property")
	for i in 10:
		s.buy_property("studio")
	check(s.owned_count("studio") == 10, "max units of studio")
	check(not s.buy_property("studio").ok, "cap enforced")


func test_vehicles() -> void:
	var s := Sim.new(8)
	check(s.buy_vehicle("bike").ok, "buy bike with starting cash")
	check(s.active_vehicle == "bike" and s.speed_mult() > 1.0, "auto-equip bike")
	s.cash = 1_000_000.0
	s.buy_vehicle("sports")
	check(s.active_vehicle == "sports", "faster car auto-equips")
	check(s.buy_vehicle("yacht").ok == false, "can't afford yacht")
	s.cash = 20_000_000.0
	s.buy_vehicle("yacht")
	check(s.active_vehicle == "sports", "yacht doesn't replace street car")
	check(not s.set_vehicle("yacht").ok, "can't drive a yacht")
	check(s.has_fast_travel(), "yacht grants fast travel")
	check(s.sell_vehicle("sports").ok and s.active_vehicle == "bike", "selling falls back to best vehicle")
	check(s.set_vehicle("").ok and s.speed_mult() == 1.0, "walk")


func test_stocks() -> void:
	var s := Sim.new(9)
	s.cash = 10_000.0
	var p := s.market.price("BYTE")
	check(s.buy_shares("BYTE", 10).ok and s.shares("BYTE") == 10, "buy shares")
	check(near(s.cash, 10_000.0 - p * 10.0), "cash debited")
	check(near(s.portfolio_value(), p * 10.0), "portfolio value")
	s.market.stocks.BYTE.price = p * 2.0
	var r := s.sell_shares("BYTE", 5)
	check(r.ok and near(r.profit, p * 5.0), "profit on doubled price")
	check(s.shares("BYTE") == 5, "partial sell")
	s.sell_shares("BYTE", 999)
	check(s.shares("BYTE") == 0 and not s.holdings.has("BYTE"), "sell all clears holding")
	check(not s.buy_shares("NOPE", 1).ok, "bad ticker")
	check(s.max_affordable_shares("NEUR") == int(floor(s.cash / s.market.price("NEUR"))), "max affordable")
	# prices move and stay positive
	var m := Market.new(RandomNumberGenerator.new())
	var e := Economy.new(RandomNumberGenerator.new())
	var p0 := m.price("ORBT")
	for i in 500:
		m.tick_hour(e)
	check(m.price("ORBT") != p0, "prices move")
	for t in m.order:
		check(m.price(t) > 0.0, "%s price positive" % t)
		check(m.stocks[t].history.size() == Market.HISTORY, "%s history capped" % t)
	# crash drags prices down on average
	var up := 0
	for trial in 30:
		var rng := RandomNumberGenerator.new()
		rng.seed = trial
		var m2 := Market.new(rng)
		var e2 := Economy.new(rng)
		e2.phase = "crash"
		var before := m2.price("NEUR")
		for i in 48:
			m2.tick_hour(e2)
		if m2.price("NEUR") > before:
			up += 1
	check(up < 8, "crash pushes NEUR down most of the time (%d/30 up)" % up)


func test_economy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var e := Economy.new(rng)
	var seen := {}
	for d in 600:
		e.tick_day(d)
		seen[e.phase] = true
	check(seen.size() >= 3, "economy cycles through phases: %s" % str(seen.keys()))
	check(e.price_index > 1.0, "inflation raises prices over time (%.3f)" % e.price_index)
	for k in e.district_index:
		check(e.district_index[k] >= 0.45 and e.district_index[k] <= 6.0, "district index bounded")
	check(e.headlines.size() > 0, "headlines generated")
	e.set_phase("boom", 1)
	check(e.income_mult() > 1.0, "boom boosts income")
	e.set_phase("crash", 2)
	check(e.income_mult() < 1.0 and e.asset_mult() < 1.0, "crash hurts")


func test_crime() -> void:
	var s := Sim.new(10)
	check(s.crime_available("smuggle") != "", "smuggling needs a car")
	check(s.crime_available("heist") != "", "heist needs net worth")
	check(s.crime_chance("robbery") > 0.0 and s.crime_chance("robbery") < 1.0, "risk in range")
	var got := 0
	var caught := 0
	for i in 200:
		var t := Sim.new(1000 + i)
		t.cash = 10_000.0
		var r := t.attempt_crime("robbery")
		if r.get("caught", false):
			caught += 1
			check(t.in_jail(), "caught -> jailed")
			check(t.cash < 10_000.0, "caught -> fined")
		else:
			got += 1
			check(t.cash > 10_000.0, "success -> paid")
	check(caught > 20 and caught < 80, "robbery catch rate ~22%% (%d/200)" % caught)
	# heat raises risk, jail blocks actions
	var h := Sim.new(11)
	h.heat = 4
	check(h.crime_chance("robbery") > C.CRIMES.robbery.risk, "heat raises risk")
	h.jail_until = h.total_minutes() + 100.0
	check(not h.complete_job("package").ok, "can't work in jail")
	h.advance(101.0)
	check(not h.in_jail(), "released after sentence")
	# seizure at high heat
	var seized := false
	for i in 300:
		var z := Sim.new(5000 + i)
		z.cash = 100_000.0
		z.buy_property("studio")
		z.buy_property("duplex")
		z.heat = 4
		var r := z.attempt_crime("robbery")
		if r.get("caught", false):
			seized = r.seized != "" and z.properties.size() == 1
			break
	check(seized, "property seized when caught at high heat")


func test_endgame() -> void:
	var s := Sim.new(12)
	check(s.project_available("skyscraper") != "", "skyscraper locked before $1B")
	s.cash = 3_000_000_000.0
	s._check_milestones()
	check(s.billionaire_day == 1, "billionaire milestone recorded")
	check(s.start_project("skyscraper").ok, "build skyscraper")
	check(not s.start_project("skyscraper").ok, "only once")
	check(s.project_available("global").begins_with("Need 5"), "global needs maxed businesses")
	check(s.prestige() >= 500, "project prestige")


func test_cosmetics() -> void:
	var s := Sim.new(13)
	check(s.coins == C.START_COINS, "starting coins")
	check(s.claim_daily().ok and not s.claim_daily().ok, "daily once per day")
	check(s.buy_cosmetic("skin", "ruby").ok and s.skin == "ruby", "buy + equip skin")
	check(not s.buy_cosmetic("skin", "tux").ok, "can't afford tux")
	check(s.equip("skin", "default").ok and s.skin == "default", "re-equip default")
	var cash := s.cash
	s.buy_cosmetic("paint", "factory")
	check(s.cash == cash, "cosmetics never cost cash (not pay-to-win)")
	check(not s.claim_pass(1, false).ok, "tier 1 locked at 0 xp")
	s.add_pass_xp(250)
	check(s.pass_tier() == 2, "pass tier from xp")
	check(s.claim_pass(1, false).ok and not s.claim_pass(1, false).ok, "claim free tier once")
	check(not s.claim_pass(1, true).ok, "premium locked")


func test_formatting() -> void:
	check(Sim.fmt_money(0) == "0", "fmt 0")
	check(Sim.fmt_money(1234567) == "1.23M", "fmt M: " + Sim.fmt_money(1234567))
	check(Sim.fmt_money(999) == "999", "fmt small")
	check(Sim.fmt_money(12345) == "12,345", "fmt commas: " + Sim.fmt_money(12345))
	check(Sim.fmt_money(2.5e9) == "2.50B", "fmt B")
	check(Sim.fmt_money(1e12) == "1.00T", "fmt T")
	check(Sim.fmt_money(-1500) == "-1,500", "fmt negative")
	check(Sim.fmt_money(12.5, 2) == "12.50", "fmt decimals")


func test_save_roundtrip() -> void:
	var s := Sim.new(14)
	s.player_name = "Tester"
	s.cash = 5_000_000.0
	s.buy_business("restaurant")
	s.upgrade_business("restaurant")
	s.buy_property("family")
	s.buy_property("villa")
	s.add_feature(1, "theater")
	s.set_home(1)
	s.toggle_rent(0)
	s.buy_vehicle("sports")
	s.buy_shares("VOLT", 25)
	s.complete_job("lawn")
	s.advance(3000.0)
	s.buy_cosmetic("skin", "ruby")
	var json := JSON.stringify(s.to_dict())
	var t := Sim.new(99)
	t.from_dict(JSON.parse_string(json))
	check(t.player_name == "Tester", "name restored")
	check(near(t.cash, s.cash, 0.0001), "cash restored")
	check(t.day == s.day and near(t.minute, s.minute), "clock restored")
	check(t.businesses.restaurant.level == 2, "business level restored")
	check(t.properties.size() == 2 and t.properties[1].features == ["theater"], "properties restored")
	check(t.home == 1 and t.properties[0].rented, "home + rent restored")
	check(t.active_vehicle == "sports", "vehicle restored")
	check(t.shares("VOLT") == 25, "shares restored")
	check(near(t.market.price("VOLT"), s.market.price("VOLT"), 0.0001), "stock price restored")
	check(t.economy.phase == s.economy.phase, "economy phase restored")
	check(near(t.networth(), s.networth(), 0.001), "net worth identical after load (%.2f vs %.2f)" % [t.networth(), s.networth()])
	check(t.skin == "ruby", "cosmetics restored")
	# junk in save is ignored safely
	var u := Sim.new(1)
	u.from_dict({"businesses": {"fake": {"level": 3}}, "vehicles": ["ufo"], "properties": [{"id": "castle"}], "home": 5})
	check(u.businesses.is_empty() and u.vehicles.is_empty() and u.properties.is_empty() and u.home == -1, "unknown ids dropped")


func test_save_signature() -> void:
	var G = load("res://scripts/core/save_util.gd")
	var data := JSON.stringify({"cash": 100})
	var sig: String = G.sign_data(data)
	check(sig.length() == 64, "sha256 signature")
	check(G.sign_data(data.replace("100", "999999999")) != sig, "tampering changes the signature")


func test_leaderboard() -> void:
	var s := Sim.new(15)
	var lb := s.leaderboard([{"name": "Online Olivia", "networth": 1e12}])
	check(lb[0].name == "Online Olivia", "online players ranked")
	check(lb.size() == C.RIVALS.size() + 2, "everyone listed")
	for i in lb.size() - 1:
		check(float(lb[i].networth) >= float(lb[i + 1].networth), "sorted desc")
	for d in 120:
		s.advance(1440.0)
	var richest := 0.0
	for r in s.rivals:
		richest = maxf(richest, r.networth)
	check(richest > 1e5, "rivals grow over time (%.0f)" % richest)
