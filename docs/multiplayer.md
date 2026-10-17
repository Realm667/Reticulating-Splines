# Multiplayer

Experimental LAN/direct-IP multiplayer supports **Koop**, **Competitive Shared**
and **Competitive Region**, with two to eight players on supported SC2X map sizes.
All participants need the same network build. The host owns the simulation;
clients send commands, never authoritative balances or city files.

## Starting a game

Open Multiplayer from the main menu. Select Host or Join, player name and color.
The host chooses the mode, terrain, land price and optional password. Guests enter
the host address and TCP port (default 20000), or use **Search LAN games**. Select
a result to fill in its address and port, enter its password if required, then
join and create or request a city seat. Search results include both waiting lobbies
and running games, with city, host, mode, connected players and password status.
Full games and different network builds cannot be selected from the list.
A new game begins only after everyone is ready and the host starts it. A lobby
change resets readiness. The host can rename their own city and assign visible
starting handicaps; each player can edit their own city-name cell.

LAN discovery uses IPv4 broadcast queries on UDP ports 20001–20008. Hosts answer
only while hosting; the small port range also permits multiple host processes on
one computer. A search sends three probes over four seconds, closes its socket,
and expires results after 15 seconds. Refresh to find newly opened/closed games.
Closing the dialog, changing to Host or joining cancels the search. Discovery
never bypasses the normal TCP password, version, capacity or seat checks. It does
not advertise passwords, credentials, city data or computer account names.

The host firewall must allow the game's discovery UDP port and chosen TCP port
on the local network. Isolated Wi-Fi clients, routed subnets, IPv6-only networks
or blocked broadcasts may prevent discovery; direct-IP joining remains available.
Older hosts without discovery support can also be reached by direct IP. Discovery
packets have an independent version, bounded sizes, rate limits and a per-search
nonce; responses use the actual sender's address rather than a claimed endpoint.

Starting funds use localized currency formatting. Shared starting territories
have Very small, Small, Medium (standard), Large and Generous presets: 50%, 75%,
100%, 125% and 150% of the map-dependent standard. Custom sizes remain available.
The dialog and lobby show actual land and water counts. Start grants cost no cash.
A water tile counts as half a land equivalent, compensating for less usable land.
Starts cross shorelines, stay connected and favor similar land/water proportions.
Shapes vary; an outer-edge start may touch the map boundary. Unsupported sizes
are reported rather than silently reduced. Region cities have their own whole map.

Shared start sectors retain public access corridors. A contiguous expansion ring
reserves approximately 50% additional area around each start, rounded to complete
outer tile layers and clipped by map edges, other ownership and access protection.
It is an initial reservation, not an automatically expanding claim on every purchase.
Owned borders are strong; reservation borders use a much more transparent player color.

## Simulation and permissions

Only the host changes speed or pauses. Client dialogs, construction drags,
connection interruptions and winner dialogs do not pause the running simulation.
Single-player pause behavior is unchanged. Debug and disasters belong to the host;
client Debug is disabled in both the menu and alternate entry points. Host changes
that affect fairness appear in the shared chat. New text ships in English and German.

Koop players share one city, treasury and decisions. Shared players have independent
municipal accounts, zones and services on one physical terrain. Region players
have separate cities. City visits are strictly read-only: information windows show
the visited city, administrative windows and construction are disabled, and private
owner dialogs are never shown to the visitor. An edge glow and Return to your city
button identify visits. Eye buttons beside progress rows switch views quickly.

Shared infrastructure must stay on owned land, apart from explicitly public road
and power corridors. Adjacent foreign networks do not provide free services.
Intermunicipal supply contracts, cross-border environmental propagation, Shared
Undo and city rotation are not implemented.

## Land market

The land toolbar has Buy and Sell modes plus Include water. Neutral purchases
show the eligible area and price while selecting, then buy without an extra dialog.
Only edge-connected expansion is allowed. Existing ownership, foreign land,
excluded water and protected territory are skipped without charging for them.
The same success sound as zoning confirms a purchase.

Expansion reservations are closed around the starting parcel. They no longer
contain an artificial access corridor. Loading an older match restores empty
corridor cuts inside recorded reservations; existing public infrastructure and
separate public sector boundaries remain intact. Buying another player's reserved
neutral land still requires that player's consent and pays the normal price to
the game. Ownership and edge-connection checks still apply.

Selecting foreign land prepares a purchase request; selecting owned land in Sell
mode prepares an offer. Each has an exact parcel and total price. Incoming requests
show a prominent nonmodal notification with View and remain in the market inbox.
Opening a trade centers and highlights its actual parcel in the running city view,
with direct accept, counteroffer, decline, price-change or withdrawal actions as
appropriate. It never buys simply by viewing. The server rechecks ownership,
connection, seller continuity, complete buildings, balances and offer identity.
A counteroffer creates a new offer identity, invalidating previous acceptance.
Raced/expired transactions charge nothing. The history retains recent outcomes.

## Competition

