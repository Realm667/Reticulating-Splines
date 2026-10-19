# Tips & Knowledge

This optional, local help feature offers 24 short entries, a searchable window
under Help, and a read-only growth check from the query tool. It does not create
tutorial tasks or modify city data, game speed, random state, or multiplayer rules.

## Presentation and preferences

One card appears at the lower right, or at the upper right if selected. Cards
collapse after 20 seconds unless expanded, pinned, hovered or keyboard-focused.
Existing dialogs and photo mode hide them. The same catalog supplies new-city,
loading and in-game text; loading is never delayed to make a tip readable.
Long explanations scroll inside the card. Every action only opens an existing
view or report. No action builds, spends money or moves the camera.

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
