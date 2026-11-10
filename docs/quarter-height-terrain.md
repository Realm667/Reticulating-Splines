# Quarter-height terrain

Visual Enhancements > Models offers an opt-in terrain capability for Expanded
SC2X cities. The initial conversion reads the existing SC2000 corner masks.
Classic cities retain their original tools, storage and prices.

The brush moves a tile by 1/4, 1/2, one or two original levels. Gentle, normal
and steep brushes limit the corner span to 1/2, one and two levels per tile.
Shared vertices propagate together. Cliff mode deliberately separates tile
edges and draws the exposed vertical faces. Existing cliffs stay independent
when a smooth brush changes their neighboring plateau.

Surface roads, railways and power lines require a supporting plane with a
corner span of at most one level. Routes cannot cross disconnected cliff
edges. Highway sections follow a continuous cardinal plane over their 2x2
footprint without legacy grading. Sloping highway sections cannot replace
ground-level crossings. Existing bridge choices and deck heights remain in
use; their automatic bank grading also updates the saved corner geometry.
Existing highways, ramps, bridges and buildings protect their supporting ground;
remove them before grading their footprint.
Buildings and zoning require flat tiles; multi-tile buildings require one
exact height throughout the footprint. Growth applies the same rule.

Terrain editing costs 25 per original tile-level of moved volume. Each corner
quarter is 1/16 of that volume. A saved fractional carry makes four isolated
quarter steps cost 6, 6, 6 and 7, totaling 25. Propagated changes are included.
Free editor actions do not charge or consume the carry. Failed edits leave
money, geometry and random state unchanged. Undo restores the geometry,
compatibility planes and cost carry while retaining the current brush choice.

Meshes are rasterized into the existing native indexed regional renderer.
All three sprite sizes use nearest-pixel coverage; building sprites and painter
order remain in use. Identical relative corner and edge profiles share a terrain
raster. Infrastructure reuses the existing nine SC2000-derived geometry recipes
at the actual supporting heights. Moving figures use the resulting silhouettes.
Quarter cities require Models for an accurate display; the local toggle cannot
hide their geometry. Capability activation and brush configuration are disabled
during multiplayer sessions; previously configured quarter cities retain their
saved geometry and authoritative build rules. Shared-map composition and land
transfers copy corner payloads without transferring municipal cost carries.

## XQTR version 1

The required feature is `rs.quarter-terrain.v1`, in addition to `rs.expanded.v1`.
An optional singleton `XQTR` archive entry contains a 16-byte header followed by
eight bytes per tile, in the same X-major order as ALTM.

| Offset | Type | Value |
| --- | --- | --- |
| 0 | 4 bytes | ASCII `QTR1` |
| 4 | u16 big-endian | Map edge |
| 6 | u8 | Brush step in quarters: 1, 2, 4 or 8 |
| 7 | u8 | Maximum span: 2, 4, 8; 0 means cliffs |
| 8 | u8 | Cost carry in sixteenths of one currency unit, 0–15 |
| 9 | 7 bytes | Reserved, zero |
| 16 | 4 × u16 big-endian per tile | NW, NE, SE, SW corner heights in quarters, 0–128 |

ALTM and XTER retain whole-height compatibility hints. XQTR is authoritative
for geometry and the new building rules. Conversion preserves existing slopes;
terrain regeneration rebuilds the quarter plane from the generated terrain.
Rotation changes tile indices and corner order. Missing capabilities, missing
payloads, invalid dimensions, unsupported header values and out-of-range heights
are rejected at load. Existing SC2X compression and integrity checks still apply.
