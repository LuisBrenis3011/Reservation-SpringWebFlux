[CmdletBinding()]
param(
    [ValidateSet('PrepareArtifact','VerifyIsolated','Review')][string]$Stage = 'PrepareArtifact',
    [string]$Commit,
    [string]$Author,
    [switch]$AllowBuild,
    [string]$Candidate,
    [string]$ExecutedBy,
    [string]$IsolationImages,
    [string[]]$Reports,
    [string]$ReviewedBy,
    [switch]$AllowIsolatedExecution
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ReservationBridge.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Pending.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Source.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Runtime.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Isolation.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Environment.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Observation.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Catalog.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Execution.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Review.ps1')

function Assert-BridgePreparationInput([string]$Commit, [string]$Author, [bool]$Allowed) {
    if ($Commit -cnotmatch '^[a-fA-F0-9]{40}$') { throw 'Commit completo requerido.' }
    Assert-BridgeText $Author 'Author'
    if (-not $Allowed) { throw 'PrepareArtifact requiere -AllowBuild para exportar y compilar.' }
}
function Write-BridgeNewJson([string]$Path, $Value) {
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 40))
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
}
function Invoke-BridgeGit([string]$Repo, [string[]]$Arguments) {
    $result = @(& git -C $Repo @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Git no pudo preparar el artefacto.' }
    return $result
}
function Get-BridgeHash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Get-BridgeLfHash([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $stream=[IO.MemoryStream]::new()
    try {
        for($i=0;$i -lt $bytes.Length;$i++) {
            if($bytes[$i] -eq 13 -and $i+1 -lt $bytes.Length -and $bytes[$i+1] -eq 10) { continue }
            $stream.WriteByte($bytes[$i])
        }
        $stream.Position=0; $sha=[Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Assert-BridgeWorkingSource([string]$Repo,[string]$Relative,[string]$Exported,[string]$Working) {
    if ((Get-BridgeHash $Working) -ceq (Get-BridgeHash $Exported)) { return }
    if ((Get-BridgeLfHash $Working) -cne (Get-BridgeLfHash $Exported)) { throw 'Commit y fuentes productivas actuales distintos.' }
    # Git debe confirmar que su filtro de entrada reconoce la misma identidad.
    # La comparacion SHA256 anterior limita la excepcion a CRLF/LF, incluso con filtros personalizados.
    $workingOid=@(Invoke-BridgeGit $Repo @('hash-object',('--path='+$Relative),'--',$Working))
    $exportOid=@(Invoke-BridgeGit $Repo @('hash-object',('--path='+$Relative),'--',$Exported))
    if ($workingOid.Count -ne 1 -or $exportOid.Count -ne 1 -or $workingOid[0] -cnotmatch '^[0-9a-f]{40,64}$' -or $workingOid[0] -cne $exportOid[0]) { throw 'Commit y fuentes productivas actuales distintos.' }
}

function Invoke-BridgePrepareArtifact([string]$Commit, [string]$Author, [bool]$Allowed) {
    Assert-BridgePreparationInput $Commit $Author $Allowed
    $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $resolved=@(Invoke-BridgeGit $repo @('rev-parse','--verify',($Commit+'^{commit}')))
    if ($resolved.Count -ne 1 -or $resolved[0] -ine $Commit) { throw 'Commit resuelto distinto.' }
    $tree=@(Invoke-BridgeGit $repo @('rev-parse',($Commit+'^{tree}')))[0]
    $scope=@('src/main','build.gradle','settings.gradle','gradle.properties','gradlew','gradlew.bat','gradle')
    $dirty=@(Invoke-BridgeGit $repo (@('status','--porcelain','--untracked-files=all','--')+$scope))
    if ($dirty.Count -gt 0) { throw 'Fuentes productivas o Gradle con cambios locales.' }
    $java=@(& java --version 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0 -or ($java -join ' ') -notmatch '(?m)^(java|openjdk) 21[. ]') { throw 'Java 21 requerido.' }
    $runId=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N')
    $parent=Join-Path $repo 'backups/reservation-bridge'
    $null=New-Item -ItemType Directory -Path $parent -Force
    $root=Join-Path $parent $runId
    if (Test-Path -LiteralPath $root) { throw 'Directorio de ensayo existente.' }
    $null=New-Item -ItemType Directory -Path $root
    $archive=Join-Path $root 'source.zip'
    $null=Invoke-BridgeGit $repo @('archive','--format=zip',("--output=$archive"),$Commit)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach($entry in $zip.Entries) {
            $name=$entry.FullName
            if ($name -match '(^|/)([.][.]|[.]env|secrets)(/|$)' -or $name.StartsWith('/') -or $name.Contains(':') -or $name.Contains('\')) { throw 'Ruta o secreto no permitido en exportacion.' }
            if ((($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw 'Enlace no permitido en exportacion.' }
        }
    } finally { $zip.Dispose() }
    $export=Join-Path $root 'export'
    [IO.Compression.ZipFile]::ExtractToDirectory($archive,$export)
    $manifest=@()
    foreach($file in (Get-ChildItem -LiteralPath $export -Recurse -File | Sort-Object FullName)) {
        $relative=$file.FullName.Substring($export.Length+1).Replace('\','/')
        $hash=Get-BridgeHash $file.FullName
        $manifest+=@{path=$relative;sha256=$hash}
        if ($relative -match '^(src/main/|gradle/)' -or $scope -contains $relative) {
            $working=Get-BridgeSafeFile $repo $relative
            Assert-BridgeWorkingSource $repo $relative $file.FullName $working
        }
    }
    $tracked=@(Invoke-BridgeGit $repo (@('ls-files','--')+$scope))
    foreach($relative in $tracked) {
        if (-not (Test-Path -LiteralPath (Join-Path $export $relative) -PathType Leaf)) { throw 'Fuente actual ausente del commit.' }
    }
    $manifestPath=Join-Path $root 'source-files.json'
    Write-BridgeNewJson $manifestPath @{commit=$Commit;tree=$tree;files=$manifest}
    $gradle=@(& (Join-Path $export 'gradlew.bat') --version --no-daemon 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo identificar Gradle.' }
    $recipePath=Join-Path $root 'recipe.json'
    Write-BridgeNewJson $recipePath @{
        commit=$Commit;tree=$tree;java=$java;gradle=$gradle
        arguments=@('bootJar','--no-daemon');scriptSha256=(Get-BridgeHash $PSCommandPath)
        helperSha256=(Get-BridgeHash (Join-Path $PSScriptRoot 'ReservationBridge.Common.ps1'))
    }
    $provenance=@{commit=$Commit;sourceArchiveSha256=(Get-BridgeHash $archive);buildRecipeSha256=(Get-BridgeHash $recipePath)}
    $resourceDir=Join-Path $export 'src/main/resources/META-INF'
    $null=New-Item -ItemType Directory -Path $resourceDir -Force
    $metadataPath=Join-Path $resourceDir 'bridge.json'
    Write-BridgeNewJson $metadataPath $provenance
    Push-Location $export
    try {
        & (Join-Path $export 'gradlew.bat') bootJar --no-daemon
        if ($LASTEXITCODE -ne 0) { throw 'Compilacion del JAR fallida.' }
    } finally { Pop-Location }
    $jars=@(Get-ChildItem -LiteralPath (Join-Path $export 'build/libs') -Filter '*.jar' -File | Where-Object { $_.Name -notlike '*-plain.jar' })
    if ($jars.Count -ne 1) { throw 'Se requiere exactamente un bootJar.' }
    $jar=Join-Path $root 'bridge.jar'
    $inputStream=[IO.File]::OpenRead($jars[0].FullName)
    try {
        $outputStream=[IO.File]::Open($jar,[IO.FileMode]::CreateNew)
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
    $candidate=[pscustomobject]@{
        schemaVersion=2;kind='reservation-bridge-candidate';state='Prepared';runId=$runId
        preparedBy=$Author;preparedAtUtc=[DateTime]::UtcNow.ToString('o');commit=$Commit;sourceTree=$tree
        sourceArchivePath='source.zip';sourceArchiveSha256=(Get-BridgeHash $archive)
        sourceFilesManifestPath='source-files.json';sourceFilesManifestSha256=(Get-BridgeHash $manifestPath)
        buildRecipePath='recipe.json';buildRecipeSha256=(Get-BridgeHash $recipePath)
        jarPath='bridge.jar';jarSha256=(Get-BridgeHash $jar)
        provenanceEntry='META-INF/bridge.json';provenanceSha256=(Get-BridgeHash $metadataPath)
        toolchain=[pscustomobject]@{jdk='21';gradle=($gradle -join ' ')}
    }
    Assert-BridgeCandidate $candidate $root
    Write-BridgeNewJson (Join-Path $root 'candidate.json') $candidate
    Write-Host "Prepared: $root"
    Write-Host 'Candidato sin evidencia de aislamiento ni aprobacion. No se inicia ninguna etapa posterior.'
}
function Assert-BridgeIsolationInput([string]$CandidatePath, [string]$Actor, [bool]$Allowed) {
    Assert-BridgeText $CandidatePath 'Candidate'
    Assert-BridgeText $Actor 'ExecutedBy'
    if (-not $Allowed) { throw 'VerifyIsolated requiere -AllowIsolatedExecution.' }
}
function Read-BridgeIsolationImages([string]$Path) {
    Assert-BridgeText $Path 'IsolationImages'
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Manifiesto de imagenes invalido.' }
    $images=Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $images -or $images -is [array] -or $images -isnot [pscustomobject]) { throw 'Manifiesto de imagenes debe ser un objeto JSON.' }
    $roles=@('mongo','redis','java','tools')
    $properties=@($images.PSObject.Properties)
    if ($properties.Count -ne $roles.Count) { throw 'Roles de imagenes incompletos o desconocidos.' }
    foreach ($role in $roles) {
        $matches=@($properties | Where-Object { $_.Name -ceq $role })
        if ($matches.Count -ne 1 -or $matches[0].Value -isnot [string] -or -not (Test-BridgeImageReference $matches[0].Value)) {
            throw "Imagen por digest invalida: $role"
        }
    }
    return $images
}
function Assert-BridgeExportArchive($Candidate, [string]$Root) {
    # La fuente utilizada por las pruebas debe corresponder al archive identificado por
    # el candidato, no a la carpeta export mutable ni solo a un JSON con hash.
    $manifest=Read-BridgeJson $Root (Get-BridgeField $Candidate 'sourceFilesManifestPath') (Get-BridgeField $Candidate 'sourceFilesManifestSha256')
    if ((Get-BridgeField $manifest 'commit') -ine (Get-BridgeField $Candidate 'commit') -or
        (Get-BridgeField $manifest 'tree') -ine (Get-BridgeField $Candidate 'sourceTree')) { throw 'Manifiesto de fuente corresponde a otro commit o arbol.' }
    $files=Get-BridgeField $manifest 'files'
    if ($files -isnot [array] -or $files.Count -eq 0) { throw 'Manifiesto de fuente vacio o invalido.' }
    $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        $name=Get-BridgeField $file 'path'; $hash=Get-BridgeField $file 'sha256'
        Assert-BridgeText $name 'source.path'; Assert-BridgeHash $hash 'source.sha256'
        if ($name.StartsWith('/') -or $name.Contains('\') -or $name.Contains(':') -or
            $name -match '(^|/)(\.|\.\.|\.env|secrets)(/|$)' -or $name -match '//|/$') { throw 'Ruta de fuente no permitida.' }
        if ($expected.ContainsKey($name)) { throw 'Ruta de fuente duplicada.' }
        $expected.Add($name,$hash)
    }
    $archive=Assert-BridgeFile $Root (Get-BridgeField $Candidate 'sourceArchivePath') (Get-BridgeField $Candidate 'sourceArchiveSha256')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name=$entry.FullName
            if ([string]::IsNullOrWhiteSpace($name) -or $name.StartsWith('/') -or $name.Contains('\') -or $name.Contains(':') -or
                $name -match '(^|/)(\.|\.\.|\.env|secrets)(/|$)' -or $name -match '//') { throw 'Ruta no permitida en archive.' }
            if ((($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw 'Enlace no permitido en archive.' }
            if ($name.EndsWith('/')) { continue }
            if (-not $seen.Add($name) -or -not $expected.ContainsKey($name)) { throw 'Archivo duplicado o no declarado en archive.' }
            $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
            try { $actual=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
            finally { $sha.Dispose(); $stream.Dispose() }
            if ($actual -ine $expected[$name]) { throw 'Archivo exportado distinto del manifiesto.' }
        }
        if ($seen.Count -ne $expected.Count) { throw 'Archivo declarado ausente del archive.' }
    } finally { $zip.Dispose() }
}
function Invoke-BridgeVerifyIsolated([string]$CandidatePath, [string]$Actor, [bool]$Allowed, [string]$ImagesPath) {
    Assert-BridgeIsolationInput $CandidatePath $Actor $Allowed
    $candidateFile=Get-Item -LiteralPath $CandidatePath -ErrorAction Stop
    if ($candidateFile.PSIsContainer -or $candidateFile.Name -cne 'candidate.json') { throw 'Se requiere candidate.json.' }
    $root=$candidateFile.Directory.FullName
    $candidateHash=Get-BridgeHash $candidateFile.FullName
    $value=Read-BridgeJson $root 'candidate.json' $candidateHash
    Assert-BridgeCandidate $value $root
    Assert-BridgeExportArchive $value $root
    $images=Read-BridgeIsolationImages $ImagesPath
    $catalog=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../specs/005-confirmar-reserva/contracts/bridge-catalog.md'))
    $result=Invoke-BridgeVerificationExecution $value $candidateHash $root $images $Actor $catalog
    foreach($ref in $result.reports){Write-Host ($ref.groupId+': '+$ref.status+' '+$ref.path)}
    Write-Host ('Ensayo conservado: '+$result.directory)
    if($result.status -cne 'Passed'){throw ('VerifyIsolated termino '+$result.status+'. No existe evidencia revisada ni autorizacion de corte.')}
}

# Dot sourcing solo expone funciones para comprobaciones puras.
if ($MyInvocation.InvocationName -ne '.') {
    if ($Stage -ceq 'PrepareArtifact') { Invoke-BridgePrepareArtifact $Commit $Author ([bool]$AllowBuild) }
    elseif ($Stage -ceq 'VerifyIsolated') { Invoke-BridgeVerifyIsolated $Candidate $ExecutedBy ([bool]$AllowIsolatedExecution) $IsolationImages }
    else {
        $catalog=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../specs/005-confirmar-reserva/contracts/bridge-catalog.md'))
        Invoke-BridgeReview $Candidate $Reports $ReviewedBy $catalog
    }
}