Competitive games can be endless, or target population or net wealth (cash minus
bank debt and outstanding player debt). New competitions require the target plus
**cumulative sole-leadership time**. The host selects 1, 3, 5 or 10 game years,
with 10 as standard, before starting. One game year is 300 simulation days.
Only the sole ranked leader at or above the target earns time. Ties pause all
clocks; being overtaken or dropping below the target preserves earned time.
The first player to accumulate the required time wins. A leadership decade can
therefore take more than ten calendar years. Older saves retain their continuous
holding rule; their rules are never silently reinterpreted.

The HUD separates the white goal flag from the three-color Statistics button.
Thin rounded bars show player name and actual target values, then leadership
progress. Target fill uses 60% opacity and earned leadership uses full opacity.
Late-founded cities remain unranked; taking over an original seat preserves rank.
The centered victory window has results, fireworks, cheer/music and the shared
chat. Only the host can continue without scoring or propose a rematch. Rematches
rotate starts without reusing a prior start for the same city seat.

Player loans use the game's existing bond rate, selected principal and lender,
with lender consent and no fixed maturity. Banks and players remain separate
creditors during multiplayer; debt counts toward net wealth.

## Communication

Chat is compact and collapsible, can be enlarged upward, preserves drafts across
lobby/game/victory docking, and has unread counts and a brief collapsed preview.
Reading older messages stops automatic scrolling; the new-message button returns
to the newest entry. Names use player colors, system notices are smaller and italic.
A short two-tone chat cue respects local sound and volume settings. Text entry does
not trigger game shortcuts. Remote cursors are precise arrows with compact fading
name tags; construction previews are separate. They appear only in the relevant
city view. Own action sounds remain normal; remote sounds attenuate with distance
outside the visible map. The host synchronizes cosmetic weather/season/time choices.

Build commands receive an immediate authoritative acknowledgement. Consecutive
brush edits share a snapshot publication within 40 ms, and recipient preparation
is spread across frames. The integrated runtime retains its native archive codec;
the GDScript feature branch reuses unchanged compressed members. Statistics
reuse tile counts until the underlying map or ownership changes. Protection masks
use the same checked delta path as city and ownership data. A missing baseline
requests a full state without replaying or charging a completed command again.

Presence messages contain cursor and player identity data, without city statistics.
Stationary cursors use a heartbeat. Weather descriptions travel on changes with a
periodic phase anchor; clouds, particles, lightning and transition animation run
locally. Reliable command order and the authoritative simulation remain on the host.

The capture cache classifies changed raw pages once and reuses their versions for
each recipient. Delta construction and reconstruction run in isolated workers.
Large city displays prepare an immutable document off-thread, retain only the
latest waiting checkpoint, and commit at most one complete transaction per frame.
Separate changed sprite bounds avoid invalidating the space between distant edits.
Commands use the displayed revision; changing city views cannot reuse old targets.

Clients advertise a bounded viewport with an elevation/prefetch margin. Visible
changes, city switches, policy changes, open detail windows and the client's own
actions take priority. Distant city checkpoints have a one-second scheduling
deadline; transport congestion can add delay. Global standings and trade summaries
have a separate coalesced channel. Every city checkpoint remains complete; the
host still simulates all cities and applies every command in order.

State streams use small slices so acknowledgements can pass between them. Control
messages can be handled while a state worker runs. A pending building footprint
appears immediately and stays until the authoritative display catches up, or the
host rejects the action. This preview never spends money or predicts simulation.

## Saves, shutdown and single-player copies

File > Save saves the complete match on the host, including private reconnect
identities. The prior file is retained as .bak. Keep saves and personal profiles
private. Reconnect restores identities and ordered commands. Normal host shutdown
sends a final city copy before disconnecting; clients receive a visible notice with
Save city copy. Canceling or failing a save retains the city for another attempt.
Region exports the client's own city even while visiting another. Unexpected loss
uses the reconnect path, not the deliberate-shutdown dialog.

Opening a multiplayer save offers Continue multiplayer or Open single-player copy.
Koop copies the shared city. Region lets you choose a player's city. Shared composes
the physical map once, adds municipal cash and external bank bonds, and cancels
internal player debts. Host taxes, funding and ordinances become the common policy;
combined population is rebuilt from the map instead of adding overlapping totals.
If combined bank bonds exceed the single-player format's 50 slots, excess principal
is repaid from combined cash, preserving net assets. An unrepresentable combined
cash balance reports an error. Save the result to a new single-player file: the
multiplayer original is preserved and the copy has no active session identity.

## Limits and validation

TCP uses ordered bounded queues and checked streamed snapshots. There is no
Internet discovery, NAT traversal, transport encryption or automatic host migration.
Use trusted participants. Loopback tests do not establish performance on eight
physical LAN computers. Automated audio tests use Dummy audio, not listening tests.
Per-frame work limits apply between messages and recipients; one large archive or
JSON message can still exceed that budget. Batching does not guarantee hitch-free
rendering for every city size or computer.
Run the complete release suite plus native two-window review before distribution.
Tests cover competition/save compatibility, land protections, copy conversion,
shutdown while visiting, client Debug guards, synchronization and private dialogs.
