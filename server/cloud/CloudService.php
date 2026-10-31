<?php
declare(strict_types=1);

namespace ReticulatingSplines\Cloud;

use PDO;
use RuntimeException;
use Throwable;

final class ApiError extends RuntimeException
{
    public function __construct(public int $status, string $code, public array $details = [])
    {
        parent::__construct($code);
    }
}

/** Private storage service. No cookies, browser sessions, or multiplayer credentials. */
final class CloudService
{
    public const CHUNK_SIZE = 1048576;
    private PDO $db;
    private array $config;
    private int $now;

    public function __construct(array $config)
    {
        $this->config = $config + ['quota' => 524288000, 'versions' => 5, 'trash_days' => 30,
            'upload_hours' => 48, 'session_days' => 90, 'base_path' => '/api/cloud/v1'];
        if (!isset($config['storage'], $config['secret']) || !is_string($config['secret']) ||
            !preg_match('/^[a-f0-9]{64}$/D', $config['secret'])) {
            throw new RuntimeException('Cloud storage and a random secret are required');
        }
        foreach (['quota', 'versions', 'trash_days', 'upload_hours', 'session_days'] as $key) {
            if (!is_int($this->config[$key]) || $this->config[$key] < 1) {
                throw new RuntimeException('Invalid cloud configuration');
            }
        }
        foreach (['', '/blobs', '/chunks'] as $suffix) {
            $directory = $config['storage'] . $suffix;
            if (!is_dir($directory) && !mkdir($directory, 0700, true) && !is_dir($directory)) {
                throw new RuntimeException('Cannot create private storage');
            }
        }
        $this->db = new PDO('sqlite:' . $config['storage'] . '/cloud.sqlite', null, null,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
        $this->db->exec('PRAGMA busy_timeout=10000; PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;');
        $this->db->exec(file_get_contents(__DIR__ . '/schema.sql'));
        $this->now = time();
    }

    /** Returns status/json or status/stream/size/sha256. Caller must close streams. */
    public function handle(string $method, string $path, array $body = [], string $token = '',
        string $raw = '', string $ip = 'local', ?int $now = null): array
    {
        $this->now = $now ?? time();
        try {
            // One SQLite write lock covers authorization, quota reservations and head CAS.
            // Staged files are immutable after publication. Cleanup deletes only unreferenced files.
            $this->db->exec('BEGIN IMMEDIATE');
            $this->expireRows();
            $query = [];
            parse_str((string)parse_url($path, PHP_URL_QUERY), $query);
            $route = (string)parse_url($path, PHP_URL_PATH);
            if (!str_starts_with($route, $this->config['base_path'] . '/')) {
                throw new ApiError(404, 'not_found');
            }
            $route = substr($route, strlen($this->config['base_path']));
            if (in_array($route, ['/register', '/verify', '/login', '/reset-request', '/reset'], true)) {
                if ($method !== 'POST') {
                    throw new ApiError(405, 'method_not_allowed');
                }
                $this->rate('auth-ip:' . $ip, 60, 3600);
                $result = $this->auth($route, $body);
            } else {
                $device = $this->authenticate($token);
                $result = $this->authorized($method, $route, $body, $device, $raw, $query);
            }
            $this->db->exec('COMMIT');
            return $result;
        } catch (ApiError $error) {
            // Persist throttling and failed code attempts. All mutating endpoints validate
            // before changing published rows; file publication failures throw Throwable.
            $this->db->exec('COMMIT');
            return ['status' => $error->status, 'json' => ['error' => $error->getMessage()] + $error->details];
        } catch (Throwable $error) {
            try { $this->db->exec('ROLLBACK'); } catch (Throwable) {}
            // No paths, credentials, emails, or stack traces leave this boundary.
            return ['status' => 503, 'json' => ['error' => 'service_unavailable']];
        }
    }

    private function sql(string $query, array $params = []): \PDOStatement
    {
        $statement = $this->db->prepare($query);
        $statement->execute($params);
        return $statement;
    }

    private function one(string $query, array $params = []): array|false
    {
        return $this->sql($query, $params)->fetch();
    }

    private function ok(array $value = ['ok' => true], int $status = 200): array
    {
        return ['status' => $status, 'json' => $value];
    }

    private function id(): string { return bin2hex(random_bytes(16)); }
    private function digest(string $value): string { return hash_hmac('sha256', $value, $this->config['secret']); }

    private function text(array $data, string $key, int $min, int $max): string
    {
        $value = $data[$key] ?? null;
        if (!is_string($value) || strlen($value) < $min || strlen($value) > $max ||
            preg_match('/[\x00-\x1f\x7f]/', $value) || !preg_match('//u', $value)) {
            throw new ApiError(400, 'invalid_' . $key);
        }
        return $value;
    }

    private function email(array $data): string
    {
        $email = strtolower(trim($this->text($data, 'email', 3, 254)));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) { throw new ApiError(400, 'invalid_email'); }
        return $email;
    }

