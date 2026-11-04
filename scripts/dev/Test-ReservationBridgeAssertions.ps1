# Comprobaciones puras; no conectan a servicios ni generan evidencia del puente.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ReservationBridge.Common.ps1')

function Expect-Failure([scriptblock]$Action, [string]$Label, [string]$Expected = '') {
    $causes = @{
        'booleano invalido'='Booleano verdadero requerido'; 'caso ausente'='Faltan casos'
        'caso duplicado'='Caso duplicado o desconocido'; 'nivel invalido'='Nivel incorrecto'
        'booleano string'='Booleano verdadero requerido'; 'grupo desconocido'='Grupo desconocido'
        'fecha invalida'='Fecha UTC invalida'; 'hash invalido'='SHA256 invalido'
        'ruta exterior'='Ruta no permitida'; 'autor ausente'='Texto invalido'
        'bandera string'='Booleano verdadero requerido'; 'commit distinto'='Candidato distinto'
        'grupo duplicado'='Grupo repetido o desconocido'; 'aislamiento no acreditado'='Booleano verdadero requerido'
        'evidencia alterada'='Hash de archivo no coincide'; 'catalogo alterado'='Catalogo alterado'
        'etapa interrumpida'='Cannot find path|No se encuentra|no existe|does not exist'
        'no sobrescribir'='No se sobrescribe fixture'; 'archivo alterado'='Hash de archivo no coincide'
        'jar alterado'='Hash de archivo no coincide'
    }
    if (-not $Expected) {
        if (-not $causes.ContainsKey($Label)) { throw "Falta causa esperada: $Label" }
        $Expected = $causes[$Label]
    }
    $failed = $false
    try { & $Action } catch {
        $failed = $true
        if ($_.Exception.Message -notmatch $Expected) { throw "Causa inesperada en $Label : $($_.Exception.Message)" }
    }
    if (-not $failed) { throw "Debio rechazarse: $Label" }
}

# ConvertFrom-Json reproduce la forma recibida por los validadores.
foreach ($json in @('{"items":[]}', '{"items":[{"path":"a"}]}', '{"items":[1,2]}')) {
    $shape = $json | ConvertFrom-Json
    $value = Get-BridgeField $shape 'items'
    if ($value -isnot [array] -or $value.Count -ne $shape.items.Count) {
        throw 'Get-BridgeField no conserva el arreglo JSON.'
    }
}
$scalar = Get-BridgeField ('{"items":"a"}' | ConvertFrom-Json) 'items'
if ($scalar -is [array] -or $scalar -cne 'a') { throw 'El escalar se convirtio en arreglo.' }

Assert-BridgeTrue $true 'true'
foreach ($bad in @($false, 'true', 'false', 0, 1, $null)) {
    Expect-Failure { Assert-BridgeTrue $bad 'prueba' } 'booleano invalido'
}
$groups = @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified','rollbackControlsVerified','isolation')
$counts = @(5,6,10,54,9)
for ($i=0; $i -lt $groups.Count; $i++) {
    $map = Get-BridgeCases $groups[$i]
    if ($map.Count -ne $counts[$i]) { throw 'Cantidad de casos inesperada.' }
    $cases = @($map.Keys | ForEach-Object { [pscustomobject]@{id=$_;level=$map[$_];expected='ok';actual='ok';passed=$true} })
    Assert-BridgeCases $cases $groups[$i]
    Expect-Failure { Assert-BridgeCases @($cases | Select-Object -Skip 1) $groups[$i] } 'caso ausente'
    Expect-Failure { Assert-BridgeCases @($cases + $cases[0]) $groups[$i] } 'caso duplicado'
    $changed = @($cases | ForEach-Object { $_.PSObject.Copy() })
    $changed[0].level='INVALIDO'
    Expect-Failure { Assert-BridgeCases $changed $groups[$i] } 'nivel invalido'
    $changed = @($cases | ForEach-Object { $_.PSObject.Copy() })
    $changed[0].passed='true'
    Expect-Failure { Assert-BridgeCases $changed $groups[$i] } 'booleano string'
}
Expect-Failure { Get-BridgeCases 'desconocido' } 'grupo desconocido'
Expect-Failure { Assert-BridgeUtc 'fecha' 'fecha' } 'fecha invalida'
Expect-Failure { Assert-BridgeHash 'abc' 'hash' } 'hash invalido'
Expect-Failure { Get-BridgeSafeFile $PSScriptRoot '..\fuera' } 'ruta exterior'

