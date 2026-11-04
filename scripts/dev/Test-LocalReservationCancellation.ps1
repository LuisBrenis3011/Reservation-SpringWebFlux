[CmdletBinding()]
param([guid]$ReservationId=[guid]::Empty,[guid]$NearStartReservationId=[guid]::Empty,[guid]$Q4ReservationId=[guid]::Empty,
 [switch]$Q4Only,[switch]$AfterRestart,[switch]$AllowFixtureWrites,[switch]$AllowDatabaseReads,[switch]$DedicatedReservations,[switch]$ActivationPrerequisitesConfirmed)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationCancellation.Assertions.ps1')
if(!$ActivationPrerequisitesConfirmed -or !$AllowDatabaseReads){throw 'Requiere -ActivationPrerequisitesConfirmed y -AllowDatabaseReads; verificar T129, version puente, respaldo y corte antes de ejecutar.'}
if(!$AfterRestart -and (!$AllowFixtureWrites -or !$DedicatedReservations)){throw 'Requiere permiso explicito de escrituras HTTP y reservas dedicadas.'}
$root='http://localhost:8082/catalog';$base=$root+'/restaurants/'+$script:RestaurantA
$checkpointName='reservation-cancellation-http-checkpoint.json';if($Q4Only){$checkpointName='reservation-cancellation-q4-http-checkpoint.json'}; $path=Join-Path $script:IdentityPrivate $checkpointName
$envValues=Read-LocalEnv (Join-Path $script:IdentityRoot '.env');$database=$envValues['MONGODB_DATABASE']
if($envValues['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $envValues['MONGODB_PORT'] -ne '27018' -or $database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')){throw 'Solo base de aplicacion en Mongo local 27018.'}
function Save-Cancel {
 $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp';Write-PrivateText $temp ($script:cp|ConvertTo-Json -Depth 60)
 if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
}
function Cancel-Now {return [DateTimeOffset]::UtcNow}
function Cancel-Identity([string]$actor){
 $token=[Environment]::GetEnvironmentVariable($actor,'Process');if(!$token){throw ('Falta '+$actor)}
 $claims=ConvertFrom-JwtPayload $token
 if($claims.iss -cne $script:IdentityIssuer -or @($claims.aud) -notcontains 'eats-hub-catalog' -or !$claims.sub -or [long]$claims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+30){throw ('Renueva '+$actor)}
 return [pscustomobject]@{issuer=$claims.iss;subject=$claims.sub}
}
function Cancel-ReadMongo([string]$file,$expectations=$null){
 $argsList=@('exec','-i','-e',('EATS_BACKUP_DATABASE='+$database),'-e','EATS_BACKUP_SOURCE=true')
 if($null -ne $expectations){$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($expectations|ConvertTo-Json -Depth 20 -Compress)));$argsList+=@('-e',('EATS_CANCELLATION_EXPECTATIONS_BASE64='+$encoded))}
 $argsList+=@('eats-availability-mongodb-replica-1','mongosh','--quiet','--port','27018','--file','/dev/stdin')
 $old=$OutputEncoding
 try{$OutputEncoding=[Text.UTF8Encoding]::new($false);$raw=Get-Content (Join-Path $PSScriptRoot $file) -Raw|& docker @argsList;Assert-DockerSuccess 'leer evidencia de cancelacion';return (($raw -join "`n")|ConvertFrom-Json)}finally{$OutputEncoding=$old}
}
function Cancel-Manifest {return Cancel-ReadMongo 'mongo-backup-manifest.js'}
function Cancel-Delta($entry){return Cancel-ReadMongo 'mongo-cancellation-manifest.js' ([pscustomobject]@{restaurantId=$script:RestaurantA;reservationId=$entry.id;issuer=$entry.identity.issuer;subject=$entry.identity.subject;key=$entry.key;match=$entry.match})}
function Cancel-Request([string]$uri,[string]$method,[string]$actor,[string]$match,[string]$key,$body,[int]$expected){
 if(!$uri.StartsWith($root+'/',[StringComparison]::Ordinal)){throw 'Destino no local.'}
 $headers=@{};if($actor){$null=Cancel-Identity $actor;$headers.Authorization='Bearer '+[Environment]::GetEnvironmentVariable($actor,'Process')}
 if($match){$headers['If-Match']=$match};if($key){$headers['Idempotency-Key']=$key}
 $requestArgs=@{Uri=$uri;Method=$method;Headers=$headers};if($null -ne $body){$requestArgs.Body=[string]$body}
 $response=Invoke-LocalHttp @requestArgs
 if($response.Status -ne $expected){throw ('Esperado '+$expected+', recibido '+$response.Status+'. Conserva la misma clave/checkpoint.')}
 $etag='';$location='';if($null -ne $response.Headers['ETag']){$etag=[string](@($response.Headers['ETag'])[0])};if($null -ne $response.Headers['Location']){$location=[string](@($response.Headers['Location'])[0])}
 return [pscustomobject]@{status=$response.Status;body=($response.Content|ConvertFrom-Json);etag=$etag;location=$location}
}
function Cancel-Get([string]$id){return Cancel-Request ($base+'/reservations/'+$id) 'Get' 'EATS_HUB_TOKEN_CUSTOMER_A' '' '' $null 200}
function Set-CancelExpected([string]$id,$response){
 $script:cp.expected=@($script:cp.expected|Where-Object {$_.id -cne $id})+@([pscustomobject]@{id=$id;response=$response})
}
function Check-CancelContinuity([string]$pending=''){
 Assert-CancellationContinuity $script:cp (Cancel-Manifest) $pending
}
function Cancel-Step([string]$name,[string]$id,[string]$actor,[string]$match,[int]$expected,[string]$effect,$body=$null){
 $found=@($script:cp.steps|Where-Object {$_.name -ceq $name})
 if(!$found.Count){
  Check-CancelContinuity
  $identity=$null;if($actor){$identity=Cancel-Identity $actor}
  $entry=[pscustomobject]@{name=$name;id=$id;actor=$actor;identity=$identity;match=$match;key=($script:cp.runId+'-'+$name);expected=$expected;effect=$effect;body=$body;before=$null;response=$null;original=$null;afterManifest=$null}
  $script:cp.steps=@($script:cp.steps)+@($entry);Save-Cancel
 }else{$entry=$found[0]}
 if($entry.actor){Equal-Cancel $entry.identity (Cancel-Identity $entry.actor) 'Identidad del ensayo'}
 if($null -ne $entry.response){Check-CancelContinuity;Write-Host ('Checkpoint: '+$name);return $entry.response}
 if($null -eq $entry.before){
  Check-CancelContinuity
  if($effect -eq 'none'){$entry.before=Cancel-Manifest}else{$entry.original=Cancel-Get $entry.id;$entry.before=Cancel-Delta $entry}
  $script:cp.pendingName=$name;Save-Cancel
 }
 if($script:cp.pendingName -cne $name){throw 'La etapa no es la intencion pendiente.'}
 if($effect -eq 'none'){Equal-Cancel $entry.before (Cancel-Manifest) 'Antes de rechazo'}else{
  $current=Cancel-Delta $entry
  if($current.receiptCount -eq 0){Equal-Cancel $script:cp.lastManifest (Cancel-Manifest) 'Antes de nueva escritura'}
  elseif($current.receiptCount -eq 1){
   $recovered=[pscustomobject]@{status=200;body=$current.receiptView;etag=('"'+$current.receiptVersion+'"');location=''}
   Assert-CancellationDelta $entry.before $current $recovered $entry.effect
  }else{throw 'Recibo pendiente no verificable.'}
  Assert-CancellationWindow $entry $current (Cancel-Now)
 }
 $result=Cancel-Request ($base+'/reservations/'+$entry.id+'/cancellation') 'Post' $entry.actor $entry.match $entry.key $entry.body $entry.expected
 if($effect -eq 'none'){Equal-Cancel $entry.before (Cancel-Manifest) $name}else{
  Assert-CancellationDelta $entry.before (Cancel-Delta $entry) $result $entry.effect
  Set-CancelExpected $entry.id $result
 }
 $entry.response=$result;$entry.afterManifest=Cancel-Manifest
 $script:cp.lastManifest=$entry.afterManifest;$script:cp.pendingName=$null;Save-Cancel
 Write-Host ('OK: '+$name+' -> HTTP '+$expected);return $result
}
function Cancel-NewDelta($intent){
 return Cancel-ReadMongo 'mongo-cancellation-confirmation-manifest.js' ([pscustomobject]@{restaurantId=$script:RestaurantA;reservationId=$script:cp.id;issuer=$intent.identity.issuer;subject=$intent.identity.subject;key=$intent.key;match='';body=($intent.body|ConvertFrom-Json)})
}
function Cancel-NewConfirmation {
 if($null -eq $script:cp.newIntent){
  Check-CancelContinuity;$original=$script:cp.initial.body
  $script:cp.newIntent=[pscustomobject]@{key=($script:cp.runId+'-new');identity=(Cancel-Identity 'EATS_HUB_TOKEN_CUSTOMER_A');body=([ordered]@{shiftId=$original.shiftId;partySize=$original.partySize;notes=('SPEC-008 '+$script:cp.runId)}|ConvertTo-Json -Compress);before=$null;afterManifest=$null}
  Save-Cancel
 }
 $intent=$script:cp.newIntent
 Equal-Cancel $intent.identity (Cancel-Identity 'EATS_HUB_TOKEN_CUSTOMER_A') 'Titular nueva reserva'
 if($null -ne $script:cp.newResponse){Check-CancelContinuity;return}
 if($null -eq $intent.before){Check-CancelContinuity;$intent.before=Cancel-NewDelta $intent;$script:cp.pendingName='new-confirmation';Save-Cancel}
 if($script:cp.pendingName -cne 'new-confirmation'){throw 'Otra intencion pendiente.'}
 $current=Cancel-NewDelta $intent
 if($current.receiptCount -eq 0){
  Equal-Cancel $script:cp.lastManifest (Cancel-Manifest) 'Antes de confirmar'
  $now=Cancel-Now;$start=[DateTimeOffset]::Parse($script:cp.initial.body.startInstant)
  if($start -lt $now.AddHours(2) -or $start -gt $now.AddDays(90)){throw 'Plazo de nueva confirmacion vencido; conserva intencion y checkpoint.'}
 }
 elseif($current.receiptCount -eq 1){
  $recovered=[pscustomobject]@{status=201;body=$current.receiptView;etag='"1"';location=$current.receiptLocation}
  Assert-CancellationConfirmation $intent.before $current $recovered $intent $script:RestaurantA
 }else{throw 'Recibo de confirmacion no verificable.'}
 $result=Cancel-Request ($base+'/reservations') 'Post' 'EATS_HUB_TOKEN_CUSTOMER_A' '' $intent.key $intent.body 201
 Assert-CancellationConfirmation $intent.before (Cancel-NewDelta $intent) $result $intent $script:RestaurantA
 if($result.body.id -ceq $script:cp.id){throw 'No se creo otra reserva.'}
 Set-CancelExpected $result.body.id $result
 $script:cp.newResponse=$result;$intent.afterManifest=Cancel-Manifest
 $script:cp.lastManifest=$intent.afterManifest;$script:cp.pendingName=$null;Save-Cancel
}
function Recover-CancelPending {
 if(!$script:cp.pendingName){Check-CancelContinuity;return}
 if($script:cp.pendingName -ceq 'new-confirmation'){Cancel-NewConfirmation;return}
 $entries=@($script:cp.steps|Where-Object {$_.name -ceq $script:cp.pendingName})
 if($entries.Count -ne 1){throw 'Etapa pendiente desconocida.'}
 $e=$entries[0];$null=Cancel-Step $e.name $e.id $e.actor $e.match $e.expected $e.effect $e.body
}
function Check-CancelExpected {
 Check-CancelContinuity
 foreach($snapshot in @($script:cp.expected)){Assert-CancellationStored $snapshot.response (Cancel-Get $snapshot.id)}
 Check-CancelContinuity
}

