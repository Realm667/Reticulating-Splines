#!/usr/bin/env python3
"""Run the real cloud client against a disposable, loopback-only PHP service.

Requires PHP with PDO SQLite and the project's Godot/native build. Credentials,
mail codes, database and uploaded saves live only in a TemporaryDirectory.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--php", default="php")
    parser.add_argument("--php-extension-dir")
    parser.add_argument("--artifact-dir", type=Path)
    arguments = parser.parse_args()
    checkout = Path(__file__).resolve().parent.parent
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="rs-cloud-http-") as folder:
        fixture = Path(folder)
        config = fixture / "config.php"
        config.write_text("""<?php
return [
 'storage' => __DIR__ . '/private',
 'secret' => '%s',
 'allow_local_http' => true,
 'quota' => 500 * 1024 * 1024,
 'base_path' => '/api/cloud/v1',
 'mail' => static function ($email, $purpose, $code): void {
   file_put_contents(__DIR__ . '/' . hash('sha256', $email . ':' . $purpose) . '.code', $code);
 }
];
""" % secrets.token_hex(32), encoding="utf-8")
        endpoint = f"http://127.0.0.1:{port}/api/cloud/v1"
        environment = dict(os.environ, RS_CLOUD_CONFIG=str(config),
                           RS_CLOUD_TEST_DIRECTORY=str(fixture), RS_CLOUD_TEST_ENDPOINT=endpoint)
        command = [arguments.php]
        if arguments.php_extension_dir:
            command += ["-d", f"extension_dir={arguments.php_extension_dir}", "-d", "extension=pdo_sqlite"]
        command += ["-S", f"127.0.0.1:{port}", "-t", "server/cloud/public", "server/cloud/public/index.php"]
        flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        with (fixture / "server.log").open("wb") as server_log:
            server = subprocess.Popen(command, cwd=checkout, env=environment, stdout=server_log,
                                      stderr=subprocess.STDOUT, creationflags=flags)
            try:
                ready = False
                for _ in range(100):
                    if server.poll() is not None:
                        break
                    try:
                        urllib.request.urlopen(endpoint + "/me", timeout=0.2).close()
                    except urllib.error.HTTPError as error:
                        ready = error.code == 401
                    except (OSError, urllib.error.URLError):
                        pass
                    if ready:
                        break
                    time.sleep(0.1)
                if not ready:
                    raise RuntimeError("Disposable PHP service did not become ready; PDO SQLite is required.")
                run = subprocess.run([arguments.godot, "--headless", "--audio-driver", "Dummy",
                                      "--path", "game", "--script", "tests/integration/cloud_http_integration_test.gd"],
                                     cwd=checkout, env=environment, capture_output=True, text=True,
                                     encoding="utf-8", errors="replace", timeout=180, creationflags=flags)
                output = run.stdout + run.stderr
                passed = (run.returncode == 0 and "Cloud HTTP integration: 0 failure(s)" in output
                          and "SCRIPT ERROR" not in output and "ERROR:" not in output)
                if arguments.artifact_dir:
                    arguments.artifact_dir.mkdir(parents=True, exist_ok=True)
                    (arguments.artifact_dir / "cloud-http.log").write_text(output, encoding="utf-8")
                    (arguments.artifact_dir / "cloud-http.json").write_text(json.dumps({
                        "passed": passed, "exit_code": run.returncode, "fixture": "disposable loopback PHP/SQLite",
                        "test": "game/tests/integration/cloud_http_integration_test.gd"}, indent=2), encoding="utf-8")
                print(output, end="")
                return 0 if passed else 1
            finally:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
