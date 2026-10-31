# Private Cloud Saves service

PHP 8.1-compatible source, SQLite via PDO, JSON, hash and OpenSSL. Deploy a currently
security-supported PHP build (hosting preflight: PHP 8.5.12). There are no Composer
packages, browser cookies or multiplayer-token dependencies. The service treats a
save as opaque bytes: the client validates the complete city/region/host checkpoint,
removes local paths and external assets, and checks game/mod compatibility before loading.

## Production deployment for REL

Production API base: `https://rs.realm667.com/cloud-saves/api/cloud/v1`.
No live deployment or real emails are performed by these source tests.

Keep all service source, SQLite data, blobs, staging and configuration **outside** the
document root. Use this exact mapping on the preflighted hosting account:

| Local source | Remote path |
| --- | --- |
| `CloudService.php`, `schema.sql`, `bootstrap.php`, `SmtpMailer.php`, `maintenance.php`, `backup.php` | `/www/htdocs/w021da2c/rs.realm667.com_cloud-saves/backend/` |
| `public/index.php` | `/www/htdocs/w021da2c/rs.realm667.com_cloud-saves/backend/public/index.php` |
| Filled private configuration below | `/www/htdocs/w021da2c/rs.realm667.com_cloud-saves/config.php` |
| Small public wrapper below | `/www/htdocs/w021da2c/rs.realm667.com/cloud-saves/api/cloud/v1/index.php` |
| Scoped rewrite below | `/www/htdocs/w021da2c/rs.realm667.com/cloud-saves/api/cloud/v1/.htaccess` |

FTP cwd is the website root; private paths are in its sibling directory. Do not upload
tests, `config.example.php`, configuration secrets or database under the webroot.
Do not change the existing root/Joomla/multiplayer rewrites. If those intercept the
scoped route, stop and report the exact response; do not silently edit the root rules.

Public wrapper (only file besides the scoped `.htaccess`):

```php
<?php
declare(strict_types=1);
putenv('RS_CLOUD_CONFIG=/www/htdocs/w021da2c/rs.realm667.com_cloud-saves/config.php');
require '/www/htdocs/w021da2c/rs.realm667.com_cloud-saves/backend/public/index.php';
```

Scoped `.htaccess` (copy `public/.htaccess`):

```apache
Options -Indexes
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^ index.php [QSA,L]
SetEnvIf Authorization "(.+)" HTTP_AUTHORIZATION=$1
```

Private `config.php`, fill SMTP credentials only through REL's existing private channel:

```php
<?php
declare(strict_types=1);
require_once __DIR__ . '/backend/SmtpMailer.php';
return [
    'storage' => __DIR__ . '/data',
    'secret' => 'GENERATE-64-RANDOM-HEX-CHARACTERS-ONCE',
    'base_path' => '/cloud-saves/api/cloud/v1',
    'quota' => 500 * 1024 * 1024,
    'versions' => 5,
    'trash_days' => 30,
    'upload_hours' => 48,
    'session_days' => 90,
    'garbage_interval' => 3600,
    'mail' => new ReticulatingSplines\Cloud\SmtpMailer([
        'host' => 'SMTP-HOST-FROM-REL',
        'username' => 'rs@realm667.com',
        'password' => 'PRIVATE-SMTP-PASSWORD',
        'from' => 'rs@realm667.com',
    ]),
];
```

Generate the secret with `php -r 'echo bin2hex(random_bytes(32)), PHP_EOL;'`; store it
privately and retain it across deployments (changing it invalidates every device and code).
Config/data dirs should be mode 0700 and config mode 0600. The bootstrap verifies real
paths are outside the document root and uses umask 0077. No client-controlled proxy
headers are trusted. HTTPS must appear as `HTTPS=on/1` in PHP; a trusted TLS proxy must
set it itself. `allow_local_http=true` is only for explicit loopback testing and must
not be enabled in production. Responses are `no-store` and do not enable CORS.

SMTP adapter uses certificate-verified STARTTLS on port 587, AUTH LOGIN and a ten-second
socket timeout. It never logs credentials or codes. PHP native `mail()` can instead be
provided explicitly via the callback in `config.example.php`; absence of an adapter
fails account mail operations closed. Existing users cannot be inferred from successful
register/reset-request responses. The UI handles the eight-digit code entirely in-game.