function Cancel-Replay([string]$name){
 Check-CancelContinuity
 $entry=@($script:cp.steps|Where-Object {$_.name -ceq $name})[0];Equal-Cancel $entry.identity (Cancel-Identity $entry.actor) 'Identidad replay'
 $before=Cancel-Manifest;$result=Cancel-Request ($base+'/reservations/'+$entry.id+'/cancellation') 'Post' $entry.actor $entry.match $entry.key $entry.body 200
 Equal-Cancel $entry.response $result 'Replay completo';Equal-Cancel $before (Cancel-Manifest) 'Replay sin escrituras'
}
$lock=$null
try{
 [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null;$lock=[IO.File]::Open(($path+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 if(Test-Path -LiteralPath $path){$script:cp=Get-Content $path -Raw|ConvertFrom-Json;Assert-CancellationCheckpoint $script:cp
  if([bool]$script:cp.q4Only -ne [bool]$Q4Only){throw 'Modo distinto del checkpoint.'}
  foreach($pair in @(@('ReservationId','id'),@('NearStartReservationId','nearId'),@('Q4ReservationId','q4Id'))){if($PSBoundParameters.ContainsKey($pair[0]) -and (Get-Variable $pair[0] -ValueOnly).ToString() -cne $script:cp.($pair[1])){throw 'IDs distintos del checkpoint.'}}
 }else{
  if($AfterRestart -or $ReservationId -eq [guid]::Empty){throw 'Indica ReservationId dedicada, confirmada y propia.'}
  if($Q4Only -and $Q4ReservationId -ne $ReservationId){throw 'Q4Only usa ReservationId=Q4ReservationId, ambos dedicados.'}
  if(!$Q4Only -and $Q4ReservationId -ne [guid]::Empty){throw 'Q4 requiere -Q4Only en ensayo independiente; el bloqueo global impide nueva confirmacion normal.'}
  $ids=@($ReservationId,$NearStartReservationId);if(!$Q4Only){$ids+=@($Q4ReservationId)}; $ids=$ids|Where-Object {$_ -ne [guid]::Empty};if(@($ids|Select-Object -Unique).Count -ne @($ids).Count){throw 'Reservas dedicadas distintas.'}
  foreach($file in Get-ChildItem $script:IdentityPrivate -Filter '*checkpoint.json'){$other=Get-Content $file.FullName -Raw;if(@($ids|Where-Object {$other.Contains($_.ToString())}).Count){throw 'Reserva presente en otro checkpoint; no reutilizar.'}}
  $initial=Cancel-Get $ReservationId; $identity=Cancel-Identity 'EATS_HUB_TOKEN_CUSTOMER_A'
  if($initial.body.status -cne 'CONFIRMED' -or $initial.body.restaurantId -cne $script:RestaurantA -or $initial.body.owner.subject -cne $identity.subject -or $initial.body.owner.issuer -cne $identity.issuer -or [DateTimeOffset]::Parse($initial.body.startInstant) -lt [DateTimeOffset]::UtcNow.AddHours(2).AddMinutes(5)){throw 'Reserva propia confirmada sin margen 2h+5min.'}
  $script:cp=[pscustomobject]@{schemaVersion=2;spec='SPEC-008';pendingName=$null;lastManifest=(Cancel-Manifest);expected=@([pscustomobject]@{id=$ReservationId.ToString();response=$initial});q4Only=[bool]$Q4Only;runId=[guid]::NewGuid().ToString('N');id=$ReservationId.ToString();nearId=$NearStartReservationId.ToString();q4Id=$Q4ReservationId.ToString();initial=$initial;steps=@();newIntent=$null;newResponse=$null;final=$null;manifest=$null;restart=@();temporal=$false;q4=$false};Save-Cancel
 }
 Assert-CancellationCheckpoint $script:cp
 if($AfterRestart -and $script:cp.pendingName){throw 'Hay una intencion pendiente; recuperar con el comando inicial antes de comprobar reinicio.'}
 Recover-CancelPending
 if($AfterRestart){if($null -eq $script:cp.final){throw 'Recorrido incompleto.'};Check-CancelExpected;Equal-Cancel $script:cp.manifest (Cancel-Manifest) 'Mongo tras reinicio declarado';foreach($snapshot in @($script:cp.final)){Equal-Cancel $snapshot.response (Cancel-Get $snapshot.id) 'GET tras reinicio'};Equal-Cancel $script:cp.manifest (Cancel-Manifest) 'GET sin escrituras';$script:cp.restart+=@([pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');operatorDeclaredRestart=$true});Save-Cancel;Write-Host 'OK: reinicio declarado, historia/nueva reserva/ETag y Mongo conservados. T191 pendiente.';return}
 if($null -ne $script:cp.final){throw 'Recorrido completo. Reinicia manualmente y usa -AfterRestart.'}
 Write-Host 'Evita otras escrituras. Solo reservas dedicadas; no se borran fixtures ni se cambia el gate.'
 if(!$Q4Only){
 $id=$script:cp.id;$tag=$script:cp.initial.etag
 $null=Cancel-Step 'sin-token' $id '' $tag 401 'none'
 $null=Cancel-Step 'encargado-ajeno' $id 'EATS_HUB_TOKEN_B' $tag 403 'none'
 $null=Cancel-Step 'otro-cliente' $id 'EATS_HUB_TOKEN_CUSTOMER_B' $tag 404 'none'
 $null=Cancel-Step 'sin-perfil' $id 'EATS_HUB_TOKEN_NO_ROLE' $tag 403 'none'
 Check-CancelContinuity
 $beforeMissingKey=Cancel-Manifest;$null=Cancel-Request ($base+'/reservations/'+$id+'/cancellation') 'Post' 'EATS_HUB_TOKEN_CUSTOMER_A' $tag '' $null 400
 Equal-Cancel $beforeMissingKey (Cancel-Manifest) 'Sin Idempotency-Key'
 $null=Cancel-Step 'sin-If-Match' $id 'EATS_HUB_TOKEN_CUSTOMER_A' '' 400 'none'
 $null=Cancel-Step 'If-Match-debil' $id 'EATS_HUB_TOKEN_CUSTOMER_A' 'W/"1"' 400 'none'
 $null=Cancel-Step 'obsoleto-confirmada' $id 'EATS_HUB_TOKEN_CUSTOMER_A' '"0"' 412 'none'
 $null=Cancel-Step 'con-cuerpo' $id 'EATS_HUB_TOKEN_CUSTOMER_A' $tag 400 'none' '{}'
 $cancelled=Cancel-Step 'primera' $id 'EATS_HUB_TOKEN_CUSTOMER_A' $tag 200 'transition';Cancel-Replay 'primera'
 Check-CancelContinuity
 $entry=@($script:cp.steps|Where-Object {$_.name -ceq 'primera'})[0];$beforeConflict=Cancel-Manifest
 $conflict=Cancel-Request ($base+'/reservations/'+$id+'/cancellation') 'Post' $entry.actor '"0"' $entry.key $null 409
 if($conflict.body.code -cne 'IDEMPOTENCY_CONFLICT'){throw 'Conflicto no atribuible a la clave.'};Equal-Cancel $beforeConflict (Cancel-Manifest) 'Conflicto de clave'
 $null=Cancel-Step 'repetida-obsoleta' $id 'EATS_HUB_TOKEN_CUSTOMER_A' '"0"' 200 'noop';Cancel-Replay 'repetida-obsoleta'
 Cancel-NewConfirmation
 Cancel-Replay 'primera'
 $null=Cancel-Step 'repetida-tras-nueva' $id 'EATS_HUB_TOKEN_CUSTOMER_A' '"0"' 200 'noop'
 }
 if($Q4Only -and $script:cp.q4Id -eq ([guid]::Empty).ToString()){throw 'Q4Only exige Q4ReservationId.'}
 foreach($case in @(@('nearId','temporal'),@('q4Id','q4'))){
  $extraId=$script:cp.($case[0]);if($extraId -eq ([guid]::Empty).ToString()){Write-Host ('PENDIENTE fixture '+$case[1]);continue}
  # Congelar antes de la primera escritura; al reanudar no exigir CONFIRMED otra vez.
  $snapshotName=$case[1]+'Snapshot';if($null -eq $script:cp.PSObject.Properties[$snapshotName]){
   $snap=Cancel-Get $extraId;if($snap.body.status -cne 'CONFIRMED'){throw 'Fixture adicional no confirmada.'}
   if($case[1] -eq 'temporal'){ $start=[DateTimeOffset]::Parse($snap.body.startInstant);if($start -le [DateTimeOffset]::UtcNow.AddMinutes(5) -or $start -ge [DateTimeOffset]::UtcNow.AddHours(2)){throw 'NearStart requiere inicio entre 5min y 2h.'}}
   else{$date=([string]$snap.body.localStart).Substring(0,10);$view=Cancel-Request ($base+'/availability?date='+$date+'&partySize='+$snap.body.partySize) 'Get' '' '' '' $null 200;$item=@($view.body.items|Where-Object {$_.shiftId -ceq $snap.body.shiftId});if($item.Count -ne 1 -or $item[0].availability -cne 'UNDETERMINED'){throw 'Q4 requiere ocupacion no verificable preexistente; no se crea legado ni fallo global.'}}
   $script:cp|Add-Member -NotePropertyName $snapshotName -NotePropertyValue $snap;Save-Cancel
  };$snap=$script:cp.($snapshotName)
  if($case[1] -eq 'temporal'){$rejected=Cancel-Step 'cliente-fuera-plazo' $extraId 'EATS_HUB_TOKEN_CUSTOMER_A' $snap.etag 409 'none';if($rejected.body.code -cne 'RESERVATION_WINDOW_CLOSED'){throw 'Conflicto no temporal.'};$null=Cancel-Step 'encargado-cerca-inicio' $extraId 'EATS_HUB_TOKEN_A' $snap.etag 200 'transition'}else{$null=Cancel-Step 'Q4-propia' $extraId 'EATS_HUB_TOKEN_CUSTOMER_A' $snap.etag 200 'transition'}
  if($case[1] -eq 'q4'){
   $date=([string]$snap.body.localStart).Substring(0,10);$beforeRead=Cancel-Manifest
   $view=Cancel-Request ($base+'/availability?date='+$date+'&partySize='+$snap.body.partySize) 'Get' '' '' '' $null 200
   $item=@($view.body.items|Where-Object {$_.shiftId -ceq $snap.body.shiftId})
   if($item.Count -ne 1 -or $item[0].availability -cne 'UNDETERMINED'){throw 'Q4 no debe levantar el bloqueo global.'}
   Equal-Cancel $beforeRead (Cancel-Manifest) 'Q4 consulta sin escrituras'
  }
  $script:cp.($case[1])=$true;Save-Cancel
 }
 Check-CancelExpected
 $targets=@($script:cp.id,$script:cp.nearId,$script:cp.q4Id);if($null -ne $script:cp.newResponse){$targets+=@($script:cp.newResponse.body.id)}; $script:cp.final=@();foreach($target in $targets|Select-Object -Unique){if($target -ne ([guid]::Empty).ToString()){$script:cp.final+=@([pscustomobject]@{id=$target;response=(Cancel-Get $target)})}}
 $script:cp.manifest=Cancel-Manifest;Save-Cancel
 Write-Host 'OK: recorrido inicial guardado sin JWT. Reinicia manualmente IntelliJ 8082 y usa -AfterRestart. Fixtures temporales/Q4 ausentes no quedan aprobadas; gates/restore/reversion/cierre pendientes.'
}finally{if($null -ne $lock){$lock.Dispose()}}