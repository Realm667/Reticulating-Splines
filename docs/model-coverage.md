# Model integration and coverage

The Models option uses spatial recipes projected into the existing indexed
isometric renderer. It does not replace the whole renderer with a 3D scene.
SC2000 supplies the design reference. Original imported artwork is not shipped.
This is an experimental implementation, excluded from the approved product
source, Runtime, Distributable and releases until separately authorized.

## Terrain and water

Dry terrain, water, shores, channels and waterfalls use spatial geometry.
Their indexed materials sample the loaded SC2000-style artwork. Water shapes
share bank profiles, corner banks, open channel ports, horizontal caps and
vertical water curtains, rather than keeping one mesh per source sprite.
Classic shoreline codes select those profiles. With XQTR the banks also follow
the actual corner surface; shallow bank detail does not flatten a higher slope.
Circular lake corners join straight shores tangentially. An adjacent open water
port at the same surface height opens a river mouth through the shallow bank
detail. Saved XQTR ground remains authoritative, and neighboring terrain/flag
edits invalidate the affected shore's cached model.
Turning Models off restores the original pictures in classic cities. Fractional
cities continue using geometry to display their saved terrain accurately.

The water plane clips the underlying terrain. Exposed water walls join lower
neighbors or the map boundary. Both waterfall codes (including the older coastal
code used by dams) retain the SC2000 cap one level above the foot. Curtains repeat
the original indexed falling-water material, including on taller exposed water
walls. Original palette addresses keep their color cycles; the optional flowing
water shader also follows the spatial material mask. It stops with the existing
animation clock. No simulated water flow or saved water altitude changes.

Spatial material masks match each model raster's actual dimensions and distinguish
soil, horizontal water and falling water. Seasons, water coloring, shore-distance
effects and paged atlases use these masks. Reflections receive only on horizontal
water at its real cap altitude; vertical curtains do not receive flat mirrors.
All geometry is coverage-reduced to the three existing native pixel sizes.

The following retain sprite artwork:

- Dam structures remain building sprites. Their terrain/water is drawn separately.
- Zone/lot colors, trees, decorative objects, markers, pedestrian
  figures and disaster effects stay in their existing sprite/effect paths.
  They are outside the terrain and transport model inventory.

These remaining objects deliberately retain sprites by the user's scope decision;
further model conversion is not planned for them.

Aircraft shadow silhouettes project the current model onto the receiver. Other
existing shadow/effect artwork remains in its established compositor.

Rubble IDs 1–4 compose one shared pile template in four poses: broken brown
timbers, gray masonry and a loose dark base following the SC2000 reference.
Each rigid fragment mounts on its own terrain plane; the loose base follows the
two actual XQTR triangles. Models off restores the imported rubble artwork.
The native model-height registry includes these four IDs, while radioactive
waste, vegetation and other objects keep their existing sprite paths.

The aircraft and ship recipes use the original SC2000 proportions and palette:
swept airliner wings and blue tail, a dithered animated helicopter rotor, aft
cargo-ship superstructure, and separate colored container rows. The rubble uses
the original dark brown and gray material ramps. No reference pixels are shipped.

## Visual effects

Models use the existing environment dispatcher and palette shaders. The parity
test compares scalar/vector effect parameters at identical transition times
with Models off and on; it also renders winter on actual dry model terrain.
This verifies common effect semantics, not identical pixels for different bodies.

