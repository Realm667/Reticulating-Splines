# Local building variants

Open **Settings > Graphics > Building variants…**. Add local SCURK MIF files,
enable mixing, select categories and press **Apply**. Each set and the original
have a relative weight, initially 50. With one compatible additional set this
gives each building a 50:50 choice. Zero excludes a source when alternatives
exist. Missing alternatives always keep the base building.

The nine categories cover residential, commercial, industrial, education,
public services, recreation, ports (including airport and military facilities),
power plants and rewards. Construction and abandoned buildings, terrain,
trees and transport networks retain their base graphics.

Mixing takes precedence over replacement SCURK sets while enabled. Turning it
off restores the previous replacement selection. The base graphics must use
the indexed SC2000 palette. This feature does not import or distribute artwork.

A family needs compatible footprint widths and nonempty artwork at all three
original sizes. Incomplete or identical families are skipped as a unit. Height
may differ. The selected family supplies its own indexed pixels, transparency
and palette animation at every size. MIF files contain no authored light masks;
an alternative does not borrow the original building's mask or HD artwork.
Existing matching masks for the original stay intact.

Selection uses a local visual hash of the building type, canonical footprint
center and saved mix value. It is stable across zoom, rotation, redraw and load;
file order does not matter. **Shuffle again**, followed by **Apply**, changes
the mix value. This affects no simulation random state, city file or multiplayer
state. Other players can use different local artwork.

Settings retain up to eight local files. Identical file content is deduplicated
(the larger weight wins). Each file is limited to 16 MiB, and admitted families
share a conservative 64 MiB decoded-input budget. The existing CPU/GPU region
and bounded atlas caches are reused; there is no per-frame file access or new
effect pass. Adding variants can still increase atlas storage and cold preparation
time. Missing files never prevent opening a city.
