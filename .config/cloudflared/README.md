# Cloudflare Tunnel Configuration

This folder contains the configuration for a named Cloudflare tunnel that exposes local services to the internet securely.

## Tunnel Details

- **Tunnel Name**: `local8000`
- **Tunnel ID**: `d21fa304-74b3-41b3-a907-c75e6317cb72`
- **Public URL**: `https://local8000.predbjorn.com.prebenhafnor.com`
- **Local Service**: `http://localhost:8000`

## Usage

To start the tunnel, run:

```bash
cloudflared tunnel run local8000
cloudflared tunnel run --url http://localhost:3000 local8000
cloudflared tunnel info local8000
```

This will make your local service at `localhost:8000` accessible via the public URL.
Use --url to override the port or local adress.

## How It Works

1. The `config.yml` file is symlinked to `~/.cloudflared/config.yml` during dotfiles installation
2. Tunnel credentials are stored separately in `~/.cloudflared/d21fa304-74b3-41b3-a907-c75e6317cb72.json`
3. When you run the tunnel, cloudflared reads the config and establishes a secure connection to Cloudflare's edge

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
