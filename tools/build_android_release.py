#!/usr/bin/env python3
"""Export an ARM64 APK from a clean checkout and prebuilt native libraries.

Signing secrets are supplied only through Godot's keystore environment variables.
The work directory holds a reusable isolated editor/import cache, never user data.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

import rs_release_assets

ROOT = Path(__file__).resolve().parents[1]


def build(args):
    if subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'], text=True).strip():
        raise SystemExit('Commit the reviewed source before exporting an Android package')
    commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    version = re.search(r'config/version="([^"]+)"', (ROOT / 'game/project.godot').read_text()).group(1)
    work = args.work.resolve()
    if ROOT.is_relative_to(work) or work.is_relative_to(ROOT):
        raise SystemExit('Use a separate work directory outside the checkout')
    project = work / 'project'
    project.mkdir(parents=True, exist_ok=True)
    tracked = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z', 'game'], text=True).split('\0')
    for relative in filter(None, tracked):
        if relative.startswith('game/tests/'):
            continue
        destination = project / Path(relative).relative_to('game')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, destination)
    host = 'windows-x86_64' if os.name == 'nt' else 'linux-x86_64'
    for module in ('simulation', 'rendering', 'formats', 'audio', 'scripting'):
        for platform in ('android-arm64', host):
            shutil.copytree(ROOT / f'game/bin/opensc2k_{module}' / platform,
                            project / f'bin/opensc2k_{module}' / platform, dirs_exist_ok=True)
    bundle = project / 'android-packs.zip'
    with zipfile.ZipFile(bundle, 'w', zipfile.ZIP_DEFLATED, compresslevel=3, strict_timestamps=False) as archive:
        files = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z', 'packs', 'game/assets/licenses'], text=True).split('\0')
        for relative in filter(None, files):
            destination = rs_release_assets.destination(relative)
            if relative.startswith('game/assets/licenses/'):
                destination = 'licenses/' + relative.removeprefix('game/assets/licenses/')
            if destination:
                archive.write(ROOT / relative, destination)
    digest = hashlib.file_digest(bundle.open('rb'), 'sha256').hexdigest()
    (project / 'android-packs.zip.sha256').write_text(digest)
    preset = project / 'export_presets.cfg'
    preset.write_text(preset.read_text().replace('include_filter="', 'include_filter="android-packs.zip,android-packs.zip.sha256,'))
    engine = work / 'engine'
    engine.mkdir(exist_ok=True)
    executable = engine / ('Godot.exe' if os.name == 'nt' else 'godot')
    shutil.copy2(args.godot, executable)
    (engine / '_sc_').touch()
    settings = engine / 'editor_data/editor_settings-4.7.tres'
    settings.parent.mkdir(exist_ok=True)
    settings.write_text('[gd_resource type="EditorSettings" format=3]\n[resource]\n'
                        'export/android/android_sdk_path = ' + json.dumps(args.sdk.resolve().as_posix()) + '\n'
                        'export/android/java_sdk_path = ' + json.dumps(args.java.resolve().as_posix()) + '\n')
    templates = settings.parent / 'export_templates/4.7.2.stable'
    templates.mkdir(parents=True, exist_ok=True)
    for name in ('android_debug.apk', 'android_release.apk'):
        shutil.copy2(args.templates / name, templates / name)
    args.output.mkdir(parents=True, exist_ok=True)
    apk = args.output.resolve() / f'ReticulatingSplines-{version}-android-arm64.apk'
    env = dict(os.environ, JAVA_HOME=str(args.java.resolve()), ANDROID_HOME=str(args.sdk.resolve()))
    env['TEMP'] = env['TMP'] = str(work / 'tmp')
    Path(env['TEMP']).mkdir(exist_ok=True)
    if not args.debug and not env.get('GODOT_ANDROID_KEYSTORE_RELEASE_PATH'):
        raise SystemExit('A protected release keystore is required; use --debug only for internal tests')
    for label, options in [('import', ['--editor', '--import', '--quit']),
                           ('export', ['--export-debug' if args.debug else '--export-release', 'Android ARM64', str(apk)])]:
        with (work / f'{label}.log').open('wb') as log:
            subprocess.run([str(executable), '--headless', '--audio-driver', 'Dummy', '--path', str(project), *options],
                           env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=900)
    with apk.open('rb') as stream:
        checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
    (args.output / 'android-build-info.json').write_text(json.dumps(dict(commit=commit, version=version,
        platform='android-arm64', debug=args.debug, archive=apk.name, sha256=checksum, bundled_sha256=digest), indent=2) + '\n')
    print(apk)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('godot', 'work', 'output', 'sdk', 'java', 'templates'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--debug', action='store_true')
    build(parser.parse_args())
