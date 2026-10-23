# Multiplayer

Money Empire uses Godot's high-level multiplayer API over **ENet (UDP)**. One server, up to
**100 players**, one shared economy.

## Ways to play

| Mode | How |
|---|---|
| **Host** (listen server) | Phone → Online → **Host**. You play and serve at the same time. |
| **Join** | Phone → Online → enter the host's IP → **Join**. |
| **Dedicated server** | `./MoneyEmpireServer.x86_64 --headless -- --server --port 7777` (from the release), or from source: `godot --headless --path . -- --server` |

- LAN: join with the host's local IP (e.g. `192.168.1.20`).
- Internet: forward **UDP 7777** on the host's router, or run the dedicated server on a cloud VM (any $5/month Linux box handles 100 players; the server runs no rendering).
- The **browser build can't host or join** — browsers don't allow raw UDP. A WebSocket/WebRTC transport is on the roadmap.

## What the server owns

| Server-authoritative | Client-side |
|---|---|
| Economy phase, inflation, district markets | Your wallet, businesses, properties (simulated locally) |
| Stock prices & company news | Your position (sent 10×/s) |
| The clock (online games always run at 1×) | Your cosmetics |
| Chat (rate limited, length capped) | |
| Money transfers (validated against your last reported cash) | |
| Corporations & the online leaderboard | |
| Net-worth sanity checks (anti-cheat) | |

Every 5 seconds the server broadcasts the economy snapshot; clients overwrite their local
economy and stock market with it, so a crash hits everyone at the same moment.

## Anti-cheat

- The server tracks each player's reported net worth over time. Growth faster than
  `1.5× per second + $2M/s` is rejected (the old value is kept) and counts as a strike.
  Three strikes → disconnected.
- Transfers are capped and must not exceed the sender's last reported cash.
- Names and chat are sanitized; chat is rate limited.
- Single-player saves are signed (SHA-256 with a salt). Edited saves are rejected and backed up.

This stops casual cheating. For a competitive public release, move wallets fully server-side
(the `EmpireSim` class is already node-free, so the server can run one per player).

## Trading & teams

- **Send money:** Phone → Online → pick an amount → **Send** on a player row.
- **Corporations:** Phone → Empire → type a name → **Form / Join**. Everyone using the same
  name is on the same team; the Leaderboard tab shows a corporate ranking.

## Voice chat

Not in v0.1. Planned: Steam Voice on Steam builds and WebRTC elsewhere, with proximity audio.
Text chat works now (press **T**).

## Protocol summary (`scripts/net/net.gd`)

| RPC | Direction | Mode |
|---|---|---|
| `_register(info)` | client → server | reliable |
| `_sync_players(players)` | server → all | reliable |
| `_push_state(pos, yaw, vehicle, networth, cash)` | client → server | unreliable ordered, 10 Hz |
| `_world_state(states)` | server → all | unreliable ordered, 10 Hz |
| `_econ_sync(snapshot)` | server → all | reliable, every 5 s + on join |
| `_chat_req` / `_chat_msg` | client → server → all | reliable |
| `_transfer_req` / `_transfer_done` / `_receive_money` | client → server → both | reliable |
| `_company_req` | client → server | reliable |