| Effect family | Model integration |
| --- | --- |
| Seasons, frost, terrain variation | Masks follow generated soil caps; interior rock and water are separate. |
| Height coloring, edge sediment | Ranges and boundary profiles track exact quarter heights and their edits. Packed vertex tags retain every 1/16-level corner mean in indexed, artwork and waterfall draws. Only map-boundary faces receive sediment. |
| Day/night, dawn/dusk, LUTs, artwork color | Existing shared palette/environment pipeline. |
| Rain/snow, lightning, cloud/fog shadows | Shared environment passes; the fog ray uses the actual quarter-height triangles, water flags and waterfall caps. Native corner bytes upload directly into resident textures. |
| Traffic/detail lights and glow | Geometry-sized signal and vehicle emission; foreground clipping uses the model mask. Entrance approaches require matching actual edge heights. |
| Aircraft shadows | Flattened current model, with the existing opaque/transparent shadow choices. |
| Ship wakes and reflections | Indexed animated wakes; enhanced water exposes live water beneath neutral foam. Reflections use signed model heights, retain blue cargo and navigation lights, and exclude wakes. |
| Underground pipe flow | Supplied tubes carry cycling water indices and the existing optional flow overlay. Dry tubes remain static. |
| Disaster sprites, dust, crowds | Retained sprite/effect paths and the same painter/foreground integration. |
| Forest shadows | Retained canopy silhouettes project onto actual quarter-height receiver triangles. |
| Tilt shift, idle saving, zoom/detail cutoff | Existing final-view and refresh controls. |

Quarter-only terrain edits invalidate cosmetic traffic paths and local geometry
without resetting their simulation-independent figure population. The parity
matrix visits both Boolean states, both numeric endpoints and every choice of
the shared visual options at a fixed transition instant. Tree-growth mechanics
and custom file paths retain their separate existing tests and loaders.

Custom LUT/brightmap file loading remains in the common loaders. Geometry-sized
procedural signal masks are available even without an external brightmap catalog;
compatible explicit replacement masks still take precedence.

## Preparation performance

Native palette matching is shared by palette contents and three structural
material families. A mutex protects publication between rendering workers;
callers receive independent swatches. The cache holds at most twelve entries.
Equivalent palettes share results; edits invalidate them. No city or image
resources are retained by this cache.

Shore generation evaluates each of its 17×17 vertices once. Fully submerged soil
faces keep their conservative image bounds but skip invisible raster work.
The 10,080-case terrain matrix retains its exact aggregate pixel/material
checksum, and the 306 network/debris rasters and representative city-region
images retain their SHA-256 fingerprints.

Serial local measurements with Godot 4.7.2 and isolated Dummy profiles:

| Preparation work | Before | After |
| --- | ---: | ---: |
| 306 material requests, median of three | 1,897 ms | 16 ms |
| 306 native model rasters, median of three | 2,781 ms | 817 ms |
| Static model archive preparation | 891 ms | 252 ms |

Reused 512×384 regions remain about 0.25 ms on classic model terrain and 1.8 ms
with quarter-height water in these fixtures. These are worker timings, not total
frame costs. A separate 120-frame native check of the generated 128-tile city at
1360×900 and 2× zoom measured medians of 1.24 ms with sprites and 1.23 ms with
Models, with 152 draw calls in both cases. That check paused the city, disabled
VSync/idle caps and used the Vanilla effect preset to isolate the model overhead.

Buildings and zones still require flat supporting terrain. Keeping their artwork
preserves the original design and the existing painter/foreground masks.

## Underground

Subways and water mains compose shared tube arms, rails, pipe collars, service
frames and station shafts. Curves, junctions and the two pipe/subway crossings
reuse these components. Crossings separate pipe and subway depth. Cutaway tunnel
shells expose the shared train bodies. Relative corner profiles share raster
entries across tiles; the native substitution table scales with distinct profiles,
not with four sprite records for every city tile.

The existing painter still chooses the original logical sprite IDs and layer
order. Optional model images replace their artwork afterwards. The four PIPED /
WATERED flag combinations, hidden mains, service areas, subway layers, tunnel
depths and altitude cutaways retain that selection. Dry mains are dark; supplied
mains are blue; connected and supplied service frames have distinct green tones.
Reserved unused XUND values retain the existing fallback behavior.

Connected neighbors use one native port-height calculation. Their shared edge
uses the lower buried endpoint, including a pipe's deeper subway-crossing level.
Arms slope from their own center to that shared endpoint. They remain continuous
across independent cliffs without moving a pipe above either terrain side.
Subway vehicles sample these same arms. Raster baselines expand for deep drops;
transparent padding never clips the model at its original sprite boundary.

## Data, height and minimap views

