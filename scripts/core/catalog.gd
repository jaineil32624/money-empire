extends RefCounted
## Money Empire — static game data.
## Every number that defines the economy lives here so balance can be tuned in one place.
## Rows are plain dictionaries so they serialize and mod easily.

const VERSION := "0.1.0"
const GOAL := 1_000_000_000.0            # $1 Billion — the headline goal
const STRETCH_GOAL := 1_000_000_000_000.0  # $1 Trillion — the online race
const START_CASH := 100.0
const DAY_SECONDS := 180.0                 # real seconds per in-game day at 1x speed
const DAYS_PER_YEAR := 60                  # game "year" used for inflation

# ---------------------------------------------------------------- districts
const DISTRICTS := {
	"downtown":   {"name": "Downtown",         "color": Color("#4f8cff"), "blurb": "Banks, towers, apartments and the Stock Exchange."},
	"suburbs":    {"name": "Suburbs",          "color": Color("#58c26b"), "blurb": "Houses, lawns and small businesses."},
	"industrial": {"name": "Industrial Zone",  "color": Color("#f0a030"), "blurb": "Factories, warehouses and the spaceport."},
	"luxury":     {"name": "Luxury District",  "color": Color("#c47bff"), "blurb": "Mansions, supercars and the private airport."},
	"harbor":     {"name": "Harbor",           "color": Color("#2ec4c4"), "blurb": "Cargo ships, imports and trading."},
}

# ---------------------------------------------------------------- jobs
# kind: deliver (go to N drop-offs), hold (stay in zone), patches (visit spots), carry (shuttle loads)
const JOBS := {
	"package":   {"name": "Package Delivery",  "district": "downtown",   "pay": 60.0, "kind": "deliver", "stops": 1, "xp": 10, "desc": "Grab a parcel and drop it at the marked address."},
	"carwash":   {"name": "Car Wash",          "district": "suburbs",    "pay": 50.0, "kind": "hold",    "hold": 5.0, "xp": 8,  "desc": "Stand in the wash bay and scrub until it shines."},
	"lawn":      {"name": "Lawn Mowing",       "district": "suburbs",    "pay": 72.0, "kind": "patches", "patches": 5, "xp": 12, "desc": "Mow every overgrown patch in the yard."},
	"food":      {"name": "Food Delivery",     "district": "downtown",   "pay": 100.0, "kind": "deliver", "stops": 2, "time_limit": 75.0, "xp": 15, "desc": "Two hot orders, one clock. Tips for speed."},
	"warehouse": {"name": "Warehouse Shift",   "district": "industrial", "pay": 82.0, "kind": "carry",   "loads": 3, "xp": 14, "desc": "Move pallets from the dock to the racks."},
	"dockhand":  {"name": "Dock Hand",         "district": "harbor",     "pay": 185.0, "kind": "carry",  "loads": 4, "xp": 25, "unlock_jobs": 10, "desc": "Unload cargo ships. Unlocks after 10 jobs."},
}

# ---------------------------------------------------------------- businesses
# income is per in-game day at level 1 in a stable economy
const BUSINESSES := [
	{"id": "taco",        "name": "Taco Stand",                "tier": 1, "district": "downtown",   "price": 750.0,          "income": 190.0},
	{"id": "suds",        "name": "Suds Car Wash Co.",         "tier": 1, "district": "suburbs",    "price": 4_000.0,        "income": 950.0},
	{"id": "laundromat",  "name": "Spin City Laundromat",      "tier": 1, "district": "suburbs",    "price": 9_000.0,        "income": 2_000.0},
	{"id": "restaurant",  "name": "Bistro 88 Restaurant",      "tier": 2, "district": "downtown",   "price": 28_000.0,       "income": 5_600.0},
	{"id": "store",       "name": "Corner Mart",               "tier": 2, "district": "suburbs",    "price": 42_000.0,       "income": 8_000.0},
	{"id": "gas",         "name": "FuelUp Gas Station",        "tier": 2, "district": "industrial", "price": 75_000.0,       "income": 13_600.0},
	{"id": "dealership",  "name": "Apex Car Dealership",       "tier": 3, "district": "luxury",     "price": 400_000.0,      "income": 66_000.0},
	{"id": "hotel",       "name": "Grand Vista Hotel",         "tier": 3, "district": "downtown",   "price": 900_000.0,      "income": 145_000.0},
	{"id": "factory",     "name": "Ironworks Factory",         "tier": 3, "district": "industrial", "price": 2_500_000.0,    "income": 385_000.0},
	{"id": "shipping",    "name": "Harbor Shipping Co.",       "tier": 3, "district": "harbor",     "price": 6_000_000.0,    "income": 880_000.0},
	{"id": "mall",        "name": "Skyline Shopping Mall",     "tier": 4, "district": "downtown",   "price": 18_000_000.0,   "income": 2_570_000.0},
	{"id": "resort",      "name": "Azure Luxury Resort",       "tier": 4, "district": "luxury",     "price": 45_000_000.0,   "income": 6_250_000.0},
	{"id": "bank",        "name": "Monolith Bank",             "tier": 4, "district": "downtown",   "price": 90_000_000.0,   "income": 12_000_000.0},
	{"id": "investfirm",  "name": "Summit Capital Partners",   "tier": 4, "district": "downtown",   "price": 160_000_000.0,  "income": 20_800_000.0},
	{"id": "megacorp",    "name": "OmniCorp Mega Corporation", "tier": 5, "district": "downtown",   "price": 400_000_000.0,  "income": 50_000_000.0},
	{"id": "space",       "name": "Starforge Aerospace",       "tier": 5, "district": "industrial", "price": 1_200_000_000.0, "income": 141_000_000.0},
]
const TIER_NAMES := ["", "Starter", "Mid Game", "Big League", "Tycoon", "Mega Empire"]
const MAX_BUSINESS_LEVEL := 5
const MAX_WORKERS := 5
const WORKER_BONUS := 0.10        # +10% income per worker
const WORKER_SALARY := 0.035      # each worker costs 3.5% of base daily income

