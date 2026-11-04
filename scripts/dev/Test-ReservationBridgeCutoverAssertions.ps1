# Dobles locales: no se ejecutan Docker, HTTP, servicios ni corte.
$ErrorActionPreference='Stop'
$cutoverFixtureRoot=& { . (Join-Path $PSScriptRoot 'Test-ReservationBridgeReviewAssertions.ps1');$reviewFixtureRoot }
. (Join-Path $PSScriptRoot 'Set-LocalReservationCutover.ps1') -BackupDirectory 'unused' -BridgeEvidence 'unused'
$script:BridgeCutoverCatalogPath=Join-Path $cutoverFixtureRoot 'catalog.md'
$script:BridgeCutoverScriptRoot=Join-Path $cutoverFixtureRoot 'current-scripts'
$script:CutoverCalls=[ordered]@{network=0;environment=0;http=0;docker=0;writes=0}
function Get-NetTCPConnection { $script:CutoverCalls.network++;throw 'ACCESO_NO_PERMITIDO_NET' }
function Read-LocalEnv { $script:CutoverCalls.environment++;throw 'ACCESO_NO_PERMITIDO_ENV' }
function docker { $script:CutoverCalls.docker++;throw 'ACCESO_NO_PERMITIDO_DOCKER' }
function Invoke-RestMethod { $script:CutoverCalls.http++;throw 'ACCESO_NO_PERMITIDO_HTTP' }
function Invoke-WebRequest { $script:CutoverCalls.http++;throw 'ACCESO_NO_PERMITIDO_HTTP' }
$evidenceFile=Join-Path $cutoverFixtureRoot 'bridge-evidence.json'
$originalEvidence=[IO.File]::ReadAllBytes($evidenceFile)
function Restore-CutoverEvidence { [IO.File]::WriteAllBytes($evidenceFile,$originalEvidence) }
function Write-CutoverFixture($Value) {
    [IO.File]::WriteAllText($evidenceFile,($Value|ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($false))
}
function Expect-CutoverBlocked([string]$Label) {
    $failed=$false
    try{Invoke-ReservationCutover 'unused' $evidenceFile $true $true}catch{
        if($_.Exception.Message -match 'ACCESO_NO_PERMITIDO'){throw "Se accedio al origen en $Label"}
        $failed=$true
    }
    if(-not $failed){throw "Evidencia invalida aceptada: $Label"}
    foreach($key in $script:CutoverCalls.Keys){if($script:CutoverCalls[$key] -ne 0){throw "Acceso incidental en $Label : $key"}}
}
$baseline=Get-Content -LiteralPath $evidenceFile -Raw -Encoding UTF8
foreach($bad in @($false,'true','false',0,1,$null)){
    $value=$baseline|ConvertFrom-Json;$value.legacyReadsAuthorized=$bad;Write-CutoverFixture $value
    Expect-CutoverBlocked 'booleano invalido'
}
$value=$baseline|ConvertFrom-Json;$value.schemaVersion=1;Write-CutoverFixture $value
Expect-CutoverBlocked 'schema antiguo'
$value=$baseline|ConvertFrom-Json;$value.author='';Write-CutoverFixture $value
Expect-CutoverBlocked 'revisor ausente'
$value=$baseline|ConvertFrom-Json;$value.reports=@($value.reports|Select-Object -First 3);Write-CutoverFixture $value
Expect-CutoverBlocked 'grupo faltante'
$value=$baseline|ConvertFrom-Json;$value.reports[1]=$value.reports[0];Write-CutoverFixture $value
Expect-CutoverBlocked 'grupo duplicado'
$value=$baseline|ConvertFrom-Json;$value.commit='c'*40;Write-CutoverFixture $value
Expect-CutoverBlocked 'commit distinto'
Restore-CutoverEvidence
$fixtureJar=Join-Path $cutoverFixtureRoot 'candidate.jar';$jarBytes=[IO.File]::ReadAllBytes($fixtureJar)
[IO.File]::WriteAllText($fixtureJar,'JAR alterado')
Expect-CutoverBlocked 'JAR alterado'
[IO.File]::WriteAllBytes($fixtureJar,$jarBytes)
$operationalScript=Join-Path $script:BridgeCutoverScriptRoot 'ManagedReservations.Common.ps1'
$scriptBytes=[IO.File]::ReadAllBytes($operationalScript)
[IO.File]::WriteAllText($operationalScript,'script C1 modificado')
Expect-CutoverBlocked 'script C1 modificado'
[IO.File]::WriteAllBytes($operationalScript,$scriptBytes)
$initial=Assert-CutoverBridgeEvidence $evidenceFile
# Simula que el preflight pudo leer origen y evidencia cambia antes de Apply.
$script:CutoverCalls.network=1
[IO.File]::AppendAllText($evidenceFile,' ')
$failed=$false
try{Invoke-CutoverApplyGate $initial {$script:CutoverCalls.writes++}}catch{$failed=$true}
if(-not $failed -or $script:CutoverCalls.writes -ne 0){throw 'Apply alcanzo escritura con evidencia modificada.'}
Restore-CutoverEvidence
$script:CutoverCalls.network=0
$catalogOriginal=[IO.File]::ReadAllBytes($script:BridgeCutoverCatalogPath)
$initial=Assert-CutoverBridgeEvidence $evidenceFile
[IO.File]::AppendAllText($script:BridgeCutoverCatalogPath,' cambiado')
$failed=$false
try{Invoke-CutoverApplyGate $initial {$script:CutoverCalls.writes++}}catch{$failed=$true}
if(-not $failed -or $script:CutoverCalls.writes -ne 0){throw 'Apply alcanzo escritura con catalogo modificado.'}
[IO.File]::WriteAllBytes($script:BridgeCutoverCatalogPath,$catalogOriginal)
$initial=Assert-CutoverBridgeEvidence $evidenceFile
Invoke-CutoverApplyGate $initial {
    $blocked=$false
    try{[IO.File]::AppendAllText($evidenceFile,' intento de mutacion')}catch{$blocked=$true}
    if(-not $blocked){throw 'La evidencia pudo cambiar durante Apply.'}
    $script:CutoverCalls.writes++
}
if($script:CutoverCalls.writes -ne 1){throw 'El doble no alcanzo Apply con evidencia sintetica valida.'}
Write-Host 'OK: evidencia v2 sintetica antes de origen y nueva validacion antes de Apply; no acredita corte real.'
Write-Host "Fixtures conservadas: $cutoverFixtureRoot"
