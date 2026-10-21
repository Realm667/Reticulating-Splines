# Tips & Knowledge

This optional, local help feature offers short entries about city planning and individual buildings, a searchable window
under Help, and a read-only growth check from the query tool. It does not create
tutorial tasks or modify city data, game speed, random state, or multiplayer rules.

## Presentation and preferences

One card appears at the lower right, or at the upper right if selected. Cards
stay readable for 45 seconds; pinning, hovering and keyboard focus suspend expiry.
Existing dialogs and photo mode hide them. The same catalog supplies new-city,
loading and in-game text; loading is never delayed to make a tip readable.
Long explanations scroll inside the card. Actions open an existing view or report, or explicitly locate a known disaster. No action builds or spends money; merely showing a card never moves the camera.

Preferences are stored beside the local settings file as `.knowledge.cfg`:
off, start/loading only, or also during play (default); position; hidden topic
IDs. Help remains available when automatic tips are off. City changes discard
diagnoses and recent context. No city save-format or network protocol change.

## Context selection

`KnowledgeRules` consumes successful, complete phase results. It never runs a
second simulation or scans the whole city. Ordinary cards are separated by
180 seconds of active play; the same topic waits at least 540 seconds.
Unrefreshed candidates expire after 180 seconds. Document revisions invalidate
pending diagnoses after edits, so the next relevant phase must confirm them.

| Family | Evidence | Exclusions |
| --- | --- | --- |
| Power | Two complete phases with consumers greater than supplied consumers | Usage percentage alone; partial phases |
| Water | Two complete phases with consumers greater than watered consumers | Capacity or pipe presence alone; partial phases |
| Growth | Three complete RCI scans with RCI tiles and no starts, completions or population additions | No promise of a particular cause; defer behind supply problems |
| Budget | Two completed budget phases with negative `BudgetReport.estimated_cash` | Cash spent is not a forecast deficit |
| Plant age | Confirmed annual expired-plant records | No invented fixed explosion date |
| Unlock | Confirmed invention, reward or military proposal | No prediction based only on year/population |
| Disaster | Confirmed disaster event | Existing notices/newspaper/game-over reports take priority |
| Scenario | Active, unmet actual scenario goals within its final 12 months | No universal scenario goal or invented deadline |

Multiplayer uses only applied host state. Current host summaries do not contain
complete utility phase counts; the client therefore does not fabricate automatic
power, water or growth diagnoses. Catalog browsing and query inspection remain
available. Confirmed disaster completion can offer recovery knowledge. Region
visits do not use the player's own disaster to diagnose the visited city.

## Local growth inspection

The existing native `growth_inputs` query supplies power, local transport,
demand, density and applicable land-value thresholds. The query does not use
the simulation's random trip search. Destination reachability is explicitly
**Not checked**, as is local transport where the native input calculation did
not perform that check. A non-anchor tile is not diagnosed as an isolated
building. Thresholds are not generalized from residential/commercial to industry.
Results are a snapshot, not a guarantee of construction on the next visit.

The separate `industry` card explains industrial startup: power and
transport connections to a reachable residential **or** commercial zone.
Commerce is not a mandatory unlock; the trip destination check uses zone type,
not whether the destination already has buildings. This is conditional advice,
not a diagnosis that industry is stalled. It is available after choosing industrial zoning, in the loading rotation and in the searchable catalog, with no additional city scan.
Evidence: `trip.rs` (`DESTINATION_ZONE_MASKS`, `has_walking_destination`) and
`growth/mod.rs` (`process_rci_tile`, `record_trip`, `try_advance_density`).

## Editorial provenance

All displayed prose is authored paraphrase, not copied guide text. Historical
guides supplied topics and questions; the current RS implementation determines
which claims can ship. This feature was AI-assisted and reviewed against these
existing code paths. Detailed research notes are maintained in the workspace.

