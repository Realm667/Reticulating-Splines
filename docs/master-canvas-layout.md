# Master canvas layout

## Current standalone pack: Classic Native

Since 23 October 2026, the default RS pack uses `master_scale: 1` and
`master_canvas: "legacy"`. Each master has the original logical pixel dimensions;
the loader retains those pixels without resampling at native scale. Building IDs
1112-1255 retain their existing footprints and normal legacy placement.
`packs/standalone-graphics/templates/building-canvases.json` lists the current
native dimensions. Construct straight isometric edges in the 2:1 pixel grid,
then author lightmaps at the final dimensions. Art, masks and animation frames
must have identical canvases. Do not independently resize or trim a lightmap.

## Older and custom packs: centered-footprint-v1

The following describes the previous RS pack and remains supported for custom
packs. The four footprint SVGs in the templates directory are examples of this
older 2x convention, not the dimensions of the current standalone art.

The previous RS pack used `"master_canvas": "centered-footprint-v1"` at the top of `graphics/pack.json`.
This applies to building IDs 1112-1255. Other sprites retain their existing format.
Packs that omit the field keep legacy placement. Original SC2K packs are unchanged.

## Authoring

Create one 2x PNG per building and keep its approved physical size inside the image.
The game gets the footprint from the existing building ID. A tile is 64x32 master
pixels in 2:1 dimetric projection; height projects vertically.

For a building occupying N by N tiles:

- The footprint width is `64 * N` master pixels.
- The PNG width is that width plus `16 * gutter_steps`, where gutter_steps is a
  nonnegative integer. Extra space is divided equally between the left and right.
- The front ground corner is `(PNG_width / 2, PNG_height - 2)`.
- Image height must be a multiple of two. Grow upwards for roofs or smoke.
- The other ground corners are at `(cx +/- 32*N, front - 16*N)` and
  `(cx, front - 32*N)`.
- Keep unused space transparent. Include the full motion envelope of every frame.
  Retain at least 8 transparent master rows above it when trimming an existing
  canvas, so overview sampling retains the same coverage cells.
- Base art, optional RGBA art, lightmaps and all animation frames use identical
  canvases. Translate or resize them together; never independently trim a frame.

There are no individual scale or position settings in this layout. `logical_size`
is the PNG size divided by two. Do not add `visual_registration`; conflicting
legacy registrations are rejected. The loader derives the common anchor once.
The renderer still uses its existing internal registration structure for footprint
geometry, borders, lighting and culling; there is no per-frame placement calculation.

The four SVG guides show the older centered footprint and centerline; they are
authoring guides, not runtime textures.
See [object animation frames](object-animation-frames.md) for timing and masks.

## Accepted RS corrections

The previously accepted scales and offsets were already baked into RS pixels.
The 2026-10-15 migration removes residual asymmetric transparent padding and
normalizes the anchor. It uses only integer translation and transparent cropping:
no resampling, architecture changes or loss of visible pixels. Six buildings keep
symmetric gutters for overhang or movement. All 144 building records omit explicit
placement overrides. City tiles, traffic artwork and UI retain their accepted art.
`graphics/canvas-normalization.json` records the previous layout, file hashes and
transform for each source. Original editable assets and exports remain preserved.

`review_reference_size` and `review_padding` are private-gallery comparison metadata;
they do not control game placement. Negative top padding means the image has been
trimmed above the fixed ground anchor. Never reapply an old correction export to an
already corrected image without checking its source hash.

The previous RS source raster was 2× (16 October 2026). Set `master_scale` to 2.
The loader also supports 4× packs (the legacy default): multiply these master-pixel
measurements by two, while keeping logical dimensions and footprints unchanged.
