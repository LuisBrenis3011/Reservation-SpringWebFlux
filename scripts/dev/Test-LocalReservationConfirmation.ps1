[CmdletBinding()]
param([guid]$ShiftId=[guid]::Empty,[ValidateRange(1,20)][int]$PartySize=2,
 [guid]$DualShiftId=[guid]::Empty,[switch]$AfterRestart,[switch]$AllowFixtureWrites,
 [switch]$AllowDatabaseReads,[switch]$DedicatedFixtures,[switch]$ActivationPrerequisitesConfirmed)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationCancellation.Assertions.ps1')
# Reutilizar SOLO funciones de transporte. No ejecutar instrucciones superiores de SPEC-008.
$tokens=$null;$errors=$null
$source=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-LocalReservationCancellation.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Transporte compartido con sintaxis invalida.'}
$sharedNames=@('Cancel-Identity','Cancel-ReadMongo','Cancel-Manifest','Cancel-Request','Cancel-Now')
foreach($node in $source.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
 if($node.Name -in $sharedNames){Invoke-Expression $node.Extent.Text}
}
if(!$AllowDatabaseReads -or !$ActivationPrerequisitesConfirmed){throw 'Revisar T127-T129, respaldo/puente/corte y permisos antes de ejecutar. Exige -AllowDatabaseReads -ActivationPrerequisitesConfirmed.'}
if(!$AfterRestart -and (!$AllowFixtureWrites -or !$DedicatedFixtures)){throw 'Exige -AllowFixtureWrites -DedicatedFixtures; se conservan nuevas reservas.'}
$root='http://localhost:8082/catalog';$base=$root+'/restaurants/'+$script:RestaurantA
$path=Join-Path $script:IdentityPrivate 'reservation-confirmation-http-checkpoint.json'
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env');$database=$values['MONGODB_DATABASE']
if($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018' -or $database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')){throw 'Solo Mongo local 27018 y base de aplicacion.'}
function Save-Confirmation {
 $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 Write-PrivateText $temp ($script:confirmation|ConvertTo-Json -Depth 60)
 if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
}
function Check-ConfirmationCheckpoint($cp){
 foreach($field in @('schemaVersion','spec','runId','shiftId','dualShiftId','partySize','shifts','steps','pendingName','lastManifest','final','restart')){
  if($null -eq $cp.PSObject.Properties[$field]){throw 'Checkpoint incompleto; conservar intacto.'}
 }
 if($cp.schemaVersion -ne 1 -or $cp.spec -cne 'SPEC-005' -or $cp.runId -cnotmatch '^[0-9a-f]{32}$' -or $null -eq $cp.lastManifest){throw 'Checkpoint desconocido.'}
 foreach($id in @($cp.shiftId,$cp.dualShiftId)){$parsed=[guid]::Empty;if(![guid]::TryParse($id,[ref]$parsed)){throw 'UUID invalido.'}}
 if($cp.partySize -lt 1 -or $cp.partySize -gt 20){throw 'Grupo alterado.'}
 $names=@();foreach($entry in @($cp.steps)){
  foreach($field in @('name','actor','identity','body','key','expected','code','before','response','afterManifest','shift')){
   if($null -eq $entry.PSObject.Properties[$field]){throw 'Etapa incompleta.'}
  }
  if($entry.actor -and $entry.actor -cnotin @('EATS_HUB_TOKEN_CUSTOMER_A','EATS_HUB_TOKEN_DUAL','EATS_HUB_TOKEN_A','EATS_HUB_TOKEN_NO_ROLE')){throw 'Actor desconocido.'}
  $intent=$entry.body|ConvertFrom-Json
  if($intent.shiftId -cnotin @($cp.shiftId,$cp.dualShiftId) -or $intent.notes -cne ('SPEC-005 '+$cp.runId)){throw 'Contenido congelado alterado.'}
  if($entry.expected -eq 201 -and ($intent.partySize -ne $cp.partySize -or $entry.shift.id -cne $intent.shiftId)){throw 'Grupo/turno congelado alterado.'}
  if($entry.name -cin $names -or $entry.key -cne ($cp.runId+'-'+$entry.name)){throw 'Intencion alterada.'}
  if($entry.actor -and ($null -eq $entry.identity -or !$entry.identity.subject -or !$entry.identity.issuer)){throw 'Identidad congelada ausente.'}
  if($entry.expected -eq 201 -and $null -eq $entry.shift){throw 'Falta turno congelado.'}
  if($null -ne $entry.response -and $null -eq $entry.afterManifest){throw 'Respuesta sin evidencia.'}
  $names+=@($entry.name)
 }
 if($cp.pendingName -and $cp.pendingName -cnotin $names){throw 'Etapa pendiente desconocida.'}
}
function Check-ConfirmationContinuity {
 if($script:confirmation.pendingName){throw 'Recuperar primero la intencion pendiente.'}
 Equal-Cancel $script:confirmation.lastManifest (Cancel-Manifest) 'Continuidad de confirmacion'
}
function Confirmation-Delta($entry){
 $intent=$entry.body|ConvertFrom-Json
 return Cancel-ReadMongo 'mongo-cancellation-confirmation-manifest.js' ([pscustomobject]@{
  restaurantId=$script:RestaurantA;reservationId=$intent.shiftId;issuer=$entry.identity.issuer;subject=$entry.identity.subject;key=$entry.key;match='';body=$intent
 })
}
function Confirmation-Step([string]$name,[string]$actor,$body,[int]$expected,[string]$code=''){
 $found=@($script:confirmation.steps|Where-Object {$_.name -ceq $name})
 if(!$found.Count){
  Check-ConfirmationContinuity
  $frozenIdentity=$null;if($actor){$frozenIdentity=Cancel-Identity $actor}
  $frozenShift=$null
  if($expected -eq 201){$frozenShift=@($script:confirmation.shifts|Where-Object {$_.id -ceq $body.shiftId})[0]}
  $entry=[pscustomobject]@{name=$name;actor=$actor;identity=$frozenIdentity;body=($body|ConvertTo-Json -Compress);key=($script:confirmation.runId+'-'+$name);expected=$expected;code=$code;before=$null;response=$null;afterManifest=$null;shift=$frozenShift}
  $script:confirmation.steps=@($script:confirmation.steps)+@($entry);Save-Confirmation
 }else{$entry=$found[0]}
 if($entry.actor){Equal-Cancel $entry.identity (Cancel-Identity $entry.actor) 'Identidad de confirmacion'}
 if($null -ne $entry.response){Check-ConfirmationContinuity;Write-Host ('Checkpoint: '+$name);return $entry.response}
 if($null -eq $entry.before){
  Check-ConfirmationContinuity
  if($entry.expected -eq 201){$entry.before=Confirmation-Delta $entry}else{$entry.before=Cancel-Manifest}
  $script:confirmation.pendingName=$name;Save-Confirmation
 }
 if($script:confirmation.pendingName -cne $name){throw 'Otra intencion pendiente.'}
 if($entry.expected -eq 201){
  $current=Confirmation-Delta $entry
  if($current.receiptCount -eq 0){
   Equal-Cancel $script:confirmation.lastManifest (Cancel-Manifest) 'Antes de POST'
   $now=Cancel-Now;$start=[DateTimeOffset]::Parse($entry.shift.startInstant)
   if($start -lt $now.AddHours(2) -or $start -gt $now.AddDays(90)){throw 'Intencion sin aceptar fuera de plazo; conservar clave y checkpoint.'}
  }elseif($current.receiptCount -eq 1){
   $recovered=[pscustomobject]@{status=201;body=$current.receiptView;etag='"1"';location=$current.receiptLocation}
   Assert-CancellationConfirmation $entry.before $current $recovered $entry $script:RestaurantA
  }else{throw 'Recibo no verificable.'}
 }else{Equal-Cancel $entry.before (Cancel-Manifest) 'Antes de rechazo'}
 $result=Cancel-Request ($base+'/reservations') 'Post' $entry.actor '' $entry.key $entry.body $entry.expected
 if($entry.expected -eq 201){Assert-CancellationConfirmation $entry.before (Confirmation-Delta $entry) $result $entry $script:RestaurantA}
 else{
  if($entry.code -and $result.body.code -cne $entry.code){throw 'HTTP esperado pero codigo de error distinto.'}
  Equal-Cancel $entry.before (Cancel-Manifest) 'Rechazo sin escrituras'
 }
 $entry.response=$result;$entry.afterManifest=Cancel-Manifest
 $script:confirmation.lastManifest=$entry.afterManifest;$script:confirmation.pendingName=$null;Save-Confirmation
 Write-Host ('OK: '+$name+' -> HTTP '+$entry.expected);return $result
}
function Confirmation-Replay([string]$name,[switch]$Conflict){
 Check-ConfirmationContinuity;$entry=@($script:confirmation.steps|Where-Object {$_.name -ceq $name})[0]
 Equal-Cancel $entry.identity (Cancel-Identity $entry.actor) 'Identidad de replay'
 $before=Cancel-Manifest;$body=$entry.body;$expected=201
 if($Conflict){$intent=$body|ConvertFrom-Json;$intent.notes+=' diferente';$body=$intent|ConvertTo-Json -Compress;$expected=409}
 $result=Cancel-Request ($base+'/reservations') 'Post' $entry.actor '' $entry.key $body $expected
 if($Conflict){if($result.body.code -cne 'IDEMPOTENCY_CONFLICT'){throw 'No acredita conflicto de clave.'}}else{Equal-Cancel $entry.response $result 'Replay completo'}
 Equal-Cancel $before (Cancel-Manifest) 'Replay/conflicto sin escrituras'
}
function Confirmation-ReadBack {
 Check-ConfirmationContinuity
 foreach($entry in @($script:confirmation.steps|Where-Object {$_.expected -eq 201 -and $null -ne $_.response})){
  Equal-Cancel $entry.identity (Cancel-Identity $entry.actor) 'Identidad de consulta'
  $actual=Cancel-Request ($base+'/reservations/'+$entry.response.body.id) 'Get' $entry.actor '' '' $null 200
  Assert-CancellationStored $entry.response $actual
 }
 Check-ConfirmationContinuity
}
$lock=$null
try{
 [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
 $lock=[IO.File]::Open(($path+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 if(Test-Path -LiteralPath $path){
  $script:confirmation=Get-Content $path -Raw|ConvertFrom-Json;Check-ConfirmationCheckpoint $script:confirmation
  foreach($pair in @(@('ShiftId','shiftId'),@('DualShiftId','dualShiftId'),@('PartySize','partySize'))){
   if($PSBoundParameters.ContainsKey($pair[0]) -and (Get-Variable $pair[0] -ValueOnly).ToString() -cne $script:confirmation.($pair[1]).ToString()){throw 'Parametros distintos del checkpoint.'}
  }
 }else{
  if($AfterRestart -or $ShiftId -eq [guid]::Empty){throw 'Primero indica ShiftId dedicada y futura.'}
  if($DualShiftId -ne [guid]::Empty -and $DualShiftId -eq $ShiftId){throw 'Turno dual debe ser distinto.'}
  $shifts=@();foreach($target in @($ShiftId,$DualShiftId)|Select-Object -Unique){
   if($target -eq [guid]::Empty){continue}
   $shift=(Cancel-Request ($base+'/shifts/'+$target) 'Get' 'EATS_HUB_TOKEN_A' '' '' $null 200).body
   $shifts+=@($shift)
  }
  $script:confirmation=[pscustomobject]@{schemaVersion=1;spec='SPEC-005';runId=[guid]::NewGuid().ToString('N');shiftId=$ShiftId.ToString();dualShiftId=$DualShiftId.ToString();partySize=$PartySize;shifts=$shifts;steps=@();pendingName=$null;lastManifest=(Cancel-Manifest);final=$null;restart=@()}
  Save-Confirmation
 }
 Check-ConfirmationCheckpoint $script:confirmation
 if($AfterRestart -and $script:confirmation.pendingName){throw 'Recupera primero con el comando inicial; reinicio solo lee.'}
 if($script:confirmation.pendingName){
  $entry=@($script:confirmation.steps|Where-Object {$_.name -ceq $script:confirmation.pendingName})[0]
  $null=Confirmation-Step $entry.name $entry.actor ($entry.body|ConvertFrom-Json) $entry.expected $entry.code
 }else{Check-ConfirmationContinuity}
 if($AfterRestart){
  if($null -eq $script:confirmation.final){throw 'Recorrido incompleto.'}
  Equal-Cancel $script:confirmation.final (Cancel-Manifest) 'Mongo tras reinicio declarado'
  Confirmation-ReadBack
  $script:confirmation.restart+=@([pscustomobject]@{timestampUtc=[DateTime]::UtcNow.ToString('o');operatorDeclaredRestart=$true})
  Save-Confirmation;Write-Host 'OK: reservas, snapshots, ETag, recibos e indices tras reinicio declarado. Evidencia integral pendiente.';return
 }
 if($null -ne $script:confirmation.final){throw 'Recorrido completo; reinicia manualmente y usa -AfterRestart.'}
 Write-Host 'Evita otros escritores. Se conservaran una o dos reservas nuevas dedicadas; no se cambia oferta ni gate.'
 $intent=[ordered]@{shiftId=$script:confirmation.shiftId;partySize=$script:confirmation.partySize;notes=('SPEC-005 '+$script:confirmation.runId)}
 $null=Confirmation-Step 'sin-token' '' $intent 401
 $null=Confirmation-Step 'sin-perfil' 'EATS_HUB_TOKEN_NO_ROLE' $intent 403
 $null=Confirmation-Step 'encargado-sin-CUSTOMER' 'EATS_HUB_TOKEN_A' $intent 403
 $invalid=[ordered]@{shiftId=$intent.shiftId;partySize=0;notes=$intent.notes}
 $null=Confirmation-Step 'grupo-invalido' 'EATS_HUB_TOKEN_CUSTOMER_A' $invalid 422
 $null=Confirmation-Step 'cliente' 'EATS_HUB_TOKEN_CUSTOMER_A' $intent 201
 Confirmation-Replay 'cliente';Confirmation-Replay 'cliente' -Conflict
 $null=Confirmation-Step 'duplicado-activo' 'EATS_HUB_TOKEN_CUSTOMER_A' $intent 409 'DUPLICATE_RESERVATION'
 if($script:confirmation.dualShiftId -ne ([guid]::Empty).ToString()){
  $dual=[ordered]@{shiftId=$script:confirmation.dualShiftId;partySize=$script:confirmation.partySize;notes=$intent.notes}
  $null=Confirmation-Step 'cuenta-dual' 'EATS_HUB_TOKEN_DUAL' $dual 201
  Confirmation-Replay 'cliente';Confirmation-Replay 'cuenta-dual'
 }else{Write-Host 'PENDIENTE recorrido cuenta dual: falta DualShiftId.'}
 Confirmation-ReadBack
 $script:confirmation.final=Cancel-Manifest;Save-Confirmation
 Write-Host 'OK: POST, permisos, asignacion, replay y conservacion. Checkpoint propio sin JWT. Reinicia manualmente IntelliJ 8082 y usa -AfterRestart.'
 Write-Host 'Bordes exactos, carrera, fallo de commit, revocacion y legado no se acreditan por este script secuencial. T127-T130 y cierres pendientes.'
}finally{if($null -ne $lock){$lock.Dispose()}}
