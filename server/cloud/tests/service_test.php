<?php
declare(strict_types=1);
require dirname(__DIR__) . '/CloudService.php';
use ReticulatingSplines\Cloud\CloudService;

$root = sys_get_temp_dir() . '/rs-cloud-test-' . bin2hex(random_bytes(8));
$codes = [];
$config = ['storage' => $root, 'secret' => bin2hex(random_bytes(32)),
    'quota' => 12 * 1048576, 'mail' => function ($email, $purpose, $code) use (&$codes) { $codes[$email][$purpose] = $code; }];
$service = new CloudService($config);
$now = time();
$checks = 0;

function check(bool $ok, string $name): void {
    global $checks;
    $checks++;
    if (!$ok) { throw new RuntimeException('FAIL: ' . $name); }
}
function request(string $method, string $path, array $data = [], string $token = '', int $expected = 200, string $raw = ''): array {
    global $service, $now;
    $response = $service->handle($method, '/api/cloud/v1' . $path, $data, $token, $raw, '192.0.2.1', $now);
    check($response['status'] === $expected, "$method $path status $expected (got {$response['status']} " . ($response['json']['error'] ?? '') . ')');
    return $response['json'] ?? $response;
}
function account(string $email): array {
    global $codes;
    request('POST', '/register', ['email' => $email, 'password' => 'test-password-one']);
    request('POST', '/login', ['email' => $email, 'password' => 'test-password-one', 'device' => 'Desktop'], '', 403);
    request('POST', '/verify', ['email' => $email, 'code' => $codes[$email]['verify']]);
    return request('POST', '/login', ['email' => $email, 'password' => 'test-password-one', 'device' => 'Desktop']);
}
function createSave(string $token, string $key): string {
    return request('POST', '/saves', ['name' => 'Test city', 'kind' => 'city', 'metadata' => ['year' => 1950, 'population' => 100], 'client_id' => $key], $token, 201)['id'];
}
function stage(string $token, string $save, ?string $base, string $bytes, ?string $sha = null): string {
    $upload = request('POST', '/saves/' . $save . '/uploads', ['base_revision' => $base, 'size' => strlen($bytes), 'sha256' => $sha ?? hash('sha256', $bytes), 'metadata' => ['year' => 1951]], $token, 201);
    $id = $upload['id'];
    foreach (str_split($bytes, CloudService::CHUNK_SIZE) as $index => $chunk) {
        request('PUT', "/saves/$save/uploads/$id/chunks/$index", [], $token, 200, $chunk);
    }
    return $id;
}
function commit(string $token, string $save, string $upload, int $status = 201): array {
    return request('POST', "/saves/$save/uploads/$upload/commit", [], $token, $status);
}
function removeTree(string $path): void {
    if (!is_dir($path)) { return; }
    foreach (new DirectoryIterator($path) as $entry) {
        if ($entry->isDot()) { continue; }
        if ($entry->isDir()) { removeTree($entry->getPathname()); } else { unlink($entry->getPathname()); }
    }
    rmdir($path);
}