# ---------------------------------------------------------------- real estate
# max = how many units of this listing you may own
const PROPERTIES := [
	{"id": "studio",      "name": "Studio Apartment",       "district": "downtown", "kind": "apartment", "price": 6_000.0,       "rent": 200.0,        "max": 10},
	{"id": "duplex",      "name": "Suburban Duplex",        "district": "suburbs",  "kind": "house",     "price": 22_000.0,      "rent": 680.0,       "max": 6},
	{"id": "family",      "name": "Family House",           "district": "suburbs",  "kind": "house",     "price": 65_000.0,      "rent": 1_800.0,       "max": 6},
	{"id": "townhouse",   "name": "Downtown Townhouse",     "district": "downtown", "kind": "house",     "price": 180_000.0,     "rent": 4_400.0,     "max": 4},
	{"id": "waterfront",  "name": "Harbor Waterfront Loft", "district": "harbor",   "kind": "apartment", "price": 450_000.0,     "rent": 10_250.0,     "max": 4},
	{"id": "penthouse",   "name": "Skyline Penthouse",      "district": "downtown", "kind": "apartment", "price": 1_200_000.0,   "rent": 24_500.0,     "max": 2},
	{"id": "villa",       "name": "Hillside Villa",         "district": "luxury",   "kind": "mansion",   "price": 3_500_000.0,   "rent": 62_500.0,    "max": 2},
	{"id": "mansion",     "name": "Royal Crest Mansion",    "district": "luxury",   "kind": "mansion",   "price": 12_000_000.0,  "rent": 187_500.0,    "max": 1},
	{"id": "megamansion", "name": "Mega Mansion Estate",    "district": "luxury",   "kind": "mansion",   "price": 60_000_000.0,  "rent": 800_000.0,   "max": 1},
	{"id": "island",      "name": "Private Island",         "district": "harbor",   "kind": "island",    "price": 250_000_000.0, "rent": 2_750_000.0, "max": 1},
]
const RENOVATE_COST := 0.15       # flip: pay 15% of value...
const RENOVATE_GAIN := 0.25       # ...to add 25% value
const HOME_JOB_BONUS := 0.10      # living in your own place: +10% job pay

# mansion upgrades (cost = pct of base property price)
const MANSION_FEATURES := {
	"pool":     {"name": "Infinity Pool",     "pct": 0.08, "prestige": 20},
	"theater":  {"name": "Home Theater",      "pct": 0.06, "prestige": 15},
	"trophy":   {"name": "Trophy Room",       "pct": 0.05, "prestige": 25},
	"garage":   {"name": "10-Car Garage",     "pct": 0.07, "prestige": 15},
	"security": {"name": "Security System",   "pct": 0.04, "prestige": 10},
	"helipad":  {"name": "Rooftop Helipad",   "pct": 0.09, "prestige": 30},
}
const FEATURE_VALUE_RETURN := 1.3  # each feature adds 130% of its cost to the property value

