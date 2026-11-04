$ErrorActionPreference='Stop'
# Reutilizar la cadena sintetica del comparador, en scope separado para evitar
# colisiones con parametros tipados del punto de entrada. No se ejecutan servicios.
$reviewFixtureRoot=& { . (Join-Path $PSScriptRoot 'Test-ReservationBridgeAssertions.ps1');$testRoot }
. (Join-Path $PSScriptRoot 'Prepare-LocalReservationBridge.ps1')
function docker { throw 'NO_DEBE_INVOCARSE_DOCKER' }
function gradle { throw 'NO_DEBE_INVOCARSE_GRADLE' }
function java { throw 'NO_DEBE_INVOCARSE_JAVA' }
function Invoke-BridgeGit { throw 'NO_DEBE_INVOCARSE_GIT' }
function Invoke-WebRequest { throw 'NO_DEBE_INVOCARSE_HTTP' }
function Invoke-RestMethod { throw 'NO_DEBE_INVOCARSE_HTTP' }
function Start-Process { throw 'NO_DEBE_ARRANCARSE_PROCESO' }
function Set-ReviewFixture([string]$Name,$Value) {
    $path=Join-Path $reviewFixtureRoot $Name
    [IO.File]::WriteAllText($path,($Value|ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($false))
    return Get-BridgeHash $path
}
function Read-ReviewFixture([string]$Name){return Get-Content -LiteralPath (Join-Path $reviewFixtureRoot $Name) -Raw -Encoding UTF8|ConvertFrom-Json}
function Expect-ReviewRejection([scriptblock]$Action,[string]$Reason){
    $message=$null;try{& $Action}catch{$message=$_.Exception.Message}
    if($null -eq $message -or $message -notmatch $Reason){throw "Rechazo inesperado: $message; esperado: $Reason"}
    if(Test-Path -LiteralPath (Join-Path $reviewFixtureRoot 'bridge-evidence.json')){throw 'Se publico Review tras rechazo.'}
}
$currentScripts=Join-Path $reviewFixtureRoot 'current-scripts'
$snapshots=Join-Path $reviewFixtureRoot 'scripts'
$null=New-Item -ItemType Directory -Path $currentScripts
$null=New-Item -ItemType Directory -Path $snapshots
$scriptReferences=@()
foreach($name in @('ManagedReservations.Common.ps1','Test-LocalMongoRestore.ps1','Test-LocalVersionRollback.ps1','Test-LocalManagedReservationRollback.ps1','read-managed-reservation-policy.js','LocalIdentity.Common.ps1','ReservationReplacement.Assertions.ps1','ReservationCancellation.Assertions.ps1','ReservationBridge.Catalog.ps1','ReservationBridge.C1Stages.ps1','ReservationBridge.C1Remaining.ps1','mongo-backup-manifest.js','mongo-cancellation-confirmation-manifest.js','ReservationBridge.Common.ps1','ReservationBridge.Execution.ps1','ReservationBridge.Observation.ps1','ReservationBridge.Environment.ps1','ReservationBridge.Isolation.ps1','ReservationBridge.Runtime.ps1','bridge/bridge_observer.py','bridge/bridge_trace.py','bridge/bridge_probe.py','bridge/bridge_sentinel.py','bridge/observer-seccomp.json')){
    $text='Fixture sintetica de script '+$name
    if($name -ceq 'bridge/observer-seccomp.json'){$text=Get-Content -LiteralPath (Join-Path $PSScriptRoot $name) -Raw}
    foreach($parent in @((Split-Path -Parent (Join-Path $currentScripts $name)),(Split-Path -Parent (Join-Path $snapshots $name)))){[IO.Directory]::CreateDirectory($parent)|Out-Null}
    [IO.File]::WriteAllText((Join-Path $currentScripts $name),$text)
    [IO.File]::WriteAllText((Join-Path $snapshots $name),$text)
    $scriptReferences+=@{path=('scripts/'+$name);sha256=(Get-BridgeHash (Join-Path $snapshots $name))}
}
$before=@{startedUtc='2026-01-01T00:00:00.5Z';finishedUtc='2026-01-01T00:00:00.8Z';connected=$true;acknowledged=$true;correlationId='positive-before-synthetic'}
$after=@{startedUtc='2026-01-01T00:00:02.1Z';finishedUtc='2026-01-01T00:00:02.2Z';connected=$true;acknowledged=$true;correlationId='positive-after-synthetic'}
$probe=@{startedUtc='2026-01-01T00:00:01.5Z';finishedUtc='2026-01-01T00:00:02Z';connected=$false;acknowledged=$false;errorCode=101;correlationId='synthetic';address='192.0.2.1';port=9}
$proof=@{blocked=$true;runId='synthetic';correlationId='synthetic';sentinelInspectionId='sentinel';independence='Fixtures de sonda y servidor independientes de captura';positiveBefore=$before;positiveAfter=$after;probe=$probe;listenerRecords=@(@{correlationId=$before.correlationId},@{correlationId=$after.correlationId})}
$proofHash=Set-ReviewFixture 'proof.json' $proof
$sentinel=Read-ReviewFixture 'sentinel.json';$sentinel.records[0].proofRef.sha256=$proofHash
$sentinelHash=Set-ReviewFixture 'sentinel.json' $sentinel
$isolation=Read-ReviewFixture 'isolation.json';$isolation.sentinelProof.sha256=$sentinelHash;$isolation.preflightFinishedUtc='2026-01-01T00:00:02.5Z'
$isoHash=Set-ReviewFixture 'isolation.json' $isolation
$reportNames=@('legacyReadsAuthorized.json','v2ReadsVerified.json','legacyBarrierVerified.json','rollbackControlsVerified.json')
foreach($name in $reportNames){
    $report=Read-ReviewFixture $name;$report.scriptHashes=$scriptReferences;$report.isolation.sha256=$isoHash
    $null=Set-ReviewFixture $name $report
}
$candidateFile=Join-Path $reviewFixtureRoot 'candidate.json'
$reviewCatalog=Join-Path $reviewFixtureRoot 'catalog.md'
$call={Invoke-BridgeReview $candidateFile $reportNames 'reviewer' $reviewCatalog $currentScripts}
Expect-ReviewRejection {Invoke-BridgeReview $candidateFile $reportNames '' $reviewCatalog $currentScripts} 'ReviewedBy'
Expect-ReviewRejection {Invoke-BridgeReview $candidateFile @($reportNames[0]) 'reviewer' $reviewCatalog $currentScripts} 'cuatro reportes'
Expect-ReviewRejection {Invoke-BridgeReview $candidateFile @($reportNames[0],$reportNames[0],$reportNames[2],$reportNames[3]) 'reviewer' $reviewCatalog $currentScripts} 'duplicado'
$c1Report=Read-ReviewFixture $reportNames[3]
$c1Report.scriptHashes=@($c1Report.scriptHashes|Where-Object {$_.path -cne 'scripts/ReservationBridge.C1Remaining.ps1'})
$null=Set-ReviewFixture $reportNames[3] $c1Report
Expect-ReviewRejection $call 'Falta script operativo C1 evaluado'
$c1Report.scriptHashes=$scriptReferences;$null=Set-ReviewFixture $reportNames[3] $c1Report
$httpReport=Read-ReviewFixture $reportNames[0]
$httpReport.scriptHashes=@($scriptReferences|Where-Object {$_.path -cne 'scripts/bridge/bridge_trace.py'})
$null=Set-ReviewFixture $reportNames[0] $httpReport
Expect-ReviewRejection $call 'Falta script de aislamiento evaluado'
$httpReport.scriptHashes=$scriptReferences;$null=Set-ReviewFixture $reportNames[0] $httpReport
foreach($missing in @('mongo-backup-manifest.js','mongo-cancellation-confirmation-manifest.js')){
    $c1Report.scriptHashes=@($scriptReferences|Where-Object {$_.path -cne ('scripts/'+$missing)})
    $null=Set-ReviewFixture $reportNames[3] $c1Report
    Expect-ReviewRejection $call 'Falta script operativo C1 evaluado'
}
$c1Report.scriptHashes=$scriptReferences;$null=Set-ReviewFixture $reportNames[3] $c1Report
foreach($manifestName in @('mongo-backup-manifest.js','mongo-cancellation-confirmation-manifest.js')){
    $manifestPath=Join-Path $currentScripts $manifestName
    $manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
    try{[IO.File]::AppendAllText($manifestPath,' alterado');Expect-ReviewRejection $call 'Script actual distinto'}finally{[IO.File]::WriteAllBytes($manifestPath,$manifestBytes)}
}
$jarFixture=Join-Path $reviewFixtureRoot 'candidate.jar'
$savedJar=[IO.File]::ReadAllBytes($jarFixture)
[IO.File]::WriteAllText($jarFixture,'JAR reconstruido aunque conserve commit')
Expect-ReviewRejection $call 'Hash de archivo no coincide'
[IO.File]::WriteAllBytes($jarFixture,$savedJar)
$report=Read-ReviewFixture $reportNames[3]
foreach($status in @('Pending','Failed')){
    $report.status=$status;$null=Set-ReviewFixture $reportNames[3] $report
    Expect-ReviewRejection $call 'Reporte invalido'
}
$report.status='Passed';$report.cases[0].passed='true';$null=Set-ReviewFixture $reportNames[3] $report
Expect-ReviewRejection $call 'Booleano verdadero requerido'
$report.cases[0].passed=$true;$null=Set-ReviewFixture $reportNames[3] $report
$changedScript=Join-Path $currentScripts 'ManagedReservations.Common.ps1'
$savedScript=[IO.File]::ReadAllText($changedScript);[IO.File]::WriteAllText($changedScript,'alterado')
Expect-ReviewRejection $call 'Script actual distinto'
[IO.File]::WriteAllText($changedScript,$savedScript)
$proof.probe.connected=$true;$proofHash=Set-ReviewFixture 'proof.json' $proof
$sentinel.records[0].proofRef.sha256=$proofHash;$sentinelHash=Set-ReviewFixture 'sentinel.json' $sentinel
$isolation.sentinelProof.sha256=$sentinelHash;$isoHash=Set-ReviewFixture 'isolation.json' $isolation
foreach($name in $reportNames){$r=Read-ReviewFixture $name;$r.isolation.sha256=$isoHash;$null=Set-ReviewFixture $name $r}
Expect-ReviewRejection $call 'conexion bloqueada'
$proof.probe.connected=$false;$proofHash=Set-ReviewFixture 'proof.json' $proof
$sentinel.records[0].proofRef.sha256=$proofHash;$sentinelHash=Set-ReviewFixture 'sentinel.json' $sentinel
$isolation.sentinelProof.sha256=$sentinelHash;$isoHash=Set-ReviewFixture 'isolation.json' $isolation
foreach($name in $reportNames){$r=Read-ReviewFixture $name;$r.isolation.sha256=$isoHash;$null=Set-ReviewFixture $name $r}
# Interrupcion durante staging: nunca publica el nombre definitivo.
$script:ReviewBaseWriter=(Get-Command Write-BridgeNewJson).ScriptBlock
function Write-BridgeNewJson([string]$Path,$Value){
    if($Path.EndsWith('.tmp')){[IO.File]::WriteAllText($Path,'{');throw 'Interrupcion sintetica de staging'}
    & $script:ReviewBaseWriter $Path $Value
}
Expect-ReviewRejection $call 'Interrupcion sintetica'
Set-Item -Path Function:Write-BridgeNewJson -Value $script:ReviewBaseWriter
$result=& $call
$review=Read-BridgeJson $reviewFixtureRoot 'bridge-evidence.json' $result.sha256
Assert-BridgeEvidence $reviewFixtureRoot 'bridge-evidence.json' $result.sha256 $reviewCatalog (Get-BridgeHash $reviewCatalog)
foreach($group in @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified','rollbackControlsVerified')){Assert-BridgeTrue $review.$group $group}
$originalHash=$result.sha256
$rejected=$false;try{& $call}catch{if($_.Exception.Message -notmatch 'No se sobrescribe'){throw};$rejected=$true}
if(-not $rejected -or (Get-BridgeHash $result.path) -ine $originalHash){throw 'Review existente fue sobrescrito'}
Write-Host 'OK: productor Review sintetico; no acredita aislamiento real, corte ni aprobacion de spec.'
Write-Host "Fixtures conservadas: $reviewFixtureRoot"
