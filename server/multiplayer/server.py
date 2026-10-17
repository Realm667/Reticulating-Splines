"""Ephemeral directory and bounded relay; deploy behind an HTTPS reverse proxy.

No accounts, credentials or game payloads are persisted. The host owns admission
and simulation. TLS protects both network hops; the relay is a trusted operator.
"""
import asyncio
import contextlib
import json
import ipaddress
import os
from pathlib import Path
import secrets
import time
from dataclasses import dataclass, field

from aiohttp import WSMsgType, web

PREFIX = "/api/multiplayer/v1"
CHUNK = 65536
MAX_ROOMS = 256
LEASE = 60


def metadata(value):
    if not isinstance(value, dict):
        raise ValueError("metadata")
    result = {}
    for key in ("city", "host", "build", "mode", "phase"):
        text = value.get(key)
        if not isinstance(text, str) or not 1 <= len(text) <= 64:
            raise ValueError(key)
        result[key] = "".join(c for c in text if c.isprintable())
    if result["mode"] not in ("coop", "shared", "region") or result["phase"] not in ("lobby", "running"):
        raise ValueError("mode/phase")
    if type(value.get("players")) is not int or not 1 <= value["players"] <= 8:
        raise ValueError("players")
    for key in ("locked", "open"):
        if type(value.get(key)) is not bool:
            raise ValueError(key)
        result[key] = value[key]
    result["players"] = value["players"]
    return result


@dataclass
class Pair:
    guest: web.WebSocketResponse
    host: web.WebSocketResponse | None = None
    ready: asyncio.Event = field(default_factory=asyncio.Event)
    guest_ready: asyncio.Event = field(default_factory=asyncio.Event)
    host_ready: asyncio.Event = field(default_factory=asyncio.Event)


@dataclass
class Room:
    control: web.WebSocketResponse
    token: str
    ip: str
    info: dict
    seen: float = field(default_factory=time.monotonic)
    listed: bool = True
    peers: dict = field(default_factory=dict)