# ---------------------------------------------------------------- vehicles
# speed is a multiplier on walking speed; 0 = not drivable on the street (fast-travel / prestige)
const VEHICLES := [
	{"id": "bike",   "name": "City Bike",              "price": 80.0,          "speed": 1.6, "kind": "land", "prestige": 1,   "color": Color("#58c26b")},
	{"id": "scooter","name": "Electric Scooter",       "price": 1_200.0,       "speed": 1.9, "kind": "land", "prestige": 2,   "color": Color("#2ec4c4")},
	{"id": "sedan",  "name": "Used Sedan",             "price": 6_000.0,       "speed": 2.4, "kind": "land", "prestige": 4,   "color": Color("#9aa7b8")},
	{"id": "suv",    "name": "Family SUV",             "price": 38_000.0,      "speed": 2.6, "kind": "land", "prestige": 8,   "color": Color("#30475e")},
	{"id": "sports", "name": "Velocity GT",            "price": 120_000.0,     "speed": 3.2, "kind": "land", "prestige": 20,  "color": Color("#e8423f")},
	{"id": "hyper",  "name": "Hypercar X1",            "price": 2_400_000.0,   "speed": 4.2, "kind": "land", "prestige": 60,  "color": Color("#f5c542")},
	{"id": "heli",   "name": "Helicopter",             "price": 14_000_000.0,  "speed": 5.0, "kind": "air",  "prestige": 90,  "color": Color("#ffffff")},
	{"id": "yacht",  "name": "Superyacht",             "price": 9_000_000.0,   "speed": 0.0, "kind": "sea",  "prestige": 80,  "color": Color("#ffffff")},
	{"id": "jet",    "name": "Private Jet",            "price": 70_000_000.0,  "speed": 0.0, "kind": "air",  "prestige": 150, "color": Color("#dfe6ee")},
]
const VEHICLE_RESALE := 0.6

# ---------------------------------------------------------------- stock market
# vol = daily volatility; beta = how strongly the sector follows the economy
const STOCKS := [
	{"ticker": "NEUR", "name": "NeuralForge AI",     "sector": "AI",          "price": 120.0, "vol": 0.045, "beta": 1.6},
	{"ticker": "BYTE", "name": "ByteWave Tech",      "sector": "Technology",  "price": 85.0,  "vol": 0.030, "beta": 1.3},
	{"ticker": "VOLT", "name": "VoltGrid Energy",    "sector": "Energy",      "price": 60.0,  "vol": 0.025, "beta": 0.8},
	{"ticker": "CART", "name": "CartMax Retail",     "sector": "Retail",      "price": 42.0,  "vol": 0.020, "beta": 1.0},
	{"ticker": "BRIK", "name": "BrickStone REIT",    "sector": "Real Estate", "price": 70.0,  "vol": 0.018, "beta": 1.1},
	{"ticker": "ORBT", "name": "Orbital Dynamics",   "sector": "Space",       "price": 25.0,  "vol": 0.060, "beta": 1.8},
]

# ---------------------------------------------------------------- economy phases
const PHASES := {
	"boom":      {"name": "BOOM",      "color": Color("#2ecc71"), "income": 1.25, "assets": 1.10, "wages": 1.15, "drift": 0.006,  "inflation": 0.05},
	"stable":    {"name": "STABLE",    "color": Color("#4f8cff"), "income": 1.00, "assets": 1.00, "wages": 1.00, "drift": 0.0015, "inflation": 0.03},
	"recession": {"name": "RECESSION", "color": Color("#f0a030"), "income": 0.80, "assets": 0.88, "wages": 0.90, "drift": -0.004, "inflation": 0.015},
	"crash":     {"name": "MARKET CRASH", "color": Color("#e8423f"), "income": 0.60, "assets": 0.72, "wages": 0.80, "drift": -0.03, "inflation": 0.0},
}
# daily transition chances (only after a phase has lasted 3+ days)
const PHASE_TRANSITIONS := {
	"stable":    {"boom": 0.08, "recession": 0.06, "crash": 0.01},
	"boom":      {"stable": 0.12, "recession": 0.03, "crash": 0.04},
	"recession": {"stable": 0.12, "crash": 0.05, "boom": 0.01},
	"crash":     {"recession": 0.30, "stable": 0.05},
}

