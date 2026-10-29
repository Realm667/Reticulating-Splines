<?php
declare(strict_types=1);
// Opt-in presence only. Single-player records never enter the join directory.
function activity_schema(PDO $db): void {
    $db->exec('CREATE TABLE IF NOT EXISTS solo_sessions (id TEXT PRIMARY KEY, token TEXT NOT NULL, source TEXT NOT NULL, info TEXT NOT NULL, expires INTEGER NOT NULL)');
    $db->exec('CREATE TABLE IF NOT EXISTS solo_cities (id TEXT PRIMARY KEY, population INTEGER NOT NULL, updated INTEGER NOT NULL)');
    $db->exec('CREATE TABLE IF NOT EXISTS solo_totals (id INTEGER PRIMARY KEY CHECK(id=1), since TEXT, sessions INTEGER, day TEXT, today INTEGER, peak_players INTEGER)');
    $db->exec("INSERT OR IGNORE INTO solo_totals VALUES (1, date('now'), 0, date('now'), 0, 0)");
    $db->exec('CREATE TABLE IF NOT EXISTS activity_peak (id INTEGER PRIMARY KEY CHECK(id=1), players INTEGER NOT NULL)');
    // Preserve the historical multiplayer peak. Never add independent peaks.
    $db->exec('INSERT OR IGNORE INTO activity_peak SELECT 1, peak_players FROM totals WHERE id=1');
}

function activity_counts(PDO $db): array {
    $players = 0;
    $games = 0;
    foreach ($db->query('SELECT info FROM games') as $row) {
        $players += json_decode($row['info'], true)['players'];
        $games++;
    }
    $solo = (int)$db->query('SELECT count(*) FROM solo_sessions')->fetchColumn();
    return [$solo, $players, $games];
}

function activity_update_peak(PDO $db): void {
    [$solo, $players] = activity_counts($db);
    directory_query($db, 'UPDATE solo_totals SET peak_players=max(peak_players, CAST(? AS INTEGER)) WHERE id=1', [$solo]);
    directory_query($db, 'UPDATE activity_peak SET players=max(players, CAST(? AS INTEGER)) WHERE id=1', [$solo + $players]);
}

function activity_statistics(PDO $db, array $multiplayer, string $day): array {
    $solo = $db->query('SELECT since, sessions, day, today, peak_players FROM solo_totals WHERE id=1')->fetch(PDO::FETCH_ASSOC);
    if ($solo['day'] !== $day) $solo['today'] = 0;
    unset($solo['day']);
    $cities = $db->query('SELECT count(*) AS cities_founded, coalesce(sum(population), 0) AS total_population FROM solo_cities')->fetch(PDO::FETCH_ASSOC);
    $solo = array_merge($solo, $cities);
    [$solo['online_players'], $multiplayer['online_players'], $multiplayer['online_sessions']] = activity_counts($db);
    $solo['online_sessions'] = $solo['online_players'];
    $total = [];
    foreach (['sessions', 'today', 'cities_founded', 'total_population', 'online_players', 'online_sessions'] as $key) {
        $total[$key] = (int)$solo[$key] + (int)$multiplayer[$key];
    }
    $total['peak_players'] = (int)$db->query('SELECT players FROM activity_peak WHERE id=1')->fetchColumn();
    // A saved city can be played in both modes. Count it once overall, and
    // use its latest report rather than adding two versions of its population.
    $unique = $db->query('SELECT count(*) AS cities_founded, coalesce(sum(population), 0) AS total_population FROM (
        SELECT s.id, s.population FROM solo_cities s WHERE NOT EXISTS (SELECT 1 FROM activity_cities m WHERE m.id=s.id AND m.updated>s.updated)
        UNION ALL
        SELECT m.id, m.population FROM activity_cities m WHERE NOT EXISTS (SELECT 1 FROM solo_cities s WHERE s.id=m.id AND s.updated>=m.updated)
    )')->fetch(PDO::FETCH_ASSOC);
    $total = array_merge($total, $unique);
    return ['singleplayer' => $solo, 'multiplayer' => $multiplayer, 'total' => $total];
}

function activity_dispatch(PDO $db, string $method, string $id, mixed $body, string $auth, string $ip, int $now): array {
    if (!in_array($method, ['PUT', 'DELETE'], true)) return [404, ['error' => 'not_found']];
    if (!preg_match('/^Bearer ([a-f0-9]{64})$/D', $auth, $token)) return [401, ['error' => 'unauthorized']];
    if (!filter_var($ip, FILTER_VALIDATE_IP)) return [400, ['error' => 'invalid_source']];
    $hash = hash('sha256', $token[1]);
    $source = hash('sha256', $ip);
    $row = directory_query($db, 'SELECT token FROM solo_sessions WHERE id=?', [$id])->fetch(PDO::FETCH_ASSOC);
    if ($row && !hash_equals($row['token'], $hash)) return [403, ['error' => 'unauthorized']];
    if ($method === 'DELETE') {
        directory_query($db, 'DELETE FROM solo_sessions WHERE id=?', [$id]);
        return [200, ['ok' => true]];
    }
    $info = is_array($body) ? ($body['activity'] ?? null) : null;
    if (($body['version'] ?? null) !== 2 || !is_array($info)
        || !is_string($info['city'] ?? null) || strlen($info['city']) > 256
        || preg_match('//u', $info['city']) !== 1 || preg_match_all('/./us', $info['city']) > 64
        || preg_match('/[\x00-\x1f\x7f]/u', $info['city'])
        || !in_array($info['phase'] ?? null, ['running', 'paused'], true)) return [400, ['error' => 'invalid_activity']];
    $cities = directory_city_report($body['cities'] ?? null);
    if ($cities === null || count($cities) !== 1) return [400, ['error' => 'invalid_cities']];
    if (!directory_limit($db, 'solo-update:' . $ip, 120, $now)) return [429, ['error' => 'rate_limit']];
    if (!$row) {
        if (!directory_limit($db, 'solo-create:' . $ip, 12, $now)) return [429, ['error' => 'rate_limit']];
        if ((int)$db->query('SELECT count(*) FROM solo_sessions')->fetchColumn() >= 1024
            || (int)directory_query($db, 'SELECT count(*) FROM solo_sessions WHERE source=?', [$source])->fetchColumn() >= 8) return [429, ['error' => 'capacity']];
        $day = gmdate('Y-m-d', $now);
        directory_query($db, 'UPDATE solo_totals SET sessions=sessions+1, today=CASE WHEN day=? THEN today+1 ELSE 1 END, day=? WHERE id=1', [$day, $day]);
    }
    // Explicit allowlist: never retain submitted host/port/player names or files.
    $public = ['city' => $info['city'], 'phase' => $info['phase'], 'population' => array_values($cities)[0]];
    directory_query($db, 'INSERT INTO solo_sessions VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET source=excluded.source, info=excluded.info, expires=excluded.expires', [$id, $hash, $source, json_encode($public, JSON_THROW_ON_ERROR), $now + DIRECTORY_LEASE]);
    foreach ($cities as $city => $population) {
        directory_query($db, 'INSERT INTO solo_cities VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET population=excluded.population, updated=excluded.updated', [$city, $population, $now]);
    }
    activity_update_peak($db);
    return [200, ['version' => 2, 'id' => $id, 'lease' => DIRECTORY_LEASE]];
}
