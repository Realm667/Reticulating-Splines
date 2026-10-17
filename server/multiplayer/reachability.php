<?php
declare(strict_types=1);
require_once __DIR__ . '/directory.php';

// Only the authenticated room owner can test their observed public source IP.
// Commit rate limits before network I/O; a slow host never holds the DB lock.
function reachability_prepare(PDO $db, string $path, mixed $body, string $auth, string $ip, int $now): array {
    if (!preg_match('#^/games/([a-f0-9]{32})/check$#D', $path, $match)) return [404, ['error'=>'not_found']];
    if (!preg_match('/^Bearer ([a-f0-9]{64})$/D', $auth, $token)) return [401, ['error'=>'unauthorized']];
    if (!is_array($body) || !is_string($body['nonce'] ?? null) || !preg_match('/^[a-f0-9]{64}$/D', $body['nonce'])) return [400, ['error'=>'invalid_nonce']];
    if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) || str_starts_with(strtolower($ip), '::ffff:')) return [400, ['error'=>'public_address_required']];
    $db->exec('BEGIN IMMEDIATE');
    try {
        directory_query($db, 'DELETE FROM limits WHERE expires<=?', [$now]);
        $row = directory_query($db, 'SELECT * FROM games WHERE id=? AND expires>?', [$match[1], $now])->fetch(PDO::FETCH_ASSOC);
        if (!$row || !hash_equals($row['token'], hash('sha256', $token[1])) || $row['ip'] !== $ip) {
            $result = [403, ['error'=>'unauthorized']];
        } elseif (!directory_limit($db, 'probe:'.$ip, 2, $now) || !directory_limit($db, 'probe:global', 30, $now)) {
            $result = [429, ['error'=>'rate_limit']];
        } else {
            $info = json_decode($row['info'], true, 16, JSON_THROW_ON_ERROR);
            $result = [200, ['ip'=>$ip, 'port'=>$info['port'], 'nonce'=>$body['nonce']]];
        }
        $db->exec('COMMIT');
        return $result;
    } catch (Throwable $e) {
        $db->exec('ROLLBACK');
        throw $e;
    }
}

function reachability_read($stream, int $length, float $deadline): string {
    $data = '';
    while (strlen($data) < $length && microtime(true) < $deadline && !feof($stream)) {
        $part = fread($stream, $length - strlen($data));
        if ($part === false || $part === '') break;
        $data .= $part;
    }
    return $data;
}

function reachability_probe(string $ip, int $port, string $nonce): string {
    if (!function_exists('stream_socket_client')) return 'unavailable';
    $address = str_contains($ip, ':') ? '['.$ip.']' : $ip;
    $errno = 0;
    $error = '';
    $stream = @stream_socket_client('tcp://'.$address.':'.$port, $errno, $error, 2, STREAM_CLIENT_CONNECT);
    if (!$stream) return in_array($errno, [1, 13, 97, 100, 101], true) ? 'unavailable' : 'unreachable';
    try {
        stream_set_timeout($stream, 1);
        $deadline = microtime(true) + 2;
        $json = json_encode(['type'=>'reachability', 'nonce'=>$nonce], JSON_THROW_ON_ERROR);
        $packet = pack('V', strlen($json)).$json;
        if (@fwrite($stream, $packet) !== strlen($packet)) return 'unreachable';
        $header = reachability_read($stream, 4, $deadline);
        if (strlen($header) !== 4) return 'unreachable';
        $length = unpack('V', $header)[1];
        if ($length < 2 || $length > 256) return 'unreachable';
        $data = json_decode(reachability_read($stream, $length, $deadline), true);
        return is_array($data) && ($data['type'] ?? '') === 'reachability_ok' && ($data['nonce'] ?? '') === $nonce ? 'reachable' : 'unreachable';
    } finally {
        fclose($stream);
    }
}

function reachability_handle(PDO $db, string $path, mixed $body, string $auth, string $ip, int $now): array {
    [$status, $data] = reachability_prepare($db, $path, $body, $auth, $ip, $now);
    if ($status !== 200) return [$status, $data];
    return [200, ['version'=>2, 'status'=>reachability_probe($data['ip'], $data['port'], $data['nonce'])]];
}
