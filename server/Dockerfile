# Money Empire dedicated server (WebSocket, up to 100 players).
# Pulls the headless server binary from the latest GitHub release.
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ARG RELEASE_URL=https://github.com/jaineil32624/money-empire/releases/latest/download/MoneyEmpireServer.x86_64
RUN curl -fsSL -o MoneyEmpireServer "$RELEASE_URL" && chmod +x MoneyEmpireServer
# Hosting platforms (Render, Railway, Fly, Koyeb...) inject $PORT and put TLS in front,
# which is what gives browsers the secure wss:// address they need.
ENV PORT=7777
EXPOSE 7777
CMD ["sh", "-c", "./MoneyEmpireServer --headless -- --server --port ${PORT}"]
