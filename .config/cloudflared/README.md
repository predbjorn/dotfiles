# Cloudflare Tunnel Configuration

This folder contains the configuration for a named Cloudflare tunnel that exposes local services to the internet securely.

## Tunnel Details

- **Tunnel Name**: `local8000`
- **Tunnel ID**: `d21fa304-74b3-41b3-a907-c75e6317cb72`

`config.yml` is the **single source of truth** for this tunnel's routing. It maps
several hostnames onto local ports:

| Hostname                        | Local service     | Notes                          |
|---------------------------------|-------------------|--------------------------------|
| `daemon.prebenhafnor.com`       | `:8787`           | nors ai-daemon dashboard (always-on) |
| `local3000.prebenhafnor.com`    | `:3000`           | local dev (e.g. tren_web)      |
| `local8000.prebenhafnor.com`    | `:8000`           | local dev                      |
| `local8001.prebenhafnor.com`    | `:8001`           | local dev                      |
| *(anything else)*               | `http_status:404` | catch-all                      |

> ⚠️ **One tunnel, one config.** This single tunnel UUID has two runners (see below).
> They must read the **same** config — never give the tunnel a second config with
> different ingress, or Cloudflare's edge will fan requests across mismatched
> connectors and you'll get intermittent 404s.

## Usage

The tunnel normally runs always-on via the `com.prebenhafnor.cloudflared` launchd job, so you
don't need to start it by hand. To run/inspect it manually:

```bash
cloudflared tunnel run local8000          # uses ~/.cloudflared/config.yml (-> this file)
cloudflared tunnel info local8000
cloudflared tunnel --config ~/.cloudflared/config.yml ingress validate
```

## How It Works

This file is symlinked into **both** consumers of the tunnel during `install.sh`:

1. `~/.cloudflared/config.yml` → the always-on launchd job `com.prebenhafnor.cloudflared`
   and manual `cloudflared tunnel run`
2. `~/.ai-daemon/cloudflared.yml` → legacy alias kept for older ai-daemon references

The launchd plist (`com.prebenhafnor.cloudflared.plist`) now lives here in dotfiles and
is installed/loaded by `install.sh`.

Tunnel credentials are stored separately in
`~/.cloudflared/d21fa304-74b3-41b3-a907-c75e6317cb72.json` (not in dotfiles).
When a runner starts, cloudflared reads this config and establishes a secure
connection to Cloudflare's edge.

After editing this file, restart the always-on runner:

```bash
launchctl kickstart -k gui/$(id -u)/com.prebenhafnor.cloudflared
```

## Benefits Over Quick Tunnels

- **Stable URL**: The URL doesn't change between runs
- **No DNS hijacking issues**: Works even with ISP DNS filtering
- **Better uptime**: Named tunnels have better reliability guarantees
- **Production-ready**: Suitable for long-running services

## Modifying Configuration

To expose a different port, edit `config.yml` and change the service URL:

```yaml
ingress:
  - service: http://localhost:3000 # Change port here
```

To create additional tunnels for other ports, create a new tunnel with:

```bash
cloudflared tunnel create <tunnel-name>
cloudflared tunnel route dns <tunnel-name> <subdomain>.predbjorn.com
```

Then update the config.yml with the new tunnel ID.

# Manage UI:

https://one.dash.cloudflare.com/d0f949f3cd75273ce515ec3815a22a1b/networks/tunnels
