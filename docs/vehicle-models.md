# Vehicle models

Visual Enhancements > Models replaces road traffic, surface and underground
trains, airplanes, helicopters, cargo ships and sailboats with spatial bodies.
These ten classes use nine shared geometry templates. Engine and coach colors share the same train
mesh. Materials follow the SC2000 palette and pixel style; RS artwork is not a
model design reference.

Models use rigid yaw and pitch transforms of body, roof, wheel and lamp parts.
The supporting surface is sampled at both ends of the wheelbase. Each train
record has its own pose during the existing display interpolation. Terrain,
bridge decks, highways and on-ramps retain their authoritative saved geometry.
No transport simulation, route, timing, random state or city bytes are changed.
Aircraft retain their interpolated absolute flight height; ships use the water
surface. Subway trains follow the quarter-height track one level below ground,
including curves and the existing display interpolation. They appear only with
the subway and vehicle layers visible in the underground view. Pedestrians,
disaster creatures, effects and dispatch markers retain their existing representations.

The renderer produces bounded cached indexed rasters at the native city sprite
resolution. Geometry is shared across colors. Road figures enter both the CPU
compositor and the persistent GPU atlas, including matching lamp pixels and
foreground masks. Atlas growth preserves live source rectangles; its working
set is bounded. Original artwork returns when Models is disabled. Quarter-city
silhouette caches and vehicle geometry track fractional height edits.

Power masts have transverse arms for each connected cable axis, at the actual
cable attachment height. Crossing arms share their existing offset support.

`vehicle_models_test` checks rigid dimensions, native raster sizes, cache reuse,
actual application commands, display-only state, restoration and cable mounts.
`vehicle_models_gpu_test` compares model pixels and foreground coverage against
CPU stamps at four zooms, including persistent-atlas growth.
`model_integration_gpu_test` also compares all 32 aircraft/ship headings through
the moving-object canvas at four zooms. Larger moving objects use individual
textures, rather than the road-traffic atlas's 32-pixel cells.
