<?php
declare(strict_types=1);
// HTTP-only discovery. Never receives game state, game passwords or chat.
const DIRECTORY_LEASE = 180;

function directory_db(string $path): PDO {
    $db = new PDO('sqlite:' . $path, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    $db->exec('PRAGMA busy_timeout=3000');
    $db->exec('CREATE TABLE IF NOT EXISTS games (id TEXT PRIMARY KEY, token TEXT NOT NULL, ip TEXT NOT NULL, info TEXT NOT NULL, expires INTEGER NOT NULL, started INTEGER NOT NULL DEFAULT 0)');
    $db->exec('CREATE TABLE IF NOT EXISTS limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL)');
    $db->exec('CREATE TABLE IF NOT EXISTS totals (id INTEGER PRIMARY KEY CHECK(id=1), since TEXT, sessions INTEGER, day TEXT, today INTEGER, peak_players INTEGER)');
    $db->exec("INSERT OR IGNORE INTO totals VALUES (1, date('now'), 0, date('now'), 0, 0)");
    return $db;
}

function directory_query(PDO $db, string $sql, array $args = []): PDOStatement {
    $statement = $db->prepare($sql);
    $statement->execute($args);
    return $statement;
}

function directory_metadata(mixed $value): ?array {
    if (!is_array($value)) return null;
    $info = [];
    foreach (['city', 'host', 'build', 'mode', 'phase'] as $key) {
        if (!isset($value[$key]) || !is_string($value[$key]) || strlen($value[$key]) > 256 || preg_match_all('/./us', $value[$key]) > 64 || preg_match('/[\x00-\x1f\x7f]/u', $value[$key])) return null;
        $info[$key] = $value[$key];
    }
    if (!in_array($info['mode'], ['coop', 'shared', 'region'], true) || !in_array($info['phase'], ['lobby', 'running'], true)) return null;
    foreach (['players' => [1, 8], 'port' => [1024, 65535]] as $key => [$low, $high]) {
        if (!isset($value[$key]) || !is_int($value[$key]) || $value[$key] < $low || $value[$key] > $high) return null;
        $info[$key] = $value[$key];
    }
    foreach (['locked', 'open'] as $key) {
        if (!isset($value[$key]) || !is_bool($value[$key])) return null;
        $info[$key] = $value[$key];
    }
    return $info;
}

function directory_limit(PDO $db, string $key, int $max, int $now): bool {
    $key = hash('sha256', $key);
    directory_query($db, 'INSERT INTO limits VALUES (?, 1, ?) ON CONFLICT(key) DO UPDATE SET count=count+1', [$key, $now + 60]);
    return (int)directory_query($db, 'SELECT count FROM limits WHERE key=?', [$key])->fetchColumn() <= $max;
}

function directory_handle(PDO $db, string $method, string $path, mixed $body, string $auth, string $ip, int $now): array {
    $db->exec('BEGIN IMMEDIATE');
    try {
        directory_query($db, 'DELETE FROM games WHERE expires<=?', [$now]);
        directory_query($db, 'DELETE FROM limits WHERE expires<=?', [$now]);
        $result = directory_dispatch($db, $method, $path, $body, $auth, $ip, $now);
        $db->exec('COMMIT');
        return $result;
    } catch (Throwable $e) {
        $db->exec('ROLLBACK');
        throw $e;
    }
}

function directory_dispatch(PDO $db, string $method, string $path, mixed $body, string $auth, string $ip, int $now): array {
    $day = gmdate('Y-m-d', $now);
    if ($method === 'GET' && $path === '/health') return [200, ['ok' => true, 'transport' => 'direct', 'version' => 2]];
    if ($method === 'GET' && in_array($path, ['/games', '/activity'], true)) {
        $games = [];
        foreach ($db->query('SELECT id, ip, info FROM games ORDER BY id') as $row) {
            $info = json_decode($row['info'], true, 16, JSON_THROW_ON_ERROR);
            $info['id'] = $row['id'];
            if ($path === '/games') $info['address'] = $row['ip'];
            else unset($info['port']);
            $games[] = $info;
        }
        $totals = $db->query('SELECT since, sessions, day, today, peak_players FROM totals WHERE id=1')->fetch(PDO::FETCH_ASSOC);
        if ($totals['day'] !== $day) $totals['today'] = 0;
        unset($totals['day']);
        $totals['available'] = true;
        return [200, ['version' => 2, 'games' => $games, 'totals' => $totals]];
    }
    if (!preg_match('#^/games/([a-f0-9]{32})$#D', $path, $match) || !in_array($method, ['PUT', 'DELETE'], true)) return [404, ['error' => 'not_found']];
    if (!preg_match('/^Bearer ([a-f0-9]{64})$/D', $auth, $token)) return [401, ['error' => 'unauthorized']];
    if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) return [400, ['error' => 'public_address_required']];
    $id = $match[1];
    $hash = hash('sha256', $token[1]);
    $row = directory_query($db, 'SELECT * FROM games WHERE id=?', [$id])->fetch(PDO::FETCH_ASSOC);
    if ($row && !hash_equals($row['token'], $hash)) return [403, ['error' => 'unauthorized']];
    if ($method === 'DELETE') {
        directory_query($db, 'DELETE FROM games WHERE id=?', [$id]);
        return [200, ['ok' => true]];
    }
    if (!is_array($body)) return [400, ['error' => 'invalid_game']];
    $info = directory_metadata($body['game'] ?? null);
    if (!$info || ($body['version'] ?? null) !== 2) return [400, ['error' => 'invalid_game']];
    if (!directory_limit($db, 'update:' . $ip, 120, $now)) return [429, ['error' => 'rate_limit']];
    if (!$row) {
        if (!directory_limit($db, 'create:' . $ip, 12, $now)) return [429, ['error' => 'rate_limit']];
        if ((int)$db->query('SELECT count(*) FROM games')->fetchColumn() >= 256 || (int)directory_query($db, 'SELECT count(*) FROM games WHERE ip=?', [$ip])->fetchColumn() >= 4) return [429, ['error' => 'capacity']];
    }
    $started = (int)($row['started'] ?? 0);
    if ($info['phase'] === 'running' && !$started) {
        directory_query($db, 'UPDATE totals SET sessions=sessions+1, today=CASE WHEN day=? THEN today+1 ELSE 1 END, day=? WHERE id=1', [$day, $day]);
        $started = 1;
    }
    directory_query($db, 'INSERT INTO games VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET ip=excluded.ip, info=excluded.info, expires=excluded.expires, started=excluded.started', [$id, $hash, $ip, json_encode($info, JSON_THROW_ON_ERROR), $now + DIRECTORY_LEASE, $started]);
    $players = 0;
    foreach ($db->query('SELECT info FROM games') as $game) $players += json_decode($game['info'], true)['players'];
    directory_query($db, 'UPDATE totals SET peak_players=max(peak_players, ?) WHERE id=1', [$players]);
    return [200, ['version' => 2, 'id' => $id, 'lease' => DIRECTORY_LEASE]];
}
