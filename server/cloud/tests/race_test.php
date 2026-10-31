<?php
declare(strict_types=1);
require dirname(__DIR__) . '/CloudService.php';
use ReticulatingSplines\Cloud\CloudService;
$root = sys_get_temp_dir() . '/rs-cloud-race-' . bin2hex(random_bytes(8));
$config = ['storage' => $root, 'secret' => bin2hex(random_bytes(32)), 'quota' => 12 * 1048576, 'garbage_interval' => 3600];
$code = '';
$service = new CloudService($config + ['mail' => function ($email, $purpose, $value) use (&$code) { $code = $value; }]);
$checks = 0;
function ensure(bool $condition, string $message): void { global $checks; $checks++; if (!$condition) { throw new RuntimeException($message); } }
function callApi(string $path, array $body, string $token = ''): array {
    global $service;
    $response = $service->handle('POST', '/api/cloud/v1' . $path, $body, $token);
    ensure($response['status'] < 300, 'fixture request failed: ' . json_encode($response));
    return $response['json'];
}
function race(array $jobs): array {
    global $root, $config;
    $go = $root . '/go-' . bin2hex(random_bytes(4));
    $processes = [];
    foreach ($jobs as $index => $job) {
        $file = $go . '-' . $index . '.json';
        file_put_contents($file, json_encode($job + ['config' => $config, 'go' => $go], JSON_THROW_ON_ERROR));
        $command = [PHP_BINARY];
        if (php_ini_loaded_file()) { array_push($command, '-c', php_ini_loaded_file()); }
        array_push($command, __DIR__ . '/race_worker.php', $file);
        $process = proc_open($command, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
        ensure(is_resource($process), 'worker starts');
        fclose($pipes[0]);
        $processes[] = [$process, $pipes, $file];
    }
    $deadline = microtime(true) + 10;
    foreach ($processes as [$process, $pipes, $file]) {
        while (!is_file($file . '.ready')) {
            if (microtime(true) > $deadline) { proc_terminate($process); throw new RuntimeException('worker not ready'); }
            usleep(10000);
        }
    }
    file_put_contents($go, 'go');
    $results = [];
    foreach ($processes as [$process, $pipes, $file]) {
        $result = stream_get_contents($pipes[1]); $error = stream_get_contents($pipes[2]);
        fclose($pipes[1]); fclose($pipes[2]);
        ensure(proc_close($process) === 0 && $error === '', 'worker finishes without warning');
        $results[] = json_decode($result, true, 32, JSON_THROW_ON_ERROR);
    }
    return $results;
}
function job(string $path, array $body, string $token): array { return ['method' => 'POST', 'path' => '/api/cloud/v1' . $path, 'body' => $body, 'token' => $token]; }
function clean(string $path): void {
    foreach (new DirectoryIterator($path) as $entry) {
        if ($entry->isDot()) { continue; }
        if ($entry->isDir()) { clean($entry->getPathname()); } else { unlink($entry->getPathname()); }
    }
    rmdir($path);
}
try {
    callApi('/register', ['email' => 'race@example.test', 'password' => 'race-password-one']);
    callApi('/verify', ['email' => 'race@example.test', 'code' => $code]);
    $token = callApi('/login', ['email' => 'race@example.test', 'password' => 'race-password-one', 'device' => 'Race test'])['token'];
    $created = race([job('/saves', ['name' => 'Race', 'kind' => 'city', 'client_id' => 'same'], $token), job('/saves', ['name' => 'Race', 'kind' => 'city', 'client_id' => 'same'], $token)]);
    ensure($created[0]['json']['id'] === $created[1]['json']['id'], 'concurrent create idempotent');
    $save = $created[0]['json']['id'];
    $uploads = [];
    foreach (['left', 'right'] as $bytes) {
        $upload = callApi("/saves/$save/uploads", ['base_revision' => null, 'size' => strlen($bytes), 'sha256' => hash('sha256', $bytes)], $token)['id'];
        ensure($service->handle('PUT', "/api/cloud/v1/saves/$save/uploads/$upload/chunks/0", [], $token, $bytes)['status'] === 200, 'chunk staged');
        $uploads[] = $upload;
    }
    $commits = race([job("/saves/$save/uploads/{$uploads[0]}/commit", [], $token), job("/saves/$save/uploads/{$uploads[1]}/commit", [], $token)]);
    $statuses = array_column($commits, 'status'); sort($statuses);
    ensure($statuses === [201, 409], 'exactly one concurrent predecessor wins');
    $winner = $commits[0]['status'] === 201 ? 0 : 1;
    $revision = $commits[$winner]['json']['revision'];
    $repeated = race([job("/saves/$save/uploads/{$uploads[$winner]}/commit", [], $token), job("/saves/$save/uploads/{$uploads[$winner]}/commit", [], $token)]);
    ensure($repeated[0]['json']['revision'] === $revision && $repeated[1]['json']['revision'] === $revision, 'concurrent retry returns original revision');
    $reservation = ['base_revision' => $revision, 'size' => 7 * 1048576, 'sha256' => str_repeat('0', 64)];
    $reservations = race([job("/saves/$save/uploads", $reservation, $token), job("/saves/$save/uploads", $reservation, $token)]);
    $statuses = array_column($reservations, 'status'); sort($statuses);
    ensure($statuses === [201, 413], 'concurrent reservations cannot oversubscribe quota');
    $rotations = race([job('/session/rotate', [], $token), job('/session/rotate', [], $token)]);
    $statuses = array_column($rotations, 'status'); sort($statuses);
    ensure($statuses === [200, 401], 'concurrent token rotation revokes old token atomically');
    $maintenanceNow = time();
    file_put_contents($root . '/blobs/maintenance-orphan', 'orphan');
    $maintenance = race([['action' => 'maintenance', 'now' => $maintenanceNow], ['action' => 'maintenance', 'now' => $maintenanceNow]]);
    ensure(count(array_filter($maintenance, fn($result) => $result['ran'])) === 1, 'only one parallel collector runs');
    ensure(!is_file($root . '/blobs/maintenance-orphan'), 'scheduled collector removes orphan');
    file_put_contents($root . '/blobs/maintenance-later', 'orphan');
    ensure(!$service->maybeCollectGarbage($maintenanceNow + 3599)['ran'] && is_file($root . '/blobs/maintenance-later'), 'requests inside hourly interval do not collect');
    ensure($service->maybeCollectGarbage($maintenanceNow + 3600)['ran'] && !is_file($root . '/blobs/maintenance-later'), 'first request after interval collects');
    $maintenanceLock = fopen($root . '/maintenance.lock', 'c+b');
    flock($maintenanceLock, LOCK_EX);
    $contended = race([['action' => 'maintenance', 'now' => $maintenanceNow + 7200]]);
    ensure(!$contended[0]['ran'], 'private lock contention skips collection without blocking');
    flock($maintenanceLock, LOCK_UN); fclose($maintenanceLock);
    $busyDatabase = new PDO('sqlite:' . $root . '/cloud.sqlite');
    $busyDatabase->exec('BEGIN IMMEDIATE');
    $started = microtime(true);
    ensure(!$service->maybeCollectGarbage($maintenanceNow + 7200)['ran'], 'busy database skips optional maintenance');
    ensure(microtime(true) - $started < 1.0, 'optional maintenance never waits for active database writer');
    $busyDatabase->exec('ROLLBACK'); unset($busyDatabase);
    ensure(!$service->maybeCollectGarbage($maintenanceNow + 7201)['ran'], 'failed maintenance is throttled too');
    ensure($service->handle('GET', '/api/cloud/v1/me')['status'] === 401, 'failed maintenance cannot bypass authentication');
    echo "Cloud races: $checks checks passed\n";
} finally { unset($service); gc_collect_cycles(); clean($root); }
