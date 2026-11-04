# Comprobacion pura manual: sin HTTP, Docker, Mongo, JWT ni checkpoints privados.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReservationCancellation.Assertions.ps1')
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-LocalReservationConfirmation.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Recorrido con sintaxis invalida.'}
$names=@('Check-ConfirmationCheckpoint','Check-ConfirmationContinuity','Confirmation-Step')
foreach($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){if($node.Name -in $names){Invoke-Expression $node.Extent.Text}}
function Copy-ConfirmTest($value){return ($value|ConvertTo-Json -Depth 60|ConvertFrom-Json)}
function Reject-ConfirmTest([scriptblock]$action,[string]$message){
 $failed=$false;try{& $action}catch{if($message -and $_.Exception.Message -cne $message){throw ('Error inesperado: '+$_.Exception.Message)};$failed=$true}
 if(!$failed){throw 'Falta rechazo esperado.'}
}
$script:ConfirmationTestIdentity=[pscustomobject]@{issuer='https://issuer.test';subject='customer'}
$script:ConfirmationTestWrongIdentity=$false
$script:ConfirmationTestOwner='11111111-1111-4111-8111-111111111111';$script:RestaurantA=$script:ConfirmationTestOwner
$script:ConfirmationTestShift=[pscustomobject]@{id='33333333-3333-4333-8333-333333333333';startInstant='2035-01-01T13:00:00Z'}
$script:ConfirmationTestBody=[ordered]@{shiftId=$script:ConfirmationTestShift.id;partySize=2;notes=('SPEC-005 '+('b'*32))}
$script:ConfirmationTestResponse=[pscustomobject]@{status=201;etag='"1"';location=('/catalog/restaurants/'+$script:RestaurantA+'/reservations/44444444-4444-4444-8444-444444444444');body=[pscustomobject]@{
 kind='MANAGED';id='44444444-4444-4444-8444-444444444444';restaurantId=$script:RestaurantA;owner=$script:ConfirmationTestIdentity;shiftId=$script:ConfirmationTestShift.id;partySize=2;notes=$script:ConfirmationTestBody.notes;status='CONFIRMED';version=1;createdAt='2035-01-01T10:00:00Z';updatedAt='2035-01-01T10:00:00.000Z';cancelledAt=$null
}}
$script:ConfirmationTestBefore=[pscustomobject]@{protectedCollections=@(@{name='existing';hash='same'});operationInvariantSha256='metadata';revision=9;receiptCount=0;reservationView=$null}
$script:ConfirmationTestAfter=[pscustomobject]@{protectedCollections=@(@{name='existing';hash='same'});operationInvariantSha256='metadata';revision=10;receiptCount=1;reservationView=$script:ConfirmationTestResponse.body;receiptView=$script:ConfirmationTestResponse.body;receiptFingerprintMatches=$true;receiptStatus=201;receiptRevision=10;receiptVersion=1;receiptLocation=$script:ConfirmationTestResponse.location;assignmentValid=$true;snapshotValid=$true;noOverlap=$true}
function Cancel-Now {return [DateTimeOffset]::Parse('2035-01-01T10:00:00Z')}
function Cancel-Identity([string]$actor){
 if($script:ConfirmationTestWrongIdentity){return [pscustomobject]@{issuer=$script:ConfirmationTestIdentity.issuer;subject='other'}}
 return $script:ConfirmationTestIdentity
}
function Cancel-Manifest {return [pscustomobject]@{phase=[int]$script:ConfirmationTestAccepted;drift=$script:ConfirmationTestDrift}}
function Confirmation-Delta($entry){if($script:ConfirmationTestAccepted){return $script:ConfirmationTestAfter};return $script:ConfirmationTestBefore}
function Save-Confirmation {
 if($script:ConfirmationTestCrash -ceq 'save' -and @($script:confirmation.steps|Where-Object {$null -ne $_.response}).Count){$script:ConfirmationTestCrash='';throw 'Interrupcion guardando respuesta'}
 $script:ConfirmationTestPersisted=$script:confirmation|ConvertTo-Json -Depth 60
 if($script:ConfirmationTestCrash -ceq 'before' -and $script:confirmation.pendingName){$script:ConfirmationTestCrash='';throw 'Interrupcion antes de POST'}
}
function Cancel-Request([string]$uri,[string]$method,[string]$actor,[string]$match,[string]$key,$body,[int]$expected){
 if($script:ConfirmationTestKey -and $script:ConfirmationTestKey -cne $key){throw 'Se cambio clave durante recuperacion.'}
 $script:ConfirmationTestKey=$key
 Equal-Cancel ($body|ConvertFrom-Json) $script:ConfirmationTestBody 'Intencion sintetica'
 if(!$script:ConfirmationTestAccepted){$script:ConfirmationTestAccepted=$true;$script:ConfirmationTestWrites++}
 if($script:ConfirmationTestCrash -ceq 'response'){$script:ConfirmationTestCrash='';throw 'Respuesta perdida'}
 return $script:ConfirmationTestResponse
}
$base='http://localhost:8082/catalog/restaurants/'+$script:RestaurantA
foreach($crash in @('before','response','save')){
 $script:ConfirmationTestAccepted=$false;$script:ConfirmationTestDrift=$false;$script:ConfirmationTestWrites=0;$script:ConfirmationTestKey=''
 $script:ConfirmationTestCrash=$crash
 $script:confirmation=[pscustomobject]@{schemaVersion=1;spec='SPEC-005';runId=('b'*32);shiftId=$script:ConfirmationTestShift.id;dualShiftId=([guid]::Empty).ToString();partySize=2;shifts=@($script:ConfirmationTestShift);steps=@();pendingName=$null;lastManifest=(Cancel-Manifest);final=$null;restart=@()}
 Check-ConfirmationCheckpoint $script:confirmation
 $message=switch($crash){'before'{'Interrupcion antes de POST'}'response'{'Respuesta perdida'}'save'{'Interrupcion guardando respuesta'}}
 Reject-ConfirmTest {$null=Confirmation-Step 'cliente' 'EATS_HUB_TOKEN_CUSTOMER_A' $script:ConfirmationTestBody 201} $message
 $script:confirmation=$script:ConfirmationTestPersisted|ConvertFrom-Json
 Check-ConfirmationCheckpoint $script:confirmation
 $script:ConfirmationTestWrongIdentity=$true
 try{Reject-ConfirmTest {$null=Confirmation-Step 'cliente' 'EATS_HUB_TOKEN_CUSTOMER_A' $script:ConfirmationTestBody 201} 'Identidad de confirmacion: diferencia no permitida.'}
 finally{$script:ConfirmationTestWrongIdentity=$false}
 $null=Confirmation-Step 'cliente' 'EATS_HUB_TOKEN_CUSTOMER_A' $script:ConfirmationTestBody 201
 $null=Confirmation-Step 'cliente' 'EATS_HUB_TOKEN_CUSTOMER_A' $script:ConfirmationTestBody 201
 if($script:ConfirmationTestWrites -ne 1 -or $script:confirmation.pendingName){throw 'Recuperacion no es idempotente.'}
 Check-ConfirmationCheckpoint $script:confirmation
 $script:ConfirmationTestDrift=$true
 Reject-ConfirmTest {Check-ConfirmationContinuity} 'Continuidad de confirmacion: diferencia no permitida.'
 $script:ConfirmationTestDrift=$false
 $bad=Copy-ConfirmTest $script:confirmation;$bad.schemaVersion=99
 Reject-ConfirmTest {Check-ConfirmationCheckpoint $bad} 'Checkpoint desconocido.'
}
$get=Copy-ConfirmTest $script:ConfirmationTestResponse;$get.status=200;$get.location=''
Assert-CancellationStored $script:ConfirmationTestResponse $get
$get.body.owner.subject='other'
Reject-ConfirmTest {Assert-CancellationStored $script:ConfirmationTestResponse $get} 'Cuerpo persistido: diferencia no permitida.'
Write-Host 'OK: recuperacion e invariantes sinteticos de confirmacion; no acredita HTTP ni Mongo.'
