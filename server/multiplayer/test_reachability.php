<?php
declare(strict_types=1);
require __DIR__.'/reachability.php';
require __DIR__.'/test_directory.php';
$db = directory_db(':memory:');
$nonce = str_repeat('d',64);
$path = '/games/'.$id.'/check';
$body = ['nonce'=>$nonce];
call_directory('PUT','/games/'.$id,['version'=>2,'game'=>$game]);
check(reachability_prepare($db,$path,$body,'','8.8.8.8',$now)[0] === 401,'probe requires bearer');
check(reachability_prepare($db,$path,$body,'Bearer '.str_repeat('c',64),'8.8.8.8',$now)[0] === 403,'probe requires owner');
check(reachability_prepare($db,$path,$body,$auth,'1.1.1.1',$now)[0] === 403,'cannot probe another source');
check(reachability_prepare($db,$path,$body,$auth,'127.0.0.1',$now)[0] === 400,'no internal probe');
check(reachability_prepare($db,$path,$body,$auth,'::ffff:127.0.0.1',$now)[0] === 400,'no mapped internal probe');
check(reachability_prepare($db,$path,['nonce'=>'bad'],$auth,'8.8.8.8',$now)[0] === 400,'strict nonce');
check(reachability_prepare($db,$path,$body,$auth,'8.8.8.8',$now+181)[0] === 403,'expired room cannot probe');
$request = reachability_prepare($db,$path,$body+['ip'=>'1.1.1.1','port'=>22],$auth,'8.8.8.8',$now);
check($request[0]===200 && $request[1]['ip']==='8.8.8.8' && $request[1]['port']===20000,'target comes only from registered room');
check(!$db->inTransaction(),'network I/O outside DB lock');
check(reachability_prepare($db,$path,$body,$auth,'8.8.8.8',$now)[0]===200,'second bounded check');
check(reachability_prepare($db,$path,$body,$auth,'8.8.8.8',$now)[0]===429,'probe rate limit');
if (isset($argv[1])) {
    check(reachability_probe('127.0.0.1',(int)$argv[1],$nonce)==='reachable','real fragmented TCP challenge');
    check(reachability_probe('127.0.0.1',(int)$argv[2],$nonce)==='unreachable','other protocol is not our game');
    check(reachability_probe('127.0.0.1',(int)$argv[3],$nonce)==='unreachable','closed port');
}
echo "$checks total directory/reachability checks passed\n";