    private function rate(string $key, int $limit, int $seconds): void
    {
        $bucket = $this->digest($key);
        $row = $this->one('SELECT count FROM rate_limits WHERE bucket=?', [$bucket]);
        if ($row && (int)$row['count'] >= $limit) { throw new ApiError(429, 'rate_limited'); }
        $this->sql('INSERT INTO rate_limits VALUES(?,1,?) ON CONFLICT(bucket) DO UPDATE SET count=count+1',
            [$bucket, $this->now + $seconds]);
    }

    private function auth(string $route, array $data): array
    {
        $email = $this->email($data);
        $account = $this->one('SELECT * FROM accounts WHERE email=?', [$email]);
        if ($route === '/register' || $route === '/reset-request') {
            $this->rate('mail:' . $email, 3, 3600);
            if (!is_callable($this->config['mail'] ?? null)) { throw new ApiError(503, 'mail_unavailable'); }
            if ($route === '/register') {
                $password = $this->text($data, 'password', 12, 1024);
                if (!$account) {
                    $account = ['id' => $this->id(), 'email' => $email, 'verified' => 0];
                    $this->sql('INSERT INTO accounts VALUES(?,?,?,0,?)',
                        [$account['id'], $email, $this->passwordHash($password), $this->now]);
                }
                // A repeated registration never changes an existing password.
            }
            if ($account && (($route === '/register' && !$account['verified']) ||
                ($route === '/reset-request' && $account['verified']))) {
                $purpose = $route === '/register' ? 'verify' : 'reset';
                $code = (string)random_int(10000000, 99999999);
                $this->sql('INSERT OR REPLACE INTO codes VALUES(?,?,?,?,0)',
                    [$account['id'], $purpose, $this->digest($account['id'] . ':' . $purpose . ':' . $code), $this->now + 900]);
                ($this->config['mail'])($email, $purpose, $code);
            }
            return $this->ok(); // Do not disclose whether an account exists.
        }
        if ($route === '/verify' || $route === '/reset') {
            $this->rate('code:' . $email, 10, 900);
            $code = $this->text($data, 'code', 8, 8);
            $purpose = $route === '/verify' ? 'verify' : 'reset';
            $record = $account ? $this->one('SELECT * FROM codes WHERE account_id=? AND purpose=?', [$account['id'], $purpose]) : false;
            if (!$record || $record['expires_at'] <= $this->now || $record['attempts'] >= 5) {
                throw new ApiError(400, 'invalid_code');
            }
            $this->sql('UPDATE codes SET attempts=attempts+1 WHERE account_id=? AND purpose=?', [$account['id'], $purpose]);
            if (!hash_equals($record['digest'], $this->digest($account['id'] . ':' . $purpose . ':' . $code))) {
                throw new ApiError(400, 'invalid_code');
            }
            if ($purpose === 'reset') {
                $password = $this->text($data, 'password', 12, 1024);
                $this->sql('UPDATE accounts SET password=? WHERE id=?', [$this->passwordHash($password), $account['id']]);
                $this->sql('DELETE FROM devices WHERE account_id=?', [$account['id']]);
            } else {
                $this->sql('UPDATE accounts SET verified=1 WHERE id=?', [$account['id']]);
            }
            $this->sql('DELETE FROM codes WHERE account_id=? AND purpose=?', [$account['id'], $purpose]);
            return $this->ok();
        }
        $this->rate('login:' . $email, 15, 900);
        $password = $this->text($data, 'password', 1, 1024);
        // A valid fixed bcrypt hash ensures unknown accounts still run password_verify.
        $valid = password_verify(base64_encode(hash('sha256', $password, true)), $account['password'] ?? '$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2uheWG/igi.');
        if (!$account || !$valid) { throw new ApiError(401, 'invalid_credentials'); }
        if (!$account['verified']) { throw new ApiError(403, 'verification_required'); }
        $name = $this->text($data, 'device', 1, 80);
        if ((int)$this->sql('SELECT COUNT(*) FROM devices WHERE account_id=?', [$account['id']])->fetchColumn() >= 30) {
            throw new ApiError(409, 'device_limit');
        }
        return $this->session($account, $this->id(), $name);
    }