class Directory:
    def __init__(self):
        self.rooms = {}
        self.rates = {}
        self.host_slots = {}

    def allow(self, key, maximum=30):
        now = time.monotonic()
        self.rates = {k: v for k, v in self.rates.items() if now - v[0] < 60}
        if key not in self.rates and len(self.rates) >= 4096:
            return False
        start, count = self.rates.get(key, (now, 0))
        self.rates[key] = (start, count + 1)
        return count < maximum

    async def games(self, request):
        now = time.monotonic()
        games = [dict(room.info, id=key) for key, room in self.rooms.items()
                 if room.listed and now - room.seen < LEASE and not room.control.closed]
        return web.json_response({"version": 1, "games": games}, headers={
            "Cache-Control": "public, max-age=5", "Access-Control-Allow-Origin": "*"})

    async def host(self, request):
        ip = request.remote or "unknown"
        if (sum(self.host_slots.values()) >= MAX_ROOMS or self.host_slots.get(ip, 0) >= 4
                or not self.allow((ip, "host"), 12)):
            raise web.HTTPTooManyRequests()
        self.host_slots[ip] = self.host_slots.get(ip, 0) + 1
        ws = web.WebSocketResponse(max_msg_size=2048, heartbeat=20, compress=False)
        room_id = secrets.token_hex(16)
        room = None
        try:
            await ws.prepare(request)
            first = await asyncio.wait_for(ws.receive(), 10)
            if first.type != WSMsgType.TEXT:
                raise ValueError("registration")
            packet = json.loads(first.data)
            if not isinstance(packet, dict) or packet.get("version") != 1:
                raise ValueError("protocol")
            room = Room(ws, secrets.token_hex(32), ip, metadata(packet.get("game")))
            if len(self.rooms) >= MAX_ROOMS or sum(r.ip == ip for r in self.rooms.values()) >= 4:
                raise ValueError("capacity")
            self.rooms[room_id] = room
            await ws.send_json({"type": "registered", "id": room_id, "token": room.token})
            async for message in ws:
                if message.type != WSMsgType.TEXT or not self.allow((room_id, "update"), 90):
                    break
                packet = json.loads(message.data)
                if not isinstance(packet, dict):
                    break
                if packet.get("type") == "update":
                    room.info = metadata(packet.get("game"))
                    room.seen = time.monotonic()
                elif packet.get("type") == "unlist":
                    room.listed = False
                    room.seen = time.monotonic()
                else:
                    break
        except (ValueError, TypeError, asyncio.TimeoutError, ConnectionError):
            pass
        finally:
            self.host_slots[ip] -= 1
            if not self.host_slots[ip]:
                del self.host_slots[ip]
            self.rooms.pop(room_id, None)
            if room:
                for pair in list(room.peers.values()):
                    await pair.guest.close()
                    if pair.host is not None:
                        await pair.host.close()
            await ws.close()
        return ws

    async def join(self, request):
        room = self.rooms.get(request.match_info["room"])
        if room is None or not room.listed or time.monotonic() - room.seen >= LEASE:
            raise web.HTTPNotFound()
        if not room.info["open"] or len(room.peers) >= 7:
            raise web.HTTPConflict()
        if not self.allow((request.remote, "join"), 30):
            raise web.HTTPTooManyRequests()
        ws = web.WebSocketResponse(max_msg_size=CHUNK + 1, heartbeat=20, compress=False)
        peer_id = secrets.token_hex(16)
        pair = Pair(ws)
        room.peers[peer_id] = pair
        try:
            await ws.prepare(request)
            await asyncio.wait_for(room.control.send_json({"type": "peer", "id": peer_id}), 5)
            await asyncio.wait_for(pair.ready.wait(), 10)
            await ws.send_json({"type": "ready"})
            pair.guest_ready.set()
            await asyncio.wait_for(pair.host_ready.wait(), 10)
            await self.forward(ws, pair.host)
        except (asyncio.TimeoutError, ConnectionError, RuntimeError):
            pass
        finally:
            room.peers.pop(peer_id, None)
            if pair.host is not None:
                await pair.host.close()
            await ws.close()
        return ws

    async def attach(self, request):
        room = self.rooms.get(request.match_info["room"])
        bearer = request.headers.get("Authorization", "")
        if room is None or not secrets.compare_digest(bearer, "Bearer " + room.token):
            raise web.HTTPForbidden()
        pair = room.peers.get(request.match_info["peer"])
        if pair is None or pair.host is not None:
            raise web.HTTPNotFound()
        ws = web.WebSocketResponse(max_msg_size=CHUNK + 1, heartbeat=20, compress=False)
        pair.host = ws
        try:
            await ws.prepare(request)
            pair.ready.set()
            await asyncio.wait_for(pair.guest_ready.wait(), 10)
            await ws.send_json({"type": "ready"})
            pair.host_ready.set()
            await self.forward(ws, pair.guest)
        except (asyncio.TimeoutError, ConnectionError, RuntimeError):
            pass
        finally:
            await pair.guest.close()
            await ws.close()
        return ws

    @staticmethod
    async def forward(source, target):
        # Await each write: bounded buffers apply backpressure per connection.
        # A stalled recipient cannot accumulate an unbounded city queue.
        async for message in source:
            if message.type != WSMsgType.BINARY or len(message.data) > CHUNK:
                break
            await asyncio.wait_for(target.send_bytes(message.data), 10)

    async def lifecycle(self, app):
        async def expire():
            while True:
                await asyncio.sleep(5)
                for room in list(self.rooms.values()):
                    if time.monotonic() - room.seen >= LEASE:
                        await room.control.close()
        task = asyncio.create_task(expire())
        yield
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
        for room in list(self.rooms.values()):
            await room.control.close()


async def health(_request):
    return web.json_response({"status": "ok"})


@web.middleware
async def proxy_identity(request, handler):
    # Only trust the explicitly configured local reverse proxy, never arbitrary
    # forwarded headers from public clients. The proxy must replace X-Real-IP.
    trusted = os.getenv("TRUST_PROXY", "").split(",")
    if request.remote in trusted:
        try:
            remote = str(ipaddress.ip_address(request.headers.get("X-Real-IP", "")))
        except ValueError:
            raise web.HTTPBadRequest()
        request = request.clone(remote=remote)
    return await handler(request)


def create_app(service=None):
    service = service or Directory()
    app = web.Application(client_max_size=2048, middlewares=[proxy_identity])
    app.cleanup_ctx.append(service.lifecycle)
    app.router.add_get(PREFIX + "/games", service.games)
    app.router.add_get(PREFIX + "/host", service.host)
    app.router.add_get(PREFIX + "/join/{room}", service.join)
    app.router.add_get(PREFIX + "/host/{room}/{peer}", service.attach)
    app.router.add_get("/health", health)
    app.router.add_static("/widgets/", Path(__file__).parent / "widgets", show_index=False)
    return app


if __name__ == "__main__":
    web.run_app(create_app(), host=os.getenv("BIND", "127.0.0.1"),
                port=int(os.getenv("PORT", "8787")), access_log=None)
