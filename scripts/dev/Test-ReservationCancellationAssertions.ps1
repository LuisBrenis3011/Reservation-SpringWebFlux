# Suite pura manual. No HTTP, Docker, Mongo, JWT, reloj modificado ni checkpoints de disco.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReservationCancellation.Assertions.ps1')
function Copy-Test($x){return ($x|ConvertTo-Json -Depth 60|ConvertFrom-Json)}
function Reject-Test([scriptblock]$action,[string]$expectedMessage=''){
 $failed=$false
 try{& $action}catch{
  if($expectedMessage -and $_.Exception.Message -cne $expectedMessage){throw ('Rechazo inesperado: '+$_.Exception.Message)}
  $failed=$true
 }
 if(!$failed){throw 'Se esperaba rechazo sintetico.'}
}
function Require-Test([bool]$ok){if(!$ok){throw 'Asercion sintetica incumplida.'}}
Equal-Cancel ([pscustomobject]@{a=1;b=2}) ([pscustomobject]@{b=2;a=1}) 'Propiedades reordenadas'
Equal-Cancel ([pscustomobject]@{startInstant='2030-01-01T10:00:00Z';cancelledAt=$null}) ([pscustomobject]@{cancelledAt=$null;startInstant='2030-01-01T05:00:00.000-05:00'}) 'Instantes equivalentes'
Reject-Test {Equal-Cancel @{createdAt='2030-01-01T10:00:00.000000001Z'} @{createdAt='2030-01-01T10:00:00.000000002Z'} 'Nanosegundos distintos'}
Reject-Test {Equal-Cancel @{cancelledAt=$null} @{cancelledAt='2030-01-01T10:00:00Z'} 'Null distinto'}
Reject-Test {Equal-Cancel @{version=1} @{version=2} 'Version distinta'}
Reject-Test {Equal-Cancel @{version=1} @{version=1;extra=0} 'Campo extra'}
Reject-Test {Equal-Cancel @('a','b') @('b','a') 'Orden de array significativo'}
$owner='11111111-1111-4111-8111-111111111111';$id='33333333-3333-4333-8333-333333333333';$newId='44444444-4444-4444-8444-444444444444'
$script:CancellationTestIdentity=[pscustomobject]@{issuer='https://issuer.test';subject='client'}
$row=[pscustomobject]@{kind='MANAGED';id=$id;restaurantId=$owner;owner=$script:CancellationTestIdentity;shiftId='55555555-5555-4555-8555-555555555555';partySize=2;notes='Prueba';status='CANCELLED';version=2;tableIds=@('66666666-6666-4666-8666-666666666666');combinationId=$null;assignedCapacity=4;localStart='2035-01-01T13:00:00';localEnd='2035-01-01T14:00:00';zoneId='UTC';startInstant='2035-01-01T13:00:00Z';endInstant='2035-01-01T14:00:00Z';createdAt='2030-01-01T09:00:00Z';updatedAt='2030-01-01T10:00:00Z';cancelledAt='2030-01-01T10:00:00Z'}
$accepted=[pscustomobject]@{status=200;etag='"2"';location='';body=$row}
$before=[pscustomobject]@{protectedCollections=@(@{name='other';hash='stable'});reservationInvariantSha256='history';reservationSha256='confirmed';operationInvariantSha256='meta';version=1;revision=7;receiptCount=0;reservationView=$null}
$after=Copy-Test $before;$after.version=2;$after.revision=8;$after.receiptCount=1;$after.reservationSha256='cancelled'
foreach($pair in @(@('receiptFingerprintMatches',$true),@('receiptStatus',200),@('receiptLocation',$null),@('receiptVersion',2),@('receiptRevision',8),@('receiptView',$row))){$after|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}
$after.reservationView=$row
Assert-CancellationDelta $before $after $accepted 'transition'
foreach($field in @('revision','version','receiptCount','receiptVersion','receiptRevision')){$bad=Copy-Test $after;$bad.$field=99;Reject-Test {Assert-CancellationDelta $before $bad $accepted 'transition'}}
$bad=Copy-Test $after;$bad.protectedCollections[0].hash='external';Reject-Test {Assert-CancellationDelta $before $bad $accepted 'transition'}
$noopBefore=Copy-Test $before;$noopBefore.version=2;$noopBefore.revision=8;$noopBefore.reservationView=$row;$noopBefore.reservationSha256='cancelled'
Assert-CancellationDelta $noopBefore $after $accepted 'noop'
$bad=Copy-Test $after;$bad.reservationSha256='rewritten';Reject-Test {Assert-CancellationDelta $noopBefore $bad $accepted 'noop'}
$entry=[pscustomobject]@{effect='transition';actor='EATS_HUB_TOKEN_CUSTOMER_A';original=$accepted}
$now=[DateTimeOffset]::Parse($row.startInstant).AddHours(-2)
Assert-CancellationWindow $entry $before $now
Reject-Test {Assert-CancellationWindow $entry $before $now.AddTicks(1)}
Assert-CancellationWindow $entry $after $now.AddDays(1) # recibo aceptado se recupera fuera de plazo
$entry.actor='EATS_HUB_TOKEN_A';Reject-Test {Assert-CancellationWindow $entry $before $now.AddHours(2)}
$cp=[pscustomobject]@{lastManifest=@{phase=0};pendingName=$null}
Assert-CancellationContinuity $cp @{phase=0}
Reject-Test {Assert-CancellationContinuity $cp @{phase=1}}
$cp.pendingName='first';Assert-CancellationContinuity $cp @{phase=1} 'first'
Reject-Test {Assert-CancellationContinuity $cp @{phase=1} 'other'}
$intent=[pscustomobject]@{identity=$script:CancellationTestIdentity;body=([ordered]@{shiftId=$row.shiftId;partySize=2;notes='Nueva'}|ConvertTo-Json -Compress)}
$new=Copy-Test $accepted;$new.status=201;$new.etag='"1"';$new.location='/catalog/restaurants/'+$owner+'/reservations/'+$newId
$new.body.updatedAt=$new.body.createdAt;$new.body.id=$newId;$new.body.status='CONFIRMED';$new.body.version=1;$new.body.notes='Nueva';$new.body.cancelledAt=$null
$newBefore=[pscustomobject]@{protectedCollections=@(@{name='cancelled-and-other';hash='stable'});operationInvariantSha256='meta';revision=8;receiptCount=0;reservationView=$null}
$newAfter=Copy-Test $newBefore;$newAfter.revision=9;$newAfter.receiptCount=1;$newAfter.reservationView=$new.body
foreach($pair in @(@('receiptFingerprintMatches',$true),@('receiptStatus',201),@('receiptRevision',9),@('receiptVersion',1),@('receiptLocation',$new.location),@('receiptView',$new.body),@('assignmentValid',$true),@('snapshotValid',$true),@('noOverlap',$true))){$newAfter|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}
Assert-CancellationConfirmation $newBefore $newAfter $new $intent $owner
foreach($field in @('shiftId','notes','restaurantId','partySize','status','version')){$bad=Copy-Test $new;if($field -in @('partySize','version')){$bad.body.$field=99}else{$bad.body.$field='alterado'};Reject-Test {Assert-CancellationConfirmation $newBefore $newAfter $bad $intent $owner}}
foreach($field in @('assignmentValid','snapshotValid','noOverlap')){$bad=Copy-Test $newAfter;$bad.$field=$false;Reject-Test {Assert-CancellationConfirmation $newBefore $bad $new $intent $owner}}
$bad=Copy-Test $newAfter;$bad.protectedCollections[0].hash='cancelled-changed';Reject-Test {Assert-CancellationConfirmation $newBefore $bad $new $intent $owner}
$get=Copy-Test $new;$get.status=200;$get.location='';Assert-CancellationStored $new $get
$bad=Copy-Test $get;$bad.body.owner.subject='other';Reject-Test {Assert-CancellationStored $new $bad}
# Cargar SOLO funciones por AST; no ejecutar el recorrido ni sus instrucciones superiores.
$t=$null;$e=$null;$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-LocalReservationCancellation.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Script con sintaxis incorrecta.'}
$names=@('Cancel-Step','Set-CancelExpected','Recover-CancelPending','Cancel-NewConfirmation')
foreach($node in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)){if($node.Name -in $names){Invoke-Expression $node.Extent.Text}}
$script:wrongIdentity=$false
function Cancel-Now {return [DateTimeOffset]::Parse('2035-01-01T10:00:00Z')}
function Cancel-Identity([string]$actor){if($script:wrongIdentity){return @{issuer=$script:CancellationTestIdentity.issuer;subject='other'}};return $script:CancellationTestIdentity}
function Cancel-Manifest {return [pscustomobject]@{phase=[int]$script:serverAccepted}}
function Check-CancelContinuity {Assert-CancellationContinuity $script:cp (Cancel-Manifest)}
function Cancel-Get([string]$target){return $script:CancellationTestAccepted}
function Cancel-Delta($entry){if($script:serverAccepted){return $script:CancellationTestAfter};return $script:CancellationTestBefore}
function Cancel-NewDelta($intent){if($script:serverAccepted){return $script:CancellationTestNewAfter};return $script:CancellationTestNewBefore}
function Save-Cancel {
 if($script:crash -eq 'save' -and ($null -ne $script:cp.newResponse -or @($script:cp.steps|Where-Object {$null -ne $_.response}).Count)){$script:crash='';throw 'Interrupcion antes de persistir respuesta'}
 $script:persisted=$script:cp|ConvertTo-Json -Depth 60
 if($script:crash -eq 'before' -and $script:cp.pendingName){$script:crash='';throw 'Interrupcion antes de HTTP'}
}
function Cancel-Request([string]$uri,[string]$method,[string]$actor,[string]$match,[string]$key,$body,[int]$expected){
 if($script:firstKey){Require-Test ($script:firstKey -ceq $key)}else{$script:firstKey=$key}
 if(!$script:serverAccepted){$script:serverAccepted=$true;$script:writes++}
 if($script:crash -eq 'response'){$script:crash='';throw 'Respuesta perdida'}
 if($expected -eq 201){return $script:CancellationTestNew};return $script:CancellationTestAccepted
}
$new.body.notes='SPEC-008 '+('a'*32);$newAfter.reservationView.notes=$new.body.notes;$newAfter.receiptView.notes=$new.body.notes
# Fixtures explicitas: los dobles no heredan variables locales del llamador.
$script:CancellationTestAccepted=$accepted
$script:CancellationTestBefore=$before
$script:CancellationTestAfter=$after
$script:CancellationTestNew=$new
$script:CancellationTestNewBefore=$newBefore
$script:CancellationTestNewAfter=$newAfter
$base='http://localhost:8082/catalog/restaurants/'+$owner;$script:RestaurantA=$owner
foreach($mode in @('cancel','confirm')){
 foreach($crashPoint in @('before','response','save')){
  $script:serverAccepted=$false;$script:writes=0;$script:firstKey='';$script:crash=$crashPoint
  $script:cp=[pscustomobject]@{schemaVersion=2;spec='SPEC-008';q4Only=$false;runId=('a'*32);id=$id;nearId=([guid]::Empty).ToString();q4Id=([guid]::Empty).ToString();initial=$accepted;steps=@();newIntent=$null;newResponse=$null;final=$null;manifest=$null;restart=@();pendingName=$null;lastManifest=[pscustomobject]@{phase=0};expected=@();temporal=$false;q4=$false}
  Assert-CancellationCheckpoint $script:cp
  $interruptionMessage=switch($crashPoint){'before'{'Interrupcion antes de HTTP'}'response'{'Respuesta perdida'}'save'{'Interrupcion antes de persistir respuesta'}}
  if($mode -eq 'cancel'){Reject-Test {$null=Cancel-Step 'first' $id 'EATS_HUB_TOKEN_CUSTOMER_A' '"1"' 200 'transition'} $interruptionMessage}
  else{Reject-Test {Cancel-NewConfirmation} $interruptionMessage}
  $script:cp=$script:persisted|ConvertFrom-Json
  Assert-CancellationCheckpoint $script:cp
  $identityMessage='Identidad del ensayo: diferencia no permitida.'
  if($mode -eq 'confirm'){$identityMessage='Titular nueva reserva: diferencia no permitida.'}
  $script:wrongIdentity=$true
  try{Reject-Test {Recover-CancelPending} $identityMessage}finally{$script:wrongIdentity=$false}
  Recover-CancelPending
  Require-Test ($script:writes -eq 1 -and $null -eq $script:cp.pendingName)
  Assert-CancellationCheckpoint $script:cp
  # La misma identidad renovada pasa; volver a ejecutar etapa no escribe.
  if($mode -eq 'cancel'){$null=Cancel-Step 'first' $id 'EATS_HUB_TOKEN_CUSTOMER_A' '"1"' 200 'transition'}else{Cancel-NewConfirmation}
  Require-Test ($script:writes -eq 1)
  $bad=Copy-Test $script:cp;$bad.schemaVersion=1;Reject-Test {Assert-CancellationCheckpoint $bad}
 }
}
$claims=[pscustomobject]@{iss=$script:CancellationTestIdentity.issuer;sub=$script:CancellationTestIdentity.subject;exp=4102444800}
Assert-ReplacementIdentity $script:CancellationTestIdentity $claims 1893456000
$claims.sub='other';Reject-Test {Assert-ReplacementIdentity $script:CancellationTestIdentity $claims 1893456000}
$claims.sub=$script:CancellationTestIdentity.subject;$claims.exp=1893456000;Reject-Test {Assert-ReplacementIdentity $script:CancellationTestIdentity $claims 1893456000}
Write-Host 'OK: comparacion, deltas, noChange y recuperacion sinteticos. No acredita HTTP ni Mongo.'