    private function session(array $account, string $id, string $name, bool $rotate = false): array
    {
        $token = bin2hex(random_bytes(32));
        $expires = $this->now + $this->config['session_days'] * 86400;
        if ($rotate) {
            $this->sql('UPDATE devices SET token_hash=?,expires_at=?,last_seen=? WHERE id=?', [$this->digest($token), $expires, $this->now, $id]);
        } else {
            $this->sql('INSERT INTO devices VALUES(?,?,?,?,?,?,?)', [$id, $account['id'], $name, $this->digest($token), $this->now, $this->now, $expires]);
        }
        return $this->ok(['token' => $token, 'account_id' => $account['id'], 'device_id' => $id,
            'expires_at' => $expires, 'account' => ['id' => $account['id'], 'email' => $account['email']]]);
    }

    private function passwordHash(string $password): string
    {
        // Fixed-length prehash avoids bcrypt's 72-byte truncation, including UTF-8 passwords.
        return password_hash(base64_encode(hash('sha256', $password, true)), PASSWORD_BCRYPT, ['cost' => 12]);
    }

    private function authenticate(string $token): array
    {
        if (!preg_match('/^[a-f0-9]{64}$/D', $token)) { throw new ApiError(401, 'unauthorized'); }
        $device = $this->one('SELECT d.*,a.email FROM devices d JOIN accounts a ON a.id=d.account_id WHERE d.token_hash=? AND d.expires_at>? AND a.verified=1', [$this->digest($token), $this->now]);
        if (!$device) { throw new ApiError(401, 'unauthorized'); }
        $this->sql('UPDATE devices SET last_seen=? WHERE id=?', [$this->now, $device['id']]);
        return $device;
    }

