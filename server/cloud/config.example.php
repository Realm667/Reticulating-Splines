<?php
declare(strict_types=1);
// Copy OUTSIDE the document root. Set RS_CLOUD_CONFIG to that absolute path.
// Generate secret once: php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'
return [
    'storage' => '/srv/private/reticulating-splines-cloud',
    'secret' => 'REPLACE-WITH-64-RANDOM-HEX-CHARACTERS',
    'quota' => 500 * 1024 * 1024,
    'versions' => 5,
    'trash_days' => 30,
    'upload_hours' => 48,
    'session_days' => 90,
    // Explicitly configure an adapter before account creation/reset can work.
    // Adapter: function(string $email, string $purpose, string $code): void.
    // Throw on failure. Never log codes or write them in public files.
    // Native-mail example (requires a configured host MTA):
    // 'mail' => static function ($email, $purpose, $code): void {
    //     $subject = $purpose === 'verify' ? 'Verify your account' : 'Reset your password';
    //     if (!mail($email, 'Reticulating Splines: '.$subject,
    //         "Your code: $code\nThis code expires after 15 minutes.",
    //         "From: Reticulating Splines <cloud@example.invalid>\r\nContent-Type: text/plain; charset=UTF-8")) {
    //         throw new RuntimeException('Mail transport unavailable');
    //     }
    // },
];
