<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require __DIR__ . '/bootstrap.php';
$service = new ReticulatingSplines\Cloud\CloudService(cloud_config());
echo json_encode($service->collectGarbage(), JSON_THROW_ON_ERROR), PHP_EOL;
