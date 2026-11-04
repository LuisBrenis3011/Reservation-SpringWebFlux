$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Prepare-LocalReservationBridge.ps1')
function Expect-PreparationFailure([scriptblock]$Action,[string]$Cause) {
    $message=$null
    try { & $Action } catch { $message=$_.Exception.Message }
    if ($null -eq $message -or $message -notmatch $Cause) { throw "Causa inesperada; se esperaba: $Cause; se obtuvo: $message" }
}
# Si el preflight falla, nunca debe alcanzarse la llamada externa.
function Invoke-BridgeGit { throw 'NO_DEBE_INVOCARSE_GIT' }
Expect-PreparationFailure { Invoke-BridgePrepareArtifact '' 'tester' $true } 'Commit completo requerido'
Expect-PreparationFailure { Invoke-BridgePrepareArtifact ('a'*40) '' $true } 'Texto invalido: Author'
Expect-PreparationFailure { Invoke-BridgePrepareArtifact ('a'*40) 'tester' $false } 'requiere -AllowBuild'
Assert-BridgePreparationInput ('a'*40) 'tester' $true
$testDirectory=Join-Path ([IO.Path]::GetTempPath()) ('bridge-prepare-synthetic-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $testDirectory
# Dobles de Git: se exige equivalencia de bytes salvo CRLF/LF y confirmacion del filtro.
$exportedSource=Join-Path $testDirectory 'exported.txt'
$workingSource=Join-Path $testDirectory 'working.txt'
[IO.File]::WriteAllText($exportedSource,"uno`ndos`n",[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($workingSource,"uno`r`ndos`r`n",[Text.UTF8Encoding]::new($false))
$script:BridgeSyntheticOidMismatch=$false
function Invoke-BridgeGit([string]$Repo,[string[]]$Arguments) {
    if($Arguments[0] -cne 'hash-object') { throw 'Git sintetico inesperado' }
    if($script:BridgeSyntheticOidMismatch -and $Arguments[-1] -ceq $exportedSource) { return ('b'*40) }
    return ('a'*40)
}
Assert-BridgeWorkingSource $testDirectory 'src/main/test.txt' $exportedSource $workingSource
[IO.File]::WriteAllText($exportedSource,"uno`r`ndos`r`n",[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($workingSource,"uno`ndos`n",[Text.UTF8Encoding]::new($false))
Assert-BridgeWorkingSource $testDirectory 'src/main/test.txt' $exportedSource $workingSource
$script:BridgeSyntheticOidMismatch=$true
Expect-PreparationFailure { Assert-BridgeWorkingSource $testDirectory 'src/main/test.txt' $exportedSource $workingSource } 'fuentes productivas actuales distintos'
$script:BridgeSyntheticOidMismatch=$false
[IO.File]::WriteAllText($workingSource,"uno`r`ncambiado`r`n",[Text.UTF8Encoding]::new($false))
Expect-PreparationFailure { Assert-BridgeWorkingSource $testDirectory 'src/main/test.txt' $exportedSource $workingSource } 'fuentes productivas actuales distintos'
function Invoke-BridgeGit { throw 'NO_DEBE_INVOCARSE_GIT' }
$path=Join-Path $testDirectory 'partial.json'
Write-BridgeNewJson $path @{state='Incomplete'}
$before=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
Expect-PreparationFailure { Write-BridgeNewJson $path @{state='Prepared'} } 'exist|existe|usado|used'
if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $before) { throw 'Archivo existente modificado.' }
Expect-PreparationFailure { Read-BridgeJson $testDirectory 'candidate.json' ('0'*64) } 'Cannot find|No se encuentra|no existe|does not exist'
# Un archivo JSON truncado representa una interrupción: nunca se acepta como candidato.
$truncated=Join-Path $testDirectory 'interrupted.json'
[IO.File]::WriteAllText($truncated,'{',[Text.UTF8Encoding]::new($false))
$hash=(Get-FileHash -LiteralPath $truncated -Algorithm SHA256).Hash
Expect-PreparationFailure { Read-BridgeJson $testDirectory 'interrupted.json' $hash } 'JSON|json|object|objeto|Unexpected|inesperado|Invalid|primitiv|Esperaba|Expected'
if (Test-Path -LiteralPath (Join-Path $testDirectory 'candidate.json')) { throw 'Candidato creado incidentalmente.' }
# Archive y manifiesto se contrastan por contenido, no solo por sus hashes propios.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archivePath=Join-Path $testDirectory 'source.zip'
$zip=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
$content=[Text.UTF8Encoding]::new($false).GetBytes('fuente sintetica')
try {
    $entry=$zip.CreateEntry('src/main/example.txt'); $stream=$entry.Open()
    try { $stream.Write($content,0,$content.Length) } finally { $stream.Dispose() }
} finally { $zip.Dispose() }
$sha=[Security.Cryptography.SHA256]::Create()
try { $contentHash=([BitConverter]::ToString($sha.ComputeHash($content))).Replace('-','') } finally { $sha.Dispose() }
$manifestPath=Join-Path $testDirectory 'source-files.json'
$manifest=@{commit=('a'*40);tree=('b'*40);files=@(@{path='src/main/example.txt';sha256=$contentHash})}
Write-BridgeNewJson $manifestPath $manifest
$syntheticCandidate=[pscustomobject]@{commit=('a'*40);sourceTree=('b'*40);sourceArchivePath='source.zip';sourceArchiveSha256=(Get-BridgeHash $archivePath);sourceFilesManifestPath='source-files.json';sourceFilesManifestSha256=(Get-BridgeHash $manifestPath)}
Assert-BridgeExportArchive $syntheticCandidate $testDirectory
$badPath=Join-Path $testDirectory 'bad-source-files.json'
$manifest.files[0].sha256='0'*64
Write-BridgeNewJson $badPath $manifest
$syntheticCandidate.sourceFilesManifestPath='bad-source-files.json';$syntheticCandidate.sourceFilesManifestSha256=Get-BridgeHash $badPath
Expect-PreparationFailure { Assert-BridgeExportArchive $syntheticCandidate $testDirectory } 'Archivo exportado distinto del manifiesto'
# Un intento sin ejecutores no puede producir reportes Passed ni revisión.
$syntheticCandidate | Add-Member -NotePropertyName runId -NotePropertyValue 'synthetic'
$syntheticCandidate | Add-Member -NotePropertyName jarSha256 -NotePropertyValue ('a'*64)
$syntheticCandidate | Add-Member -NotePropertyName toolchain -NotePropertyValue ([pscustomobject]@{jdk='21';gradle='synthetic'})
$sourcePending=Invoke-BridgeExportedAssertions $syntheticCandidate $testDirectory
if ($sourcePending.status -cne 'Pending' -or @($sourcePending.cases).Count -ne 4) { throw 'La herramienta no identificada debe conservar cuatro casos pendientes.' }
foreach ($sourceCase in $sourcePending.cases) {
    if ($sourceCase.passed -isnot [bool] -or $sourceCase.passed) { throw 'Fuente no ejecutada no puede aprobarse.' }
}
$syntheticCandidatePath=Join-Path $testDirectory 'candidate.json'
Write-BridgeNewJson $syntheticCandidatePath $syntheticCandidate
$syntheticCandidateHash=Get-BridgeHash $syntheticCandidatePath
$catalogPath=Join-Path $testDirectory 'catalog.md'
[IO.File]::WriteAllText($catalogPath,'catalogo sintetico',[Text.UTF8Encoding]::new($false))
$pendingReports=@(Write-BridgePendingReports $syntheticCandidate $syntheticCandidateHash $testDirectory 'tester' $catalogPath)
if ($pendingReports.Count -ne 4) { throw 'Se requieren cuatro reportes pendientes.' }
foreach ($reference in $pendingReports) {
    $report=Read-BridgeJson $testDirectory $reference.path $reference.sha256
    if ($report.status -cne 'Pending' -or @($report.cases).Count -ne (Get-BridgeCases $reference.groupId).Count) { throw 'Reporte pendiente incorrecto.' }
    foreach ($case in $report.cases) { if ($case.passed -isnot [bool] -or $case.passed) { throw 'Caso no ejecutado no puede aprobarse.' } }
    Expect-PreparationFailure { Assert-BridgeReport $report $syntheticCandidate $syntheticCandidateHash (Get-BridgeHash $catalogPath) $testDirectory } 'Reporte invalido'
}
if (Test-Path -LiteralPath (Join-Path $testDirectory 'bridge-evidence.json')) { throw 'La preparacion creo una revision.' }
Write-Host 'OK: prerrequisitos, no sobrescritura e interrupcion sinteticos. No acredita Git ni compilacion.'
Write-Host "Fixtures conservadas: $testDirectory"