| Catalog IDs | RS rule/report evidence |
| --- | --- |
| start, demand, vacant, density, time | `native/core/sim/src/sim/growth/demand.rs`, `growth/inputs.rs`, published `GrowthResult` |
| power, plants, age | `infrastructure/power.rs`, `civic/annual.rs`, power menu availability and plant queries |
| water, pumps, waterworks | `infrastructure/water.rs`, published `WaterPhase.Result` |
| access, networks, traffic | Existing transport/trip rules, traffic maps, budget maintenance |
| value, environment | `growth/inputs.rs`, existing land-value, pollution and crime maps |
| services, education | Existing service coverage, `civic/education.rs`, population graphs |
| budget, bonds, ordinances | `economy/budget.rs`, `economy/ordinances.rs`, `BudgetReport` and bond commands |
| limits | `growth/demand.rs` capacity and outside-connection calculations |
| unlock, recovery | Published milestone, invention, disaster and scenario results |

Primary research: [Sixfortyfive's guide, v1.2](https://gamefaqs.gamespot.com/pc/198648-simcity-2000/faqs/81608)
(primarily Windows 95 Special Edition observations), the
[SimCity 2000 manual](https://archive.org/details/sc2000_manual), and selected
sections of [Power, Politics, and Planning](https://archive.org/details/sim-city-2000-power-politics-and-planning-revised-edition-strategy-guide).
Additional player perspectives: [Somacon](https://www.somacon.com/p606.php),
[Kerstin's solutions](https://www.kerstins-spieleloesungen.de/loesungen/sim.htm),
and the [author's Reddit discussion](https://www.reddit.com/r/SimCity/comments/1h3kjko/deconstructing_simcity_2000_an_exhaustive_look/).
Related guides were treated as historical corroboration, not independent proof
of RS behavior. StrategyWiki was excluded as requested.

Do not add fixed zone ratios, guaranteed development dates, original-game
exploits, or exact statistical effects without checking their RS implementation.
Keep new translations in all seven central catalogs and extend behavioral tests
when adding a trigger or diagnosis.


## October 2026 follow-up

Cards display their complete short explanation without an expand/collapse button.
The library has no view action or inner close button. In-game cards allow 45 seconds
of reading time; hovering, keyboard focus and pinning suspend expiry. Ordinary
edits clear pending diagnoses and withdraw the current diagnostic heading/action,
but retain the readable general advice and pin. Complete later phases can confirm
the condition again. No simulation call is added to the frame loop.

Disaster and scenario guidance are separate entries. Disaster actions use the
existing read-only focus query on presentation/click, or the recorded event point
from this city, transformed for the current rotation. No known point means no
navigation action. City changes discard the point; MP summaries without a host
location do not invent one. Opening a card never moves the camera.

The expanded catalog consolidates the requested building advice rather than
repeating the same facts in multiple entries. Tool selection offers relevant
general knowledge after three seconds, at low priority and at most once per topic
per city session. Existing cooldowns and muting apply. It does not diagnose a
shortage from tool selection. All entries are searchable and available while loading.

Reviewed native sources: `sim/growth/inputs.rs`, `sim/growth/development.rs`,
`sim/trip.rs`, power and water phases, annual microsimulation, demand caps,
service funding, land-value and pollution phases. Industry accepts residential OR
commercial destinations, including a zoned empty destination; no employment or
goods economy is inferred. Local transport searches the Manhattan-distance-three
offsets, not a square radius. Three rows beside a straight road (six between two
roads) describe local access, not guaranteed growth. The separate full route still
matters. Mature-building local access is explicitly untested by the growth query.

Power guidance describes relative costs/output and environmental trade-offs,
without presenting published megawatt labels as the simulation's consumer units.
Hydro/wind do not use the large-plant aging cycle. Pump fresh-water adjacency,
desalination salt-water intake, tower storage, rainfall reserve, service funding,
education/health over time, recovery from abandonment and conditional growth caps
follow the implemented rules. Original walkthroughs are context, not authority for
mechanics absent from this fork. No new simulation, RNG, save or multiplayer rules.
