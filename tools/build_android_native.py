#!/usr/bin/env python3
"""Cross-build ARM64 Android extensions and dynamically loaded FluidSynth.

Requires an installed Android NDK, CMake, Ninja, and Rust. Never builds the
desktop native application or writes desktop libraries. See docs/android.md.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

import build_fluidsynth as fluid

ROOT = Path(__file__).resolve().parents[1]
MODULES = ('simulation', 'rendering', 'formats', 'audio', 'scripting')
TRIPLE = 'aarch64-linux-android'
API = '28'


def run(args, env):
    subprocess.run([str(a) for a in args], env=env, check=True)


def build(ndk):
    ndk = ndk.resolve(strict=True)
    host = 'windows-x86_64' if sys.platform == 'win32' else 'linux-x86_64'
    toolchain = ndk / 'toolchains/llvm/prebuilt' / host / 'bin'
    suffix = '.cmd' if sys.platform == 'win32' else ''
    compiler = toolchain / f'aarch64-linux-android{API}-clang{suffix}'
    if not compiler.is_file():
        raise SystemExit(f'Android compiler missing: {compiler}')
    env = dict(os.environ)
    target_directory = Path(env.get('CARGO_TARGET_DIR', str(ROOT / 'native/target'))).resolve()
    env['CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER'] = str(compiler)
    env['CC_aarch64_linux_android'] = str(compiler)
    env['AR_aarch64_linux_android'] = str(toolchain / ('llvm-ar.exe' if suffix else 'llvm-ar'))
    run(['rustup', 'target', 'add', TRIPLE], env)
    command = ['cargo', 'build', '--manifest-path', ROOT / 'native/Cargo.toml', '--locked', '--release', '--target', TRIPLE]
    for module in MODULES:
        command += ['-p', f'opensc2k_{module}']
    run(command, env)
    work = ROOT / 'native/audio/target/fluidsynth/android-arm64'
    prefix = work / 'prefix'
    prefix.mkdir(parents=True, exist_ok=True)

    def configure(source, name, options):
        run(['cmake', '-S', source, '-B', work / 'build' / name, '-G', 'Ninja',
             *fluid.COMMON_OPTIONS,
             f'-DCMAKE_TOOLCHAIN_FILE={ndk / "build/cmake/android.toolchain.cmake"}',
             '-DANDROID_ABI=arm64-v8a', f'-DANDROID_PLATFORM=android-{API}',
             '-DANDROID_STL=c++_static', f'-DCMAKE_INSTALL_PREFIX={prefix}',
             f'-DCMAKE_PREFIX_PATH={prefix}', f'-DCMAKE_FIND_ROOT_PATH={prefix}', *options], env)
        run(['cmake', '--build', work / 'build' / name, '--parallel', '4'], env)
        run(['cmake', '--install', work / 'build' / name], env)

    for name in ('ogg', 'vorbis', 'flac', 'opus', 'sndfile'):
        source = fluid.extract(fluid.download(*fluid.SOURCES[name]), work / 'source' / name)
        configure(source, name, fluid.DEPENDENCY_OPTIONS[name])
    source = fluid.extract(fluid.download(*fluid.SOURCES['fluidsynth']), work / 'source/fluidsynth')
    for name, folder in (('gcem', 'gcem'), ('signalsmith', 'signalsmith-audio-basics')):
        dependency = fluid.extract(fluid.download(*fluid.SOURCES[name]), work / 'source' / name)
        shutil.copytree(dependency, source / folder, dirs_exist_ok=True)
    options = [*fluid.FLUIDSYNTH_OPTIONS, '-DFETCHCONTENT_FULLY_DISCONNECTED=ON',
               '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384']
    for name in ('signalsmith-linear', 'signalsmith-dsp', 'signalsmith-hilbert'):
        dependency = fluid.extract(fluid.download(*fluid.SOURCES[name]), work / 'source' / name)
        options.append(f'-DFETCHCONTENT_SOURCE_DIR_{name.upper()}={dependency}')
    codecs = ' '.join((prefix / 'lib' / f'lib{name}.a').as_posix() for name in fluid.CODEC_LIBRARIES)
    options += [f'-DCMAKE_C_STANDARD_LIBRARIES={codecs} -lm', f'-DCMAKE_CXX_STANDARD_LIBRARIES={codecs} -lm']
    configure(source, 'fluidsynth', options)
    for module in MODULES:
        destination = ROOT / 'game/bin' / f'opensc2k_{module}' / 'android-arm64'
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target_directory / TRIPLE / 'release' / f'libopensc2k_{module}.so', destination)
    library = prefix / 'lib/libfluidsynth.so'
    shutil.copy2(library.resolve(strict=True), ROOT / 'game/bin/opensc2k_audio/android-arm64/libfluidsynth.so')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ndk', type=Path, default=os.environ.get('ANDROID_NDK_HOME'))
    args = parser.parse_args()
    if args.ndk is None:
        parser.error('--ndk or ANDROID_NDK_HOME is required')
    build(args.ndk)
