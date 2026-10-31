<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require __DIR__ . '/bootstrap.php';
if ($argc !== 2) { fwrite(STDERR, "Usage: php backup.php /private/new-backup-directory\n"); exit(2); }
umask(0077);
$service = new ReticulatingSplines\Cloud\CloudService(cloud_config());
$service->backup($argv[1]);
echo "Cloud snapshot complete. Protect the configuration/secret separately.\n";
