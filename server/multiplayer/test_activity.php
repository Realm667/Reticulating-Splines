<?php
declare(strict_types=1);
require __DIR__ . '/test_directory.php';
// test_directory supplies an isolated SQLite database and assertion helpers.
$db = directory_db(':memory:');
$body = ['version'=>2, 'activity'=>['city'=>'Solo <safe>', 'phase'=>'running'],
    'cities'=>[['id'=>str_repeat('d',64), 'population'=>12000]]];
$path = '/singleplayer/'.$id;
check(call_directory('PUT', $path, $body)[0] === 200, 'solo presence accepted');
for ($i=0;$i<3;$i++) check(call_directory('PUT', $path, $body)[0] === 200, 'solo heartbeat idempotent');
$activity = call_directory('GET', '/activity')[1];
check(count($activity['singleplayer']) === 1 && $activity['statistics']['singleplayer']['sessions'] === 1, 'one active solo session');
check(call_directory('GET','/games')[1]['games'] === [] && !isset(call_directory('GET','/games')[1]['singleplayer']), 'never joinable or in game browser');
check(!str_contains(json_encode($activity), str_repeat('d',64)) && !str_contains(json_encode($activity), $id)
    && !str_contains(json_encode($activity), '8.8.8.8'), 'opaque identifiers and network source private');
check(call_directory('DELETE',$path,[],'Bearer '.str_repeat('f',64))[0] === 403, 'foreign delete blocked');
check(call_directory('PUT',$path,$body,'Bearer '.str_repeat('f',64))[0] === 403, 'foreign replacement blocked');
foreach ([-1, 1.2, '42', 8589934591, null] as $invalid) {
    $bad=$body; $bad['cities'][0]['population']=$invalid;
    check(call_directory('PUT',$path,$bad)[0] === 400, 'invalid solo population');
}
foreach ([[], 12, null, str_repeat('x',65), "bad\nname", "\xff"] as $invalid) {
    $bad=$body; $bad['activity']['city']=$invalid;
    check(call_directory('PUT',$path,$bad)[0] === 400, 'invalid solo city name');
}
$bad=$body; $bad['cities'][]=$body['cities'][0];
check(call_directory('PUT',$path,$bad)[0] === 400, 'one solo city only');
$bad=$body; $bad['activity']['phase']='lobby';
check(call_directory('PUT',$path,$bad)[0] === 400, 'solo has no join lobby');
$body['activity']['city']='Renamed'; $body['activity']['phase']='paused'; $body['cities'][0]['population']=9000;
check(call_directory('PUT',$path,$body)[0] === 200, 'pause/rename/population decline');
$stats=call_directory('GET','/activity')[1]['statistics'];
check($stats['singleplayer']['cities_founded'] === 1 && $stats['singleplayer']['total_population'] === 9000, 'same saved ID updates');
$multi=['version'=>2,'game'=>array_merge($game,['phase'=>'running','players'=>2]),'cities'=>$body['cities']];
$multi['cities'][0]['population']=11000;
check(call_directory('PUT','/games/'.$id,$multi,null,$now+1)[0] === 200,'same city in multiplayer');
$stats=call_directory('GET','/activity',[],null,$now+1)[1]['statistics'];
check($stats['total']['cities_founded'] === 1 && $stats['total']['total_population'] === 11000,'deduplicated total uses newest report');
check($stats['singleplayer']['cities_founded'] === 1 && $stats['multiplayer']['cities_founded'] === 1,'mode columns retain participation');
check($stats['total']['peak_players'] === 3 && $stats['total']['online_sessions'] === 2, 'simultaneous peak and session totals');
call_directory('DELETE',$path,[],null,$now+2);
check(call_directory('GET','/activity',[],null,$now+2)[1]['singleplayer'] === [],'normal leave removes presence');
call_directory('DELETE','/games/'.$id,[],null,$now+2);
// Separate peaks cannot be added to create a fictitious combined peak.
$multi['game']['players']=4;
call_directory('PUT','/games/'.$id,$multi,null,$now+65);
call_directory('DELETE','/games/'.$id,[],null,$now+66);
for ($i=0;$i<3;$i++) call_directory('PUT','/singleplayer/'.str_pad((string)$i,32,'0'),$body,null,$now+67);
$stats=call_directory('GET','/activity',[],null,$now+67)[1]['statistics'];
check($stats['singleplayer']['peak_players'] === 3 && $stats['multiplayer']['peak_players'] === 4 && $stats['total']['peak_players'] === 4,'peak is measured, not sum: '.json_encode($stats));
check($stats['total']['cities_founded'] === 1 && $stats['total']['total_population'] === 9000,'copied saves and last report win');
$expired=call_directory('GET','/activity',[],null,$now+250)[1];
check($expired['singleplayer'] === [] && $expired['statistics']['total']['online_players'] === 0,'crashed clients expire');
check($expired['statistics']['total']['cities_founded'] === 1,'expiry retains counters');
check(call_directory('GET','/activity',[],null,$now+86400)[1]['statistics']['total']['today'] === 0,'both day counters roll at UTC midnight');
// Additive migration: reopening the same database preserves old counters.
$file=tempnam(sys_get_temp_dir(),'rs-activity-');
try {
    $migrated=directory_db($file);
    $migrated->exec('UPDATE totals SET sessions=123, peak_players=9 WHERE id=1');
    $migrated->exec('DROP TABLE activity_peak');
    $migrated=null;
    $migrated=directory_db($file);
    check((int)$migrated->query('SELECT sessions FROM totals')->fetchColumn() === 123,'migration preserves old totals');
    check((int)$migrated->query('SELECT players FROM activity_peak')->fetchColumn() === 9,'combined peak seeded from historical multiplayer');
    $migrated=null;
} finally { unlink($file); }
echo "$checks total directory/activity checks passed\n";
