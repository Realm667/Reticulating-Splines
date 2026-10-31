<?php
declare(strict_types=1);
require dirname(__DIR__) . '/CloudService.php';
$job = json_decode(file_get_contents($argv[1]), true, 32, JSON_THROW_ON_ERROR);
$service = new ReticulatingSplines\Cloud\CloudService($job['config']);
file_put_contents($argv[1] . '.ready', 'ready');
$deadline = microtime(true) + 10;
while (!is_file($job['go'])) {
    if (microtime(true) > $deadline) { exit(2); }
    usleep(10000);
}
$result = $service->handle($job['method'], $job['path'], $job['body'], $job['token']);
echo json_encode($result, JSON_THROW_ON_ERROR);