# Carpeta nueva propia; se conserva para inspeccion, no se toca ningun checkpoint.
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('bridge-synthetic-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop
function Write-TestJson([string]$Name, $Value) {
    $path = Join-Path $testRoot $Name
    if (Test-Path -LiteralPath $path) { throw 'No se sobrescribe fixture.' }
    [IO.File]::WriteAllText($path, ($Value | ConvertTo-Json -Depth 50 -Compress), [Text.UTF8Encoding]::new($false))
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Write-TestFile([string]$Name, [string]$Value) {
    $path = Join-Path $testRoot $Name
    if (Test-Path -LiteralPath $path) { throw 'No se sobrescribe fixture.' }
    [IO.File]::WriteAllText($path, $Value, [Text.UTF8Encoding]::new($false))
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
$archiveHash=Write-TestFile 'source.archive' 'archivo sintetico'
$manifestHash=Write-TestFile 'manifest.json' '{}'
$recipeHash=Write-TestFile 'recipe.json' '{}'
$catalogHash=Write-TestFile 'catalog.md' 'catalogo sintetico'
$attachmentHash=Write-TestFile 'attachment.json' '{}'
$commit='a'*40
$metadata=[ordered]@{commit=$commit;sourceArchiveSha256=$archiveHash;buildRecipeSha256=$recipeHash}
$metadataJson=$metadata | ConvertTo-Json -Compress
$metadataBytes=[Text.UTF8Encoding]::new($false).GetBytes($metadataJson)
$sha=[Security.Cryptography.SHA256]::Create()
try { $metadataHash=([BitConverter]::ToString($sha.ComputeHash($metadataBytes))).Replace('-','') } finally { $sha.Dispose() }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$jarPath=Join-Path $testRoot 'candidate.jar'
$zip=[IO.Compression.ZipFile]::Open($jarPath,[IO.Compression.ZipArchiveMode]::Create)
try {
    $entry=$zip.CreateEntry('META-INF/bridge.json')
    $stream=$entry.Open()
    try {$stream.Write($metadataBytes,0,$metadataBytes.Length)} finally {$stream.Dispose()}
} finally {$zip.Dispose()}
$jarHash=(Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash
$candidate=[ordered]@{
    schemaVersion=2;kind='reservation-bridge-candidate';state='Prepared';runId='synthetic'
    preparedBy='tester';preparedAtUtc='2026-01-01T00:00:00Z';commit=$commit;sourceTree='b'*40
    sourceArchivePath='source.archive';sourceArchiveSha256=$archiveHash
    sourceFilesManifestPath='manifest.json';sourceFilesManifestSha256=$manifestHash
    buildRecipePath='recipe.json';buildRecipeSha256=$recipeHash;jarPath='candidate.jar';jarSha256=$jarHash
    provenanceEntry='META-INF/bridge.json';provenanceSha256=$metadataHash
    toolchain=@{jdk='21';gradle='synthetic'}
}
$candidateHash=Write-TestJson 'candidate.json' $candidate
function New-TestCases([string]$Group) {
    $map=Get-BridgeCases $Group
    return @($map.Keys | ForEach-Object {[pscustomobject]@{id=$_;level=$map[$_];expected='ok';actual='ok';passed=$true}})
}
$ref=@{path='attachment.json';sha256=$attachmentHash}

$proofHash=Write-TestJson 'proof.json' @{kind='synthetic-block';runId='synthetic';blocked=$true}
$allow=@{schemaVersion=1;kind='reservation-bridge-isolation-allowlist';runId='synthetic';records=@(@{sourceId='app';destinationId='mongo';address='172.29.0.2';protocol='TCP';port=27017})}
$topology=@{schemaVersion=1;kind='reservation-bridge-isolation-topology';runId='synthetic';records=@(@{
 networkId='net';appContainerId='app';observerContainerId='obs';internal=$true;hostNetwork=$false;hostGateway=$false;observerPrivileged=$false;appExtraCapabilities=$false;sourceMounts=$false
 services=@(@{id='mongo';address='172.29.0.2';role='MONGO'},@{id='redis';address='172.29.0.3';role='REDIS'},@{id='jwks';address='172.29.0.4';role='JWKS'},@{id='dns';address='172.29.0.5';role='DNS'})
})}
$observation=@{schemaVersion=1;kind='reservation-bridge-isolation-observation';runId='synthetic';records=@(@{
 observerContainerId='obs';startedUtc='2026-01-01T00:00:00Z';finishedUtc='2026-01-01T00:00:05Z';continuous=$true;droppedEvents=0
 events=@(
 @{phase='AUTOCOMPROBACION';timestampUtc='2026-01-01T00:00:01Z';sourceId='app';destinationId='mongo';address='172.29.0.2';protocol='TCP';port=27017;correlationId='allowed';outcome='ATTEMPT';channel='PACKET'},
 @{phase='AUTOCOMPROBACION';timestampUtc='2026-01-01T00:00:02Z';sourceId='app';destinationId='sentinel';address='192.0.2.1';protocol='TCP';port=9;correlationId='synthetic';outcome='BLOCKED';channel='SYSCALL';traceId='denied-probe';pid=11},
 @{phase='RECORRIDO';timestampUtc='2026-01-01T00:00:03Z';sourceId='app';destinationId='mongo';address='172.29.0.2';protocol='TCP';port=27017;correlationId='run';outcome='ATTEMPT';channel='SYSCALL';traceId='java';pid=12},
 @{phase='AUTOCOMPROBACION';timestampUtc='2026-01-01T00:00:01.1Z';sourceId='app';destinationId='mongo';address='172.29.0.2';protocol='TCP';port=27017;correlationId='allowed-syscall';outcome='ATTEMPT';channel='SYSCALL';traceId='allowed-probe';pid=10}
 )
})}
$sentinel=@{schemaVersion=1;kind='reservation-bridge-isolation-sentinelProof';runId='synthetic';records=@(@{sourceId='app';destinationId='sentinel';address='192.0.2.1';protocol='TCP';port=9;correlationId='synthetic';blocked=$true;proofRef=@{path='proof.json';sha256=$proofHash}})}
$allowHash=Write-TestJson 'allow.json' $allow
$topologyHash=Write-TestJson 'topology.json' $topology
$observationHash=Write-TestJson 'observation.json' $observation
$sentinelHash=Write-TestJson 'sentinel.json' $sentinel
$coverage=@{schemaVersion=1;kind='reservation-bridge-isolation-syscallCoverage';runId='synthetic';records=@(@{method='AF_PACKET+STRACE-v1';traceVersion='strace synthetic';capabilities=@('NET_RAW','SYS_PTRACE');pidMode='container:app';seccompSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'bridge/observer-seccomp.json') -Algorithm SHA256).Hash;targets=@(
 @{id='allowed-probe';pid=10;tracerPid=20;kind='probe';ready=$true;startedUtc='2026-01-01T00:00:01Z';finishedUtc='2026-01-01T00:00:01.4Z';exitCode=0},
 @{id='denied-probe';pid=11;tracerPid=21;kind='probe';ready=$true;startedUtc='2026-01-01T00:00:01.5Z';finishedUtc='2026-01-01T00:00:02Z';exitCode=0},
 @{id='java';pid=12;tracerPid=22;kind='java';ready=$true;startedUtc='2026-01-01T00:00:03Z';finishedUtc='2026-01-01T00:00:04Z';exitCode=0;threadChecks=1;lastThreadCheckUtc='2026-01-01T00:00:03.5Z'}
)})}
$coverageHash=Write-TestJson 'coverage.json' $coverage
$iso=[ordered]@{
    kind='reservation-bridge-isolation';status='Passed';runId='synthetic';observerVersion='AF_PACKET+STRACE-v1'
    sentinelCorrelationId='synthetic';cases=@(New-TestCases 'isolation')
    observerContinuous=$true;observerSawAllowed=$true;observerSawDenied=$true;sentinelBlocked=$true
    preflightComplete=$true;runNoForeignDestinations=$true
    preflightStartedUtc='2026-01-01T00:00:01Z';preflightFinishedUtc='2026-01-01T00:00:02Z'
    runStartedUtc='2026-01-01T00:00:03Z';runFinishedUtc='2026-01-01T00:00:04Z'
    allowlist=@{path='allow.json';sha256=$allowHash};topology=@{path='topology.json';sha256=$topologyHash};observation=@{path='observation.json';sha256=$observationHash};sentinelProof=@{path='sentinel.json';sha256=$sentinelHash};syscallCoverage=@{path='coverage.json';sha256=$coverageHash}
}
$isoHash=Write-TestJson 'isolation.json' $iso
$reports=@()
foreach ($group in @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified','rollbackControlsVerified')) {
    $report=[ordered]@{
        schemaVersion=2;kind='reservation-bridge-verification';catalogVersion='1.4.0';catalogSha256=$catalogHash
        runId='synthetic';candidateSha256=$candidateHash;commit=$commit;jarSha256=$jarHash;groupId=$group
        executedBy='tester';startedAtUtc='2026-01-01T00:00:03Z';finishedAtUtc='2026-01-01T00:00:05Z'
        status='Passed';cases=@(New-TestCases $group);scriptHashes=@($ref);attachments=@($ref)
        isolation=@{path='isolation.json';sha256=$isoHash}
    }
    $name=$group+'.json'
    $hash=Write-TestJson $name $report
    $reports+=@{path=$name;sha256=$hash;groupId=$group}
}
$evidence=[ordered]@{
    schemaVersion=2;kind='reservation-bridge-review';catalogVersion='1.4.0';catalogSha256=$catalogHash
    runId='synthetic';commit=$commit;jarPath='candidate.jar';jarSha256=$jarHash
    candidate=@{path='candidate.json';sha256=$candidateHash};reports=$reports
    author='reviewer';reviewedAtUtc='2026-01-01T00:00:06Z';reviewScope='local-isolated'
    legacyReadsAuthorized=$true;v2ReadsVerified=$true;legacyBarrierVerified=$true;rollbackControlsVerified=$true
}
$evidenceHash=Write-TestJson 'evidence.json' $evidence
$catalogPath=Join-Path $testRoot 'catalog.md'
Assert-BridgeEvidence $testRoot 'evidence.json' $evidenceHash $catalogPath $catalogHash

$badEvidence=[ordered]@{}; foreach($key in $evidence.Keys){$badEvidence[$key]=$evidence[$key]}
$badEvidence.author=''
$badHash=Write-TestJson 'bad-author.json' $badEvidence
Expect-Failure { Assert-BridgeEvidence $testRoot 'bad-author.json' $badHash $catalogPath $catalogHash } 'autor ausente'
$badEvidence.author='reviewer'; $badEvidence.legacyReadsAuthorized='true'
$badHash=Write-TestJson 'bad-boolean.json' $badEvidence
Expect-Failure { Assert-BridgeEvidence $testRoot 'bad-boolean.json' $badHash $catalogPath $catalogHash } 'bandera string'
$badEvidence.legacyReadsAuthorized=$true; $badEvidence.commit='c'*40
$badHash=Write-TestJson 'bad-commit.json' $badEvidence
Expect-Failure { Assert-BridgeEvidence $testRoot 'bad-commit.json' $badHash $catalogPath $catalogHash } 'commit distinto'
$badEvidence.commit=$commit; $badEvidence.reports=@($reports[0],$reports[0],$reports[2],$reports[3])
$badHash=Write-TestJson 'bad-reports.json' $badEvidence
Expect-Failure { Assert-BridgeEvidence $testRoot 'bad-reports.json' $badHash $catalogPath $catalogHash } 'grupo duplicado'
$badIso=[pscustomobject]@{}; foreach($key in $iso.Keys){$badIso | Add-Member -NotePropertyName $key -NotePropertyValue $iso[$key]}
$badIso.sentinelBlocked=$false
Expect-Failure { Assert-BridgeIsolation $badIso $testRoot } 'aislamiento no acreditado'

Expect-Failure { Assert-BridgeEvidence $testRoot 'evidence.json' ('0'*64) $catalogPath $catalogHash } 'evidencia alterada'
Expect-Failure { Assert-BridgeEvidence $testRoot 'evidence.json' $evidenceHash $catalogPath ('0'*64) } 'catalogo alterado'
Expect-Failure { Read-BridgeJson $testRoot 'missing.json' ('0'*64) } 'etapa interrumpida'
Expect-Failure { Write-TestJson 'candidate.json' $candidate } 'no sobrescribir'
$before=(Get-FileHash -LiteralPath (Join-Path $testRoot 'candidate.json') -Algorithm SHA256).Hash
Expect-Failure { Assert-BridgeFile $testRoot 'source.archive' ('0'*64) } 'archivo alterado'
Expect-Failure { Assert-BridgeFile $testRoot 'candidate.jar' ('0'*64) } 'jar alterado'
if ((Get-FileHash -LiteralPath (Join-Path $testRoot 'candidate.json') -Algorithm SHA256).Hash -ne $before) { throw 'Fixture modificada.' }

# Mutaciones propias, cada una persiste su adjunto con hash correcto para ejercitar
# la semantica en vez de fallar incidentalmente por hash.
function Assert-IsolationMutation([string]$Name, [string]$Field, $Document, [string]$Reason) {
    $hash=Write-TestJson ($Name+'.json') $Document
    $copy=$iso | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $copy.$Field=[pscustomobject]@{path=($Name+'.json');sha256=$hash}
    Expect-Failure { Assert-BridgeIsolation $copy $testRoot } $Name $Reason
}
$x=$topology | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$x.records[0].hostNetwork=$true
Assert-IsolationMutation 'host-network' 'topology' $x 'Topologia insegura'
$x=$allow | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$x.records[0].address='192.0.2.10'
Assert-IsolationMutation 'foreign-allowlist' 'allowlist' $x 'Destino permitido invalido'
$x=$observation | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$x.records[0].continuous=$false
Assert-IsolationMutation 'capture-gap' 'observation' $x 'Booleano verdadero requerido'
$x=$observation | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$x.records[0].droppedEvents=1
Assert-IsolationMutation 'dropped-events' 'observation' $x 'Eventos perdidos'
$x=$coverage|ConvertTo-Json -Depth 50|ConvertFrom-Json
$x.records[0].targets[0].ready=$false
Assert-IsolationMutation 'trace-not-ready' 'syscallCoverage' $x 'Booleano verdadero requerido'
$x=$coverage|ConvertTo-Json -Depth 50|ConvertFrom-Json
$x.records[0].targets[1].finishedUtc=$null
Assert-IsolationMutation 'trace-gap' 'syscallCoverage' $x 'Fecha UTC invalida|Texto invalido'
$x=$coverage|ConvertTo-Json -Depth 50|ConvertFrom-Json
$x.records[0].capabilities=@('NET_RAW','SYS_PTRACE','NET_ADMIN')
Assert-IsolationMutation 'trace-extra-cap' 'syscallCoverage' $x 'Permisos de traza incompatibles'
$x=$coverage|ConvertTo-Json -Depth 50|ConvertFrom-Json
$x.records[0].capabilities=,@('NET_RAW','SYS_PTRACE')
Assert-IsolationMutation 'trace-nested-capabilities' 'syscallCoverage' $x 'Permisos de traza incompatibles'
$x=$coverage|ConvertTo-Json -Depth 50|ConvertFrom-Json
$x.records[0].capabilities='NET_RAW'
Assert-IsolationMutation 'trace-scalar-capabilities' 'syscallCoverage' $x 'Permisos de traza incompatibles'
$x=$observation|ConvertTo-Json -Depth 50|ConvertFrom-Json
$x.records[0].events[1].channel='PACKET'
Assert-IsolationMutation 'denied-without-syscall' 'observation' $x 'Paquete denegado sin syscall'
$x=$observation | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$x.records[0].events[2].address='192.0.2.1'
Assert-IsolationMutation 'foreign-during-run' 'observation' $x 'Destino ajeno en recorrido'
$x=$observation | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$x.records[0].events[1].correlationId='other'
Assert-IsolationMutation 'wrong-correlation' 'observation' $x 'Centinela invalido'
$x=$observation | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$x.records[0].events[1].timestampUtc='2026-01-01T00:00:04Z'
Assert-IsolationMutation 'outside-phase' 'observation' $x 'Evento fuera de fase'
$x=$sentinel | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$x.records[0].proofRef=$iso.observation
Assert-IsolationMutation 'self-proof' 'sentinelProof' $x 'Prueba no independiente'
# Lecturas repetidas conservan todos los archivos, incluso los de intentos fallidos.
$originals=@{}
Get-ChildItem -LiteralPath $testRoot -File | ForEach-Object { $originals[$_.FullName]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
Assert-BridgeEvidence $testRoot 'evidence.json' $evidenceHash $catalogPath $catalogHash
Assert-BridgeEvidence $testRoot 'evidence.json' $evidenceHash $catalogPath $catalogHash
foreach($path in $originals.Keys) {
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $originals[$path]) { throw 'Lectura modifico fixtures.' }
}

Write-Host 'OK: comprobaciones sinteticas; no acreditan HTTP, Mongo, aislamiento ni evidencia real.'
Write-Host "Fixtures sinteticas conservadas en: $testRoot"

