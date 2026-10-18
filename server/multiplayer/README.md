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

New clients also send optional top-level `cities: [{id, population}, ...]` in
PUT requests (at most eight). Each opaque 64-hex ID derives from the saved
multiplayer session; competitive municipalities also use their saved seat and
round. Co-op counts one city, shared/region modes count each municipality.
Rehosting, renaming and restoring the same multiplayer save keep these IDs;
rematches found new cities. Starting separate games from an ordinary imported
city is a new founding; no content fingerprinting of private save files is used.

Only running games update the persistent activity_cities table. Reports replace
each city's population, including declines and zero, in the existing transaction.
The last accepted report wins, even when two hosts run copies of the same save.
Missing reports, lobby status, expired rooms and unlisting do not erase cities.
Public totals expose cities_founded, total_population and cities_since; IDs and
per-city reports are never exposed by GET endpoints. These host-reported values
are community counters, not verified census data. Existing clients still work
but contribute no city/population data. No offline/single-player tracking or
historical backfill is performed. Old session totals remain unchanged.

## Widget

Existing embeds keep the same script URL:

```html
<div data-rs-activity></div>
<script defer src="https://rs.realm667.com/widgets/activity-v1.js"></script>
```

The script now reads v2/activity once per minute while the page is visible.
Names are inserted as text. The widget shows no IP addresses or passwords.
CMS placeholder fallback and aggregate counters remain supported.
The counters use a two-column table. The reporting explanation floats over the
page when the card is hovered or its information button receives focus. The
button also toggles the explanation on touch devices; Escape or clicking outside
closes it. The explanation does not add height to the card.

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

## Automatic forwarding and reachability

Internet hosts can enable **Automatically forward port (UPnP)**. Discovery and
router requests run in a worker thread. The game requests TCP only, a one-hour
lease, and renews it every 30 minutes. Routers that only allow permanent leases
fall back to manual configuration. LAN-only games never request a mapping.
Existing rules are queried first and preserved. A random description and the
internal address/port identify rules created by this session; only these may be
renewed or removed. Normal leave cleans up; expiry covers process crashes.
The game does not modify the OS firewall. UPnP cannot bypass CGNAT/DS-Lite.

After registration and the UPnP attempt, an authenticated
`POST /api/multiplayer/v2/games/{id}/check` requests one external test. Its body
contains a fresh 64-hex `nonce`. The PHP service connects only to that room's
registered TCP port at the request's observed public IP (which must match the
room). Caller-specified addresses/ports are ignored. No player password, token,
city state or chat is sent through this connection. A length-prefixed JSON
`reachability` frame must receive `reachability_ok` with the same one-time nonce.
The game admits probes separately, even when all player slots are occupied.

Results are `reachable`, `unreachable`, or `unavailable`. A failed HTTP request,
unavailable server socket support or explicit local networking denial is not
reported as a host failure. A timeout alone cannot distinguish host/router
filtering from upstream filtering; it means this check could not reach the host.
The UI offers **Check again**, limited to once per 30 seconds. Server limits are
two probes per source IP/minute and 30/minute globally, with short socket timeouts
and 256-byte response limits. Network I/O runs after the SQLite transaction ends.

Deploy `reachability.php` before the updated `directory_entry.php`, and allow
`games/{32hex}/check` through the same v2 rewrite. Preserve the SQLite database.
Validate outbound TCP from the web PHP context, not only SSH. Tests:
`php test_reachability.php` and the optional three local fixture ports;
`python run_game_test.py --godot PATH --project ISOLATED_PROJECT --script upnp_integration.gd`.
The latter uses a loopback SOAP router and never changes a real router.