# ---------------------------------------------------------------- crime (optional, risky)
const CRIMES := {
	"robbery":  {"name": "Corner Store Robbery", "risk": 0.22, "min": 400.0,       "max": 1_500.0,     "heat": 1, "desc": "Quick cash, low payoff."},
	"scam":     {"name": "Phone Scam Ring",      "risk": 0.28, "min": 2_500.0,     "max": 9_000.0,     "heat": 1, "desc": "Fake prize calls from a back-alley office."},
	"smuggle":  {"name": "Harbor Smuggling Run", "risk": 0.32, "min": 25_000.0,    "max": 90_000.0,    "heat": 2, "desc": "Needs a car (speed 2.4+) for the getaway.", "need_speed": 2.4},
	"heist":    {"name": "Monolith Bank Heist",  "risk": 0.50, "min": 1_500_000.0, "max": 6_000_000.0, "heat": 3, "desc": "The big one. Requires $1M net worth to plan.", "need_networth": 1_000_000.0},
}
const HEAT_RISK := 0.06           # each heat point adds 6% catch chance
const MAX_HEAT := 5
const FINE_PCT := 0.20
const MIN_FINE := 500.0
const JAIL_MINUTES := 180.0       # in-game minutes
const SEIZE_AT_HEAT := 4          # caught at this heat or above -> property seizure

# ---------------------------------------------------------------- endgame
const PROJECTS := {
	"skyscraper": {"name": "Build Your Skyscraper",  "cost": 500_000_000.0,   "prestige": 500,  "desc": "Put your name on the skyline — 120 floors of you."},
	"rocket":     {"name": "Launch a Rocket",        "cost": 800_000_000.0,   "prestige": 800,  "desc": "Starforge pad 39. Next stop: orbit."},
	"global":     {"name": "Go Global (IPO)",        "cost": 1_500_000_000.0, "prestige": 1500, "desc": "Needs 5 businesses at max level. Take your corporation worldwide.", "need_maxed": 5},
	"statue":     {"name": "Golden Statue Downtown", "cost": 2_000_000_000.0, "prestige": 2000, "desc": "Pure flex. Visible from every district."},
}

# ---------------------------------------------------------------- rivals (AI leaderboard)
const RIVALS := [
	{"name": "Victor Vance",      "color": Color("#e8423f"), "rate": 0.23},
	{"name": "Lena Goldsworth",   "color": Color("#f5c542"), "rate": 0.22},
	{"name": "Marco Moneybags",   "color": Color("#58c26b"), "rate": 0.21},
	{"name": "Priya Sterling",    "color": Color("#c47bff"), "rate": 0.215},
	{"name": "Big Tony Bricks",   "color": Color("#f0a030"), "rate": 0.19},
	{"name": "Aiko Tanaka",       "color": Color("#2ec4c4"), "rate": 0.2},
	{"name": "Jules Fontaine",    "color": Color("#4f8cff"), "rate": 0.18},
	{"name": "Cole Hartley",      "color": Color("#9aa7b8"), "rate": 0.17},
]

# ---------------------------------------------------------------- cosmetics (Empire Coins, not pay-to-win)
const SKINS := {
	"default":  {"name": "Orange Hoodie", "color": Color("#ff8a3d"), "cost": 0},
	"gold":     {"name": "Gold Standard", "color": Color("#f5c542"), "cost": 300},
	"neon":     {"name": "Neon Hustler",  "color": Color("#39ff88"), "cost": 250},
	"royal":    {"name": "Royal Purple",  "color": Color("#8e44ff"), "cost": 250},
	"tux":      {"name": "Black Tux",     "color": Color("#1b1f27"), "cost": 400},
	"ruby":     {"name": "Ruby Red",      "color": Color("#e8423f"), "cost": 200},
}
const PAINTS := {
	"factory":  {"name": "Factory Paint", "color": Color(0, 0, 0, 0), "cost": 0},
	"chrome":   {"name": "Chrome",        "color": Color("#dfe6ee"), "cost": 350},
	"matte":    {"name": "Matte Black",   "color": Color("#22252b"), "cost": 300},
	"candy":    {"name": "Candy Pink",    "color": Color("#ff6fb5"), "cost": 300},
	"lime":     {"name": "Toxic Lime",    "color": Color("#a8ff3c"), "cost": 300},
}
const DECOR := {
	"fountain": {"name": "Marble Fountain",    "cost": 200},
	"statue":   {"name": "Gold Lion Statues",  "cost": 300},
	"neon":     {"name": "Neon Signage",       "cost": 150},
	"aquarium": {"name": "Shark Aquarium",     "cost": 450},
}
const PASS_TIERS := 30
const PASS_XP_PER_TIER := 100
const PASS_PREMIUM_COST := 950
const DAILY_COINS := 50
const START_COINS := 200
