"""Real HTTP boundary test. Loopback, synthetic accounts, private fake-mail spool only."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--php", required=True)
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    checks = 0
    with tempfile.TemporaryDirectory(prefix="rs-cloud-http-") as temporary:
        folder = Path(temporary)
        config = folder / "config.php"
        spool = folder / "codes.json"

        def configure(allow_http: bool, public_storage: bool = False) -> None:
            storage = source / "public" / "must-not-create" if public_storage else folder / "data"
            # PHP string literal; all values are generated local test paths.
            quote = lambda value: "'" + str(value).replace("\\", "/").replace("'", "\\'") + "'"
            config.write_text(
                "<?php return ['storage'=>" + quote(storage) + ", 'secret'=>str_repeat('7',64),"
                "'allow_local_http'=>" + ("true" if allow_http else "false") + ","
                "'garbage_interval'=>3600,"
                "'base_path'=>'/cloud-saves/api/cloud/v1',"
                "'mail'=>static function($email,$purpose,$code){file_put_contents("
                + quote(spool) + ",json_encode(['email'=>$email,'purpose'=>$purpose,'code'=>$code]));}];",
                encoding="utf-8",
            )

        configure(True)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        env = dict(os.environ, RS_CLOUD_CONFIG=str(config))
        log = (folder / "server.log").open("wb")
        process = subprocess.Popen(
            [args.php, "-S", f"127.0.0.1:{port}", "-t", str(source / "public"), str(source / "public" / "index.php")],
            env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        base = f"http://127.0.0.1:{port}/cloud-saves/api/cloud/v1"

        def check(condition: bool, label: str) -> None:
            nonlocal checks
            checks += 1
            if not condition:
                raise AssertionError(label)

        def call(method: str, path: str, body=None, token: str = "", expected: int = 200, content_type="application/json"):
            data = json.dumps(body).encode() if body is not None and not isinstance(body, bytes) else body
            headers = {"Content-Type": content_type}
            if token:
                headers["Authorization"] = "Bearer " + token
            request = Request(base + path, data=data, headers=headers, method=method)
            try:
                response = urlopen(request, timeout=15)
            except HTTPError as error:
                response = error
            with response:
                payload = response.read()
                check(response.status == expected, f"{method} {path}: expected {expected}, got {response.status}: {payload[:200]!r}")
                check("no-store" in response.headers.get("Cache-Control", ""), "private response not cacheable")
                check(response.headers.get("Access-Control-Allow-Origin") is None, "no browser CORS access")
                if response.headers.get("Content-Type", "").startswith("application/octet-stream"):
                    return payload, response.headers
                return json.loads(payload)

        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError("PHP server exited before startup")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                        break
                except OSError:
                    time.sleep(0.03)
            else:
                raise TimeoutError("PHP server did not start")
            (folder / "data" / "blobs").mkdir(parents=True)
            orphan = folder / "data" / "blobs" / "expired-orphan"
            orphan.write_bytes(b"synthetic orphan")
            call("GET", "/me", expected=401)
            check(not orphan.exists(), "HTTP maintenance runs without bypassing authentication")
            orphan.write_bytes(b"next-hour orphan")
            call("GET", "/me", expected=401)
            check(orphan.exists(), "HTTP maintenance is throttled across requests")
            call("POST", "/register", b"{broken", expected=400)
            call("POST", "/register", [], expected=400)
            call("POST", "/register", b"{}", expected=415, content_type="text/plain")
            call("POST", "/register", b" " * 196609, expected=413)
            call("PUT", "/saves/ignored", b"x" * 1048577, expected=413, content_type="application/octet-stream")
            account = {"email": "http-fixture@example.test", "password": "http-test-password"}
            call("POST", "/register", account)
            mailed = json.loads(spool.read_text())
            check(mailed["email"] == account["email"] and mailed["purpose"] == "verify", "fake mail adapter receives code")
            call("POST", "/verify", {"email": account["email"], "code": mailed["code"]})
            session = call("POST", "/login", dict(account, device="HTTP fixture"))
            token = session["token"]
            call("GET", "/me", token=token)
            png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6p8AAAAASUVORK5CYII="
            created = call("POST", "/saves", {"name": "HTTP snapshot", "kind": "region", "metadata": {"preview": png}}, token, 201)
            save = created["id"]
            raw = bytes(range(256)) * 5000
            digest = hashlib.sha256(raw).hexdigest()
            upload = call("POST", f"/saves/{save}/uploads", {"base_revision": None, "size": len(raw), "sha256": digest, "metadata": {"preview": png}}, token, 201)
            for index, offset in enumerate(range(0, len(raw), 1048576)):
                call("PUT", f"/saves/{save}/uploads/{upload['id']}/chunks/{index}", raw[offset:offset + 1048576], token, content_type="application/octet-stream")
            version = call("POST", f"/saves/{save}/uploads/{upload['id']}/commit", {}, token, 201)
            repeat = call("POST", f"/saves/{save}/uploads/{upload['id']}/commit", {}, token)
            check(repeat["revision"] == version["revision"], "HTTP lost-response retry")
            downloaded, headers = call("GET", f"/saves/{save}/versions/{version['revision']}/content", token=token)
            check(downloaded == raw, "streamed binary round trip")
            check(headers.get("X-Content-SHA256") == digest and int(headers["Content-Length"]) == len(raw), "download integrity headers")
            listing = call("GET", "/saves", token=token)
            check("preview" not in listing["saves"][0]["metadata"], "account list omits previews")
            versions = call("GET", f"/saves/{save}/versions", token=token)
            check(versions["versions"][0]["metadata"]["preview"] == png, "selected version retains HTTP preview")
            call("GET", "/../../config.php", token=token, expected=404)
            configure(False)
            call("GET", "/me", token=token, expected=426)
            configure(True)
            call("DELETE", "/devices/" + session["device_id"], token=token)
            call("GET", "/me", token=token, expected=401)
            check(not any(word in (folder / "server.log").read_text(errors="replace") for word in ("PHP Warning", "PHP Fatal", "PHP Parse")), "no PHP errors")
            print(f"Cloud HTTP: {checks} checks passed")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            log.close()


if __name__ == "__main__":
    main()
