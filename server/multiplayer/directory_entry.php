<?php
declare(strict_types=1);
// Deployment defines these in a private config before requiring this entry point.
require_once __DIR__ . '/directory.php';
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('Access-Control-Allow-Origin: *');
try {
    $raw = file_get_contents('php://input', false, null, 0, 4097);
    if (strlen($raw) > 4096) {
        http_response_code(413);
        echo '{"error":"too_large"}';
        exit;
    }
    $body = $raw === '' ? [] : json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
    $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    $prefix = '/api/multiplayer/v2';
    $path = str_starts_with($path, $prefix) ? substr($path, strlen($prefix)) : '/invalid';
    $auth = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    [$status, $response] = directory_handle(directory_db(DIRECTORY_DB), $_SERVER['REQUEST_METHOD'], $path, $body, $auth, $_SERVER['REMOTE_ADDR'], time());
    http_response_code($status);
    echo json_encode($response, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
} catch (JsonException $e) {
    http_response_code(400);
    echo '{"error":"invalid_json"}';
} catch (Throwable $e) {
    http_response_code(503);
    echo '{"error":"unavailable"}';
}
