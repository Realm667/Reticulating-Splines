# Android ARM64

The Android port is under integration. A compiled APK alone does not establish
device compatibility. The initial device is an AYN Odin 2 Portal on Android 13.

## Native build

Use the Android NDK r28b (`28.1.13356709`), a Rust toolchain selected by
`rust-toolchain.toml`, CMake and Ninja. On Windows or Linux:

```sh
python tools/build_android_native.py --ndk /path/to/android-ndk
```

This builds the five extension crates for `aarch64-linux-android`, without the
desktop native application. The FluidSynth recipe uses the same pinned source
archives as desktop builds and the Android CMake toolchain. FluidSynth remains
a separate shared library; corresponding sources and LGPL notices must accompany
distribution. Never package Windows/Linux binaries as Android libraries.

The native target is Android API 28 (Android 9) or newer. The APK exporter raises
the prebuilt Godot templates' manifest minimum to the same API before Godot
signs the final package; engine code and assets remain unchanged. This avoids
advertising the template's lower minimum for libraries built against API 28.

## Data and credentials

Android always uses the application's private Godot user directory, not a
portable directory beside the executable. The export supplies the existing free
graphics/sound/music packs as `res://android-packs.zip`. First use extracts an
immutable directory named by the archive SHA256. A completion marker is written
last. Native asset readers can then use ordinary paths. Existing user imports
and previous complete bundles are preserved if extraction fails.

The archive is first copied to a regular private file and its SHA256 checked.
Android then uses the platform's indexed ZIP reader, bounded entry counts and
sizes, safe relative paths, and CRC validation. Godot's name-based ZIP reader
otherwise rescans the directory for every file. The existing reader remains
available for host-side tests. The APK carries project/dependency license notices.

Cloud device tokens use AES-GCM with a per-account key held by AndroidKeyStore.
Only ciphertext and a random IV enter private SharedPreferences. The account is
authenticated associated data. Cryptographic/API errors fail closed. The APK
disables Android automatic app-data backup so credentials are not restored onto
another device without their key. Desktop credential storage is independent.

## Export and acceptance

The `Android ARM64` Godot preset exports a landscape APK. Set the Android SDK
and Java SDK paths in an isolated editor profile. Use a debug signing key only
for internal tests. A public release needs a protected, durable signing key,
the common release source commit/version, APK inventory, license/source bundle,
`SHA256SUMS.txt` and `build-info.json`.

`tools/build_android_release.py` exports a clean committed tree in a separate
work directory. Supply `--godot`, `--work`, `--output`, `--sdk`, `--java`, and
`--templates`. Release signing uses Godot's keystore environment variables;
never put passwords in command arguments or Git. `--debug --dummy-audio` creates
an internal `-android-arm64-test.apk` and records the silent test mode in its
build information. Never publish that test artifact. Real audio requires a
separate manual listening check; automated checks use Dummy audio.

`input_devices/pointing/android/disable_scroll_deadzone` is enabled so symmetric
two-finger pinches deliver raw touch drags to the existing navigation code.
Native pan/scale emulation stays at its default to avoid duplicate gestures.

Before accepting a build, verify native library ABI/dependencies and 16KiB page
alignment, install and launch on the authorized device, then test bundled assets,
city/region saving and loading, touch/keyboard/controller focus, audio, lifecycle
pause/resume, offline/cloud conflicts and secure credential round trips. Retain
actual device/log evidence; do not substitute desktop or emulator results for
physical hardware tests.

Future GitHub asset name: `ReticulatingSplines-VERSION-android-arm64.apk`.
The website already recognizes this name. Do not publish a test APK merely to
make the Android download button appear.
