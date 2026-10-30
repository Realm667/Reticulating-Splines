# Regions

Choose **Region** above the city name in New City. Single city remains the default.
A region contains 2×2, 3×3, or 4×4 city areas. Its size is fixed. The first city
starts at a random position. Open **Windows → Region overview** to select a city
or preview an unowned area next to your territory. Diagonal contact is not enough.

The preview is the landscape you buy. Reopening a preview does not reroll it.
New areas use the first city's map dimensions, difficulty, and start year, and
begin at the current region date. The generator varies the interior while
matching existing land heights, slopes, rivers, and sea boundaries. The outer
two tile rows preserve these transitions; tools that would change their terrain
or water are rejected without charging money. Trees and construction that keep
the border geometry intact remain possible.

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
