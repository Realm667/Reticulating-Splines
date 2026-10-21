"""Check public payload boundaries and installed replacement-pack integrity."""
import json
from pathlib import Path
import tempfile
import subprocess
import verify_rs_native_reuse as reuse
import unittest
from unittest.mock import patch

import rs_release_assets as assets
import smoke_rs_package as smoke


class PublicPayloadTest(unittest.TestCase):
    def test_allowlist_excludes_originals_personal_files_and_build_receipts(self):
        excluded = ["references/SIMCITY2000/SIMCITY.EXE", "data/cities/personal.sc2", "data/settings.cfg",
                    "packs/original/SC2K.DAT", "packs/standalone-audio/music/private.sf2",
                    "packs/standalone-graphics/graphics/render.log", "packs/standalone-graphics/provenance.json"]
        for name in excluded:
            self.assertIsNone(assets.destination(name), name)
        self.assertEqual(assets.destination("packs/standalone-audio/sound/500.wav"), "sounds/reticulating-splines/500.wav")
        self.assertEqual(assets.destination("packs/standalone-graphics/graphics/tiles/1.png"), "graphic/reticulating-splines/tiles/1.png")
        for name in ("../personal.png", "/secret.png", "C:/private.png", "packs\\private.png"):
            with self.assertRaises(ValueError):
                assets.destination(name)

    def test_missing_or_escaping_manifest_assets_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = root / "pack.json"
            for value in ("../outside.png", "/outside.png", "C:/outside.png", "missing.png"):
                manifest.write_text(json.dumps({"sprites": [value]}))
                with self.assertRaises(ValueError):
                    assets.verify_manifest(manifest)
            (root / "tile.png").write_bytes(b"fixture")
            manifest.write_text(json.dumps({"sprites": ["tile.png"]}))
            assets.verify_manifest(manifest)

    def test_inventory_detects_modified_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "app").write_bytes(b"program")
            assets.inventory(folder)
            self.assertEqual(smoke.verify_files(folder), 1)
            (folder / "app").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                smoke.verify_files(folder)

    def test_mac_smoke_refuses_non_disposable_profile(self):
        with patch.dict("os.environ", {"GITHUB_ACTIONS": "false"}):
            with self.assertRaisesRegex(ValueError, "fresh disposable"):
                smoke.smoke(Path("missing"), "macos-universal", Path("unused"))

    def test_install_uses_mac_resources_and_keeps_private_provenance_out(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            fixture = {
                "LICENSE": "MIT", "THIRD_PARTY_NOTICES.md": "OpenSC2K-<version>-fluidsynth-source.zip",
                "game/assets/licenses/CC-BY-4.0.txt": "CC BY", "game/assets/fonts/example/OFL.txt": "OFL",
                "packs/standalone-graphics/provenance.json": json.dumps(dict(scope="own", generation="drawn", references=[], license="CC-BY-4.0", private_work_path="secret")),
                "packs/standalone-graphics/graphics/pack.json": '{"files":["tile.png"]}',
                "packs/standalone-graphics/graphics/tile.png": "tile",
                "packs/standalone-graphics/graphics/render.log": "private",
                "packs/standalone-audio/provenance.json": "{}", "packs/standalone-audio/README.txt": "CC BY",
                "packs/standalone-audio/music/pack.json": '{"files":["song.mp3"]}',
                "packs/standalone-audio/music/song.mp3": "song",
                "packs/standalone-audio/sound/pack.json": '{"files":["500.wav"]}',
                "packs/standalone-audio/sound/500.wav": "sound",
            }
            for name, contents in fixture.items():
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)
            bundle = root / "source.zip"
            bundle.write_bytes(b"source")
            for platform in ("macos-universal", "linux-x64", "windows-x64"):
                folder = root / platform
                folder.mkdir()
                assets.install(source, folder, platform, bundle)
                public = folder / "ReticulatingSplines.app/Contents/Resources" if platform.startswith("macos") else folder
                data = public / ("bundled-packs" if platform.startswith("macos") else "data")
                self.assertTrue((data / "graphic/reticulating-splines/tile.png").is_file())
                self.assertFalse((data / "graphic/reticulating-splines/render.log").exists())
                provenance = (public / "licenses/reticulating-splines/graphics-provenance.json").read_text()
                self.assertNotIn("secret", provenance)
                self.assertEqual((public / "FluidSynth-corresponding-source.zip").read_bytes(), b"source")
                self.assertTrue((public / "licenses/CC-BY-4.0.txt").exists())
                if platform.startswith("macos"):
                    self.assertIn("ReticulatingSplines.app/Contents/Resources/FluidSynth-corresponding-source.zip", (folder / "THIRD_PARTY_NOTICES.md").read_text())


class NativeReuseTest(unittest.TestCase):
    def test_exported_game_changes_can_reuse_but_native_inputs_cannot(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, text=True).strip()
            git("init", "-b", "main")
            git("config", "user.name", "Package test")
            git("config", "user.email", "test@example.invalid")
            (root / "native").mkdir()
            (root / "native/lib.rs").write_text("original")
            git("add", ".")
            git("commit", "-m", "Original")
            base = git("rev-parse", "HEAD")
            (root / "README.md").write_text("Release instructions")
            (root / "game").mkdir()
            (root / "game/export_presets.cfg").write_text("New bundle identity")
            (root / "game/project.godot").write_text('config/version="next"')
            (root / "game/menu.gd").write_text("# Changed UI")
            (root / "game/effect.gdshader").write_text("// Changed shader")
            git("add", ".")
            git("commit", "-m", "Packaging")
            reuse.matching_sources(base, repository=root)
            (root / "native/lib.rs").write_text("changed")
            git("add", ".")
            git("commit", "-m", "Native change")
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                reuse.matching_sources(base, repository=root)
            for name in ("game/bin/module.gdextension", "tools/build_fluidsynth.py",
                         "native/Cargo.lock", "rust-toolchain.toml",
                         ".github/workflows/rs-desktop.yml"):
                with self.subTest(input=name):
                    before = git("rev-parse", "HEAD")
                    path = root / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("Changed native build input")
                    git("add", ".")
                    git("commit", "-m", "Build input change")
                    with self.assertRaisesRegex(ValueError, "inputs changed"):
                        reuse.matching_sources(before, repository=root)


if __name__ == "__main__":
    unittest.main()
