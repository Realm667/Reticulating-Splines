# Private Cloud saves

Cloud saves are optional for each local save. Open **Settings → Account & Cloud**
to register, confirm the email code, sign in, recover a password, inspect storage,
and revoke devices. All account steps take place inside the game. Account access
is separate from multiplayer lobby or activity tokens.

After registration, enter the emailed code in **Verify email**, then sign in.
For password recovery, enter the email address, choose **Send reset code**, and
enter the code and new password. Codes expire; the service limits attempts.
Passwords are cleared from the UI after submission and when closing the window.
**Stay signed in on this device** stores only the revocable device credential in
the operating system's protected store. Without it, the login lasts for the
current process. An unavailable secure store does not fall back to plaintext.

## Saving and loading

Select **Cloud synchronization** in the Save dialog's Save/Cancel row. On narrow
screens its caption shortens to **Cloud** and retains the full tooltip. The dialog shows the account
and connection status and provides **Account & Cloud** for in-game sign-in and
management. The choice applies only after the local save succeeds. You can also
enable **Keep this save in Cloud** for an existing local file. Local save validation happens
before a separate immutable copy enters the persistent upload queue. Uploads do
not block ordinary local play. Changes are queued after manual saves and at the
periodic Cloud checkpoint. Failed/offline uploads can resume after restarting
and signing in. Disabling Cloud stops this file's future synchronization; it
does not delete existing remote copies.

The Open City dialog has separate **Local saves** and **Cloud saves** sources,
including the multiplayer continuation picker. The Cloud source embeds
the same account, versions, trash and conflict controls as Settings. It shows
the save name, preview when available, game year, population, update time and
originating device. Version selection updates its preview and metadata. Select
a version and choose **Load city** to download to a unique local file and enter
the normal loading and unsaved-change checks. The standalone Cloud browser also
offers **Download** with a new local filename. Existing local files are never
silently overwritten. The client validates size, checksum, format and required
game/gameplay-mod compatibility before publishing the local copy. A downloaded
copy keeps its Cloud identity and predecessor, so subsequent edits synchronize
with the selected branch. These managed downloads live in the private Cloud
cache, outside the local cities library. Use **Save city as** to create a local
copy, or enable Cloud synchronization for a local save whenever desired.

Regions are uploaded as one consistent SC2X archive, including all their cities
and shared state. Multiplayer session archives are saved only by their host;
opening such an archive uses the existing multiplayer continuation workflow.
Cloud account ownership does not transfer another player's seat. Graphics,
music packages, local filesystem paths and device settings are not uploaded.

## Versions and conflicts

The server compares revision predecessors, not device clocks. Concurrent offline
changes create an explicit conflict. The client keeps both versions until the
player chooses:

- **Use Cloud version:** keep the remote branch and retain the previous local
  file; download the chosen Cloud version to a new local file to continue it.
- **Use local version:** explicitly publish the queued local branch as a new
  version after the remote revision shown in the conflict. If the remote version
  changes again, another conflict is required.
- **Keep both copies:** publish the local continuation under a separate save
  identity. The existing Cloud save remains separate.

Cities and regions are never automatically merged. Restoring a previous version
creates a new current Cloud version with a predecessor check; it does not edit
the currently loaded local file.

The initial service policy keeps five versions per save and retains trash for
30 days. Each account has 20 MB (20,000,000 bytes), including versions, trash and
reserved uploads. The game reads the current quota from the service. Lowering
the limit does not delete existing saves; accounts above it can still download
their data but cannot add storage beyond the limit. Moving
a Cloud save to trash and restoring it are explicit actions. Local deletion
does not delete the Cloud copy. Device revocation removes that device's account
access while preserving its local files.

## Implementation and validation

`CloudSync` exposes account state, quota, queue, conflicts, save metadata and
devices through `snapshot()` and `changed`. `CloudPanel` supplies the shared
controls for the standalone `CloudWindow` and the embedded Open City source.
The UI never receives bearer
credentials or reads the protected credential store. It emits `downloaded(path)`
only after a verified explicit download, and `opt_in_changed(path, enabled)`
after a successful per-file preference change. The application owns save/open
guards and host authorization.

The UI uses scrollable pages, wrapping text, flow-layout actions and at least
40-pixel action targets. Windows are bounded to the current viewport. Email and
password fields request appropriate virtual keyboards; this supports future
touch ports without claiming that an Android release already exists.

`cloud_ui_test.gd` uses a fake service and generated metadata, with no account or
network requests. It covers account flows and password clearing, save/trash
selection, explicit conflict/revocation confirmation, hostile preview rejection,
and a narrow viewport. Core and backend tests cover persistence, authentication,
upload integrity and ownership independently. All feature text is held in the
central English template plus de/es/fr/it/ko/pt_BR catalogs.
