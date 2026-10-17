# Direct Internet games directory

Internet games use a direct TCP connection to the host. The directory publishes
connection details and a small amount of lobby metadata; it never transports
city snapshots, building commands, chat or game passwords. LAN-only games are
not published. The host remains authoritative for admission and simulation.

Only the host must forward its selected TCP port (default 20000) to the hosting
computer and allow inbound connections in its firewall. Use the same internal
and external port. Internet hosting needs a reachable public address; CGNAT or
DS-Lite can prevent incoming connections. Players on the host's LAN should use
LAN discovery if their router does not support NAT loopback. Direct connections
use the existing game protocol and password handling, not the directory token.

## PHP deployment

Requires PHP 8.1+ with PDO SQLite, HTTPS and a private writable directory under
the same hosting account. No persistent process, WebSocket proxy or relay is
needed. Keep directory.php, directory_entry.php and directory.sqlite outside the
public document root. Back up the SQLite database; it holds aggregate totals,
short-lived listings and rate-limit counters.

Create a public wrapper that defines DIRECTORY_DB with the absolute private
database path and requires the private directory_entry.php. Route only these
paths to that wrapper, preserving REQUEST_URI and the Authorization header:

- GET /api/multiplayer/v2/games: public host IP, port and lobby metadata.
- GET /api/multiplayer/v2/activity: widget metadata without host IP or port.
- GET /api/multiplayer/v2/health: database/service health.
- PUT /api/multiplayer/v2/games/{32-character hex ID}: create or update.
- DELETE /api/multiplayer/v2/games/{ID}: unlist.

PUT requires JSON {version:2, game:{...}} and an Authorization Bearer token
containing 64 hexadecimal characters. The client generates a fresh ID and token
per hosted session. Only the token's hash is stored. Registration retries are
idempotent while the lease remains alive. The server uses REMOTE_ADDR, never a
client-supplied address or forwarding header. If another trusted proxy is added,
configure authenticated client-IP replacement there before deployment.

Metadata: city, host, build, mode (coop/shared/region), phase (lobby/running),
players (1–8), port (1024–65535), locked and open. Names are at most 64 characters.
Passwords, city data and user rosters are not part of this API.

Hosts update once per minute, or at most every five seconds when metadata changes.
Listings expire after three minutes without a successful update. Expiry and rate
limit cleanup run in short SQLite transactions on requests, so cron is unnecessary.
Limits: 256 listed rooms, four per IP, 12 registration attempts and 120 updates
per IP per minute, 4096-byte request bodies. Failure to list does not close the
host's TCP listener or interrupt players. The client retries after one minute.
Manual direct connections remain available without the directory.

Totals count the first running status of each listed session, sessions today
(UTC), and the peak host-reported player count. Rehosting or registering again
after lease expiry counts as a new session. These are not verified unique people
or completed matches. Preserve existing totals during migration; never silently
reset a damaged database.

## Widget

Existing embeds keep the same script URL:

```html
<div data-rs-activity></div>
<script defer src="https://rs.realm667.com/widgets/activity-v1.js"></script>
```

The script now reads v2/activity once per minute while the page is visible.
Names are inserted as text. The widget shows no IP addresses or passwords.
CMS placeholder fallback and aggregate counters remain supported.

## Validation and compatibility

Run php server/multiplayer/test_directory.php for isolated in-memory database
checks. Run node --test server/multiplayer/test_widget.cjs for the widget.
run_game_test.py --godot PATH --project ISOLATED_PROJECT uses a loopback HTTP
fixture and real game TCP connections with Dummy audio. It checks discovery,
LAN-only hosting, password rejection, city transfer, reconnect, directory failure,
chat and the final city copy. The fixture is test-only, not a production server.

Before deployment, test the configured HTTPS endpoints and forwarded headers.
Actual router forwarding must also be checked from a second Internet connection;
a local TCP test does not prove a user's router configuration.

The historical v1 Python/WebSocket implementation remains in this directory for
regression coverage. It is no longer the default game path or production service.
On rs.realm667.com v1 returns HTTP 410 and the old supervisor is disabled.
Installed v1 clients need an updated Runtime for automatic Internet discovery;
manual TCP joining and LAN continue to work. Updating the Runtime is a separate
release task. Game network protocol and save format are unchanged.
