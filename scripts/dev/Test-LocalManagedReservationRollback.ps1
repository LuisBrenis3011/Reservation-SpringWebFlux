[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Prepare','StartPrevious','Previous','Current')][string]$Stage,
 [switch]$WritersStopped,[string]$BackupDirectory,[string]$BridgeCommit,[string]$BridgeEvidence)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
. (Join-Path $PSScriptRoot 'ManagedReservations.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationCancellation.Assertions.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Review.ps1')
function Get-BridgeHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
$script:ManagedBridgeCatalog=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../specs/005-confirmar-reserva/contracts/bridge-catalog.md'))
$script:ManagedBridgeScripts=$PSScriptRoot
function Assert-BridgeManagedPath([string]$Root,[string]$Path,[bool]$AllowMissing=$false){
 $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
 $full=[IO.Path]::GetFullPath($Path)
 if($full -ine $rootFull -and -not $full.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Ruta gestionada fuera de raiz permitida.'}
 $rootItem=Get-Item -LiteralPath $rootFull -Force -ErrorAction Stop
 if(-not $rootItem.PSIsContainer){throw 'Raiz gestionada no es directorio.'}
 if(-not $AllowMissing -and -not (Test-Path -LiteralPath $full)){throw 'Ruta gestionada ausente.'}
 # Recorrer desde destino hasta la unidad incluye tambien enlaces en la raiz.
 $cursor=$full
 while($cursor){
  $item=$null
  try{$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop}catch [System.Management.Automation.ItemNotFoundException]{}
  if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Ruta gestionada contiene enlace o junction.'}
  $parent=[IO.Path]::GetDirectoryName($cursor)
  if($parent -ceq $cursor){break};$cursor=$parent
 }
 return $full
}
function Assert-ManagedBridge([string]$Path,$Session=$null){
 Assert-BridgeText $Path 'BridgeEvidence'
 $file=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($file.PSIsContainer -or $file.Name -cne 'bridge-evidence.json'){throw 'Se requiere bridge-evidence.json revisado.'}
 $root=$file.Directory.FullName
 $hash=Get-BridgeHash (Get-BridgeSafeFile $root 'bridge-evidence.json')
 $catalogHash=Get-BridgeHash $script:ManagedBridgeCatalog
 $evidence=Read-BridgeJson $root 'bridge-evidence.json' $hash
 Assert-BridgeReviewChain $evidence $root $script:ManagedBridgeCatalog $catalogHash $script:ManagedBridgeScripts
 $jar=Get-BridgeSafeFile $root $evidence.jarPath
 $reports=@($evidence.reports|ForEach-Object { [pscustomobject]@{groupId=$_.groupId;path=$_.path;sha256=$_.sha256} })
 if($null -ne $Session){
  if($Session.schemaVersion -ne 2 -or $Session.spec -cne 'SPEC-005'){throw 'Sesion gestionada anterior o ajena; se conserva sin migrar.'}
  if($Session.bridgeEvidencePath -cne $file.FullName -or $Session.bridgeEvidenceSha256 -ine $hash -or
     $Session.catalogSha256 -ine $catalogHash -or $Session.candidateSha256 -ine $evidence.candidate.sha256 -or
     $Session.bridgeCommit -cne $evidence.commit -or $Session.jarSha256 -ine $evidence.jarSha256 -or
     ($Session.reportHashes|ConvertTo-Json -Depth 10 -Compress) -cne ($reports|ConvertTo-Json -Depth 10 -Compress)){throw 'La evidencia o sus referencias cambiaron desde Prepare.'}
 }
 return [pscustomobject]@{path=$file.FullName;sha256=$hash;catalogSha256=$catalogHash;candidateSha256=$evidence.candidate.sha256;reportHashes=$reports;commit=$evidence.commit;jarPath=$jar;jarSha256=$evidence.jarSha256;value=$evidence;root=$root}
}
function Invoke-ManagedBridgeGate($Bridge,$Session,[scriptblock]$Action){
 $locks=[Collections.Generic.List[IO.FileStream]]::new()
 try{
  foreach($path in @(Get-BridgeReviewLockFiles $Bridge.value $Bridge.root $script:ManagedBridgeCatalog $script:ManagedBridgeScripts)+@($Bridge.path)){
   $locks.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
  }
  $null=Assert-ManagedBridge $Bridge.path $Session
  if((Get-BridgeHash $Bridge.path) -ine $Bridge.sha256){throw 'Evidencia cambiada durante la etapa.'}
  & $Action
 }finally{foreach($stream in $locks){$stream.Dispose()}}
}
function Invoke-ManagedRollback {
$sessionPath=Join-Path $script:IdentityPrivate 'managed-reservations-rollback-session.json'
$null=Assert-BridgeManagedPath $script:IdentityRoot $sessionPath $true
$session=$null
if(Test-Path -LiteralPath $sessionPath){$session=Get-Content -LiteralPath $sessionPath -Raw|ConvertFrom-Json}
if($Stage -eq 'Prepare' -and $null -ne $session){throw 'Sesion ya existente; se conserva.'}
if($Stage -ne 'Prepare' -and $null -eq $session){throw 'Falta Prepare gestionado.'}
$bridge=Assert-ManagedBridge $BridgeEvidence $session
if($BridgeCommit -and $BridgeCommit -cne $bridge.commit){throw 'BridgeCommit difiere de la evidencia revisada.'}
$BridgeCommit=$bridge.commit
$archiveRoot=[IO.Path]::GetFullPath((Join-Path $script:IdentityRoot 'backups/managed-rollback'))+[IO.Path]::DirectorySeparatorChar
if($null -ne $session){
 $folder=[IO.Path]::GetFullPath([string]$session.folder)
 $expectedJar=Join-Path $folder 'bridge-certified.jar'
 $null=Assert-BridgeManagedPath $script:IdentityRoot $expectedJar
 if(!$folder.StartsWith($archiveRoot,[StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFullPath([string]$session.jar) -cne $expectedJar -or
    (Get-BridgeHash $expectedJar) -ine $bridge.jarSha256){throw 'JAR de sesion ausente, ajeno o alterado.'}
}
$null=Assert-BridgeManagedPath $script:IdentityRoot (Join-Path $script:IdentityRoot '.env') $true
Initialize-ManagedMode $true $false $false
$database=$script:ManagedDatabase
if($null -ne $session){
 if($BackupDirectory -and [IO.Path]::GetFullPath($BackupDirectory) -cne $session.backupDirectory){throw 'Respaldo distinto de sesion.'}
 $BackupDirectory=$session.backupDirectory
}
if($BridgeCommit -cnotmatch '^[0-9a-f]{40}$' -or !$BackupDirectory){throw 'Requiere SHA completo real del puente y BackupDirectory gestionado validado.'}
$BackupDirectory=[IO.Path]::GetFullPath($BackupDirectory)
$allowed=[IO.Path]::GetFullPath((Join-Path $script:IdentityRoot 'backups/availability'))+[IO.Path]::DirectorySeparatorChar
if(!$BackupDirectory.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Respaldo fuera de carpeta permitida.'}
$null=Assert-BridgeManagedPath $script:IdentityRoot $BackupDirectory
function Assert-ManagedCommand {if($LASTEXITCODE -ne 0){throw 'Comando fallido; ensayo no acreditado.'}}
function Managed-Manifest {
 $old=$OutputEncoding
 try{
  $OutputEncoding=[Text.UTF8Encoding]::new($false)
  $raw=Get-Content (Join-Path $PSScriptRoot 'mongo-backup-manifest.js') -Raw|& docker exec -i -e ('EATS_BACKUP_DATABASE='+$database) -e EATS_BACKUP_SOURCE=true eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin
  Assert-ManagedCommand;return (($raw -join "`n")|ConvertFrom-Json)
 }finally{$OutputEncoding=$old}
}
function Assert-ManagedStopped {
 if(@(Get-NetTCPConnection -State Listen -LocalPort 8082 -ErrorAction SilentlyContinue).Count){throw 'Detener Eats Hub 8082 y todos los escritores.'}
}
function Managed-Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Check-ManagedBaseline {
 $policy=Assert-LiveManagedMode
 if(!$policy.retired){throw 'Reversion v2 exige corte persistente activo verificado.'}
 $proofPath=Join-Path $BackupDirectory 'managed-validation.json'
 foreach($name in @('managed-validation.json','database.archive.gz','source-before.json','source-after.json','restored.json')){$null=Assert-BridgeManagedPath $BackupDirectory (Join-Path $BackupDirectory $name)}
 $proof=Get-Content $proofPath -Raw|ConvertFrom-Json
 if($proof.spec -cne 'SPEC-005' -or !$proof.validation.restoreVerified -or !$proof.validation.sourceUnchanged -or !$proof.validation.writersStoppedDeclared -or
    $proof.validation.database -cne $database -or !$proof.proof.retired -or (Managed-Hash (Join-Path $BackupDirectory 'database.archive.gz')) -cne $proof.validation.archiveSha256){throw 'Respaldo gestionado no verificable.'}
 $before=Get-Content (Join-Path $BackupDirectory 'source-before.json') -Raw|ConvertFrom-Json
 foreach($file in @('source-after.json','restored.json')){
  Equal-Cancel $before (Get-Content (Join-Path $BackupDirectory $file) -Raw|ConvertFrom-Json) 'Respaldo aislado'
 }
 Equal-Cancel $proof.proof $before.managedProof 'Prueba gestionada'
 $hashes=[ordered]@{}
 foreach($property in $proof.checkpointHashes.PSObject.Properties){$hashes[$property.Name]=$property.Value}
 if(!$hashes.Count){throw 'Respaldo sin checkpoints.'}
 foreach($checkpointPath in $hashes.Keys){$null=Assert-BridgeManagedPath $script:IdentityPrivate $checkpointPath}
 Equal-Cancel $hashes (Get-ManagedCheckpointHashes @($hashes.Keys)) 'Checkpoints del respaldo'
 # Comparar manifiesto base sin la prueba adicional, politica incluida en documentos.
 $baseline=[pscustomobject]@{database=$before.database;collections=$before.collections}
 Equal-Cancel $baseline (Managed-Manifest) 'Origen actual frente al respaldo'
 if($null -ne $session -and (Managed-Hash $proofPath) -cne $session.backupProofSha256){throw 'Prueba cambio desde Prepare.'}
 return [pscustomobject]@{baseline=$baseline;proofHash=(Managed-Hash $proofPath)}
}
function Check-ManagedSources([string]$CurrentCommit=''){
 Push-Location $script:IdentityRoot
 try{
  $resolved=& git rev-parse --verify ($BridgeCommit+'^{commit}');Assert-ManagedCommand
  if([string]$resolved -cne $BridgeCommit){throw 'SHA no coincide.'}
  $head=& git rev-parse HEAD;Assert-ManagedCommand
  if($CurrentCommit -and [string]$head -cne $CurrentCommit){throw 'Version actual cambio.'}
  # Restriccion deliberada: puente con las mismas fuentes productivas verificadas.
  & git diff --quiet $BridgeCommit HEAD -- src/main build.gradle settings.gradle gradle gradlew gradlew.bat;Assert-ManagedCommand
  & git diff --quiet HEAD -- src/main build.gradle settings.gradle gradle gradlew gradlew.bat;Assert-ManagedCommand
  $extra=@(& git ls-files --others --exclude-standard -- src/main);Assert-ManagedCommand
  if($extra.Count){throw 'Fuentes sin versionar.'}
  foreach($path in @('src/main/java/com/brenis/SpringWebFlux/services/impls/ReservationCommandServiceImpl.java','src/main/java/com/brenis/SpringWebFlux/services/impls/ReservationQueryServiceImpl.java','src/main/java/com/brenis/SpringWebFlux/collections/ReservationPolicyCollection.java')){
   & git cat-file -e ($BridgeCommit+':'+$path);Assert-ManagedCommand
  }
  return [string]$head
 }finally{Pop-Location}
}
$proof=Check-ManagedBaseline
if($Stage -eq 'Prepare'){
 if(!$WritersStopped){throw 'Exige -WritersStopped.'}
 Assert-ManagedStopped;$current=Check-ManagedSources
 $folder=Join-Path $archiveRoot ([guid]::NewGuid().ToString('N'))
 $null=Assert-BridgeManagedPath $script:IdentityRoot $folder $true
 [IO.Directory]::CreateDirectory($folder)|Out-Null
 $jar=Join-Path $folder 'bridge-certified.jar'
 Invoke-ManagedBridgeGate $bridge $null {
  $null=Assert-LiveManagedMode
  $null=Assert-BridgeManagedPath $script:IdentityRoot $jar $true
  if((Get-BridgeHash $bridge.jarPath) -ine $bridge.jarSha256){throw 'JAR certificado alterado antes de copiar.'}
  [IO.File]::Copy($bridge.jarPath,$jar,$false)
  if((Get-BridgeHash $jar) -ine $bridge.jarSha256 -or (Get-BridgeHash $bridge.jarPath) -ine $bridge.jarSha256){throw 'Copia del JAR no coincide con evidencia.'}
 }
 Assert-ManagedStopped;$null=Check-ManagedBaseline
 $session=[pscustomobject]@{schemaVersion=2;spec='SPEC-005';bridgeCommit=$BridgeCommit;currentCommit=$current;backupDirectory=$BackupDirectory;backupProofSha256=$proof.proofHash;folder=$folder;jar=$jar;jarSha256=$bridge.jarSha256;bridgeEvidencePath=$bridge.path;bridgeEvidenceSha256=$bridge.sha256;catalogSha256=$bridge.catalogSha256;candidateSha256=$bridge.candidateSha256;reportHashes=$bridge.reportHashes;previousStarted=$false;previousVerified=$false;currentVerified=$false}
 Invoke-ManagedBridgeGate $bridge $session { $null=Assert-LiveManagedMode; $null=Assert-BridgeManagedPath $script:IdentityRoot $jar; $null=Assert-BridgeManagedPath $script:IdentityRoot $sessionPath $true; if((Get-BridgeHash $jar) -ine $bridge.jarSha256){throw 'Copia del JAR alterada.'}; Write-PrivateText $sessionPath ($session|ConvertTo-Json -Depth 30) }
 Write-Host 'OK: SHA/JAR reales fijados y Mongo conservado. Prepare no arranca el puente.';return
}
foreach($path in @($session.folder,$session.jar)){
 if(![IO.Path]::GetFullPath($path).StartsWith($archiveRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Sesion fuera de carpeta propia.'}
}
if((Get-BridgeHash $session.jar) -ine $session.jarSha256){throw 'JAR de sesion alterado.'}
$null=Check-ManagedSources $session.currentCommit
if($Stage -eq 'StartPrevious'){
 Assert-ManagedStopped
 if($session.previousVerified){throw 'Previous ya verificado; no reiniciar automaticamente.'}
 $null=Check-ManagedBaseline;$null=Assert-LiveManagedMode
 Invoke-ManagedBridgeGate $bridge $session {
  $null=Assert-LiveManagedMode
  $null=Assert-BridgeManagedPath $script:IdentityRoot $session.jar
  $null=Assert-BridgeManagedPath $script:IdentityRoot $sessionPath
  $jarLock=[IO.File]::Open($session.jar,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{
   if((Get-BridgeHash $session.jar) -ine $bridge.jarSha256){throw 'JAR de sesion alterado antes de arrancar.'}
   $session.previousStarted=$true;Write-PrivateText $sessionPath ($session|ConvertTo-Json -Depth 30)
   Push-Location $script:IdentityRoot
   try{& java -jar $session.jar --server.port=8082 --availability.enabled=false --reservations.enabled=false;Assert-ManagedCommand}finally{Pop-Location}
  }finally{$jarLock.Dispose()}
 }
 return
}
$owners=@(Get-NetTCPConnection -State Listen -LocalPort 8082 -ErrorAction SilentlyContinue|Select-Object -ExpandProperty OwningProcess -Unique)
if($owners.Count -ne 1){throw 'Exige una JVM en 8082.'}
$process=Get-CimInstance Win32_Process -Filter ('ProcessId='+$owners[0])
if(!$process.CommandLine){throw 'No se pudo verificar proceso.'}
$isBridge=$process.CommandLine.Contains([string]$session.jar)
if($Stage -eq 'Previous' -and (!$isBridge -or !$session.previousStarted)){throw 'No es el puente preparado.'}
if($Stage -eq 'Current' -and ($isBridge -or !$session.previousVerified)){throw 'Primero Previous, detener puente y reiniciar actual manualmente.'}
$checks=@()
$null=Assert-ManagedBridge $BridgeEvidence $session
$null=Assert-LiveManagedMode
if((Get-BridgeHash $session.jar) -ine $bridge.jarSha256){throw 'JAR de sesion alterado antes de verificar.'}
function Check-ManagedHttp([string]$Uri,[int]$Status){
 $response=Invoke-LocalHttp -Uri $Uri
 if($response.Status -ne $Status){throw ('HTTP esperado '+$Status+', recibido '+$response.Status)}
 return [pscustomobject]@{uri=$Uri;status=$Status}
}
$root='http://localhost:8082/catalog'
$checks+=@(Check-ManagedHttp ($root+'/restaurants') 200)
$expected=if($Stage -eq 'Previous'){404}else{401}
$checks+=@(Check-ManagedHttp ($root+'/restaurants/'+$script:RestaurantA+'/reservations') $expected)
# Reutilizar expectativas aceptadas de los checkpoints propios: solo GET y ETag.
if($Stage -eq 'Current'){
 $cpPath=Join-Path $script:IdentityPrivate 'reservation-confirmation-http-checkpoint.json'
 $null=Assert-BridgeManagedPath $script:IdentityPrivate $cpPath
 $cp=Get-Content $cpPath -Raw|ConvertFrom-Json
 if($cp.spec -cne 'SPEC-005' -or $null -eq $cp.final -or $cp.pendingName){throw 'Confirmacion HTTP incompleta.'}
 foreach($entry in @($cp.steps|Where-Object {$_.expected -eq 201 -and $null -ne $_.response})){
  $token=[Environment]::GetEnvironmentVariable($entry.actor,'Process')
  $claims=ConvertFrom-JwtPayload $token;Assert-ReplacementIdentity $entry.identity $claims ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
  $r=Invoke-LocalHttp -Uri ($root+'/restaurants/'+$script:RestaurantA+'/reservations/'+$entry.response.body.id) -Headers @{Authorization=('Bearer '+$token)}
  $actual=[pscustomobject]@{status=$r.Status;body=($r.Content|ConvertFrom-Json);etag=[string](@($r.Headers['ETag'])[0]);location=''}
  $intent=$entry.body|ConvertFrom-Json
  $expectation=[pscustomobject]@{restaurantId=$script:RestaurantA;reservationId=$entry.response.body.id;issuer=$entry.identity.issuer;subject=$entry.identity.subject;key=$entry.key;match='';body=$intent}
  $encoded=ConvertTo-ManagedBase64 $expectation
  $old=$OutputEncoding
  try{
   $OutputEncoding=[Text.UTF8Encoding]::new($false)
   $raw=Get-Content (Join-Path $PSScriptRoot 'mongo-cancellation-confirmation-manifest.js') -Raw|
    & docker exec -i -e ('EATS_BACKUP_DATABASE='+$database) -e ('EATS_CANCELLATION_EXPECTATIONS_BASE64='+$encoded) eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin
   Assert-ManagedCommand;$latest=($raw -join "`n")|ConvertFrom-Json
  }finally{$OutputEncoding=$old}
  if($null -eq $latest.reservationView){throw 'Reserva del ensayo ausente.'}
  $expected=[pscustomobject]@{status=200;body=$latest.reservationView;etag=('"'+$latest.reservationView.version+'"');location=''}
  Assert-CancellationStored $expected $actual
 }
}
$null=Check-ManagedBaseline;$null=Assert-LiveManagedMode
$null=Assert-ManagedBridge $BridgeEvidence $session
if((Get-BridgeHash $session.jar) -ine $bridge.jarSha256){throw 'JAR de sesion alterado antes de acreditar.'}
Invoke-ManagedBridgeGate $bridge $session {
 $null=Assert-LiveManagedMode
 $null=Assert-BridgeManagedPath $script:IdentityRoot $session.jar
 $null=Assert-BridgeManagedPath $script:IdentityRoot $sessionPath
 $null=Assert-BridgeManagedPath $script:IdentityRoot (Join-Path $session.folder ($Stage.ToLowerInvariant()+'-validation.json')) $true
 $jarLock=[IO.File]::Open($session.jar,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  if((Get-BridgeHash $session.jar) -ine $bridge.jarSha256){throw 'JAR alterado antes de registrar.'}
  $session.previousVerified=($session.previousVerified -or $Stage -eq 'Previous')
  $session.currentVerified=($Stage -eq 'Current')
  Write-PrivateText (Join-Path $session.folder ($Stage.ToLowerInvariant()+'-validation.json')) (@{stage=$Stage;checks=$checks;bridgeCommit=$BridgeCommit;jarSha256=$session.jarSha256;bridgeEvidenceSha256=$bridge.sha256;databasePreserved=$true;operatorDeclaredCurrentRestart=($Stage -eq 'Current');timestampUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 30)
  Write-PrivateText $sessionPath ($session|ConvertTo-Json -Depth 30)
 }finally{$jarLock.Dispose()}
}
Write-Host 'OK: etapa verificada, manifiesto completo/politica/indices/recibos conservados. Sin cierre automatico.'
}
if($MyInvocation.InvocationName -ne '.') { Invoke-ManagedRollback }
