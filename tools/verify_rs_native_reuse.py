"""Allow native artifact reuse only from successful jobs with matching build inputs."""
import argparse
import json
from pathlib import Path
import re
import subprocess

NATIVE_JOBS = {f"Build native libraries ({name})" for name in
               ("macos", "linux-x86_64", "linux-arm64", "windows-x86_64", "windows-arm64")}
# GDScript, shaders, translations and project version are exported separately.
# Native sources/build scripts are self-contained under native/; retain extension
# descriptors and the workflow recipe as compatibility/build-environment inputs.
BUILD_INPUTS = ["native", "game/bin", "tools/build_native.py", "tools/build_fluidsynth.py",
                ".github/workflows/rs-desktop.yml", ".cargo", "Cargo.lock", "Cargo.toml",
                "rust-toolchain.toml", "rust-toolchain"]


def matching_sources(previous, current="HEAD", repository=Path(".")):
    changed = subprocess.check_output(["git", "diff", "--name-only", previous, current, "--", *BUILD_INPUTS],
                                      cwd=repository, text=True).splitlines()
    if changed:
        raise ValueError("Native artifact inputs changed: " + ", ".join(changed))


def verify(repository, run_id):
    if not re.fullmatch(r"[0-9]+", run_id):
        raise ValueError("Expected a numeric workflow run ID")
    def api(path):
        return json.loads(subprocess.check_output(["gh", "api", f"repos/{repository}/{path}"], text=True))
    run = api(f"actions/runs/{run_id}")
    if run["head_repository"]["full_name"].lower() != repository.lower() or run["path"] != ".github/workflows/rs-desktop.yml":
        raise ValueError("Native artifacts must come from this repository's RS workflow")
    sha = run["head_sha"]
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Invalid source SHA")
    jobs = api(f"actions/runs/{run_id}/jobs?per_page=100")["jobs"]
    successful = {job["name"] for job in jobs if job["conclusion"] == "success"}
    if not NATIVE_JOBS <= successful:
        raise ValueError("The source run has not completed every native build successfully")
    subprocess.run(["git", "fetch", "--no-tags", "--depth=1", "origin", sha], check=True)
    matching_sources(sha)
    print(f"PASS: reuse native artifacts from {run_id}, source {sha}; native inputs match")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run", required=True)
    args = parser.parse_args()
    verify(args.repository, args.run)
