# Model integration and coverage

The Models option uses spatial recipes projected into the existing indexed
isometric renderer. It does not replace the whole renderer with a 3D scene.
SC2000 supplies the design reference. Original imported artwork is not shipped.

## Terrain artwork retained as sprites

Dry terrain, fractional coast surfaces and cliff faces use spatial corner
geometry. Their palette textures still come from the loaded artwork. The
following deliberately retain sprite artwork:

- Without XQTR, classic wet tiles retain their water, shore and channel sprites.
  Those pictures encode mixed land/water shapes which ALTM alone cannot recover.
- Waterfall artwork retains the original animated cap and vertical water pattern.
  This is a special water animation rather than a freely deformable cliff model.
- Dam structures remain building sprites. Their terrain/water is drawn separately.
- Zone/lot colors, trees, rubble, decorative objects, markers, shadows, pedestrian
  figures and disaster effects stay in their existing sprite/effect paths.
  They are outside the terrain and transport model inventory.

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

Coverage is factored by independent geometry, material, painter-selection and GPU
contracts. It is not a claim to enumerate every possible arrangement of an entire
city. All valid branches of the declared local state domains are exercised:

| Domain | Coverage |
| --- | --- |
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
