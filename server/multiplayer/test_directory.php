<?php
declare(strict_types=1);
require __DIR__ . '/directory.php';
$db = directory_db(':memory:');
$now = 1792260000;
$id = str_repeat('a', 32);
$auth = 'Bearer ' . str_repeat('b', 64);
$game = ['city'=>'Test', 'host'=>'Host', 'build'=>'test', 'mode'=>'shared', 'phase'=>'lobby', 'players'=>2, 'port'=>20000, 'locked'=>true, 'open'=>true];
$checks = 0;
function check(bool $condition, string $message): void {
    global $checks;
    if (!$condition) throw new RuntimeException($message);
    $checks++;
}
function call_directory(string $method, string $path, mixed $body = [], ?string $token = null, ?int $time = null, string $ip = '8.8.8.8'): array {
    global $db, $auth, $now;
    return directory_handle($db, $method, $path, $body, $token ?? $auth, $ip, $time ?? $now);
}
$body = ['version'=>2, 'game'=>$game];
check(call_directory('PUT', '/games/'.$id, $body)[0] === 200, 'register');
$list = call_directory('GET', '/games')[1];
check(count($list['games']) === 1 && $list['games'][0]['address'] === '8.8.8.8' && $list['games'][0]['port'] === 20000, 'observed endpoint');
check(!isset($list['games'][0]['token']) && !isset($list['games'][0]['password']), 'secrets not public');
check(!isset(call_directory('GET', '/activity')[1]['games'][0]['address']), 'widget omits IP');
check(call_directory('PUT', '/games/'.$id, $body, 'Bearer '.str_repeat('c',64))[0] === 403, 'hijack rejected');
check(call_directory('DELETE', '/games/'.$id, [], 'Bearer '.str_repeat('c',64))[0] === 403, 'unauthorized delete');
$bad = $body; $bad['game']['port'] = 0;
check(call_directory('PUT', '/games/'.$id, $bad)[0] === 400, 'port bounds');
$bad['game']['port'] = '20000';
check(call_directory('PUT', '/games/'.$id, $bad)[0] === 400, 'typed port');
$bad = $body; $bad['game']['city'] = "bad\nname";
check(call_directory('PUT', '/games/'.$id, $bad)[0] === 400, 'control text rejected');
check(call_directory('PUT', '/games/'.$id, $body, null, null, '127.0.0.1')[0] === 400, 'nonpublic address rejected');
$body['game']['phase'] = 'running';
for ($i=0; $i<3; $i++) check(call_directory('PUT', '/games/'.$id, $body)[0] === 200, 'idempotent heartbeat');
check(call_directory('GET', '/games')[1]['totals']['sessions'] === 1, 'one start');
for ($i=1; $i<4; $i++) check(call_directory('PUT', '/games/'.str_repeat((string)$i,32), ['version'=>2,'game'=>$game])[0] === 200, 'concurrent rooms');
check(call_directory('PUT', '/games/'.str_repeat('4',32), $body)[0] === 429, 'per address capacity');
check(call_directory('GET', '/games')[1]['totals']['peak_players'] === 8, 'player peak');
check(call_directory('GET', '/games', [], null, $now + 181)[1]['games'] === [], 'lease cleanup');
check(call_directory('GET', '/games')[1]['totals']['sessions'] === 1, 'totals outlive rooms');
check(call_directory('PUT', '/games/'.$id, $body)[0] === 200, 're-register after expiry');
check(call_directory('DELETE', '/games/'.$id)[0] === 200 && call_directory('GET','/games')[1]['games'] === [], 'unlist');
for ($i=0; $i<13; $i++) $response = call_directory('PUT', '/games/'.str_pad(dechex($i),32,'0',STR_PAD_LEFT), $body);
check($response[0] === 429, 'create limit');
check(call_directory('GET','/games',[],null,$now+86400)[1]['totals']['today'] === 0, 'UTC day roll');
echo "$checks directory checks passed\n";
