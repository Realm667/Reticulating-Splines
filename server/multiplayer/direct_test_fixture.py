"""Loopback-only HTTP fixture for game-side integration; PHP has separate tests."""
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

    app = web.Application(client_max_size=4096)
    app.router.add_get('/api/multiplayer/v2/games', listing)
    app.router.add_put('/api/multiplayer/v2/games/{id}', update)
    app.router.add_delete('/api/multiplayer/v2/games/{id}', update)
    return app
