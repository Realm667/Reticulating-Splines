<?php
declare(strict_types=1);

require_once __DIR__ . '/CloudService.php';
umask(0077);

function cloud_config(): array
{
    $path = getenv('RS_CLOUD_CONFIG');
    if (!$path || !is_file($path)) { throw new RuntimeException('Missing private configuration'); }
    $config = require $path;
    if (!is_array($config) || !isset($config['storage'], $config['secret']) ||
        str_starts_with($config['secret'], 'REPLACE-')) {
        throw new RuntimeException('Incomplete private configuration');
    }
    // Deny storage or configuration under the public document root, even by symlink.
    $documentRoot = realpath($_SERVER['DOCUMENT_ROOT'] ?? __DIR__ . '/public');
    $storage = realpath($config['storage']);
    if (!$storage && !mkdir($config['storage'], 0700, true)) { throw new RuntimeException('Cannot create private storage'); }
    $storage = realpath($config['storage']);
    foreach ([$storage, realpath($path)] as $private) {
        $root = strtolower(str_replace('\\', '/', (string)$documentRoot));
        $candidate = strtolower(str_replace('\\', '/', (string)$private));
        if ($root !== '' && ($candidate === $root || str_starts_with($candidate, $root . '/'))) {
            throw new RuntimeException('Cloud data must be outside document root');
        }
    }
    return $config;
}
