# Godot integration guide

Money Empire is a plain **Godot 4.3** project — no plugins, no imported art, no external audio.
Everything (city, vehicles, UI, music) is generated from GDScript at runtime.

## Open it in the editor

1. Install **Godot 4.3 (standard, not .NET)** from <https://godotengine.org/download>.
2. Clone the repo: `git clone https://github.com/jaineil32624/money-empire`
3. Godot → **Import** → pick `money-empire/project.godot` → **Import & Edit**.
4. Press **F5**. The title screen shows the live city; click **NEW GAME**.

## Project layout

```
project.godot              renderer = GL Compatibility (desktop + web + Android)
scenes/main.tscn           single scene; scripts/main.gd builds everything
scripts/
  core/
    catalog.gd             ALL game data & balance (jobs, businesses, properties, vehicles, stocks, crime, cosmetics)
    empire_sim.gd          the whole simulation as pure logic (no nodes) — used by game, server and tests
    economy.gd             boom / stable / recession / crash, inflation, district property indexes
    stock_market.gd        hourly geometric random walk + company news
    game.gd     (autoload) owns the running sim, clock, save/load, settings, input map
    save_util.gd           signed save files
    sfx.gd      (autoload) synthesized SFX + lo-fi music loop
  net/net.gd    (autoload) ENet multiplayer: host / join / dedicated server, chat, trades, anti-cheat
  world/
    city.gd                procedural city, markers, traffic, pedestrians, day/night, endgame buildings, your mansion
    player.gd              third-person controller, vehicles, helicopter flight, camera rig
    world.gd               interaction, job missions, online avatars
  ui/
    hud.gd  phone.gd  title.gd  widgets.gd  ui_kit.gd
tests/
  run_tests.gd             418 unit assertions
  smoke_sim.gd             balance bot — must reach $1B within 120 game days
tools/make_art.py          icon / store graphics / social preview (headless Chromium)
export_presets.cfg         Windows, Linux, Web, Android APK, Android AAB, macOS, iOS, Linux dedicated server
```

## Architecture in one paragraph

`EmpireSim` is a `RefCounted` with zero scene dependencies, so the exact same economy code runs
in the game, on the dedicated server, and in headless tests. The `Game` autoload advances it
(`DAY_SECONDS = 180` real seconds per in-game day at 1×) and re-emits its signals. The world
and UI only read from `Game.sim` and call its action methods, which all return
`{ok, msg}` so the UI can toast + play a sound uniformly. Online, the server overwrites each
client's economy/market/clock every 5 s, so everyone shares one boom-and-bust cycle.

## Tuning the game

Open `scripts/core/catalog.gd`. Every price, income, payback, risk and reward is there.
After changing numbers run the balance bot:

```bash
godot --headless --path . -s tests/smoke_sim.gd
```

It prints the day the bot reaches $1K, $1M and $1B for three seeds and fails CI if $1B takes
more than 120 game days.

## Running tests

```bash
godot --headless --editor --quit --path .        # first time only: import
godot --headless --path . -s tests/run_tests.gd   # unit tests
godot --headless --path . -s tests/smoke_sim.gd   # balance simulation
```

## Exporting

Install export templates (Editor → Manage Export Templates), then:

```bash
godot --headless --path . --export-release "Windows Desktop" builds/windows/MoneyEmpire.exe
godot --headless --path . --export-release "Linux" builds/linux/MoneyEmpire.x86_64
godot --headless --path . --export-release "Web" builds/web/index.html
godot --headless --path . --export-release "Android" builds/android/MoneyEmpire.apk
godot --headless --path . --export-release "Linux Dedicated Server" builds/server/MoneyEmpireServer.x86_64
```

Android needs the Android SDK + a keystore configured in Editor Settings (CI generates a debug
keystore automatically — see `.github/workflows/ci.yml`). For Google Play use the
**Android AAB (Play Store)** preset with your own upload key.

## Screenshots & store art

```bash
godot --path . -- --tour=docs/screenshots   # plays a scripted camera tour and saves 15 PNGs
python3 tools/make_art.py                   # icon, Play Store graphic, Steam capsule, social preview
```

## Extending

- **New business / property / vehicle:** add a row to the arrays in `catalog.gd`. The phone UI lists it automatically.
- **New job type:** add to `JOBS` with an existing `kind` (`deliver`, `hold`, `patches`, `carry`) or add a new kind in `world.gd → start_job / _job_tick`.
- **New map landmark:** add a cell to `_reserved_cells()` and a builder case in `_landmark()` in `city.gd`; add a marker in `_place_markers()`.
- **Real 3D models:** drop `.glb` files in `assets/models/` and replace the primitive builders in `player.gd → build_vehicle_mesh` / `city.gd`.
