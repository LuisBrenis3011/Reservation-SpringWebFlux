# Dobles locales: no ejecutan Mongo, HTTP, Git, Docker ni JVM.
$ErrorActionPreference='Stop'
$rollbackCompleted=$false
$rollbackFailed=$false
try {
$fixtureRoot=& { . (Join-Path $PSScriptRoot 'Test-ReservationBridgeReviewAssertions.ps1'); $reviewFixtureRoot }
Write-Host 'Reversion sintetica: fixtures de Review preparadas; cargando el consumidor.'
. (Join-Path $PSScriptRoot 'Test-LocalManagedReservationRollback.ps1') -Stage Prepare
Write-Host 'Reversion sintetica: consumidor cargado; iniciando comprobaciones.'
$script:ManagedBridgeCatalog=Join-Path $fixtureRoot 'catalog.md'
$script:ManagedBridgeScripts=Join-Path $fixtureRoot 'current-scripts'
$script:IdentityRoot=Join-Path $fixtureRoot 'rollback-root'
$script:IdentityPrivate=Join-Path $script:IdentityRoot 'secrets/local-identity'
[IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
$evidenceFile=Join-Path $fixtureRoot 'bridge-evidence.json'
$BridgeEvidence=$evidenceFile;$BridgeCommit='';$BackupDirectory='unused';$WritersStopped=$true
$bridge=Assert-ManagedBridge $evidenceFile
$folder=Join-Path $script:IdentityRoot 'backups/managed-rollback/synthetic'
[IO.Directory]::CreateDirectory($folder)|Out-Null
$jar=Join-Path $folder 'bridge-certified.jar'
[IO.File]::Copy($bridge.jarPath,$jar,$false)
$sessionPath=Join-Path $script:IdentityPrivate 'managed-reservations-rollback-session.json'
$session=[pscustomobject]@{schemaVersion=2;spec='SPEC-005';bridgeCommit=$bridge.commit;currentCommit=('a'*40);backupDirectory='unused';backupProofSha256=('a'*64);folder=$folder;jar=$jar;jarSha256=$bridge.jarSha256;bridgeEvidencePath=$bridge.path;bridgeEvidenceSha256=$bridge.sha256;catalogSha256=$bridge.catalogSha256;candidateSha256=$bridge.candidateSha256;reportHashes=$bridge.reportHashes;previousStarted=$false;previousVerified=$false;currentVerified=$false}
function Save-RollbackFixture { [IO.File]::WriteAllText($sessionPath,($session|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false)) }
$script:RollbackCalls=0
function Initialize-ManagedMode { $script:RollbackCalls++;throw 'DOBLE_ORIGEN_ALCANZADO' }
function Expect-RollbackEarlyRejection([string]$Label){
 $failed=$false
 try{Invoke-ManagedRollback}catch{
  if($_.Exception.Message -match 'DOBLE_ORIGEN_ALCANZADO'){throw "Se alcanzo origen con $Label"}
  $failed=$true
 }
 if(!$failed -or $script:RollbackCalls -ne 0){throw "No se rechazo antes del origen: $Label"}
}
Save-RollbackFixture
foreach($Stage in @('StartPrevious','Previous','Current')){
 $original=[IO.File]::ReadAllBytes($evidenceFile)
 [IO.File]::AppendAllText($evidenceFile,' ')
 Expect-RollbackEarlyRejection "$Stage evidencia cambiada"
 [IO.File]::WriteAllBytes($evidenceFile,$original)
 $originalJar=[IO.File]::ReadAllBytes($jar)
 [IO.File]::WriteAllText($jar,'otro JAR para el mismo commit')
 Expect-RollbackEarlyRejection "$Stage JAR de sesion cambiado"
 [IO.File]::WriteAllBytes($jar,$originalJar)
}
$Stage='StartPrevious';$session.schemaVersion=1;Save-RollbackFixture
Expect-RollbackEarlyRejection 'sesion anterior'
$session.schemaVersion=2;Save-RollbackFixture
$Stage='Prepare';Move-Item -LiteralPath $sessionPath -Destination ($sessionPath+'.fixture')
$BridgeCommit='b'*40
Expect-RollbackEarlyRejection 'commit distinto'
$BridgeCommit=''
$originalJar=[IO.File]::ReadAllBytes($bridge.jarPath)
[IO.File]::WriteAllText($bridge.jarPath,'otro JAR para el mismo commit')
Expect-RollbackEarlyRejection 'JAR certificado cambiado'
[IO.File]::WriteAllBytes($bridge.jarPath,$originalJar)
$operational=Join-Path $script:ManagedBridgeScripts 'ManagedReservations.Common.ps1'
$originalScript=[IO.File]::ReadAllBytes($operational)
[IO.File]::AppendAllText($operational,' cambio')
Expect-RollbackEarlyRejection 'helper C1 cambiado'
[IO.File]::WriteAllBytes($operational,$originalScript)
$reportFile=Join-Path $fixtureRoot $bridge.reportHashes[0].path
$originalReport=[IO.File]::ReadAllBytes($reportFile)
[IO.File]::AppendAllText($reportFile,' ')
Expect-RollbackEarlyRejection 'reporte alterado'
[IO.File]::WriteAllBytes($reportFile,$originalReport)
$bridge=Assert-ManagedBridge $evidenceFile
$script:GateActions=0
Invoke-ManagedBridgeGate $bridge $null { $script:GateActions++ }
if($script:GateActions -ne 1){throw 'Cadena sintetica valida no alcanzo el doble.'}
[IO.File]::AppendAllText($evidenceFile,' ')
$failed=$false;try{Invoke-ManagedBridgeGate $bridge $null {$script:GateActions++}}catch{$failed=$true}
if(!$failed -or $script:GateActions -ne 1){throw 'Cambio entre validacion y accion no bloqueado.'}
function Read-ManagedPolicy { if($script:PolicyFailure){throw 'lector sintetico fallido'};return $script:PolicyValue }
foreach($stageName in @('Prepare','StartPrevious','Previous','Current')){
 foreach($mode in @('Default','IncludeCombinations','IncludeShifts','Managed')){
  $script:ManagedMode=($mode -eq 'Managed');$script:ManagedExpectedRetired=$null
  foreach($state in @('active','retired','failed')){
   $script:PolicyFailure=($state -eq 'failed')
   $script:PolicyValue=[pscustomobject]@{verified=$true;retired=($state -eq 'retired')}
   $actions=0;$rejected=$false
   try{ $null=Assert-LiveManagedMode; $actions++ }catch{ $rejected=$true }
   $shouldReject=($state -eq 'failed' -or ($state -eq 'retired' -and $mode -ne 'Managed'))
   if($rejected -ne $shouldReject -or $actions -ne [int](!$shouldReject)){throw "C1 inconsistente: $stageName $mode $state"}
  }
 }
}
$script:ManagedMode=$false;$script:ManagedExpectedRetired=$false;$script:PolicyFailure=$false
$script:PolicyValue=[pscustomobject]@{verified=$true;retired=$true}
$actions=0;try{$null=Assert-LiveManagedMode;$actions++}catch{}
if($actions -ne 0){throw 'Corte entre etapas no fue bloqueado.'}
$rollbackCompleted=$true
Write-Host 'OK: cadena, sesiones y JAR sinteticos; no acredita Mongo, arranque ni reversion real.'
Write-Host "Fixtures conservadas: $fixtureRoot"
} catch {
 $rollbackFailed=$true
 throw
} finally {
 if(-not $rollbackCompleted -and -not $rollbackFailed){throw 'La comprobacion de reversion termino antes de completar sus casos.'}
}
