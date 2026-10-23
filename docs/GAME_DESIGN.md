# Money Empire — game design

## Pitch
*Start homeless with $100. Become the first billionaire.* A social money sim: GTA-style city,
Roblox-tycoon progression, Monopoly investing, Sims-style mansions, online leaderboards.
Built to be shown off — your mansion, your hypercar, your name on the skyline.

## Pillars
1. **Every dollar has a job.** Cash is always better spent than held — except right before a crash.
2. **Visible wealth.** Progress shows up in the world: vehicles, your mansion, endgame buildings, your rank.
3. **Shared fate.** Online, everyone lives through the same boom and the same crash.
4. **Fair race.** Money can't be bought. Cosmetics only.

## Core loop
```
work jobs ──► buy business ──► passive income ──► upgrade / hire ──► bigger business
    │                                  │
    └──► home (+10% pay) ◄── real estate ◄── stocks (time the cycle) ◄─┘
                                       │
                         $1B ──► mega-projects ──► $1T race
```

## Pacing (verified by `tests/smoke_sim.gd`)
| Milestone | Simple bot | Notes |
|---|---|---|
| $1,000 | day 3 | ~10 real minutes |
| $1,000,000 | day 33–42 | ~2 hours at 1×, 30 min at 4× |
| $1,000,000,000 | day 94–106 | ~5 hours at 1×; skilled players faster |

One in-game day = 180 real seconds at 1×. Business payback: 4 days (tier 1) → 8.5 days (tier 5).
Upgrades cost `price × 0.4 × level` for +50% base income. Workers: +10% income for 3.5% salary.

## Economy model
- **Phases:** Markov chain, minimum 3 days per phase. Boom ×1.25 income, Recession ×0.8, Crash ×0.6.
- **Inflation:** 0–5%/year by phase over a 60-day year; raises prices, wages, rents and incomes alike.
- **Property:** per-district index, random walk + phase drift + mean reversion; renovation +25% value.
- **Stocks:** hourly GBM, drift = phase drift × sector beta; 18% daily chance of company news (±6–20%).

## Risk systems
Crime catch chance = base risk + 6% × heat. Caught: 20% cash fine (min $500), 3 in-game hours of
jail, heat reset. At heat ≥ 4 the police seize your cheapest property. Heat cools 1/day.

## Rivals
8 AI tycoons grow at 10–13.5%/day scaled by the economy and slowed by log(net worth), so they
reach a billion in the same ballpark as a good player. Online players join the same board.

## Roadmap
VR mode (OpenXR), voice chat, server-side wallets for ranked servers, WebSocket transport for
the browser build, Steamworks, building interiors, seasonal events.
