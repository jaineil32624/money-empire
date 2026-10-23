# Monetization plan — cosmetic only, never pay-to-win

**Rule:** nothing you can buy with real money changes cash, income, speed, risk or rank.
The leaderboard has to mean something, or the game isn't worth sharing.

## What's in the build now (no real payments)

| System | Status |
|---|---|
| Empire Coins (soft currency) | ✅ earned from milestones (+25 each), the daily reward (+50) and the Season Pass |
| Character skins (6) | ✅ |
| Car paints (5) — visible on your car and in your mansion garage | ✅ |
| Mansion decor (4) | ✅ |
| Season 1 "Gold Rush" pass — 30 tiers, free + premium tracks, XP from jobs/purchases | ✅ |
| Real-money store | ❌ intentionally disabled in v0.1 |

A unit test enforces the rule: buying cosmetics never touches `cash`.

## Planned store (when publishing)

| Item | Price idea | Notes |
|---|---|---|
| Coin packs | $0.99 – $19.99 | coins only buy cosmetics |
| Premium Season Pass | $4.99 / season | cosmetic rewards, seasonal themes |
| VIP house skin | $2.99 | a different look for *your* mansion, same value |
| Supporter pack | $9.99 | exclusive skin + paint + name color |

Platforms:
- **Google Play:** Play Billing via the [GodotGooglePlayBilling](https://github.com/godot-sdk-integrations/godot-google-play-billing) plugin; requires the AAB preset and a real upload key.
- **Steam:** Steam Microtransactions or DLC via GodotSteam (see `STEAM.md`).
- **iOS:** StoreKit via the official Godot iOS in-app-purchase plugin.

## Seasonal events (live-ops ideas)

- **Market Mayhem week:** crash chance ×3, double coins for anyone who ends the week richer than they started.
- **Housing Boom:** real-estate index +30%, flipping challenge leaderboard.
- **Billionaire Sprint:** fresh-start server, first to $1B gets an exclusive trophy for their mansion.

## Store-policy notes

- Crime is optional and cartoonish; content rating will likely be **Teen** (ESRB) / **PEGI 12**.
- Loot boxes are deliberately **not** used (regulated in several countries).
