"""Run the real Godot relay integration against a disposable loopback service.

Usage: python run_game_test.py --godot PATH --project ISOLATED_PROJECT
The project must already be imported, built, and use a disposable user profile.
"""
import argparse
import asyncio
import os
from pathlib import Path

from aiohttp import web
from server import create_app


async def run(args):
    runner = web.AppRunner(create_app(), access_log=None)
    await runner.setup()
    site = web.TCPSite(runner, "127.0.0.1", 0)
    await site.start()
    port = runner.addresses[0][1]
    environment = dict(os.environ, RS_MULTIPLAYER_URL=f"http://127.0.0.1:{port}")
    command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", args.project,
               "--script", Path(__file__).with_name("godot_integration.gd").as_posix()]
    process = None
    try:
        process = await asyncio.create_subprocess_exec(*command, env=environment,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
        output, _ = await asyncio.wait_for(process.communicate(), 90)
        text = output.decode("utf-8", errors="replace")
        print(text, end="", flush=True)
        return process.returncode or (0 if "Relay integration: 0 failure(s)" in text else 1)
    finally:
        if process is not None and process.returncode is None:
            process.terminate()
            await process.wait()
        await runner.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", required=True)
    raise SystemExit(asyncio.run(run(parser.parse_args())))
