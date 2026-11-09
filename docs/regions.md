# Regions

Choose the **Expanded** tab, then **Region (Expanded)** above the city name in
New City. Single city remains the default. New regions require Expanded, including
new multiplayer region campaigns. Existing regional saves retain their stored rules.
A region contains 2×2, 3×3, or 4×4 city areas. Its size is fixed. The first city
starts at a random position. Open **Windows → Region overview** to select a city
or preview an unowned area next to your territory. Diagonal contact is not enough.

The overview and its small sidebar version use the same isometric projection
including the active city's compass rotation. Owned areas have a green outline
in single-player and their owner's color in Competitive Region. The viewed area
also has a translucent fill and a thicker
outline; hovering strengthens an area's outline. Click an owned area in the
sidebar to switch directly. Only existing positions within the fixed grid can
be purchased.

**Region overview** now also contains the previous **Neighbors** information:
the viewed city's population (including arcologies), national population, and
the four neighboring names and populations. Direction arrows follow the map's
rotation. Existing Neighbors key bindings open this same overview. A single
city uses a five-area diagram and offers **Create a region** explicitly; opening
the overview does not convert a save. **Create a region** requires Expanded;
switch an existing Classic city through **Options → Classic / Expanded** first.

Competitive Region uses the same grid in the overview and sidebar, including
older games without region expansion. Those games show occupied starting slots
only, not purchasable city areas. Select a player city for its name, population,
player and connection status. **Visit city** opens that player's currently active
city read-only; inactive rival areas remain informational. **Return to your city**
restores the local player's view. The thick outline follows the city being
viewed. Visits do not expose the owner's dialogs or private archived documents.

Region cells activate on release. Dragging, leaving the control or losing focus
cancels the pending click. Enter/Space can activate the keyboard selection.

Other owned areas appear around the live map as lightly blurred grayscale static
views with a 16-tile gap between adjacent city areas. Settings > UI > Show
surrounding city areas hides or restores these views; the choice is saved and
defaults to enabled. The overview and sidebar region map remain available.
The surrounding views have 33% opacity. Hovering raises opacity to 66% over one real-time second;
leaving fades back to 33%. Click a view to open that city. Once its live graphics
are ready, it fades into the real city over one second while the city being left
fades to a gray, softened 33% view. These bounded background renders do not
run another city's simulation or animations. They refresh when you change city
or map orientation, and when visual settings change. Stills retain the active
lighting, seasons, environment and water effects. The incoming still gains its
full color before the prepared live city is revealed; transparent margins keep
the normal map background during the transition.
Multiplayer retrieves these snapshots only for the requesting
player's own areas; they are not broadcast with per-frame public summaries.
Nearby areas are prepared before distant ones. Switching cancels obsolete work
without waiting for it on the UI thread; finished canceled results are discarded.
Only one preview worker runs at a time. A rejected or unanswered multiplayer
preview request does not block the remaining queue; late replies cannot publish
into a newer request. The preview timeout does not cancel a gameplay command.
Regional entry prepares the selected zoom/traffic view first. Other views use
the existing on-demand preparation when selected, retaining completed banks.
Switch previews use isolated copies of both cities, including their saved view
orientations. Only frozen views use the blur/grayscale shader; the active city
and sidebar outlines retain their original graphics. Transitions use real time
even when the game is paused, and tools cannot place tiles during a city switch.

The preview is the landscape you buy. Reopening a preview does not reroll it.
New areas use the first city's map dimensions, difficulty, and start year, and
begin at the current region date. The generator varies the interior while
matching existing land heights, slopes, rivers, and sea boundaries. The outer
two tile rows preserve these transitions; tools that would change their terrain
or water are rejected without charging money. Trees and construction that keep
the border geometry intact remain possible.

New areas use the normal generator's layouts, compatible feature combinations,
hill/water/tree controls and independent random streams. Generation is stable
for a given regional cell. Water continues through actual basins and channels
below the connected water level; variable coast reach avoids a fixed-width water
strip. Existing city edges and saved offers are preserved. Legacy surface water
at height zero cannot receive a lower bed because the format has no negative
land heights; those existing border tiles are retained. During generation, an
inland lake opened into a lower body of water drains to that body's level,
exposing ground above it. Closed lakes retain their own levels. This prevents
cracks between different surface heights in one connected body; existing city
edges and archived terrain are not rewritten.

## Purchase and administration

The reference price is $12,000 for a flat 128×128 area. Dry slopes cost 55% of
flat land and water costs 25%; larger maps scale with their tile count. Water
over a slope counts as water only. Trees and absolute elevation do not alter
the price. These are the first balancing values, not a promise of equal economic
value for every terrain shape.

Each additional area costs **$1,200 per game year** in administration, including
empty areas. The first city is exempt. Fees accrue from the purchase date and
appear as **Regional administration** in that city's budget. The year-end
forecast accounts for fees already paid without deducting them twice.

A purchase requires enough own cash after outstanding bonds and accrued budget
deficits to pay the land price and retain one full year of administration costs
for all additional areas. The reserve remains spendable cash; it is not a second
purchase charge. Borrowing therefore does not increase purchasing power.

City budgets and debts remain separate. Available cash from your cities is
consolidated into the city you are playing, exactly once. A new city receives no
starting-money grant or new starting loan. Inactive cities retain their buildings
and population; their existing monthly budgets and administration continue.
They do not run hidden growth, traffic, or development simulations.

## Connections and saves

Regional neighbors use actual city names and population. Road, rail, and highway
bonuses require matching connections of the same network type at corresponding
positions on both sides. Unsettled areas and the outer region boundary provide
no invented city connection bonus. Power and water trading, commuters, and a
regional goods simulation are not included.

An unmatched road, rail or highway endpoint adds a sign at the corresponding
position in the other city, naming the source and network type. Connecting the
matching network removes that pending-connection hint. Hints do not place roads,
charge money or grant a connection bonus themselves.

Regions save as SC2X archives containing their cities, fixed offers, terrain
reference, ownership, calendar, and administration state. A manual save keeps
the previous save as a backup. Purchases and city switches are validated before
the live state changes. Saving a complete region as a legacy single-city file
is rejected rather than silently discarding its other cities.

An existing single-player city can become the first city of a new region from
Region overview. A separate backup is created first. Other existing cities
cannot be imported into that region. Multiplayer sessions must be resumed through
the multiplayer continuation lobby.

## Competitive Region

The host can enable **Buy additional city areas** when creating a Competitive
Region game. It is off by default and is not offered for Coop or Competitive
Shared. The setting is fixed after the game starts.

| Raster | Areas | Maximum players |
| --- | ---: | ---: |
| 2×2 | 4 | 2 |
| 3×3 | 9 | 3 |
| 4×4 | 16 | 4 |

Starting positions maximize the minimum distance between players, then the sum
of their distances. Equivalent layouts and player assignments are randomized.
Each player buys from their own combined treasury. The host validates ownership,
the displayed offer, the financial reserve, and competing purchases. The same
area cannot be bought twice. Scores aggregate the player's own cities.

Active cities advance together, at most one day apart. Administration and inactive
budgets settle only after every active city has completed that region day. An
open annual budget or ongoing disaster therefore cannot skip another city's day
or trigger an early timed victory. A city switch waits for the shared date.

Foreign city visits are read-only and do not transmit private regional archives
or budget administration records. Continuing a game preserves all owned areas.
Exporting your position to single-player keeps all your own city areas in a
region and excludes other players' cities. The Multiplayer category in Tips &
Knowledge explains the applicable rules; tips for disabled features are hidden.
