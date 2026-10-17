import asyncio
import json
import time
import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch

from aiohttp import WSMsgType, WSServerHandshakeError
from aiohttp.test_utils import TestClient, TestServer
from server import Directory, Totals, PREFIX, create_app, metadata

GAME = dict(city="Test city", host="Mayor", build="opensc2k-multiplayer-22",
            mode="coop", phase="lobby", players=1, locked=True, open=True)


class ServerTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.service = Directory()
        self.client = TestClient(TestServer(create_app(self.service)))
        await self.client.start_server()
        self.sockets = []

    async def asyncTearDown(self):
        for socket in reversed(self.sockets):
            await socket.close()
        await self.client.close()

    async def host(self, game=None):
        socket = await self.client.ws_connect(PREFIX + "/host")
        self.sockets.append(socket)
        await socket.send_json(dict(version=1, game=GAME if game is None else game))
        registered = await socket.receive_json(timeout=2)
        return socket, registered

    async def games(self):
        response = await self.client.get(PREFIX + "/games")
        self.assertEqual(response.status, 200)
        return (await response.json())["games"]

    async def test_listing_updates_expiration_and_cleanup(self):
        control, room = await self.host()
        games = await self.games()
        self.assertEqual(len(games), 1)
        self.assertTrue(games[0]["locked"])
        self.assertNotIn(room["token"], json.dumps(games))
        self.assertNotIn("ip", games[0])
        await control.send_json(dict(type="update", game=dict(GAME, phase="running", players=3)))
        await asyncio.sleep(.01)
        self.assertEqual((await self.games())[0]["players"], 3)
        self.service.rooms[room["id"]].seen = time.monotonic() - 61
        self.assertEqual(await self.games(), [])
        await control.close()
        await asyncio.sleep(.01)
        self.assertEqual(self.service.rooms, {})

    async def test_relay_auth_binary_order_and_unlist(self):
        control, room = await self.host()
        guest = await self.client.ws_connect(PREFIX + "/join/" + room["id"])
        self.sockets.append(guest)
        peer = await control.receive_json(timeout=2)
        path = PREFIX + "/host/" + room["id"] + "/" + peer["id"]
        with self.assertRaises(WSServerHandshakeError) as denied:
            await self.client.ws_connect(path, headers={"Authorization": "Bearer invalid"})
        self.assertEqual(denied.exception.status, 403)
        host = await self.client.ws_connect(path, headers={"Authorization": "Bearer " + room["token"]})
        self.sockets.append(host)
        self.assertEqual((await host.receive_json(timeout=2))["type"], "ready")
        self.assertEqual((await guest.receive_json(timeout=2))["type"], "ready")
        payloads = [b"first", bytes(range(256)) * 256, b"last"]
        for payload in payloads:
            await guest.send_bytes(payload)
            self.assertEqual((await host.receive(timeout=2)).data, payload)
            await host.send_bytes(payload)
            self.assertEqual((await guest.receive(timeout=2)).data, payload)
        await control.send_json({"type": "unlist"})
        await asyncio.sleep(.01)
        self.assertEqual(await self.games(), [])
        # Final city copies still flow after unlisting a gracefully ending host.
        await host.send_bytes(b"final copy")
        self.assertEqual((await guest.receive(timeout=2)).data, b"final copy")
        with self.assertRaises(WSServerHandshakeError):
            await self.client.ws_connect(PREFIX + "/join/" + room["id"])
        await guest.close()
        self.assertIn((await host.receive(timeout=2)).type, (WSMsgType.CLOSE, WSMsgType.CLOSED))

    async def test_bad_registration_and_full_room(self):
        socket = await self.client.ws_connect(PREFIX + "/host")
        self.sockets.append(socket)
        await socket.send_json(["invalid"])
        self.assertEqual((await socket.receive(timeout=2)).type, WSMsgType.CLOSE)
        control, room = await self.host()
        await control.send_json(dict(type="update", game=dict(GAME, open=False)))
        await asyncio.sleep(.01)
        with self.assertRaises(WSServerHandshakeError) as denied:
            await self.client.ws_connect(PREFIX + "/join/" + room["id"])
        self.assertEqual(denied.exception.status, 409)

    async def test_metadata_limits(self):
        for field, value in [("players", True), ("players", 9), ("city", "x" * 65),
                             ("locked", "false"), ("mode", "other"), ("build", [])]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                metadata(dict(GAME, **{field: value}))
        self.assertEqual(metadata(dict(GAME, city="A\nB"))["city"], "AB")
        for _ in range(30):
            self.assertTrue(self.service.allow("test"))
        self.assertFalse(self.service.allow("test"))

    async def test_four_full_rooms_keep_payloads_isolated_and_enforce_capacity(self):
        rooms = []
        pairs = []
        for _ in range(4):
            control, room = await self.host()
            rooms.append((control, room))
            for _ in range(7):
                guest = await self.client.ws_connect(PREFIX + "/join/" + room["id"])
                self.sockets.append(guest)
                peer = await control.receive_json(timeout=2)
                host = await self.client.ws_connect(
                    PREFIX + "/host/" + room["id"] + "/" + peer["id"],
                    headers={"Authorization": "Bearer " + room["token"]})
                self.sockets.append(host)
                self.assertEqual((await guest.receive_json(timeout=2))["type"], "ready")
                self.assertEqual((await host.receive_json(timeout=2))["type"], "ready")
                pairs.append((guest, host))
        self.assertEqual(sum(len(room.peers) for room in self.service.rooms.values()), 28)

        async def exchange(index, guest, host):
            # Distinct data per room/peer/direction detects cross-connection leakage.
            for sequence in range(4):
                payload = bytes([index, sequence]) * 32768
                await guest.send_bytes(payload)
                self.assertEqual((await host.receive(timeout=2)).data, payload)
                reply = bytes([255 - index, sequence]) * 32768
                await host.send_bytes(reply)
                self.assertEqual((await guest.receive(timeout=2)).data, reply)
        await asyncio.gather(*(exchange(i, *pair) for i, pair in enumerate(pairs)))
        with self.assertRaises(WSServerHandshakeError) as full:
            await self.client.ws_connect(PREFIX + "/join/" + rooms[0][1]["id"])
        self.assertEqual(full.exception.status, 409)
        with self.assertRaises(WSServerHandshakeError) as limit:
            await self.client.ws_connect(PREFIX + "/host")
        self.assertEqual(limit.exception.status, 429)

        await pairs[0][0].send_bytes(b"x" * 65537)
        self.assertIn((await pairs[0][1].receive(timeout=2)).type,
                      (WSMsgType.CLOSE, WSMsgType.CLOSED))
        await exchange(27, *pairs[-1])
        await rooms[-1][0].close()
        self.assertIn((await pairs[-1][0].receive(timeout=2)).type,
                      (WSMsgType.CLOSE, WSMsgType.CLOSED))
        await exchange(7, *pairs[7])

    async def test_totals_count_running_once_and_ignore_expired_players(self):
        control, room = await self.host()
        self.assertEqual(self.service.totals.snapshot()["sessions"], 0)
        for _ in range(2):
            await control.send_json(dict(type="update", game=dict(GAME, phase="running", players=3)))
            await asyncio.sleep(.01)
        totals = self.service.totals.snapshot()
        self.assertEqual((totals["sessions"], totals["today"], totals["peak_players"]), (1, 1, 3))
        self.service.rooms[room["id"]].seen = time.monotonic() - 61
        await self.host()
        self.assertEqual(self.service.totals.snapshot()["peak_players"], 3)
        response = await self.client.get(PREFIX + "/games")
        self.assertEqual((await response.json())["totals"]["sessions"], 1)
        await self.host(dict(GAME, phase="running", players=2))
        self.assertEqual(self.service.totals.snapshot()["sessions"], 2)

    async def test_totals_survive_restart_roll_day_and_store_only_aggregates(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "totals.json"
            with patch("server.utc_day", return_value="2026-10-17"):
                totals = Totals(path)
                totals.observe(True, 5)
                await totals.flush()
                loaded = Totals(path)
                self.assertEqual(loaded.snapshot(), totals.snapshot())
            with patch("server.utc_day", return_value="2026-10-18"):
                self.assertEqual(loaded.snapshot()["today"], 0)
                loaded.observe(True, 2)
                await loaded.flush()
                self.assertEqual(loaded.snapshot()["sessions"], 2)
                self.assertEqual(loaded.snapshot()["today"], 1)
                self.assertEqual(loaded.snapshot()["peak_players"], 5)
            self.assertEqual(set(json.loads(path.read_text())),
                             {"since", "sessions", "day", "today", "peak_players"})
            path.write_text('{broken')
            with self.assertRaises(ValueError):
                Totals(path)
            self.assertEqual(path.read_text(), '{broken')

    async def test_totals_write_failure_retries_without_losing_counts(self):
        with tempfile.TemporaryDirectory() as folder:
            totals = Totals(Path(folder) / "totals.json")
            totals.observe(True, 2)
            with patch.object(totals, "write", side_effect=OSError("disk full")):
                await totals.flush()
            self.assertFalse(totals.snapshot()["available"])
            self.assertTrue(totals.dirty)
            await totals.flush()
            self.assertTrue(totals.snapshot()["available"])
            self.assertEqual(Totals(totals.path).snapshot()["sessions"], 1)


if __name__ == "__main__":
    unittest.main()
