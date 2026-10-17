# Internet games service

This service provides the public game list, a binary WebSocket relay, and the
activity widget. It runs continuously. **FTP/PHP shared webspace alone cannot run
the relay.** Keep the existing website at its current host and run this service
on a VPS or a provider-approved application server if needed.

## Deployment prerequisites

- Linux with Python 3.12+, a service account and systemd (or an equivalent supervisor).
- SSH access for that service account and permission to install the service and
  configure the reverse proxy. Use an SSH key; never put credentials in source.
- A DNS name with a valid public TLS certificate. Public HTTPS/WSS port 443;
  the Python process listens only on loopback port 8787.
- Reverse proxy supporting WebSocket upgrades and connections lasting longer
  than 60 seconds. Forward `X-Real-IP` by replacing any client-supplied value.
- A bandwidth allocation suitable for relayed city snapshots. Measure actual
  usage before choosing production capacity; the server does not simulate cities.

The default game endpoint is `https://rs.realm667.com`. If the website host cannot
proxy the API, use a separate DNS name for the service and update
`MultiplayerOnline.DEFAULT_URL` before delivery. Do not replace the website's DNS
record with the relay address. `RS_MULTIPLAYER_URL` can override the endpoint for
development; only HTTPS or explicit loopback HTTP is allowed.

Install from this directory:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m unittest -v test_server
.venv/bin/python server.py
```

For the end-to-end game test, first prepare an imported game project with built
native libraries and a disposable user profile. Then run:

```sh
.venv/bin/python run_game_test.py --godot /path/to/godot --project /path/to/isolated/game
```

This starts a temporary loopback service and checks discovery, LAN-only hosting,
automatic publication, password rejection, city transfer, reconnect, chat and the
final city copy. It uses Dummy audio and never contacts the production endpoint.

Example systemd unit (adjust the installation directory):

```ini
[Unit]
Description=Reticulating Splines multiplayer directory and relay
After=network.target

[Service]
User=rs-multiplayer
WorkingDirectory=/opt/rs-multiplayer
ExecStart=/opt/rs-multiplayer/.venv/bin/python server.py
Environment=TRUST_PROXY=127.0.0.1,::1
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
MemoryMax=512M
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
```

Add these locations to the existing TLS virtual host, retaining its other routes:

```nginx
location /api/multiplayer/v1/ {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header X-Real-IP $remote_addr;
    proxy_read_timeout 90s;
    proxy_send_timeout 90s;
    proxy_buffering off;
    access_log off;
}
location /widgets/ {
    proxy_pass http://127.0.0.1:8787;
    proxy_set_header X-Real-IP $remote_addr;
}
```

Only configure `TRUST_PROXY` for the actual proxy's source addresses. Exposing
port 8787 publicly would bypass TLS. HTTPS protects discovery and WSS protects
both relay hops; this is not end-to-end encryption against the relay operator.
The service never logs packet bodies, passwords or bearer headers. Apply normal
TLS renewal, monitoring and proxy-level request/connection limits in production.

## Widget

Add this to a Nicepage custom HTML block; use the actual service domain if separate:

```html
<div data-rs-activity></div>
<script defer src="https://rs.realm667.com/widgets/activity-v1.js"></script>
```

It inherits the page's text color and shows public games only. It refreshes every
30 seconds while the page is visible. Names are inserted as text, never HTML.
No player IPs, participant rosters, passwords or LAN games are published. A failed
request displays unavailability, not a misleading zero-player count.

## Protocol and limits

- `GET /api/multiplayer/v1/games`: versioned public metadata, cached for five seconds.
- `WSS /api/multiplayer/v1/host`: register with `{version:1, game:{...}}`;
  returns a random room ID and per-room bearer token. Update metadata every 20s.
- `WSS /api/multiplayer/v1/join/{room}`: asks that host to attach a new peer.
- `WSS /api/multiplayer/v1/host/{room}/{peer}`: bearer-authenticated host attachment.
- Both peers receive a `ready` text frame, then exchange only binary chunks up to
  64 KiB, retaining the game's normal framing and host-side admission checks.
- `unlist` immediately hides a retiring session while final city copies drain.
  Loss of the host control connection removes the room and closes its relay peers.
- 60s registration lease, 256 rooms, four rooms per source IP, seven relay peers
  per room, bounded registration/update/join rates, ten-second pairing/write limits.
- Limits count pending connections too. Slow clients get backpressure independently;
  no unbounded application message queue or persistent city storage exists.

Restarting this service interrupts relay games. LAN/direct connections are
independent. No accounts or durable database are required. Public player counts
are host-reported session participants, not verified unique people.

Before public activation: test the configured TLS proxy from two separate external
networks, including CGNAT, password rejection, reconnect, host shutdown/final city
copy, several rooms and large snapshots. Local tests do not prove hosting reachability.
