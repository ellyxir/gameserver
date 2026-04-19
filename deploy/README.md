## Setting up SSL

### SSL / reverse proxy (Caddy)

Phoenix listens on `:4000`. Caddy sits in front, terminates TLS with a
Let's Encrypt cert

Reference configs live in [`deploy/`](deploy):

- [`deploy/Caddyfile`](deploy/Caddyfile) — site config (hostname + proxy)
- [`deploy/caddy.service`](deploy/caddy.service) — systemd unit

These configs assume `game.ellyxir.com` but you should change that to
whatever hostname you want to use.

#### One-time setup

1. Install Caddy as root:

   ```
   sudo nix profile install nixpkgs#caddy
   ```

   This puts the binary at `/nix/var/nix/profiles/default/bin/caddy`, which is what
   `deploy/caddy.service` points at.

2. Create the `caddy` user (owns the cert store at `/var/lib/caddy`):

   ```
   sudo useradd --system --home /var/lib/caddy --create-home --shell /usr/sbin/nologin caddy
   ```

3. Install the configs:

   ```
   sudo mkdir -p /etc/caddy
   sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
   sudo cp deploy/caddy.service /etc/systemd/system/caddy.service
   ```

4. Enable and start:

   ```
   sudo systemctl daemon-reload
   sudo systemctl enable --now caddy
   ```

5. Verify — the first request triggers cert issuance:

   ```
   curl -I https://game.ellyxir.com
   sudo systemctl status caddy
   sudo journalctl -u caddy -f
   ```

#### Updating the config

If you edit `deploy/Caddyfile` then do the following:

```
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

`reload` is graceful and shouldnt lead to any  dropped connections.
