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
| POST   | `/services/:label/start`      | bootstrap (if needed) then `launchctl kickstart`         |
| POST   | `/services/:label/stop`       | `launchctl bootout`                                      |
| POST   | `/services/:label/restart`    | `launchctl kickstart -k`                                 |
| POST   | `/services/:label/load`       | `launchctl bootstrap <plist>`                            |
| GET    | `/services/:label/logs`       | Tail of `StandardErrorPath` (16 KB), confined to `~/Library/Logs`, `/tmp`, `/var/log` |

```bash
TOKEN=$(jq -r .bearerToken "$HOME/Library/Application Support/LaunchDashboard/config.json")
curl -sS -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8765/services | jq '. | length'
```

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
   launchctl kickstart -k "gui/$(id -u)/com.nors.cloudflared"
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
jq '.priorityLabels = ["com.nors.ai-daemon","com.nors.cloudflared"]' "$CONFIG" \
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

## Development

```bash
swift test                  # run unit tests
swift run                   # run interactively in foreground (unbundled: notifications disabled)
swift build -c release      # build the release binary
```