try {
    request('GET', '/me', [], '', 401);
    request('POST', '/register', ['email' => "bad\r\nBcc:a@example.test", 'password' => 'test-password-one'], '', 400);
    request('POST', '/register', ['email' => 'a@example.test', 'password' => 'short'], '', 400);
    $alice = account('alice@example.test');
    $bob = account('bob@example.test');
    $a = $alice['token']; $b = $bob['token'];
    check($alice['account_id'] !== $bob['account_id'], 'account isolation');
    request('POST', '/verify', ['email' => 'alice@example.test', 'code' => $codes['alice@example.test']['verify']], '', 400);
    $db = new PDO('sqlite:' . $root . '/cloud.sqlite');
    check(!str_contains(file_get_contents($root . '/cloud.sqlite-wal'), $a), 'raw token not in database');
    check($db->query('SELECT password FROM accounts LIMIT 1')->fetchColumn() !== 'test-password-one', 'password hashed');
    $me = request('GET', '/me', [], $a);
    check($me['usage'] === 0 && $me['quota'] === $config['quota'], 'initial quota');
    $save = createSave($a, 'save-idempotent');
    $repeat = request('POST', '/saves', ['name' => 'Test city', 'kind' => 'city', 'metadata' => [], 'client_id' => 'save-idempotent'], $a);
    check($repeat['id'] === $save, 'idempotent create');
    $bobSave = createSave($b, 'save-idempotent');
    check($bobSave !== $save, 'client ids account scoped');
    $customService = $service;
    $defaults = $config;
    unset($defaults['quota']);
    $service = new CloudService($defaults);
    check(request('GET', '/me', [], $a)['quota'] === 20000000, 'default quota is exactly twenty decimal MB for existing accounts');
    $full = request('POST', "/saves/$save/uploads", ['base_revision' => null, 'size' => 20000000, 'sha256' => str_repeat('a', 64)], $a, 201);
    request('POST', "/saves/$save/uploads", ['base_revision' => null, 'size' => 1, 'sha256' => str_repeat('b', 64)], $a, 413);
    $bobFull = request('POST', "/saves/$bobSave/uploads", ['base_revision' => null, 'size' => 20000000, 'sha256' => str_repeat('a', 64)], $b, 201);
    request('DELETE', "/saves/$save/uploads/{$full['id']}", [], $a);
    request('DELETE', "/saves/$bobSave/uploads/{$bobFull['id']}", [], $b);
    request('POST', "/saves/$save/uploads", ['base_revision' => null, 'size' => 20000001, 'sha256' => str_repeat('a', 64)], $a, 400);
    $service = $customService;
    request('GET', "/saves/$save", [], $b, 404);
    request('DELETE', "/saves/$save", [], $b, 404);
    request('POST', '/saves', ['name' => 'Bad metadata', 'kind' => 'city', 'metadata' => ['path' => 'C:/personal']], $a, 400);
    request('POST', '/saves', ['name' => 'Bad preview', 'kind' => 'city', 'metadata' => ['preview' => base64_encode('not png')]], $a, 400);
    $png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6p8AAAAASUVORK5CYII=';
    request('POST', '/saves', ['name' => 'Preview', 'kind' => 'region', 'metadata' => ['preview' => $png, 'mods' => [['id' => 'mod-one', 'version' => '1']]]], $a, 201);
    // Forty legal large PNG previews previously exceeded the client's 4 MiB JSON cap.
    // Add a valid ancillary text chunk to a tiny PNG; no image library is required.
    $pngBytes = base64_decode($png);
    $textChunk = "note\0" . str_repeat('X', 90000);
    $largePng = base64_encode(substr($pngBytes, 0, -12) . pack('N', strlen($textChunk)) .
        'tEXt' . $textChunk . hash('crc32b', 'tEXt' . $textChunk, true) . substr($pngBytes, -12));
    $manyMods = array_fill(0, 100, ['id' => str_repeat('m', 128), 'version' => str_repeat('v', 64)]);
    $maxSummary = ['name' => str_repeat('\\', 160), 'kind' => str_repeat('\\', 160),
        'game_version' => str_repeat('\\', 160), 'save_format' => str_repeat('\\', 160),
        'year' => 2147483647, 'population' => 2147483647];
    check(strlen($largePng) <= 131072 && strlen($largePng) * 40 > 4 * 1048576, 'large-preview fixture crosses client response limit');
    for ($i = 0; $i < 40; $i++) {
        request('POST', '/saves', ['name' => str_repeat('\\', 160), 'kind' => 'city',
            'metadata' => $maxSummary + ['preview' => $largePng, 'mods' => $manyMods]], $a, 201);
    }
    $compactList = request('GET', '/saves', [], $a);
    check(strlen(json_encode($compactList, JSON_THROW_ON_ERROR)) < 4 * 1048576, 'many-preview account list stays below client JSON cap');
    check(count(array_filter($compactList['saves'], fn($entry) => isset($entry['metadata']['preview']))) === 0, 'save summaries omit all previews');
    check(count(array_filter($compactList['saves'], fn($entry) => isset($entry['metadata']['mods']))) === 0, 'save summaries omit all mod manifests');
    $maxDescriptor = array_values(array_filter($compactList['saves'], fn($entry) => ($entry['metadata']['population'] ?? 0) === 2147483647))[0];
    $maxDescriptor['device_name'] = str_repeat('\\', 80);
    $maxDescriptor['head'] = str_repeat('f', 32);
    check(strlen(json_encode(['saves' => array_fill(0, 1000, $maxDescriptor)], JSON_THROW_ON_ERROR)) < 4 * 1048576,
        'maximum thousand-save descriptor response fits client cap with worst escaped fields');
    $bytes = str_repeat('fixture-byte-', 90000); // Two chunks, real binary payload below.
    $bytes .= "\0\xff\r\n";
    $upload = request('POST', "/saves/$save/uploads", ['base_revision' => null, 'size' => strlen($bytes), 'sha256' => hash('sha256', $bytes), 'metadata' => ['preview' => $png, 'mods' => $manyMods]], $a, 201)['id'];
    request('GET', "/saves/$save/uploads/$upload", [], $b, 404);
    request('PUT', "/saves/$save/uploads/$upload/chunks/0", [], $a, 400, 'short');
    commit($a, $save, $upload, 409);
    $chunk0 = substr($bytes, 0, CloudService::CHUNK_SIZE);
    request('PUT', "/saves/$save/uploads/$upload/chunks/0", [], $a, 200, $chunk0);
    request('PUT', "/saves/$save/uploads/$upload/chunks/0", [], $a, 200, $chunk0);
    request('PUT', "/saves/$save/uploads/$upload/chunks/0", [], $a, 409, str_repeat('!', strlen($chunk0)));
    // New service instance simulates request/process restart while upload is partial.
    $service = new CloudService($config);
    $resume = request('GET', "/saves/$save/uploads/$upload", [], $a);
    check($resume['chunks'] === [0] && $resume['chunk_size'] === 1048576, 'durable chunk resume');
    request('PUT', "/saves/$save/uploads/$upload/chunks/1", [], $a, 200, substr($bytes, CloudService::CHUNK_SIZE));
    request('PUT', "/saves/$save/uploads/$upload/chunks/2", [], $a, 400, 'x');
    $v1 = commit($a, $save, $upload);
    check(request('GET', "/saves/$save/versions", [], $a)['versions'][0]['metadata']['preview'] === $png, 'selected version retains its preview');
    check(request('GET', "/saves/$save/versions", [], $a)['versions'][0]['metadata']['mods'] === $manyMods, 'selected version retains complete mod compatibility manifest');
    $again = commit($a, $save, $upload, 200);
    check($again === $v1, 'lost commit response retry idempotent');
    check(request('GET', "/saves/$save/uploads/$upload", [], $a)['revision'] === $v1['revision'], 'committed upload resumable');
    $download = request('GET', "/saves/$save/versions/{$v1['revision']}/content", [], $a);
    check(stream_get_contents($download['stream']) === $bytes, 'download byte exact'); fclose($download['stream']);
    $backupRoot = $root . '/snapshot';
    $service->backup($backupRoot);
    check(is_file($backupRoot . '/COMPLETE'), 'consistent backup published');
    $backupService = new CloudService(array_replace($config, ['storage' => $backupRoot]));
    $backupDownload = $backupService->handle('GET', "/api/cloud/v1/saves/$save/versions/{$v1['revision']}/content", [], $a);
    check($backupDownload['status'] === 200 && stream_get_contents($backupDownload['stream']) === $bytes, 'backup restores account and exact save');
    fclose($backupDownload['stream']); unset($backupService);
    request('GET', "/saves/$save/versions/{$v1['revision']}/content", [], $b, 404);
    request('POST', "/saves/$save/uploads", ['base_revision' => null, 'size' => 2, 'sha256' => hash('sha256', 'xx')], $a, 409);
    $bad = stage($a, $save, $v1['revision'], 'bad-checksum', hash('sha256', 'different'));
    commit($a, $save, $bad, 422);
    check(request('GET', "/saves/$save", [], $a)['head'] === $v1['revision'], 'bad checksum does not publish');
    request('DELETE', "/saves/$save/uploads/$bad", [], $a);
    // Two independent uploads share one predecessor: exactly one may publish.
    $left = stage($a, $save, $v1['revision'], 'left');
    $right = stage($a, $save, $v1['revision'], 'right');
    $v2 = commit($a, $save, $left);
    $conflict = commit($a, $save, $right, 409);
    check($conflict['head'] === $v2['revision'], 'optimistic conflict carries current head');
    check(request('GET', "/saves/$save/uploads/$right", [], $a)['chunks'] === [0], 'conflict bytes retained');
    request('POST', "/saves/$save/restore", ['revision' => $v1['revision'], 'base_revision' => $v1['revision']], $a, 409);
    $restored = request('POST', "/saves/$save/restore", ['revision' => $v1['revision'], 'base_revision' => $v2['revision']], $a, 201);
    check($restored['revision'] !== $v1['revision'] && $restored['sha256'] === $v1['sha256'], 'restore creates new revision');
    $head = $restored['revision'];
    for ($i = 0; $i < 6; $i++) { $head = commit($a, $save, stage($a, $save, $head, "version$i"))['revision']; }
    $versions = request('GET', "/saves/$save/versions", [], $a)['versions'];
    check(count($versions) === 5 && $versions[0]['revision'] === $head, 'five newest versions retained');
    check(request('GET', '/me', [], $a)['usage'] === 40, 'quota includes all retained versions');
    $lowered = $config;
    $lowered['quota'] = 20;
    $service = new CloudService($lowered);
    $overLimit = request('GET', '/me', [], $a);
    check($overLimit['quota'] === 20 && $overLimit['usage'] === 40, 'lowering quota preserves existing stored versions');
    $download = request('GET', "/saves/$save/versions/$head/content", [], $a);
    check(stream_get_contents($download['stream']) !== '', 'downloads remain available above a lowered quota');
    fclose($download['stream']);
    request('POST', "/saves/$save/uploads", ['base_revision' => $head, 'size' => 1, 'sha256' => str_repeat('a', 64)], $a, 413);
    $service = $customService;
    request('POST', "/saves/$save/uploads", ['base_revision' => $head, 'size' => $config['quota'], 'sha256' => str_repeat('a', 64)], $a, 413);
    request('DELETE', "/saves/$save", [], $a);
    check(count(request('GET', '/saves?trash=1', [], $a)['saves']) === 1, 'trash visible separately');
    check(request('GET', '/me', [], $a)['usage'] === 40, 'trash consumes quota');
    request('GET', "/saves/$save/versions", [], $a, 410);
    request('POST', "/saves/$save/undelete", [], $a);
    request('GET', "/saves/$save/versions", [], $a);
    request('DELETE', '/devices/' . $bob['device_id'], [], $a);
    request('GET', '/me', [], $b);
    $rotated = request('POST', '/session/rotate', [], $a);
    check($rotated['device_id'] === $alice['device_id'] && $rotated['token'] !== $a, 'rotate preserves device and replaces token');
    request('GET', '/me', [], $a, 401);
    $a = $rotated['token'];
    request('POST', '/reset-request', ['email' => 'nobody@example.test']);
    request('POST', '/reset-request', ['email' => 'alice@example.test']);
    request('POST', '/reset', ['email' => 'alice@example.test', 'code' => '00000000', 'password' => 'new-password-two'], '', 400);
    request('POST', '/reset', ['email' => 'alice@example.test', 'code' => $codes['alice@example.test']['reset'], 'password' => 'new-password-two']);
    request('GET', '/me', [], $a, 401);
    request('POST', '/login', ['email' => 'alice@example.test', 'password' => 'test-password-one', 'device' => 'Laptop'], '', 401);
    $a = request('POST', '/login', ['email' => 'alice@example.test', 'password' => 'new-password-two', 'device' => 'Laptop'])['token'];
    request('POST', '/reset', ['email' => 'alice@example.test', 'code' => $codes['alice@example.test']['reset'], 'password' => 'new-password-three'], '', 400);
    $deviceRows = request('GET', '/devices', [], $a)['devices'];
    check(count($deviceRows) === 1 && $deviceRows[0]['current'] && !isset($deviceRows[0]['token_hash']), 'device listing private');
    // Code attempts and mail retries are persisted, not reset by another PHP process.
    request('POST', '/register', ['email' => 'limited@example.test', 'password' => 'test-password-one']);
    for ($i = 0; $i < 5; $i++) { request('POST', '/verify', ['email' => 'limited@example.test', 'code' => '00000000'], '', 400); }
    request('POST', '/verify', ['email' => 'limited@example.test', 'code' => $codes['limited@example.test']['verify']], '', 400);
    for ($i = 0; $i < 3; $i++) { request('POST', '/reset-request', ['email' => 'unknown@example.test']); }
    request('POST', '/reset-request', ['email' => 'unknown@example.test'], '', 429);
    request('GET', '/saves/../../blobs/anything', [], $a, 404);
    request('DELETE', "/saves/$save", [], $a);
    $now += 31 * 86400;
    request('POST', "/saves/$save/undelete", [], $a, 404);
    check(request('GET', '/me', [], $a)['usage'] === 0, 'trash expires after thirty days');
    $gc = $service->collectGarbage($now);
    check($gc['deleted_files'] > 0 && count(glob($root . '/blobs/*')) === 0, 'garbage collection removes retired blobs');
    request('DELETE', '/devices', [], $a);
    request('GET', '/me', [], $a, 401);
    echo "Cloud service: $checks checks passed\n";
} finally {
    unset($service, $customService, $db);
    gc_collect_cycles();
    removeTree($root);
}
