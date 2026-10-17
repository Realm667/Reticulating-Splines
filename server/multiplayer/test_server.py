import asyncio
import json
import time
import unittest

from aiohttp import WSMsgType, WSServerHandshakeError
from aiohttp.test_utils import TestClient, TestServer
from server import Directory, PREFIX, create_app, metadata

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

    async def host(self):
        socket = await self.client.ws_connect(PREFIX + "/host")
        self.sockets.append(socket)
        await socket.send_json(dict(version=1, game=GAME))
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


if __name__ == "__main__":
    unittest.main()
