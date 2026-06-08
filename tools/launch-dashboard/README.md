# launch-dashboard

Native macOS menu bar app that monitors `~/Library/LaunchAgents/`, auto-restarts
crashed services with exponential backoff, sends crash notifications, and exposes
an authenticated **loopback-only** HTTP API for local control.

> Not part of the standard `~/.dotfiles/install.sh` run — it's an opt-in tool with
> its own installer (`./scripts/install.sh`).

## Install

```bash
cd tools/launch-dashboard
./scripts/install.sh
```

This builds a release binary, assembles a minimal `~/Applications/LaunchDashboard.app`
bundle, and installs a `KeepAlive` LaunchAgent (`com.prebenhafnor.launch-dashboard`)
so it survives reboot. The `.app` bundle gives the process a bundle identifier, which
macOS requires for the crash-notification feature to work.

First-run config lives at
`~/Library/Application Support/LaunchDashboard/config.json` (mode `0600`) and
includes an auto-generated 256-bit bearer token. Read it with:

```bash
jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json"
```

The token is **never** written to logs.

### Uninstall

```bash
launchctl bootout "gui/$(id -u)/com.prebenhafnor.launch-dashboard"
rm -rf "$HOME/Applications/LaunchDashboard.app" \
       "$HOME/Library/LaunchAgents/com.prebenhafnor.launch-dashboard.plist"
```

## HTTP API

Bound to `127.0.0.1:8765` only — **not reachable from the LAN**. All routes require
`Authorization: Bearer <token>`.

| Method | Path                          | Effect                                                   |
|--------|-------------------------------|----------------------------------------------------------|
| GET    | `/services`                   | JSON snapshot of all services                            |
| GET    | `/summary`                    | Priority-service health: `{priorityDown, priorityTotal, priority[]}` |
| POST   | `/services/:label/start`      | bootstrap (if needed) then `launchctl kickstart`         |
| POST   | `/services/:label/stop`       | `launchctl bootout`                                      |
| POST   | `/services/:label/restart`    | `launchctl kickstart -k`                                 |
| POST   | `/services/:label/load`       | `launchctl bootstrap <plist>`                            |
| GET    | `/services/:label/logs`       | Tail of `StandardErrorPath` (16 KB), confined to `~/Library/Logs`, `/tmp`, `/var/log` |

```bash
TOKEN=$(jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json")
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/services | jq '. | length'
```

### Sketchybar health glyph

`/summary` powers an ambient health glyph in the user's sketchybar. The bar item
(`.config/sketchybar/items/launchdash.sh`) and its plugin
(`.config/sketchybar/plugins/launchdash.sh`) curl this endpoint every 5s:

- **Green** check glyph — all priority services running.
- **Red** triangle glyph + count — one or more priority services not running right now.
- **Gray** "?" glyph — the dashboard isn't reachable.

Click the glyph for a popup listing each priority service with a green/red dot.

`priorityDown` counts priority services whose state is not `running` (PID-based —
catches crashes, manual stops, and never-started alike). "Priority" = `config.priorityLabels`
(empty ⇒ all services).

```bash
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/summary | jq
```

Sketchybar config is **copied, not symlinked** — after editing `.config/sketchybar/`,
deploy with `setupfiles/sync.sh` then `sketchybar --reload`.

## Remote access (optional, MUST be behind Cloudflare Access)

The API controls arbitrary LaunchAgents, so it must never be exposed to the public
internet behind only the bearer token. To reach it remotely, put it behind a
Cloudflare Access policy:

1. Add an ingress rule to `~/.dotfiles/.config/cloudflared/config.yml` **above** the
   catch-all `http_status:404`:

   ```yaml
   ingress:
     - hostname: launchpad.prebenhafnor.com
       service: http://127.0.0.1:8765
     # ...existing rules...
     - service: http_status:404
   ```

2. Create the DNS route for the hostname (one-time):

   ```bash
   cloudflared tunnel route dns d21fa304-74b3-41b3-a907-c75e6317cb72 launchpad.prebenhafnor.com
   ```

3. In the Cloudflare Zero Trust dashboard, add an **Access application** for
   `launchpad.prebenhafnor.com` with a policy restricted to your identity
   (email/SSO). Without this, do not publish the hostname.

4. Restart the tunnel:

   ```bash
   launchctl kickstart -k "gui/$(id -u)/com.prebenhafnor.cloudflared"
   ```

The bearer token still guards every request as a second layer.

## Menu bar

The status item shows a gauge icon; clicking it opens a popover listing every
LaunchAgent with a colored status dot:

| Dot    | Meaning      |
|--------|--------------|
| green  | Running      |
| red    | Crashed (crashed since the dashboard started watching) |
| yellow | Stopped (loaded, not running) |
| gray   | Not loaded   |

A badge on the menu-bar icon shows the count of currently-crashed services. The
`⋯` menu on each row offers Load / Start / Stop / Restart as appropriate; failures
surface in a red banner at the top of the popover.

## Prioritizing the services you care about

By default the dashboard treats every LaunchAgent equally. To focus on a few,
set `priorityLabels` in `config.json`:

```bash
CONFIG="$HOME/Library/Application Support/LaunchDashboard/config.json"
jq '.priorityLabels = ["com.nors.ai-daemon","com.prebenhafnor.cloudflared"]' "$CONFIG" \
  > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG" && chmod 600 "$CONFIG"
# then reload:
launchctl kickstart -k "gui/$(id -u)/com.prebenhafnor.launch-dashboard"
```

When `priorityLabels` is set:

- those services are listed **at the top** of the popover;
- everything else collapses under a **"Show more (N)"** disclosure (still fully
  controllable);
- the menu-bar **badge** and **crash notifications** fire **only** for the priority
  services — the rest no longer add alert noise.

Auto-restart stays a safety net across **all** services (it only ever acts on a real
running→crashed transition, never on a manual stop). Leave `priorityLabels` out (or
empty) to treat everything as priority again.

## Inspecting a service (open its URL)

Give a service a clickable URL by adding it to `inspectTargets` in `config.json`:

```bash
CONFIG="$HOME/Library/Application Support/LaunchDashboard/config.json"
jq '.inspectTargets = {"com.nors.ai-daemon": {"public":"https://daemon.prebenhafnor.com","local":"http://localhost:8787"}}' \
  "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG" && chmod 600 "$CONFIG"
```

The row's label turns into a link (globe icon); clicking it opens the **public**
URL. The row's `⋯` menu offers both the public and local URLs.

## Tunnel routes

The popover footer's **"Tunnel routes…"** button opens a window listing the
cloudflared ingress rules from `~/.cloudflared/config.yml`. Each hostname has an
on/off toggle; the catch-all (`http_status:404`) is always on. Toggling a route
comments/uncomments it in the config (written through the dotfiles symlink) and
reloads `com.prebenhafnor.cloudflared`. Changes appear as a git diff in dotfiles —
commit them when you're happy.

## Development

```bash
swift test                  # run unit tests
swift run                   # run interactively in foreground (unbundled: notifications disabled)
swift build -c release      # build the release binary
```
