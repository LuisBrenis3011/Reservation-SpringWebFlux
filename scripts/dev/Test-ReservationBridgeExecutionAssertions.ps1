# Ensayo de orquestacion con todas las fronteras sustituidas. No ejecuta Docker,
# HTTP, Gradle, servicios ni scripts operativos. Fixtures exclusivamente sinteticas.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Prepare-LocalReservationBridge.ps1')
$script:ExecutionTrace=[Collections.Generic.List[string]]::new()
$script:ObserverFailure=$false
function Assert-BridgeCandidate { }
function Assert-BridgeIsolation { param($Isolation,[string]$Root);$script:ExecutionTrace.Add('validate-isolation') }
function New-SyntheticPassedCases([string]$Group) {
    foreach($case in @(New-BridgeUnexecutedCases $Group 'fixture')) {
        $case.actual=$case.expected;$case.passed=$true;$case.executionStatus='Passed';$case
    }
}
function Invoke-BridgeExportedAssertions {
    param($BridgeCandidate,[string]$Root)
    $script:ExecutionTrace.Add('source')
    return [pscustomobject]@{status='Passed';cases=@(New-SyntheticPassedCases 'legacyBarrierVerified' | Where-Object {$_.level -ceq 'SOURCE_EXPORTED'});attachments=@()}
}
function Invoke-BridgeC1Catalog {
    param($Context)
    $script:ExecutionTrace.Add('c1')
    return [pscustomobject]@{groups=@{rollbackControlsVerified=@(New-SyntheticPassedCases 'rollbackControlsVerified')};attachments=@()}
}
function Invoke-BridgeEnvironment {
    param($CandidateValue,[string]$Root,$Images,[string]$Actor,[string]$AttemptDirectory)
    $script:ExecutionTrace.Add('environment')
    return [pscustomobject]@{directory=$AttemptDirectory;root=$Root;observationReady=$false;Observation=$null}
}
function Start-BridgeObservation {
    param($Context)
    $script:ExecutionTrace.Add('observer')
    if($script:ObserverFailure){throw 'Autocomprobacion sintetica fallida'}
    return [pscustomobject]@{synthetic=$true}
}
function Invoke-BridgeHttpCatalog {
    param($Context,$Observation)
    if(-not $Context.observationReady){throw 'JAR antes del observador'}
    $script:ExecutionTrace.Add('http')
    $groups=@{}
    foreach($g in @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified')){
        $groups[$g]=@(New-SyntheticPassedCases $g | Where-Object {$_.level -cne 'SOURCE_EXPORTED'})
    }
    return [pscustomobject]@{groups=$groups;attachments=@()}
}
function Stop-BridgeEnvironmentApplication { param($Context);$script:ExecutionTrace.Add('stop-java') }
function Complete-BridgeObservation {
    param($Observation,$Context)
    $script:ExecutionTrace.Add('complete')
    return [pscustomobject]@{kind='synthetic-isolation';status='Passed'}
}
function Stop-BridgeObservation { param($Observation,$Context);$script:ExecutionTrace.Add('stop-observer') }
function Stop-BridgeEnvironment { param($Context);$script:ExecutionTrace.Add('stop-environment') }
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('bridge-execution-synthetic-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixtureRoot
$candidateFixture=[pscustomobject]@{runId='synthetic';commit=('a'*40);jarSha256=('b'*64)}
$fixturePath=Join-Path $fixtureRoot 'candidate.json'
Write-BridgeNewJson $fixturePath $candidateFixture
$fixtureHash=Get-BridgeHash $fixturePath
$catalogFixture=Join-Path $fixtureRoot 'catalog.md'
[IO.File]::WriteAllText($catalogFixture,'catalogo sintetico',[Text.UTF8Encoding]::new($false))
$result=Invoke-BridgeVerificationExecution $candidateFixture $fixtureHash $fixtureRoot ([pscustomobject]@{}) 'tester' $catalogFixture
if($result.status -cne 'Passed' -or $result.reports.Count -ne 4){throw 'Orquestacion sintetica incompleta'}
$trace=$script:ExecutionTrace -join ','
if($trace -cne 'source,c1,environment,observer,http,stop-java,complete,validate-isolation,stop-observer,stop-environment'){throw "Orden incorrecto: $trace"}
foreach($ref in $result.reports){
    $report=Read-BridgeJson $fixtureRoot $ref.path $ref.sha256
    if($report.cases.Count -ne (Get-BridgeCases $ref.groupId).Count){throw 'Catalogo incompleto'}
}
$script:ExecutionTrace.Clear();$script:ObserverFailure=$true
$failed=Invoke-BridgeVerificationExecution $candidateFixture $fixtureHash $fixtureRoot ([pscustomobject]@{}) 'tester' $catalogFixture
if($failed.status -cne 'Failed' -or $script:ExecutionTrace.Contains('http')){throw 'Se ejecuto HTTP pese a autocomprobacion fallida'}
if(-not $script:ExecutionTrace.Contains('stop-environment')){throw 'No se detuvieron recursos propios'}
foreach($ref in $failed.reports|Where-Object{$_.groupId -cne 'rollbackControlsVerified'}){
    if($ref.status -ceq 'Passed'){throw 'Grupo HTTP aprobado sin aislamiento'}
}
if(Test-Path -LiteralPath (Join-Path $fixtureRoot 'bridge-evidence.json')){throw 'Se produjo Review incidentalmente'}
Write-Host 'OK: orquestacion sintetica completa y aborto antes HTTP. No acredita aislamiento real.'
Write-Host "Fixtures conservadas: $fixtureRoot"
