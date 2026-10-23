# Multiplayer

Money Empire uses Godot's high-level multiplayer API over **WebSockets**, so **every version
plays together**: the browser build on GitHub Pages, Windows, Linux, macOS and Android. One server,
up to **100 players**, one shared economy.

## Quick start

| You want to… | Do this |
|---|---|
| Play with friends on the same Wi-Fi | One person on **PC or Android**: Phone → Online → **Host**. Others: Phone → Online → type the host's local IP (e.g. `192.168.1.20`) → **Join**. |
| Play over the internet, including **browser** players | Deploy the free dedicated server (below), then everyone joins its `wss://` address. |
| Send friends a one-click link | `https://jaineil32624.github.io/money-empire/play/?server=wss://YOUR-SERVER` — they press **PLAY ONLINE** and land on your server. |

> **Why browsers need `wss://`:** GitHub Pages is served over https, and browsers refuse insecure
> `ws://` connections from https pages. A hosting platform with HTTPS (like Render below) gives
> your server a `wss://` address automatically. The browser build can't *host*, only join.

## Free public server in one click (Render)

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/jaineil32624/money-empire)

1. Click the button and sign in to Render (free, GitHub login works).
2. It reads `render.yaml` and builds `server/Dockerfile`, which downloads `MoneyEmpireServer.x86_64` from the latest release.
3. When it shows **Live**, copy the URL, e.g. `https://money-empire-server.onrender.com`.
4. Your server address is the same with `wss://`: **`wss://money-empire-server.onrender.com`**.
5. (Optional) Put it in `scripts/net/net.gd` → `OFFICIAL_SERVER` and push — every copy of the game then shows a **JOIN OFFICIAL SERVER** button.

Free Render services sleep after ~15 minutes with nobody connected; the first player to join
wakes it up (~30–60 s). Paid plans (or Railway / Fly.io / Koyeb with the same Dockerfile) stay awake.

## Other ways to run the server

```bash
# From the release (Linux):
./MoneyEmpireServer.x86_64 --headless -- --server --port 7777

# From source:
godot --headless --path . -- --server --port 7777

# Docker:
docker build -t money-empire-server server/ && docker run -p 7777:7777 money-empire-server

# Your own TLS certificate (wss:// without a proxy):
./MoneyEmpireServer.x86_64 --headless -- --server --port 443 --tls-cert fullchain.pem --tls-key privkey.pem
```

The server also honours the `PORT` environment variable. Native clients can join a plain
server by IP (`ws://`), forward **TCP 7777** for internet play.

## What the server owns

| Server-authoritative | Client-side |
|---|---|
| Economy phase, inflation, district markets | Your wallet, businesses, properties (simulated locally) |
| Stock prices & company news | Your position (sent 10×/s) |
| The clock (online games always run at 1×) | Your cosmetics |
| Chat (rate limited, length capped) | |
| Money transfers (validated against your last reported cash) | |
| Corporations & the online leaderboard | |
| Net-worth sanity checks (anti-cheat), 100-player cap | |

Every 5 seconds the server broadcasts the economy snapshot; clients overwrite their local
economy and stock market with it, so a crash hits everyone at the same moment.

## Anti-cheat

- Reported net worth growing faster than `1.5× per second + $2M/s` is rejected and counts as a strike; three strikes → disconnected.
- Transfers are capped and must not exceed the sender's last reported cash.
- Names and chat are sanitized; chat is rate limited.
- Single-player saves are signed (SHA-256 + salt); edited saves are rejected and backed up.

For ranked public servers, move wallets fully server-side (`EmpireSim` is node-free, so the server can run one per player).

## Tested

`--autojoin=ADDRESS` (or `?autojoin=ADDRESS` in the browser build) starts a bot that joins,
chats and sends money. A dedicated server with two native bots and the **web build running in
Chromium** was verified: all saw each other, chat was relayed and transfers settled.

## Protocol summary (`scripts/net/net.gd`)

| RPC | Direction | Mode |
|---|---|---|
| `_register(info)` | client → server | reliable |
| `_sync_players(players)` | server → all | reliable |
| `_push_state(pos, yaw, vehicle, networth, cash)` | client → server | 10 Hz |
| `_world_state(states)` | server → all | 10 Hz |
| `_econ_sync(snapshot)` | server → all | reliable, every 5 s + on join |
| `_chat_req` / `_chat_msg` | client → server → all | reliable |
| `_transfer_req` / `_transfer_done` / `_receive_money` | client → server → both | reliable |
| `_company_req` | client → server | reliable |

Voice chat is on the roadmap.
