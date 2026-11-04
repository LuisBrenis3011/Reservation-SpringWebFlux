[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Baseline','Disabled','Enabled')][string]$Stage,
 [guid]$LegacyId=[guid]::Empty,[switch]$AllowDatabaseReads,[switch]$NoOtherWriters,[switch]$ActivationPrerequisitesConfirmed)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
. (Join-Path $PSScriptRoot 'ManagedReservations.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationGate.Assertions.ps1')
if(!$AllowDatabaseReads -or !$NoOtherWriters -or !$ActivationPrerequisitesConfirmed){throw 'Requiere prerequisitos T129, -NoOtherWriters y -AllowDatabaseReads; no activa gates.'}
Initialize-ManagedMode $true $false $false
$database=$script:ManagedDatabase
$root='http://localhost:8082/catalog';$base=$root+'/restaurants/'+$script:RestaurantA
$path=Join-Path $script:IdentityPrivate 'reservation-integral-gate-checkpoint.json'
$sourceNames=@('reservation-availability-http-checkpoint.json','reservation-confirmation-http-checkpoint.json','reservation-queries-http-checkpoint.json','reservation-replacement-http-checkpoint.json','reservation-cancellation-http-checkpoint.json')
function Save-Gate {
 $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp';Write-PrivateText $temp ($script:gate|ConvertTo-Json -Depth 60)
 if(Test-Path $path){[IO.File]::Replace($temp,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
}
function Gate-Identity([string]$name){
 $token=[Environment]::GetEnvironmentVariable($name,'Process');if(!$token){throw ('Falta token '+$name)}
 $claim=ConvertFrom-JwtPayload $token
 if($claim.iss -cne $script:IdentityIssuer -or @($claim.aud) -notcontains 'eats-hub-catalog' -or !$claim.sub -or [long]$claim.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+30){throw 'Token invalido o por expirar.'}
 return [pscustomobject]@{issuer=$claim.iss;subject=$claim.sub}
}
function Gate-Manifest {
 $old=$OutputEncoding
 try{$OutputEncoding=[Text.UTF8Encoding]::new($false);$raw=Get-Content (Join-Path $PSScriptRoot 'mongo-backup-manifest.js') -Raw|& docker exec -i -e ('EATS_BACKUP_DATABASE='+$database) -e EATS_BACKUP_SOURCE=true eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin;Assert-DockerSuccess 'leer manifiesto';return (($raw -join "`n")|ConvertFrom-Json)}finally{$OutputEncoding=$old}
}
function Gate-Request([string]$uri,[string]$method,[string]$actor,[int]$expected){
 if(!$uri.StartsWith($root+'/',[StringComparison]::Ordinal)){throw 'Destino fuera del entorno local.'}
 $headers=@{};if($actor){$null=Gate-Identity $actor;$headers.Authorization='Bearer '+[Environment]::GetEnvironmentVariable($actor,'Process')}
 $response=Invoke-LocalHttp -Uri $uri -Method $method -Headers $headers
 if($response.Status -ne $expected){throw ('Esperado HTTP '+$expected+', recibido '+$response.Status+'; conserva evidencia.')}
 $body=$null;if($response.Content){$body=$response.Content|ConvertFrom-Json}
 $etag='';if($null -ne $response.Headers['ETag']){$etag=[string](@($response.Headers['ETag'])[0])}
 return [pscustomobject]@{status=$response.Status;body=$body;etag=$etag}
}
function Gate-Probe([string]$id){
 Assert-ReservationGatePolicy (Assert-LiveManagedMode)
 $encoded=ConvertTo-ManagedBase64 ([pscustomobject]@{database=$database;id=$id})
 $old=$OutputEncoding
 try{$OutputEncoding=[Text.UTF8Encoding]::new($false);$raw=Get-Content (Join-Path $PSScriptRoot 'read-reservation-gate-probe.js') -Raw|& docker exec -i -e ('EATS_GATE_PROBE_BASE64='+$encoded) eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin;Assert-DockerSuccess 'verificar UUID inocuo';$result=($raw -join "`n")|ConvertFrom-Json;if(!$result.absent -or !$result.retired){throw 'Objetivo o politica no verificables.'}}
 finally{$OutputEncoding=$old}
}
function Gate-Checkpoints {
 $paths=@($sourceNames|ForEach-Object {Join-Path $script:IdentityPrivate $_})
 foreach($p in $paths){if(!(Test-Path $p)){throw ('Falta checkpoint requerido: '+[IO.Path]::GetFileName($p))}}
 $items=@($paths|ForEach-Object {Get-Content $_ -Raw|ConvertFrom-Json})
 for($i=0;$i -lt 5;$i++){if($items[$i].spec -cne ('SPEC-00'+($i+4))){throw 'Checkpoint de otra spec.'}}
 foreach($i in @(0,2)){if($null -eq $items[$i].baseline -or @($items[$i].attempts|Where-Object {$_.operatorDeclaredRestart -eq $true -and $_.dataPreserved -eq $true}).Count -eq 0){throw 'Falta baseline/reinicio de consulta.'}}
 foreach($i in @(1,4)){if($items[$i].pendingName){throw 'Intencion pendiente en checkpoint de origen.'}}
 foreach($i in @(1,3,4)){if($null -eq $items[$i].final -or @($items[$i].restart|Where-Object {$_.operatorDeclaredRestart -eq $true}).Count -eq 0){throw 'Falta recorrido/reinicio de escritura.'}}
 return [pscustomobject]@{hashes=(Get-ManagedCheckpointHashes $paths);items=$items}
}
$lock=$null
try{
 [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
 $lock=[IO.File]::Open(($path+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $sources=Gate-Checkpoints
 if(Test-Path $path){
  $script:gate=Get-Content $path -Raw|ConvertFrom-Json
  Assert-ReservationGateStage $script:gate $Stage
  if($PSBoundParameters.ContainsKey('LegacyId') -and $LegacyId.ToString() -cne $script:gate.legacyId){throw 'Fixture distinta del checkpoint.'}
  Assert-ReservationGateHashes $script:gate.hashes $sources.hashes
 }else{
  if($Stage -cne 'Baseline' -or $LegacyId -eq [guid]::Empty){throw 'Baseline exige LegacyId identificable autorizado.'}
  $client=Gate-Identity 'EATS_HUB_TOKEN_CUSTOMER_A';$manager=Gate-Identity 'EATS_HUB_TOKEN_A'
  $accepted=@($sources.items[1].steps|Where-Object {$_.expected -eq 201 -and $null -ne $_.response -and $_.actor -ceq 'EATS_HUB_TOKEN_CUSTOMER_A'})
  if(!$accepted.Count){throw 'Falta confirmacion propia aceptada.'}
  Equal-Cancel $accepted[0].identity $client 'Titular de confirmacion'
  $availability=$sources.items[0]
  $script:gate=[pscustomobject]@{schemaVersion=1;spec='SPEC-005-GATE';runId=[guid]::NewGuid().ToString('N');legacyId=$LegacyId.ToString();managedId=$accepted[0].response.body.id;date=$availability.date;partySize=$availability.partySize;probeId=[guid]::NewGuid().ToString();client=$client;manager=$manager;hashes=$sources.hashes;baseline=$null;disabled=$null;enabled=$null}
 }
 Assert-ReservationGateStage $script:gate $Stage
 Equal-Cancel $script:gate.client (Gate-Identity 'EATS_HUB_TOKEN_CUSTOMER_A') 'Identidad cliente'
 Equal-Cancel $script:gate.manager (Gate-Identity 'EATS_HUB_TOKEN_A') 'Identidad encargado'
 $policy=Assert-LiveManagedMode;Assert-ReservationGatePolicy $policy
 $before=Gate-Manifest
 if($null -ne $script:gate.baseline){
  Equal-Cancel $script:gate.baseline.policy $policy 'Politica persistente'
  Equal-Cancel $script:gate.baseline.manifest $before 'Manifiesto al entrar'
 }
 $legacy=$root+'/reservation/'+$script:gate.legacyId
 $collection=$base+'/reservations';$managed=$collection+'/'+$script:gate.managedId
 $availability=$base+'/availability?date='+$script:gate.date+'&partySize='+$script:gate.partySize
 $null=Gate-Request ($root+'/restaurants') 'Get' '' 200
 $legacyRead=Gate-Request $legacy 'Get' 'EATS_HUB_TOKEN_A' 200
 $status=if($Stage -ceq 'Disabled'){404}else{401}
 foreach($target in @($collection,$managed,($root+'/me/reservations'))){$null=Gate-Request $target 'Get' '' $status}
 $null=Gate-Request $collection 'Post' '' $status
 $null=Gate-Request $managed 'Put' '' $status
 $null=Gate-Request ($managed+'/cancellation') 'Post' '' $status
 $availabilityResult=Gate-Request $availability 'Get' '' $(if($Stage -ceq 'Disabled'){404}else{200})
 $snapshot=$null;$availabilitySnapshot=$null
 if($Stage -cne 'Disabled'){
  $availabilitySnapshot=@($availabilityResult.body.items|Select-Object shiftId,localStart,localEnd,zoneId,startInstant,endInstant,availability)
  if($Stage -ceq 'Enabled'){Equal-Cancel $script:gate.baseline.availability $availabilitySnapshot 'Disponibilidad al reactivar'}
  $snapshot=Gate-Request $managed 'Get' 'EATS_HUB_TOKEN_CUSTOMER_A' 200
  if(!$snapshot.etag){throw 'Falta ETag de reserva.'}
  if($Stage -ceq 'Enabled'){Assert-ReservationGateSnapshot $script:gate.baseline.snapshot $snapshot}
 }
 # POST/PUT sin cuerpo; DELETE solo contra UUID verificado ausente. Cada solicitud revalida corte.
 foreach($request in @(@('Post',($root+'/reservation')),@('Put',($root+'/reservation/'+$script:gate.probeId)),@('Delete',($root+'/reservation/'+$script:gate.probeId)))){
  Gate-Probe $script:gate.probeId
  $reply=Gate-Request $request[1] $request[0] 'EATS_HUB_TOKEN_A' 410
  if($reply.body.code -cne 'LEGACY_WRITES_RETIRED'){throw '410 no corresponde al corte esperado.'}
 }
 Assert-ReservationGatePolicy (Assert-LiveManagedMode)
 $after=Gate-Manifest;Equal-Cancel $before $after 'Datos, indices, revisiones y recibos'
 Assert-ReservationGateHashes $script:gate.hashes (Gate-Checkpoints).hashes
 $entry=[pscustomobject]@{timestampUtc=[DateTime]::UtcNow.ToString('o');operatorDeclaredRestart=($Stage -ne 'Baseline');policy=$policy;manifest=$after;legacy=$legacyRead;snapshot=$snapshot;availability=$availabilitySnapshot}
 if($Stage -ceq 'Baseline'){$script:gate.baseline=$entry}
 else{
  Equal-Cancel $script:gate.baseline.legacy $legacyRead 'Lectura antigua'
  if($Stage -ceq 'Disabled'){$script:gate.disabled=$entry}else{$script:gate.enabled=$entry}
 }
 Save-Gate
 Write-Host ('OK: '+$Stage+' guardado; reinicios y gates declarados manualmente. Evidencia de entrega pendiente.')
}finally{if($null -ne $lock){$lock.Dispose()}}