Deploy with maintenance window before schema changes; this initial schema is version 1.
Current source creates an empty database automatically. Do not treat `CREATE IF NOT
EXISTS` as a migration mechanism for later incompatible schemas.

### Operations and limits

Run hourly, with private `RS_CLOUD_CONFIG` environment:

```sh
php /private/backend/maintenance.php
```

This expires staged uploads after 48 hours, sessions after 90 days, codes after 15 minutes,
and trash after 30 days; then removes orphaned/pruned blobs and chunks. Row expiry also
runs on API requests. If cron is unavailable, set `garbage_interval => 3600` in the private
configuration. After the HTTPS/input guards, the first eligible request attempts collection,
at most once per hour. A private persistent file lock is acquired nonblocking; its timestamp
is written before work, so parallel requests and failures cannot trigger a collection storm.
A busy database skips this optional run without waiting. Maintenance failures do not change
authentication or normal API handling. With no traffic, the fallback does not run; the next
request resumes it. Set the interval to 0 to disable the fallback (the service default).
The CLI collector remains available independently, including for hosting scheduled tasks.
Configure
host disk monitoring and backups before enabling public registrations.

500 MiB is the default **per account** quota. All five retained versions and trash count.
Incomplete uploads reserve their entire declared size atomically; delete/cancel them to
release the reservation. An upload needs enough headroom while its previous five versions
still exist. During assembly, staging plus final bytes can temporarily require roughly twice
the accounted quota; allow global disk headroom across all accounts. Restore creates a new
version and conservatively charges its logical size, even though the immutable blob is shared.
Maximum 1,000 saves, 30 devices and 16 pending uploads per account. Fixed chunks are 1 MiB,
except the final chunk. JSON request cap is 192 KiB; metadata cap 144 KiB including an optional
base64 PNG preview (encoded <=128 KiB, <=384x256). Credentials never occur in save metadata.

SQLite `BEGIN IMMEDIATE`, full durability and WAL serialize publication, quota reservations,
device revocation, and GC. Only one worker can win a predecessor revision. File writes are
flushed and fsynced before publishing DB pointers. Failure cannot expose an incomplete
version; orphan files are collected later. A busy lock returns a generic 503 for retry.
This intentionally targets the current small hosting deployment; monitor lock contention
before scaling to a large user population. SMTP currently runs inside the account transaction
to ensure a failed send never publishes a usable unseen code; its bounded network wait can
temporarily delay other writes. Do not run this SQLite file over a network filesystem.

No password is stored plaintext. Fixed-length SHA-256/base64 preprocessing avoids bcrypt's
72-byte limit; PHP `password_hash(PASSWORD_BCRYPT)` at cost 12 provides the salted expensive hash.
Passwords are 12–1024 UTF-8 bytes. Tokens are random 256-bit, only HMAC hashes are stored.
Codes are random eight digits, HMAC-hashed, valid 15 minutes, limited to five attempts.
Persistent IP/email throttles bound authentication and mail attempts. Reset revokes every
device. Device rotation replaces the bearer atomically and preserves the device identifier.
Host access logs must redact Authorization and must not record request bodies.

### Consistent backups and restore

With `RS_CLOUD_CONFIG` set, run `php backup.php /private/new-snapshot-directory`.
The destination must not exist. The service holds the writer lock while a separate SQLite
reader uses `VACUUM INTO` and copies every referenced immutable blob/staged chunk. Only a
directory containing `COMPLETE` is a finished snapshot. Backups contain private saves,
email addresses and hashed credentials: encrypt/restrict them and define retention.
Back up the private configuration/secret separately. Restore while HTTP workers/cron are
stopped: replace the data directory with a complete snapshot, retain the corresponding
secret, remove the informational `COMPLETE` if desired, then verify login and a save checksum
before reopening the endpoint. Never copy a live `.sqlite` alone and omit its WAL.

## HTTP contract

Paths below are relative to the configured base (`/api/cloud/v1` in local tests). JSON
requests use `Content-Type: application/json`; authenticated calls send
`Authorization: Bearer <token>`. JSON errors: `{ "error": "machine_code" }` (409 revision
conflict additionally includes `head`). Never display backend English codes as UI prose.