    private function metadata(array $data): string
    {
        $value = $data['metadata'] ?? [];
        if (!is_array($value) || ($value !== [] && array_is_list($value))) { throw new ApiError(400, 'invalid_metadata'); }
        $allowed = ['name', 'kind', 'game_version', 'save_format', 'population', 'year', 'mods', 'preview'];
        if (array_diff(array_keys($value), $allowed)) { throw new ApiError(400, 'invalid_metadata'); }
        foreach ($value as $key => $item) {
            if ($key === 'preview') {
                if (!is_string($item) || strlen($item) > 131072) { throw new ApiError(400, 'invalid_metadata'); }
                $png = base64_decode($item, true);
                $dimensions = $png === false ? false : @getimagesizefromstring($png);
                if (!$dimensions || $dimensions[2] !== IMAGETYPE_PNG || $dimensions[0] > 384 || $dimensions[1] > 256) { throw new ApiError(400, 'invalid_metadata'); }
            } elseif (in_array($key, ['population', 'year'], true)) {
                if (!is_int($item) || $item < 0 || $item > 2147483647) { throw new ApiError(400, 'invalid_metadata'); }
            } elseif ($key === 'mods') {
                if (!is_array($item) || !array_is_list($item) || count($item) > 100) { throw new ApiError(400, 'invalid_metadata'); }
                foreach ($item as $mod) {
                    if (!is_array($mod) || array_diff(array_keys($mod), ['id', 'version']) || !isset($mod['id'], $mod['version'])) { throw new ApiError(400, 'invalid_metadata'); }
                    $this->text($mod, 'id', 1, 128);
                    $this->text($mod, 'version', 1, 64);
                }
            } else { $this->text($value, $key, 1, 160); }
        }
        $json = json_encode((object)$value, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        if (strlen($json) > 147456) { throw new ApiError(400, 'invalid_metadata'); }
        return $json;
    }

    private function save(string $id, string $owner): array
    {
        $save = $this->one('SELECT * FROM saves WHERE id=? AND account_id=?', [$id, $owner]);
        if (!$save) { throw new ApiError(404, 'not_found'); }
        return $save;
    }

    private function saveJson(array $save): array
    {
        unset($save['account_id'], $save['client_id']);
        $save['metadata'] = json_decode($save['metadata'], true);
        // Bound account-wide lists independently of screenshots and mod manifests.
        // The selected version retains complete metadata for previews/compatibility.
        $save['metadata'] = array_intersect_key($save['metadata'], array_flip([
            'name', 'kind', 'game_version', 'save_format', 'population', 'year',
        ]));
        $head = $save['head'] ? $this->one('SELECT device_name FROM versions WHERE revision=?', [$save['head']]) : false;
        $save['device_name'] = $head ? $head['device_name'] : '';
        return $save;
    }

    private function versionJson(array $version): array
    {
        unset($version['blob'], $version['save_id'], $version['sequence']);
        $version['metadata'] = json_decode($version['metadata'], true);
        return $version;
    }

    private function usage(string $owner): int
    {
        return (int)$this->sql('SELECT COALESCE(SUM(v.size),0) FROM versions v JOIN saves s ON s.id=v.save_id WHERE s.account_id=?', [$owner])->fetchColumn();
    }

    private function reserve(string $owner, int $additional): void
    {
        $reserved = (int)$this->sql('SELECT COALESCE(SUM(u.size),0) FROM uploads u JOIN saves s ON s.id=u.save_id WHERE s.account_id=? AND u.committed IS NULL', [$owner])->fetchColumn();
        if ($this->usage($owner) + $reserved + $additional > $this->config['quota']) {
            throw new ApiError(413, 'quota_exceeded');
        }
    }

    private function base(array $data, array $save): ?string
    {
        if (!array_key_exists('base_revision', $data) ||
            ($data['base_revision'] !== null && (!is_string($data['base_revision']) || !preg_match('/^[a-f0-9]{32}$/D', $data['base_revision'])))) {
            throw new ApiError(400, 'invalid_base_revision');
        }
        if ($data['base_revision'] !== $save['head']) { throw new ApiError(409, 'revision_conflict', ['head' => $save['head']]); }
        return $data['base_revision'];
    }

    private function authorized(string $method, string $route, array $data, array $device, string $raw, array $query): array
    {
        $owner = $device['account_id'];
        if ($route === '/me' && $method === 'GET') {
            return $this->ok(['account' => ['id' => $owner, 'email' => $device['email']], 'usage' => $this->usage($owner), 'quota' => $this->config['quota']]);
        }
        if ($route === '/session/rotate' && $method === 'POST') {
            return $this->session(['id' => $owner, 'email' => $device['email']], $device['id'], $device['name'], true);
        }
        if ($route === '/devices' && $method === 'GET') {
            $rows = $this->sql('SELECT id,name,created_at,last_seen,expires_at FROM devices WHERE account_id=? ORDER BY created_at DESC', [$owner])->fetchAll();
            foreach ($rows as &$row) { $row['current'] = $row['id'] === $device['id']; }
            return $this->ok(['devices' => $rows]);
        }
        if ($route === '/devices' && $method === 'DELETE') {
            $this->sql('DELETE FROM devices WHERE account_id=?', [$owner]);
            return $this->ok();
        }
        if (preg_match('#^/devices/([a-f0-9]{32})$#D', $route, $match) && $method === 'DELETE') {
            $this->sql('DELETE FROM devices WHERE id=? AND account_id=?', [$match[1], $owner]);
            return $this->ok(); // Idempotent, no foreign device existence disclosure.
        }
        if ($route === '/saves' && $method === 'GET') {
            $trash = ($query['trash'] ?? '') === '1';
            $rows = $this->sql('SELECT * FROM saves WHERE account_id=? AND deleted_at IS ' . ($trash ? 'NOT ' : '') . 'NULL ORDER BY updated_at DESC,id', [$owner])->fetchAll();
            return $this->ok(['saves' => array_map(fn($row) => $this->saveJson($row), $rows)]);
        }
        if ($route === '/saves' && $method === 'POST') {
            $name = $this->text($data, 'name', 1, 160);
            $kind = $data['kind'] ?? '';
            if (!in_array($kind, ['city', 'region', 'multiplayer'], true)) { throw new ApiError(400, 'invalid_kind'); }
            $metadata = $this->metadata($data);
            $clientId = isset($data['client_id']) ? $this->text($data, 'client_id', 1, 100) : null;
            if ($clientId !== null) {
                $existing = $this->one('SELECT * FROM saves WHERE account_id=? AND client_id=?', [$owner, $clientId]);
                if ($existing) { return $this->ok($this->saveJson($existing)); }
            }
            if ((int)$this->sql('SELECT COUNT(*) FROM saves WHERE account_id=?', [$owner])->fetchColumn() >= 1000) { throw new ApiError(409, 'save_limit'); }
            $id = $this->id();
            $this->sql('INSERT INTO saves VALUES(?,?,?,?,?,NULL,?,NULL,?)', [$id, $owner, $name, $kind, $metadata, $this->now, $clientId]);
            return $this->ok($this->saveJson($this->save($id, $owner)), 201);
        }
        if (!preg_match('#^/saves/([a-f0-9]{32})(.*)$#D', $route, $match)) { throw new ApiError(404, 'not_found'); }
        $save = $this->save($match[1], $owner);
        $suffix = $match[2];
        if ($suffix === '' && $method === 'DELETE') {
            $this->sql('UPDATE saves SET deleted_at=COALESCE(deleted_at,?),updated_at=? WHERE id=?', [$this->now, $this->now, $save['id']]);
            $this->sql('DELETE FROM uploads WHERE save_id=? AND committed IS NULL', [$save['id']]);
            return $this->ok();
        }
        if ($suffix === '/undelete' && $method === 'POST') {
            $this->sql('UPDATE saves SET deleted_at=NULL,updated_at=? WHERE id=?', [$this->now, $save['id']]);
            return $this->ok($this->saveJson($this->save($save['id'], $owner)));
        }
        if ($save['deleted_at'] !== null) { throw new ApiError(410, 'save_deleted'); }
        if ($suffix === '' && $method === 'GET') { return $this->ok($this->saveJson($save)); }
        if ($suffix === '/versions' && $method === 'GET') {
            return $this->ok(['versions' => array_map(fn($row) => $this->versionJson($row),
                $this->sql('SELECT * FROM versions WHERE save_id=? ORDER BY sequence DESC', [$save['id']])->fetchAll())]);
        }
        if (preg_match('#^/versions/([a-f0-9]{32})/content$#D', $suffix, $parts) && $method === 'GET') {
            $version = $this->one('SELECT * FROM versions WHERE revision=? AND save_id=?', [$parts[1], $save['id']]);
            if (!$version) { throw new ApiError(404, 'not_found'); }
            $stream = fopen($this->blobPath($version['blob']), 'rb');
            if (!$stream) { throw new RuntimeException('Missing blob'); }
            return ['status' => 200, 'stream' => $stream, 'size' => (int)$version['size'], 'sha256' => $version['sha256']];
        }
        if ($suffix === '/restore' && $method === 'POST') {
            $this->base($data, $save);
            $version = $this->one('SELECT * FROM versions WHERE revision=? AND save_id=?', [$data['revision'] ?? '', $save['id']]);
            if (!$version) { throw new ApiError(404, 'not_found'); }
            $this->reserve($owner, (int)$version['size']);
            return $this->publish($save, $version['blob'], (int)$version['size'], $version['sha256'], $version['metadata'], $device['name']);
        }
        if ($suffix === '/uploads' && $method === 'POST') {
            $base = $this->base($data, $save);
            $size = $data['size'] ?? null;
            $sha = $data['sha256'] ?? '';
            if (!is_int($size) || $size < 1 || $size > $this->config['quota'] || !is_string($sha) || !preg_match('/^[a-f0-9]{64}$/D', $sha)) { throw new ApiError(400, 'invalid_upload'); }
            $metadata = $this->metadata($data);
            $this->reserve($owner, $size);
            if ((int)$this->sql('SELECT COUNT(*) FROM uploads u JOIN saves s ON s.id=u.save_id WHERE s.account_id=? AND u.committed IS NULL', [$owner])->fetchColumn() >= 16) { throw new ApiError(409, 'upload_limit'); }
            $id = $this->id();
            $this->sql('INSERT INTO uploads VALUES(?,?,?,?,?,?,?,?,NULL)', [$id, $save['id'], $base, $size, $sha, $metadata, $device['name'], $this->now + $this->config['upload_hours'] * 3600]);
            return $this->ok($this->uploadJson($this->one('SELECT * FROM uploads WHERE id=?', [$id])), 201);
        }
        if (preg_match('#^/uploads/([a-f0-9]{32})(.*)$#D', $suffix, $parts)) {
            $upload = $this->one('SELECT * FROM uploads WHERE id=? AND save_id=?', [$parts[1], $save['id']]);
            if (!$upload) { throw new ApiError(404, 'upload_not_found'); }
            if ($parts[2] === '' && $method === 'GET') { return $this->ok($this->uploadJson($upload)); }
            if ($parts[2] === '' && $method === 'DELETE') {
                $this->sql('DELETE FROM uploads WHERE id=?', [$upload['id']]);
                return $this->ok();
            }
            if ($parts[2] === '/commit' && $method === 'POST') { return $this->commit($save, $upload); }
            if (preg_match('#^/chunks/(0|[1-9][0-9]{0,8})$#D', $parts[2], $chunk) && $method === 'PUT') {
                return $this->chunk($upload, (int)$chunk[1], $raw);
            }
        }
        throw new ApiError(404, 'not_found');
    }

    private function uploadJson(array $upload): array
    {
        return ['id' => $upload['id'], 'chunk_size' => self::CHUNK_SIZE,
            'chunks' => array_map('intval', $this->sql('SELECT idx FROM chunks WHERE upload_id=? ORDER BY idx', [$upload['id']])->fetchAll(PDO::FETCH_COLUMN)),
            'expires_at' => (int)$upload['expires_at'], 'revision' => $upload['committed']];
    }

    private function chunkPath(string $id, int $index): string { return $this->config['storage'] . '/chunks/' . $id . '-' . $index; }
    private function blobPath(string $id): string { return $this->config['storage'] . '/blobs/' . $id; }

    private function chunk(array $upload, int $index, string $raw): array
    {
        if ($upload['committed'] !== null) { throw new ApiError(409, 'upload_committed'); }
        $remaining = (int)$upload['size'] - $index * self::CHUNK_SIZE;
        if ($remaining <= 0 || strlen($raw) !== min(self::CHUNK_SIZE, $remaining)) { throw new ApiError(400, 'invalid_chunk'); }
        $sha = hash('sha256', $raw);
        $existing = $this->one('SELECT sha256 FROM chunks WHERE upload_id=? AND idx=?', [$upload['id'], $index]);
        if ($existing) {
            if (!hash_equals($existing['sha256'], $sha)) { throw new ApiError(409, 'chunk_conflict'); }
            return $this->ok();
        }
        $path = $this->chunkPath($upload['id'], $index);
        $temporary = $path . '-' . $this->id() . '.tmp';
        $this->writeFile($temporary, $raw);
        if (!rename($temporary, $path)) { throw new RuntimeException('Cannot publish chunk'); }
        $this->sql('INSERT INTO chunks VALUES(?,?,?,?)', [$upload['id'], $index, strlen($raw), $sha]);
        return $this->ok();
    }

    private function writeFile(string $path, string $bytes): void
    {
        $stream = fopen($path, 'xb');
        if (!$stream) { throw new RuntimeException('Cannot create blob'); }
        try {
            $written = 0;
            while ($written < strlen($bytes)) {
                $count = fwrite($stream, substr($bytes, $written));
                if ($count === false || $count === 0) { throw new RuntimeException('Cannot write blob'); }
                $written += $count;
            }
            if (!fflush($stream) || !fsync($stream)) { throw new RuntimeException('Cannot flush blob'); }
        } finally { fclose($stream); }
        chmod($path, 0600);
    }

    private function commit(array $save, array $upload): array
    {
        if ($upload['committed'] !== null) {
            $version = $this->one('SELECT * FROM versions WHERE revision=?', [$upload['committed']]);
            if (!$version) { throw new ApiError(410, 'version_expired'); }
            return $this->ok($this->versionJson($version));
        }
        $this->base(['base_revision' => $upload['base_revision']], $save);
        $count = (int)ceil((int)$upload['size'] / self::CHUNK_SIZE);
        if ((int)$this->sql('SELECT COUNT(*) FROM chunks WHERE upload_id=?', [$upload['id']])->fetchColumn() !== $count) { throw new ApiError(409, 'upload_incomplete'); }
        $blob = $this->id();
        $path = $this->blobPath($blob);
        $temporary = $path . '.tmp';
        $output = fopen($temporary, 'xb');
        if (!$output) { throw new RuntimeException('Cannot assemble blob'); }
        try {
            for ($index = 0; $index < $count; $index++) {
                $input = fopen($this->chunkPath($upload['id'], $index), 'rb');
                if (!$input) { throw new RuntimeException('Missing upload chunk'); }
                try {
                    if (stream_copy_to_stream($input, $output) === false) { throw new RuntimeException('Cannot assemble blob'); }
                } finally { fclose($input); }
            }
            if (!fflush($output) || !fsync($output)) { throw new RuntimeException('Cannot flush blob'); }
        } finally { fclose($output); }
        if (filesize($temporary) !== (int)$upload['size'] || !hash_equals($upload['sha256'], hash_file('sha256', $temporary))) {
            unlink($temporary);
            throw new ApiError(422, 'checksum_mismatch');
        }
        chmod($temporary, 0600);
        if (!rename($temporary, $path)) { throw new RuntimeException('Cannot publish blob'); }
        $result = $this->publish($save, $blob, (int)$upload['size'], $upload['sha256'], $upload['metadata'], $upload['device_name']);
        $this->sql('UPDATE uploads SET committed=? WHERE id=?', [$result['json']['revision'], $upload['id']]);
        $this->sql('DELETE FROM chunks WHERE upload_id=?', [$upload['id']]);
        return $result;
    }

    private function publish(array $save, string $blob, int $size, string $sha, string $metadata, string $device): array
    {
        $revision = $this->id();
        $sequence = 1 + (int)$this->sql('SELECT COALESCE(MAX(sequence),0) FROM versions WHERE save_id=?', [$save['id']])->fetchColumn();
        $this->sql('INSERT INTO versions VALUES(?,?,?,?,?,?,?,?,?)', [$revision, $save['id'], $blob, $size, $sha, $metadata, $device, $this->now, $sequence]);
        $this->sql('UPDATE saves SET head=?,metadata=?,updated_at=? WHERE id=?', [$revision, $metadata, $this->now, $save['id']]);
        $this->sql('DELETE FROM versions WHERE save_id=? AND revision NOT IN (SELECT revision FROM versions WHERE save_id=? ORDER BY sequence DESC LIMIT ?)', [$save['id'], $save['id'], $this->config['versions']]);
        return $this->ok($this->versionJson($this->one('SELECT * FROM versions WHERE revision=?', [$revision])), 201);
    }

    private function expireRows(): void
    {
        $this->sql('DELETE FROM rate_limits WHERE expires_at<=?', [$this->now]);
        $this->sql('DELETE FROM codes WHERE expires_at<=?', [$this->now]);
        $this->sql('DELETE FROM devices WHERE expires_at<=?', [$this->now]);
        $this->sql('DELETE FROM uploads WHERE expires_at<=?', [$this->now]);
        $this->sql('DELETE FROM saves WHERE deleted_at IS NOT NULL AND deleted_at<=?', [$this->now - $this->config['trash_days'] * 86400]);
    }

    /** Run from cron. Write lock prevents deleting files between rename and DB commit. */
    public function collectGarbage(?int $now = null): array
    {
        $this->now = $now ?? time();
        $this->db->exec('BEGIN IMMEDIATE');
        try {
            $this->expireRows();
            // Commit expiry before deleting files: rollback must never resurrect a row
            // whose blob was already removed. Reacquire lock before the live-file snapshot.
            $this->db->exec('COMMIT');
            $this->db->exec('BEGIN IMMEDIATE');
            $blobs = array_fill_keys($this->sql('SELECT DISTINCT blob FROM versions')->fetchAll(PDO::FETCH_COLUMN), true);
            $chunks = [];
            foreach ($this->sql('SELECT upload_id,idx FROM chunks')->fetchAll() as $row) { $chunks[$row['upload_id'] . '-' . $row['idx']] = true; }
            $deleted = 0;
            foreach (['blobs' => $blobs, 'chunks' => $chunks] as $directory => $live) {
                foreach (new \DirectoryIterator($this->config['storage'] . '/' . $directory) as $file) {
                    if ($file->isFile() && !isset($live[$file->getFilename()]) && @unlink($file->getPathname())) { $deleted++; }
                }
            }
            $this->db->exec('COMMIT');
            return ['deleted_files' => $deleted];
        } catch (Throwable $error) {
            $this->db->exec('ROLLBACK');
            throw $error;
        }
    }

    /** Consistent offline-restorable snapshot. Destination must be new and private. */
    public function backup(string $destination): void
    {
        if (file_exists($destination) || !mkdir($destination, 0700, true)) {
            throw new RuntimeException('Backup destination must be new');
        }
        $this->db->exec('BEGIN IMMEDIATE');
        try {
            // The separate reader sees the last committed WAL snapshot while this
            // writer lock excludes API mutation and garbage collection until copies finish.
            $reader = new PDO('sqlite:' . $this->config['storage'] . '/cloud.sqlite', null, null,
                [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
            $reader->exec('PRAGMA busy_timeout=10000');
            $reader->exec('VACUUM INTO ' . $reader->quote($destination . '/cloud.sqlite'));
            $reader = null;
            foreach (['blobs', 'chunks'] as $directory) {
                mkdir($destination . '/' . $directory, 0700);
            }
            foreach ($this->sql('SELECT DISTINCT blob FROM versions')->fetchAll(PDO::FETCH_COLUMN) as $blob) {
                if (!copy($this->blobPath($blob), $destination . '/blobs/' . $blob)) { throw new RuntimeException('Backup copy failed'); }
            }
            foreach ($this->sql('SELECT upload_id,idx FROM chunks')->fetchAll() as $row) {
                $name = $row['upload_id'] . '-' . $row['idx'];
                if (!copy($this->chunkPath($row['upload_id'], (int)$row['idx']), $destination . '/chunks/' . $name)) { throw new RuntimeException('Backup copy failed'); }
            }
            $this->writeFile($destination . '/COMPLETE', json_encode(['schema' => 1, 'created_at' => time()], JSON_THROW_ON_ERROR));
            $this->db->exec('COMMIT');
        } catch (Throwable $error) {
            $this->db->exec('ROLLBACK');
            throw $error;
        }
    }
}
