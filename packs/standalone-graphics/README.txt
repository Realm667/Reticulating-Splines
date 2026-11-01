Reticulating Splines — Classic Native

Complete standalone replacement set; shared-effects revision 1 November 2026.
499 city masters at the exact original logical pixel dimensions; 998 smaller
views are derived by the existing renderer. Includes all 144 buildings/facilities,
terrain, networks, transport, disasters and 166 interface slots. The pack needs no imported SC2000 files.

Independent architecture and pixel construction, per-reference palette balance,
2:1 ground projection, small window/door proportions, type-colored parcel edges,
ordered shade dithering and stronger directional facade/contact shadows.
Artwork is finalized at native size before lights are authored with the existing
SC2K Author process. Equal windows use equal native pane templates. Every master
has an aligned lightmap; zero emission is intentional for unlit objects.
118 eight-frame animations include vehicles, rotors, radar, smoke, water, pipes
and authored signals. Light frames follow moving geometry; ordinary facade
windows stay stationary. Water animation retains the same shoreline silhouette.

All 144 building/facility masters now use individually referenced designs from
the approved five-building study procedure. Five approved designs are retained;
139 were newly authored. Every parcel includes its complete rear half as a 2:1
diamond. The 22 building animations and 176 emission frames follow this artwork.
Smoke changes reference-palette colors on fixed pixels instead of drifting shapes.

Format: rgba8, master_scale 1, legacy native canvas. Literal artwork colors and
logical road/water/SCURK material masks remain separate. Uses the existing GPU
renderer and animation strips. Older 2x/4x packs and original imports retain their
existing behavior. Native masters require the accompanying loader update.

All comparison images, individual analysis, generation prompts, editable scripts,
SC2K-only references and review comments stay in the private Codex workspace:
standalone-data-pack/classic/full-set and work/classic-complete-review-20261023.
The current building comparison is work/classic-building-production-20261024.
It includes RS day/night views, animations and saved per-tile comments with JSON export.
Original-game image files are not included in this pack. See provenance.json and
graphics/LICENSE-STATUS.txt for the existing attribution/license terms.

Validation includes native pixel/mask checks, full pack loading, GPU day/night and
winter city captures, animation strips and standalone startup. The consolidated set is authorized for local Runtime testing. It replaces the
previous Style A (2x) bundled pack in the same installation slot. All original
imports and personal data remain separate. This consolidation authorizes no
publication. Individual prior versions remain in the private review archive.

Visual Enhancements share the existing project artwork with SC2000: clouds,
vehicles, pedestrians, woodland and ground effects. Do not add separate RS
replacement artwork for these effects. The standalone pack supplies only the
base game replacements; shared effects also work without imported SC2000 data.
