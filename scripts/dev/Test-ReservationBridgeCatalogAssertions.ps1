$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReservationBridge.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Catalog.ps1')
# Fronteras externas bloqueadas: estas comprobaciones son puras.
function docker { throw 'NO_DEBE_INVOCARSE_DOCKER' }
function Invoke-WebRequest { throw 'NO_DEBE_INVOCARSE_HTTP' }
function Invoke-RestMethod { throw 'NO_DEBE_INVOCARSE_HTTP' }
function Write-BridgeNewJson([string]$Path,$Value) {
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 40))
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew)
    try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
}
function Get-BridgeHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
$a='{"one":1,"two":[true,null,"x"]}'|ConvertFrom-Json
$b='{"two":[true,null,"x"],"one":1}'|ConvertFrom-Json
if (-not (Test-BridgeJsonEqual $a $b)) { throw 'Orden de propiedades no debe cambiar la igualdad.' }
$b.two=@($null,$true,'x')
if (Test-BridgeJsonEqual $a $b) { throw 'Orden de arreglo debe conservarse.' }
$errorResponse='{"status":404,"body":{"code":"NOT_FOUND","message":"NOT_FOUND","status":404,"operationId":"synthetic","timestamp":"2026-01-01T00:00:00Z"}}'|ConvertFrom-Json
if (-not (Test-BridgeCatalogError $errorResponse 404 'NOT_FOUND')) { throw 'Error contractual rechazado.' }
$errorResponse.body|Add-Member -NotePropertyName notes -NotePropertyValue 'privado'
if (Test-BridgeCatalogError $errorResponse 404 'NOT_FOUND') { throw 'Fuga de reserva en error aceptada.' }
$errorResponse.body.PSObject.Properties.Remove('notes')
$errorResponse.body.PSObject.Properties.Remove('status')
if (Test-BridgeCatalogError $errorResponse 404 'NOT_FOUND') { throw 'Error incompleto aceptado.' }
if ($null -ne (Get-BridgeSanitizedEtag 'texto-privado')) { throw 'ETag ajeno persistido.' }
$expected=[pscustomobject]@{version=3;kind='MANAGED';status='CANCELLED'}
$response=[pscustomobject]@{status=200;etag='"3"';body=$expected.PSObject.Copy()}
if (-not (Test-BridgeManagedResponse $response $expected)) { throw 'Proyeccion exacta rechazada.' }
$response.etag='W/"3"'
if (Test-BridgeManagedResponse $response $expected) { throw 'ETag debil aceptado.' }
$folder=Join-Path ([IO.Path]::GetTempPath()) ('bridge-catalog-synthetic-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $folder
$ctx=[pscustomobject]@{root=$folder;directory=$folder;runId='synthetic'}
$c1=Invoke-BridgeC1Catalog $ctx
$cases=$c1.groups['rollbackControlsVerified']
if ($cases.Count -ne 54) { throw 'Catalogo C1 incompleto.' }
foreach($case in $cases) {
    if ($case.level -cne 'SYNTHETIC' -or $case.passed -isnot [bool]) { throw 'Tipo o nivel C1 invalido.' }
    if($case.executionStatus -cne 'Passed' -or -not $case.passed -or -not $case.executed){throw ('Caso C1 no acreditado: '+$case.id+'; estado='+$case.executionStatus+'; detalle='+($case.observed|ConvertTo-Json -Depth 10 -Compress)+'; motivo='+$case.actual+'; fixtures='+$folder)}
}
$cut=@($cases | Where-Object {$_.id -ceq 'C1-DEFAULT-STARTPREVIOUS-CUT'})[0]
if (-not $cut.observed.sessionPreserved -or $cut.observed.blockedActions -ne 0 -or $cut.observed.policyReads -ne 1) { throw 'Entrada real no bloqueo tras corte.' }
$noCut=@($cases | Where-Object {$_.id -ceq 'C1-DEFAULT-PREPARE-NOCUT'})[0]
if (-not $noCut.passed -or $noCut.observed.policyReads -ne 1 -or $noCut.observed.rejection -notlike '*Ya existe una sesion*') { throw 'Entrada real no conservo elegibilidad sin corte.' }
$managedNoCut=@($cases | Where-Object {$_.id -ceq 'C1-MANAGED-PREPARE-NOCUT'})[0]
if (-not $managedNoCut.observed.unchanged -or $managedNoCut.observed.failure -notlike '*exige corte persistente*') { throw 'La etapa gestionada sin corte no rechazo con fixture intacta.' }
$race=@($cases | Where-Object {$_.id -ceq 'C1-RACE-DEFAULT'})[0]
if (-not $race.observed.prepared -or -not $race.observed.positiveStart -or -not $race.observed.sessionPreserved -or $race.observed.java -ne 0 -or $race.observed.build -ne 0) { throw 'Entrada historica no bloqueo la transicion.' }
foreach($case in @($cases|Where-Object {$_.id -cmatch '^C1-MANAGED-.*-(NOCUT|READFAIL)$'})){
    if(-not $case.observed.unchanged -or $case.observed.java -ne 0 -or $case.observed.git -ne 0 -or $case.observed.http -ne 0 -or $case.observed.forbidden -ne 0){throw 'Accion alcanzada en rechazo gestionado.'}
}
$current=@($cases|Where-Object {$_.id -ceq 'C1-MANAGED-CURRENT-CUT'})[0]
if($current.observed.http -ne 3 -or $current.observed.manifestReads -lt 3){throw 'Current no ejercito GET, ETag y manifiestos sinteticos.'}
$history=@($cases|Where-Object {$_.id -ceq 'C1-SESSION-HISTORY'})[0]
if(@($history.observed.modes).Count -ne 3 -or @($history.observed.modes|Where-Object {-not $_.sessionPreserved}).Count){throw 'Sesion historica no conservada en todos los modos.'}
foreach($name in @('BridgeC1SyntheticProbe','BridgeC1StageProbe','BridgeC1HistoryProbe')){if($null -ne (Get-Variable $name -Scope Global -ErrorAction SilentlyContinue)){throw 'Sonda global C1 no liberada.'}}
Write-Host 'OK: 54 casos C1 con controles reales y transportes sinteticos; no acredita HTTP/JAR, aislamiento ni reversion reales.'
Write-Host "Fixtures conservadas: $folder"
