#!/usr/bin/env python3
"""Build an internal macOS preview from an immutable source checkout.

The source commit is retained. Only the exported application version is
overlaid, and the source manifest pins every bundled free SoundFont.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def verify_native_reuse(source, packages, expected_sha256):
    """Reject reuse unless the pinned package and native build inputs match."""
    if not re.fullmatch(r'[0-9a-f]{64}', expected_sha256 or ''):
        raise ValueError('Native reuse requires an independently verified DMG SHA256')
    info = json.loads((packages / 'build-info.json').read_text())
    previous = info['commit']
    if not re.fullmatch(r'[0-9a-f]{40}', previous):
        raise ValueError('Invalid previous source commit')
    changed = subprocess.check_output(
        ['git', 'diff', '--name-only', previous, 'HEAD', '--', 'native',
         'tools/build_native.py', 'tools/build_fluidsynth.py'], cwd=source, text=True)
    if changed.strip():
        raise ValueError(f'Native build inputs differ: {changed}')
    name = f'ReticulatingSplines-{info["version"]}-macos-universal.dmg'
    dmg = packages / name
    with dmg.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != expected_sha256 or digest != info['sha256'][name]:
        raise ValueError('Previous native DMG hash mismatch')
    return dmg, {'source_commit': previous, 'dmg_sha256': digest,
                 'native_build_inputs_identical': True}


def install_reused_native(source, dmg):
    """Copy only the six native libraries, then let normal packaging sign them."""
    with tempfile.TemporaryDirectory(prefix='rs-native-reuse-') as temporary:
        mount = Path(temporary) / 'mount'
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse',
                        '-mountpoint', str(mount), str(dmg)], check=True)
        try:
            frameworks = mount / 'ReticulatingSplines.app/Contents/Frameworks'
            subprocess.run(['codesign', '--verify', '--deep', '--strict',
                            str(mount / 'ReticulatingSplines.app')], check=True)
            entries = [(f'libopensc2k_{module}.dylib', module) for module in
                       ('simulation', 'rendering', 'formats', 'audio', 'scripting')]
            entries.append(('libfluidsynth.3.dylib', 'audio'))
            hashes = {}
            for name, module in entries:
                library = frameworks / name
                subprocess.run(['lipo', str(library), '-verify_arch', 'x86_64', 'arm64'], check=True)
                target = source / f'game/bin/opensc2k_{module}/macos' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(library, target)
                hashes[name] = hashlib.sha256(target.read_bytes()).hexdigest()
            return hashes
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True)


def build(source, commit, version, output, reuse_native_packages=None, reuse_native_sha256=None):
    source = source.resolve()
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('An immutable 40-character source commit is required')
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+-rs\.[0-9]+-dev\.[0-9]+', version):
        raise ValueError('An internal RS development version is required')
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    if actual != commit:
        raise ValueError(f'Source commit mismatch: {actual}')
    if subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], cwd=source, text=True).strip():
        raise ValueError('The source checkout contains tracked changes')
    reuse = None
    if reuse_native_packages is not None:
        dmg, reuse = verify_native_reuse(source, reuse_native_packages.resolve(), reuse_native_sha256)
        reuse['libraries'] = install_reused_native(source, dmg)
    elif reuse_native_sha256:
        raise ValueError('Native hash supplied without package directory')
    sys.path.insert(0, str(source / 'tools'))
    import build_desktop_release as release

    original_install = release.install_native
    overlays = []

    def install_preview_inputs(native, project, platforms):
        original_install(native, project, platforms)
        settings_path = project / 'project.godot'
        settings = settings_path.read_text()
        found = re.findall(r'^config/version="([^"]+)"', settings, re.M)
        if len(found) != 1:
            raise ValueError('Expected one source application version')
        settings_path.write_text(settings.replace(f'config/version="{found[0]}"',
                                                f'config/version="{version}"', 1))
        overlays.append({'path': 'game/project.godot', 'original': found[0], 'export': version})
        manifest = json.loads((project / 'assets/soundfonts/manifest.json').read_text())
        for bank in manifest['fonts']:
            name = bank['file']
            if Path(name).name != name or ':' in name or '\\' in name:
                raise ValueError('Unsafe SoundFont filename')
            downloaded = release.build_fluidsynth.download(bank['url'], bank['sha256'], name)
            if downloaded.stat().st_size != bank['bytes']:
                raise ValueError(f'SoundFont size mismatch: {name}')
            shutil.copy2(downloaded, project / 'assets/soundfonts' / name)

    release.install_native = install_preview_inputs
    release.build(output.resolve(), version, 'godot', source / 'game/bin',
                  ['macos'], require_notarization=False, reticulating_splines=True)
    if len(overlays) != 1:
        raise ValueError('Expected one export version overlay')
    info_path = output / 'build-info.json'
    info = json.loads(info_path.read_text())
    if info['commit'] != commit or info['version'] != version:
        raise ValueError('Export metadata mismatch')
    info['export_version_overlay'] = overlays[0]
    info['scope'] = 'Internal macOS Universal preview; no original-game or personal data'
    if reuse:
        info['native_reuse'] = reuse
    info_path.write_text(json.dumps(info, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reuse-native-packages', type=Path)
    parser.add_argument('--reuse-native-sha256')
    args = parser.parse_args()
    build(args.source, args.commit, args.version, args.output,
          args.reuse_native_packages, args.reuse_native_sha256)
