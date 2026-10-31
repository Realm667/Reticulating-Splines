<?php
declare(strict_types=1);

namespace ReticulatingSplines\Cloud;

use RuntimeException;

/** Small fixed-purpose SMTP submission adapter: verified TLS, no user-controlled headers. */
final class SmtpMailer
{
    public function __construct(private array $config) {}

    public function __invoke(string $email, string $purpose, string $code): void
    {
        $host = $this->config['host'] ?? '';
        $sender = $this->config['from'] ?? '';
        if (!preg_match('/^[a-zA-Z0-9.-]+$/D', $host) || !filter_var($sender, FILTER_VALIDATE_EMAIL) ||
            !filter_var($email, FILTER_VALIDATE_EMAIL) || !preg_match('/^[0-9]{8}$/D', $code) ||
            !in_array($purpose, ['verify', 'reset'], true)) { throw new RuntimeException('Invalid mail configuration'); }
        $context = stream_context_create(['ssl' => ['verify_peer' => true, 'verify_peer_name' => true,
            'peer_name' => $host, 'allow_self_signed' => false]]);
        $socket = stream_socket_client('tcp://' . $host . ':587', $errorNumber, $errorMessage, 10, STREAM_CLIENT_CONNECT, $context);
        if (!$socket) { throw new RuntimeException('Mail transport unavailable'); }
        stream_set_timeout($socket, 10);
        try {
            $this->reply($socket, 220);
            $this->command($socket, 'EHLO cloud.reticulating-splines.invalid', 250);
            $this->command($socket, 'STARTTLS', 220);
            if (!stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT | STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT)) {
                throw new RuntimeException('Mail TLS unavailable');
            }
            $this->command($socket, 'EHLO cloud.reticulating-splines.invalid', 250);
            $this->command($socket, 'AUTH LOGIN', 334);
            $this->command($socket, base64_encode($this->config['username']), 334);
            $this->command($socket, base64_encode($this->config['password']), 235);
            $this->command($socket, 'MAIL FROM:<' . $sender . '>', 250);
            $this->command($socket, 'RCPT TO:<' . $email . '>', 250);
            $this->command($socket, 'DATA', 354);
            $subject = $purpose === 'verify' ? 'Verify your account' : 'Reset your password';
            $message = 'From: Reticulating Splines <' . $sender . ">\r\nTo: <" . $email . ">\r\n" .
                'Subject: Reticulating Splines - ' . $subject . "\r\n" .
                'Date: ' . gmdate('D, d M Y H:i:s +0000') . "\r\n" .
                'Message-ID: <' . bin2hex(random_bytes(16)) . '@' . $host . ">\r\n" .
                "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n" .
                "Your Reticulating Splines code is: $code\r\n\r\nEnter it in the game. It expires after 15 minutes.\r\n" .
                "If you did not request this message, you can ignore it.\r\n";
            $this->command($socket, $message . '.', 250);
            // DATA acknowledgement is delivery acceptance. A missing QUIT reply must
            // not roll back an already accepted verification code.
            @fwrite($socket, "QUIT\r\n");
        } finally { fclose($socket); }
    }

    private function command($socket, string $command, int $expected): void
    {
        $bytes = $command . "\r\n";
        while ($bytes !== '') {
            $written = fwrite($socket, $bytes);
            if (!$written) { throw new RuntimeException('Mail transport unavailable'); }
            $bytes = substr($bytes, $written);
        }
        $this->reply($socket, $expected);
    }

    private function reply($socket, int $expected): void
    {
        for ($count = 0; $count < 50; $count++) {
            $line = fgets($socket, 2048);
            if ($line === false || !preg_match('/^([0-9]{3})([ -])/', $line, $match)) { break; }
            if ((int)$match[1] !== $expected) { break; }
            if ($match[2] === ' ') { return; }
        }
        throw new RuntimeException('Mail transport unavailable');
    }
}
