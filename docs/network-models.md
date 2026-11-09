# Optional network models

Visual Enhancements > Models > Enable models selects spatial network geometry.
It is off by default and independent of the graphics presets. The preference is
local; city documents, network rules, building rules and simulation random state
are unchanged.

The first implementation covers logical building IDs 14–111: roads, rails,
power lines, crossings, tunnels, rail/subway portals, road and rail bridges,
elevated highways, their bridges, curves, junctions and ramps. Buildings retain
their existing artwork.

## Geometry and rendering

`NetworkModelGeometry` composes nine parameterized recipes: surface routes,
cable networks, portals, elevated decks, ramps, suspension spans, lift towers,
trusses and crossings. Vertices use tile coordinates u/v and large-view pixel
heights z. Projection is `(16*(u-v), 8*(u+v)-z)`. Four corner heights describe a
grade. Composite highways preserve the painter's two-tile anchor when mirrored.
Equal geometry shares an immutable record in a bounded preparation pool; neither
materials nor source-pack names create another geometry family.

`NetworkModelRaster` resolves the components with a depth buffer once during
asset preparation. It produces indexed color and per-texel height, at the three
native sprite resolutions. Smaller views select covered indexed samples rather
than blending colors or dropping thin cables. Existing regional CPU/GPU batches,
nearest-pixel zoom, picking, foreground masks and moving graphics consume these
resources. There are no scene nodes for individual sleepers, cables or supports.
This is a fixed-projection hybrid renderer, not a freely rotating 3D scene.

SC2000 is the sole design reference. Admitted original artwork supplies surface
markings at runtime. The shipped files contain geometric instructions, palette
materials and source fingerprints, not copied original pixel assets. Compatible
replacement packs use the same SC2000-derived geometry and procedural materials;
their artwork is not a design reference. Each source sprite and any HD override
must match the admission registry. Modified or unknown art keeps its sprite.

Per-texel model height projects bridge silhouettes onto the receiving water
plane. Reflection clipping, black silhouettes and the absence of reflected bridge
lights retain the existing water rules. The native request validates the IDs,
dimensions and finite opaque heights before accepting this optional metadata.
Builders without metadata keep their original reflection path.

## Resource changes

Archives retain both their original sprites and immutable prepared model entries.
Switching changes lookup and presentation revisions, invalidates regional and
moving caches, rebuilds seasonal/light masks and carries the model state into
preparation banks and preview copies. Preview fingerprints include the model
signature. Disabling restores the loaded originals, including HD overrides.

`CityNetworkModels.VERSION` participates in the preparation signature. Changes to
the model contract must increment it. Source admission lives in
`game/assets/data/network_model_sources.json`; new entries require explicit
source and HD-artwork verification, rather than admission by pack name.

## Checks

`network_models_test` covers all 294 native rasters, resource reuse, custom-art
fallback, mirrored anchors, grades, preference persistence, the actual settings
callback, preparation copies, city/random-state preservation and existing moving
surface checks with models enabled.

`network_models_gpu_test` compares CPU pixels, production GPU pixels and foreground
commands for all 98 types at three native sizes and four city rotations. It also
checks spatial bridge reflection samples in both orientations. Run the regular
headless and renderer suites and the native workspace gates for changes here.

Additional terrain angles remain a later task. This display feature does not
introduce new slope construction rules or change the flat-only building and zone
rules.
