# Comprobacion sintetica manual: sin HTTP, Docker, secretos, Mongo ni archivos de checkpoint.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReservationReplacement.Assertions.ps1')
function Expect-Failure([scriptblock]$action){$failed=$false;try{& $action}catch{$failed=$true};if(!$failed){throw 'Se esperaba rechazo sintetico.'}}
function Copy-Synthetic($value){return ($value|ConvertTo-Json -Depth 50|ConvertFrom-Json)}
function Require-Synthetic([bool]$condition){if(!$condition){throw 'Asercion sintetica incumplida.'}}
$now=[DateTimeOffset]::Parse('2030-01-01T10:00:00Z')
Assert-ReplacementEqual ([pscustomobject]@{a=1;b=2}) ([pscustomobject]@{b=2;a=1}) 'Orden de propiedades irrelevante'
$root='http://localhost:8082/catalog'
$owner='11111111-1111-4111-8111-111111111111';$id='33333333-3333-4333-8333-333333333333';$shiftId='44444444-4444-4444-8444-444444444444';$tableId='55555555-5555-4555-8555-555555555555'
$script:RestaurantA=$owner
$prior=[pscustomobject]@{status=200;etag='"1"';location='';body=[pscustomobject]@{
    kind='MANAGED';id=$id;restaurantId=$owner;owner=[pscustomobject]@{issuer='https://issuer.test';subject='client'};createdAt='2030-01-01T09:00:00Z';updatedAt='2030-01-01T09:00:00Z';
    shiftId=$shiftId;partySize=2;notes='Antes';status='CONFIRMED';cancelledAt=$null;version=1;tableIds=@($tableId);combinationId=$null;assignedCapacity=4;
    localStart='2030-01-01T11:00:00';localEnd='2030-01-01T12:00:00';zoneId='UTC';startInstant='2030-01-01T11:00:00Z';endInstant='2030-01-01T12:00:00Z'}}
$accepted=Copy-Synthetic $prior;$accepted.etag='"2"';$accepted.body.version=2;$accepted.body.notes='Despues';$accepted.body.updatedAt='2030-01-01T10:00:00Z'
$intent=[pscustomobject]@{shiftId=$shiftId;partySize=2;notes='Despues'};$tables=@([pscustomobject]@{id=$tableId;capacity=4})
Assert-ReplacementSuccess $prior $accepted $intent $prior.body $tables @()
foreach($field in @('id','restaurantId','createdAt','status','notes','partySize','assignedCapacity','zoneId')){
    $bad=Copy-Synthetic $accepted
    if($field -in @('partySize','assignedCapacity')){$bad.body.$field=99}else{$bad.body.$field='alterado'}
    Expect-Failure {Assert-ReplacementSuccess $prior $bad $intent $prior.body $tables @()}
}
$bad=Copy-Synthetic $accepted;$bad.body.owner.subject='other';Expect-Failure {Assert-ReplacementSuccess $prior $bad $intent $prior.body $tables @()}
$before=[pscustomobject]@{protectedCollections=@([pscustomobject]@{name='other';documentsSha256='same';indexesSha256='index';options='{}'});reservationInvariantSha256='identity';operationInvariantSha256='op';version=1;revision=7;receiptCount=0;receiptVersion=$null;receiptRevision=$null;receiptStatus=$null;receiptLocation=$null;receiptSha256=$null}
$after=Copy-Synthetic $before;$after.version=2;$after.revision=8;$after.receiptCount=1;$after.receiptVersion=2;$after.receiptRevision=8;$after.receiptStatus=200;$after.receiptSha256='receipt'
$after|Add-Member -NotePropertyName reservationView -NotePropertyValue (Copy-Synthetic $accepted.body)
$after|Add-Member -NotePropertyName receiptView -NotePropertyValue (Copy-Synthetic $accepted.body)
$after|Add-Member -NotePropertyName tableSnapshots -NotePropertyValue @([pscustomobject]@{id=$tableId;capacity=4})
$after|Add-Member -NotePropertyName receiptFingerprintMatches -NotePropertyValue $true
Assert-ReplacementDelta $before $after
Assert-ReplacementDatabase $after $accepted $tables
$bad=Copy-Synthetic $after;$bad.receiptView.owner.subject='other';Expect-Failure {Assert-ReplacementDatabase $bad $accepted $tables}
$bad=Copy-Synthetic $after;$bad.tableSnapshots[0].capacity=9;Expect-Failure {Assert-ReplacementDatabase $bad $accepted $tables}
$bad=Copy-Synthetic $after;$bad.protectedCollections[0].documentsSha256='foreign-write';Expect-Failure {Assert-ReplacementDelta $before $bad}
$bad=Copy-Synthetic $after;$bad.protectedCollections[0].indexesSha256='changed';Expect-Failure {Assert-ReplacementDelta $before $bad}
$bad=Copy-Synthetic $after;$bad.revision=9;Expect-Failure {Assert-ReplacementDelta $before $bad}
$frozen=New-ReplacementNearSnapshot $prior ('http://localhost/reservations/'+$id) 'Despues' $now
Expect-Failure {New-ReplacementNearSnapshot $prior $frozen.uri 'Despues' $now.AddHours(3)}
$identity=[pscustomobject]@{issuer='https://issuer.test';subject='client'}
$claims=[pscustomobject]@{iss=$identity.issuer;sub=$identity.subject;exp=$now.ToUnixTimeSeconds()+3600}
Assert-ReplacementIdentity $identity $claims $now.ToUnixTimeSeconds()
Expect-Failure {Assert-ReplacementIdentity $identity $claims $now.AddHours(3).ToUnixTimeSeconds()}
$renewed=Copy-Synthetic $claims;$renewed.exp=$now.AddHours(4).ToUnixTimeSeconds()
Assert-ReplacementIdentity $identity $renewed $now.AddHours(3).ToUnixTimeSeconds()
$wrong=Copy-Synthetic $renewed;$wrong.sub='other';Expect-Failure {Assert-ReplacementIdentity $identity $wrong $now.AddHours(3).ToUnixTimeSeconds()}

