"""Loopback-only HTTP fixture for game-side integration; PHP has separate tests."""
import asyncio, json, struct
from aiohttp import web


def create_app():
    games = {}
    secrets = {}

    async def listing(request):
        return web.json_response({'version': 2, 'games': list(games.values())})

    async def update(request):
        key = request.match_info['id']
        token = request.headers.get('Authorization', '')
        if key in secrets and secrets[key] != token:
            raise web.HTTPForbidden()
        if request.method == 'DELETE':
            games.pop(key, None)
            secrets.pop(key, None)
            return web.json_response({'ok': True})
        data = await request.json()
        assert data['version'] == 2
        assert type(data['game']['port']) is int and 1024 <= data['game']['port'] <= 65535
        assert type(data['game']['players']) is int
        games[key] = dict(data['game'], id=key, address='127.0.0.1')
        secrets[key] = token
        return web.json_response({'version': 2, 'id': key})

    async def probe(request):
        key = request.match_info['id']
        if key not in games or secrets[key] != request.headers.get('Authorization', ''):
            raise web.HTTPForbidden()
        data = await request.json()
        writer = None
        try:
            reader, writer = await asyncio.open_connection('127.0.0.1', games[key]['port'])
            message = json.dumps({'type':'reachability', 'nonce':data['nonce']}).encode()
            writer.write(struct.pack('<I',len(message)) + message)
            await writer.drain()
            header = await asyncio.wait_for(reader.readexactly(4), 3)
            reply = json.loads(await reader.readexactly(struct.unpack('<I',header)[0]))
            assert reply == {'type':'reachability_ok','nonce':data['nonce']}
        except (OSError, asyncio.TimeoutError, asyncio.IncompleteReadError):
            return web.json_response({'version':2,'status':'unreachable'})
        finally:
            if writer:
                writer.close()
                await writer.wait_closed()
        return web.json_response({'version':2,'status':'reachable'})

    app = web.Application(client_max_size=4096)
    app.router.add_get('/api/multiplayer/v2/games', listing)
    app.router.add_put('/api/multiplayer/v2/games/{id}', update)
    app.router.add_delete('/api/multiplayer/v2/games/{id}', update)
    app.router.add_post('/api/multiplayer/v2/games/{id}/check', probe)
    return app
