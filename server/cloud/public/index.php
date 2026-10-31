<?php
declare(strict_types=1);

use ReticulatingSplines\Cloud\CloudService;

require_once dirname(__DIR__) . '/bootstrap.php';

header('Cache-Control: no-store, private');
header('X-Content-Type-Options: nosniff');
header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");
header('Referrer-Policy: no-referrer');
header('Content-Type: application/json; charset=utf-8');

try {
    $config = cloud_config();
    $https = ($_SERVER['HTTPS'] ?? '') === 'on' || ($_SERVER['HTTPS'] ?? '') === '1';
    $loopback = in_array($_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true);
    if (!$https && !(($config['allow_local_http'] ?? false) && $loopback)) {
        http_response_code(426);
        echo '{"error":"https_required"}';
        exit;
    }
    // Forwarded headers are deliberately not trusted. Configure HTTPS in the server
    // environment at a trusted TLS proxy; do not accept client-controlled X-Forwarded-*.
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    $raw = '';
    $body = [];
    $limit = $method === 'PUT' ? CloudService::CHUNK_SIZE : 196608;
    $input = fopen('php://input', 'rb');
    $raw = stream_get_contents($input, $limit + 1);
    fclose($input);
    if ($raw === false || strlen($raw) > $limit || (int)($_SERVER['CONTENT_LENGTH'] ?? 0) > $limit) {
        http_response_code(413);
        echo '{"error":"request_too_large"}';
        exit;
    }
    if ($method === 'POST' && $raw !== '') {
        if (!str_starts_with(strtolower($_SERVER['CONTENT_TYPE'] ?? ''), 'application/json')) {
            http_response_code(415);
            echo '{"error":"json_required"}';
            exit;
        }
        try { $decoded = json_decode($raw, false, 64, JSON_THROW_ON_ERROR); }
        catch (JsonException) { $decoded = null; }
        if (!$decoded instanceof stdClass) {
            http_response_code(400);
            echo '{"error":"invalid_json"}';
            exit;
        }
        $body = json_decode($raw, true, 64, JSON_THROW_ON_ERROR);
    }
    $authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    $token = preg_match('/^Bearer ([a-f0-9]{64})$/D', $authorization, $match) ? $match[1] : '';
    $service = new CloudService($config);
    $service->maybeCollectGarbage();
    $result = $service->handle($method, $_SERVER['REQUEST_URI'] ?? '', $body, $token, $raw, $_SERVER['REMOTE_ADDR'] ?? 'unknown');
    http_response_code($result['status']);
    if (isset($result['stream'])) {
        header('Content-Type: application/octet-stream');
        header('Content-Length: ' . $result['size']);
        header('X-Content-SHA256: ' . $result['sha256']);
        header('Content-Disposition: attachment; filename="cloud-save.sc2x"');
        fpassthru($result['stream']);
        fclose($result['stream']);
    } else {
        echo json_encode($result['json'], JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
    }
} catch (Throwable) {
    http_response_code(503);
    echo '{"error":"service_unavailable"}';
}