| Method/path | Request / response |
| --- | --- |
| POST `/register` | `{email,password}` -> `{ok:true}`; code sent to email |
| POST `/verify` | `{email,code}` -> `{ok:true}`; then login |
| POST `/login` | `{email,password,device}` -> `{token,account_id,device_id,expires_at,account:{id,email}}` |
| POST `/reset-request` | `{email}` -> `{ok:true}` |
| POST `/reset` | `{email,code,password}` -> `{ok:true}`, all existing devices revoked |
| POST `/session/rotate` | `{}` -> login response shape, old token revoked |
| GET `/me` | `{account:{id,email},usage,quota}` bytes |
| GET `/devices` | `{devices:[{id,name,created_at,last_seen,expires_at,current}]}` |
| DELETE `/devices/{id}` or `/devices` | Revoke one own device or all own devices -> `{ok:true}` |
| GET `/saves` | `{saves:[{id,name,kind,head,metadata,updated_at,deleted_at,device_name}]}` |
| GET `/saves?trash=1` | Same shape, deleted saves only |
| POST `/saves` | `{name,kind,metadata,client_id?}` -> save (201; idempotent retry 200) |
| GET `/saves/{id}` | Own save descriptor |
| DELETE `/saves/{id}` | Move to trash; never called merely because local file was removed |
| POST `/saves/{id}/undelete` | Restore from trash -> save descriptor |
| GET `/saves/{id}/versions` | `{versions:[{revision,sha256,size,metadata,device_name,created_at}]}` newest first |
| GET `/saves/{id}/versions/{revision}/content` | Raw bytes; `X-Content-SHA256`, `Content-Length` |
| POST `/saves/{id}/restore` | `{revision,base_revision}` -> new version (201) |
| POST `/saves/{id}/uploads` | `{base_revision,size,sha256,metadata}` -> upload (201) |
| GET `/saves/{id}/uploads/{upload}` | `{id,chunk_size,chunks:[indices],expires_at,revision}` |
| PUT `/saves/{id}/uploads/{upload}/chunks/{index}` | Raw exact-sized bytes -> `{ok:true}`; repeat identical bytes accepted |
| POST `/saves/{id}/uploads/{upload}/commit` | `{}` -> version (201; committed retry 200 with identical revision) |
| DELETE `/saves/{id}/uploads/{upload}` | Cancel/release reservation; published version unaffected |

`head`/`base_revision` are null before the first commit; afterward opaque server-issued
32-hex strings. Never use device timestamps as ordering. Commit rechecks the original
predecessor, verifies the assembled SHA-256, then publishes atomically. A conflict leaves
staged bytes intact for the upload TTL; the durable local queue must retain the original
snapshot and offer explicit selection/clone. A clone creates a new save and uploads that
snapshot against null. Committed retry state persists for the original upload TTL; a
pruned revision returns `version_expired` instead of silently publishing again.

`kind`: `city`, `region`, `multiplayer`. Metadata allowlist: `name`, `kind`, `game_version`,
`save_format` strings, nonnegative integer `population`, `year`, `mods:[{id,version}]`, optional
`preview` PNG base64. No filesystem paths, graphics/music packs or device settings.
Save descriptors (including the account-wide list) expose only the fixed-size summary
fields `name`, `kind`, `game_version`, `save_format`, `population` and `year` in metadata.
They omit `preview` and `mods`, so even 1,000 descriptors fit the client's 4 MiB response
limit. Fetch `/saves/{id}/versions` after selecting a save; each version retains its
own preview and complete mod compatibility metadata.
Owner authorization is checked before every save/upload/version operation. Random foreign
IDs return 404; devices cannot be used to infer another account's devices. Full multiplayer
payloads still require the game's host-only checkpoint and lobby continuation safeguards.

## Local verification

```sh
php tests/service_test.php
php tests/race_test.php
python tests/http_test.py --php /absolute/path/to/php
```

The actual Godot client can also be checked against a disposable local PHP service
from the repository root:

```sh
python tools/test_cloud_http.py --godot /absolute/path/to/godot --php /absolute/path/to/php --artifact-dir /tmp/cloud-proofs
```

For a PHP installation without its SQLite extension configured, add
`--php-extension-dir /absolute/path/to/php/ext`.

All tests use fresh temporary SQLite/files and fake mail callbacks; they never send a real
message, contact production or read personal game data. Race tests use independent PHP
processes and a simultaneous release barrier. HTTP tests start only a loopback server.