# Se cargan SOLO las funciones de etapa; nunca se invoca el codigo superior del recorrido.
$parseErrors=$null;$parseTokens=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-LocalReservationReplacement.ps1'),[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors.Count -gt 0){throw 'Recorrido con sintaxis invalida.'}
$functionAst=$ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Replacement-Step','Replacement-Replay','Check-ReplacementIdentity')},$false)
foreach($node in $functionAst){Invoke-Expression $node.Extent.Text}
function Replacement-Identity([string]$actor){return $identity}
function Replacement-Token([string]$actor){return 'synthetic-only'}
function ConvertFrom-JwtPayload([string]$token){return [pscustomobject]@{iss=$identity.issuer;sub=$identity.subject;exp=4102444800}}
function Replacement-Get([string]$uri,[string]$actor){if($uri -match '/shifts/'){return [pscustomobject]@{body=$prior.body}};return $prior}
function Replacement-DeltaManifest($entry){if($script:serverAccepted){return $after};return $before}
function Replacement-Manifest {return [pscustomobject]@{stable=$script:serverAccepted}}
function Equal-Replacement($a,$b,[string]$name){Assert-ReplacementEqual $a $b $name}
function Save-Replacement {
    if($script:crashAt -eq 'save' -and $null -ne $script:cp.steps[0].response){$script:crashAt='';throw 'Interrupcion sintetica antes de persistir respuesta'}
    $script:persisted=$script:cp|ConvertTo-Json -Depth 50
}
function Replacement-Request([string]$uri,[string]$method,[string]$actor,[string]$body,[string]$match,[string]$key,[int]$expected){
    if($null -ne $script:firstKey){Require-Synthetic ($script:firstKey -ceq $key)}else{$script:firstKey=$key}
    Require-Synthetic ($body -ceq ($frozen.body|ConvertTo-Json -Compress));Require-Synthetic ($match -ceq $frozen.match)
    if(!$script:serverAccepted){$script:serverAccepted=$true;$script:businessWrites++}
    if($script:crashAt -eq 'response'){$script:crashAt='';throw 'Respuesta perdida sintetica'}
    return $accepted
}
foreach($crash in @('response','save','completed')){
    $script:cp=[pscustomobject]@{runId='synthetic';steps=@();config=@([pscustomobject]@{body=[pscustomobject]@{items=$tables}},[pscustomobject]@{body=[pscustomobject]@{items=@()}});nearSnapshot=$frozen}
    $script:serverAccepted=$false;$script:businessWrites=0;$script:firstKey=$null;$script:crashAt=$crash
    if($crash -eq 'completed'){$null=Replacement-Step 'near' $frozen.uri 'synthetic' $frozen.body $frozen.match 200 $false}
    else{Expect-Failure {$null=Replacement-Step 'near' $frozen.uri 'synthetic' $frozen.body $frozen.match 200 $false}}
    $script:cp=$script:persisted|ConvertFrom-Json
    # El tiempo ya estaria fuera del margen inicial: se usa la intencion congelada, sin recrearla.
    $null=Replacement-Step 'near' $script:cp.nearSnapshot.uri 'synthetic' $script:cp.nearSnapshot.body $script:cp.nearSnapshot.match 200 $false
    Replacement-Replay 'near';Require-Synthetic ($script:businessWrites -eq 1)
}
Write-Host 'OK: comparadores y recuperacion sinteticos; sin HTTP, Mongo, Docker, JWT real ni archivos de checkpoint.'
