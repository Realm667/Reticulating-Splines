#!/usr/bin/env python3
"""Build an internal macOS preview from an immutable source checkout.

The source commit is retained. Only the exported application version is
overlaid, and the source manifest pins every bundled free SoundFont.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def build(source, commit, version, output):
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
    info_path.write_text(json.dumps(info, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.source, args.commit, args.version, args.output)