All eleven data modes use the actual quarter corners, independently exposed cliff
edges and land/water intersections. Height mode shows the seabed. Its tile value
is the mean of four corners, retaining 1/16-level precision, with separate dry-land
and underwater-depth color addresses. Float textures avoid the old byte rounding.
Hover values, mesh/value caches and the debug tile mesh track XQTR changes.
Water and hidden-water terrain use the land-relative model origin once, so water
height is consistent with the data mesh and reflection receiver.

All eighteen minimap modes retain their service/network classifications. Empty
land uses the exact corner mean over the full 0–32 range. Downsampled map pixels
average all four corners of every covered tile. The classic and modern palettes
interpolate their existing terrain ramp; no new palette is required. Classic
cities without XQTR keep their previous bytes and colors.

## Finite verification matrix

Water-specific verification includes 10,080 material/raster configurations across
21 shared forms, classic/fractional geometry, four quarter phases, five corner
profiles, four water levels and all three native pixel sizes. Bank rotations,
open channel centerlines through both ports, and the removal of internal curtains
between equal waterfall caps are checked independently. Bank side faces follow
their sampled profile, so raised corners cannot close an open port. The production painter covers all
53 water-range codes, including reserved fallbacks, both water-flag states and
classic/fractional cities: 636 selections. Model opt-out and saved maps are
unchanged. Both waterfall codes are checked at five water levels, including 31,
in all three views, with spatial material masks and reflection receivers.

The native GPU case renders all 53 codes with four profiles in 30 complete
CPU/GPU pairs (three views, four rotations, classic/fractional cities, and hidden
water). Another 24 pairs cover four connected river mouths and circular lakes in
all rotations and views, in classic and fractional cities: 54 pairs in total.
It also renders palette and flowing-water animation phases through the
production shader. Rendering is checked against saved-state snapshots; test
rotation commands are outside that read-only interval.

Coverage is factored by independent geometry, material, painter-selection and GPU
contracts. It is not a claim to enumerate every possible arrangement of an entire
city. All valid branches of the declared local state domains are exercised:

| Domain | Coverage |
| --- | --- |
| Rubble | IDs 1–4, 41 planes, four quarter phases, three native sizes: 1,968 rasters; rigid-fragment dimensions; 24 full CPU/GPU pairs, all rotations and classic/fractional cities; sprite restoration and unchanged saved state |
| Surface geometry | IDs 14–111, 41 planar normal-or-gentler grades, four quarter phases, both mirrors; two-tile highways use doubled spans |
| Native model raster | Every preceding unmirrored surface recipe and underground/service recipe at all three artwork sizes |
| Underground geometry | 67 sprite/service forms on the same 41 planes and four phases; all 6,561 relative corner forms through the shared all-arm, crossing and shaft templates |
| Underground selection | 44,236,800 cases: 40 XUND values, 72 XTER values, four water states, 16 layer combinations, three sizes, four rotations, four quarter phases and five cutaway/tunnel settings |
| Underground joins | Every pair of 40 XUND values in four directions and 17 × 17 height configurations; both network layers use identical buried endpoints; actual native image substitutions are verified |
| Terrain/data topology | All 6,561 relative corner forms × five water cases × surface/seabed; all 129 absolute quarter heights and 33 cutaway levels |
| Construction boundary | All 6,561 relative corner forms: networks require a plane with span ≤ 4 quarters; building/zone sites require zero span |
| GPU underground | 24 complete CPU/GPU image pairs: three sizes, four rotations, two cutaways; every XUND form and all water states in each city |
| GPU data | All eleven modes and all 1,010 land/depth color addresses in 1/16 steps |
| Vehicles | Ten classes, eight directions, three artwork reductions; actual application commands and unchanged saved state; road atlas and larger moving canvas at four zooms |
| Minimap | All 129 quarter heights, all local corner means, every mode/building/flag classification and full downsample-cell averaging |

The registered checks are `model_combination_matrix_test`,
`model_integration_gpu_test`, `network_models_test`, `network_models_gpu_test`,
`quarter_terrain_test`, `quarter_terrain_gpu_test`, `vehicle_models_test`,
`vehicle_models_gpu_test`, `isometric_data_view_test` and the native workspace
tests. No transportation simulation, save format, terrain price or build rule is
changed by this rendering integration.
