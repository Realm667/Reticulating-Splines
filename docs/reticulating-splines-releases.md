# Reticulating Splines desktop releases

The manual **Reticulating Splines desktop builds** workflow builds the selected branch commit on native GitHub runners. Use `reticulating-splines`; every job checks out the same immutable workflow SHA. It produces Windows x64/ARM64 ZIPs, Linux x64/ARM64 tarballs, and a universal Intel/Apple Silicon macOS DMG. The workflow stores artifacts and verification reports; it does not publish releases or change tags automatically.

The workflow adapts the upstream `package.yml`, `build_native.py`, `build_desktop_release.py`, FluidSynth build, Godot setup and optional Apple-signing helpers. The exporter uses `--reticulating-splines` to include the fork's name, replacement packs, public provenance, MIT/asset/dependency licenses and corresponding FluidSynth sources. Original game imports and personal profiles are never packaging inputs. Release assets come from the committed tree.

Windows and Linux packages use a writable `data` directory next to the executable. On macOS the replacement packs and their licenses are inside the signed application under `Contents/Resources`; personal cities and settings stay in the existing Godot user profile. Existing personal and legacy packs take precedence over bundled defaults. The fork keeps the existing OpenSC2K profile name for compatibility.

Each archive has a SHA-256 entry in `SHA256SUMS.txt` and its build commit is recorded in `build-info.json`. Every completed archive is extracted or mounted and verified before a native startup and replacement-pack manifest/reference check. macOS is tested on separate Intel and Apple Silicon runners. Tests use Dummy audio and disposable runners/profiles. Startup checks do not replace graphical playtesting or prove compatibility with every Linux distribution.

## macOS graphics compatibility

macOS defaults to the Compatibility (OpenGL) renderer. Reports from Apple M4
systems running macOS 27.0.1 describe grayscale indexed DOS graphics and a
`version_get_shader` null-version error in rs.4/rs.5 with the Metal renderer.
The correct PNG export reported alongside this failure points to the GPU
palette path; the trailing error alone does not identify the failing shader.
Using the existing Compatibility renderer is a workaround, not a verified
Metal compiler fix. A graphical test on the affected Mac is still required.
The Metal path remains available for diagnosis with `--rendering-method mobile
--rendering-driver metal`; `--rendering-method gl_compatibility` selects the
workaround explicitly on older releases as well.

Missing DOS toolbar artwork is a separate issue: incomplete graphics imports
now use the bundled replacement toolbar when available. Supplied original
toolbar images, city sprites and their palettes keep precedence. No reimport
is needed for this fallback.

## macOS signing

`none` creates an ad-hoc-signed preview. It is not Apple-notarized and Gatekeeper can require user approval. `optional` signs and notarizes only when the required repository secrets exist; `required` fails if any are absent. The upstream maintainer's certificate cannot be reused. Configure your own `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID` and `APPLE_API_ISSUER_ID` through GitHub Secrets, never in source or chat. See `ci.md` for the inherited signing setup.

## Publishing

After the authorized build and its native smoke jobs pass, download `rs-desktop-packages`, verify its recorded commit and hashes, and publish an explicitly approved tag/version with the matching archives, checksums and build metadata. Keep prior release tags and assets unchanged. Clearly label non-notarized macOS previews and the tested platforms in the release notes. Run applicable project validation and retain unchanged evidence instead of repeating unrelated checks.

This workflow and the fork-specific packaging adaptation were implemented with Codex assistance.

## Reusing native build artifacts

For packaging-only corrections, `native_run` may name an earlier run of this repository's RS workflow. The package job requires all five native jobs to have succeeded and compares the native source, game tree and native/FluidSynth build recipes with that run's exact commit. Only export-preset differences are exempt from the game-tree comparison. A mismatch fails before artifact reuse. Leave the input empty to compile all libraries normally. Artifact reuse changes neither the published source commit nor the required package smoke checks.
