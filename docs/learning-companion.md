# Learning and city adviser

Choose **Learn to play** on the main menu, or **Help → Learning & city adviser**
inside a single-player city. The companion supports the five interface themes
and all seven interface languages. At smaller sizes it docks below the map;
otherwise it can sit on either side. It can be collapsed or closed at any time.

## Courses

The basic course has 29 objectives in six chapters: orientation, the first
settlement, utilities, growth and budget, solving problems, and independent play.
Six further chapters add 18 objectives covering transport, services,
environment, disasters, late development and Reticulating Splines features.

Each objective has three levels of explanation, an associated reference article,
and optional tool and location assistance. Camera movement and tool focus require
an explicit action. Shortcut explanations use the player's actual bindings.
Completion is confirmed before **Continue** becomes available. **Later**, **Skip**
and the journal allow other learning paths without claiming those objectives were
completed. Knowledge questions do not force the player to take loans or alter
service funding.

Practice creates a separate flat 128×128 Easy city with a fresh-water shore,
normal starting funds and automatic disasters disabled. It starts in 1900,
except for the late-development chapter, which starts in 2050. Prepared chapters
pay normal construction prices for their initial buildings. The problem-solving
chapter starts with disconnected utilities. Disasters are started explicitly
by the player. There is no accelerated growth or hidden funding.

Opening a practice city or restoring a chapter start requires confirmation and
uses the normal save/discard/cancel flow for the current city. Chapter starts are
ordinary SC2 copies in the local profile. Restoring one replaces subsequent
practice changes while preserving journal achievements. It is a city checkpoint,
not a recording of transient runtime events or an exact replay.

## Evidence and advice

The companion observes ordinary tool, query, view, camera, save and simulation
events. Power and water objectives require published results from the regular
simulation after topology edits. Pipes alone do not prove water delivery.
Expansion checks demand at placement and the new zone's actual power and
transport access. Building a railway requires a contiguous segment, not an
isolated tile; the separate trip lesson teaches how to inspect route success.

The optional adviser defaults to **Off**. **Important only** reports confirmed
utility problems, disasters and a negative budget forecast. **All hints** also
includes undeveloped zones. At most three topics appear, with disaster and
utility problems first. Topics can be dismissed for the session or hidden until
restored. The adviser does not build, borrow, change speed, run simulation phases
or draw random numbers.

Tile inspection uses immutable snapshots and incremental work with a 700 µs
slice target. The target is checked after groups of 32 tiles, so it is not a hard
real-time bound. No tile scan runs when both the course and adviser are inactive.
Photo mode hides the panel and location marker. Guided learning and advice are
inactive in multiplayer; they cannot change a host's simulation.

## Local progress

Progress and advice preferences use a versioned JSON sidecar beside the
preferences file (`<settings path>.tutorial.json`). Writes replace a temporary
file atomically. The city format receives no tutorial chunks. Saved records are
bound to the SHA-256 of the saved city bytes: renames and identical copies retain
the record, while a different older save does not inherit newer active goals.
Saving under another name binds the current record to the new saved contents.
An unsaved city's work remains in the current session until the city is saved.
Invalid or unsupported progress records are ignored without preventing city load.

## Verification and contribution

`tutorial_test` checks snapshot isolation, incremental scanning, supply evidence,
advice priority, persistence and generated practice cities. A paired 72-day
simulation checks identical documents and all three RNG states with and without
the read-only companion. `tutorial_workflow_test` uses the real application for
theme/language/layout coverage, utility repairs, rotation, chapter restoration,
knowledge questions, save/load, photo mode and multiplayer exclusion. Native
input and visual checks complement these automated tests.

Implementation and supplementary translations were AI-assisted with Codex.
Original game assets remain local and are not included in this feature.
