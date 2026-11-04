# Ejecutor SOURCE_EXPORTED. Dot-source no ejecuta herramientas.
function Invoke-BridgeExportedAssertions($BridgeCandidate, [string]$Root) {
    $ids=@('BARRIER-INTERNAL-CREATE','BARRIER-INTERNAL-UPDATE','BARRIER-INTERNAL-DELETE','BARRIER-READ-FAIL')
    $cases=@($ids | ForEach-Object { [pscustomobject]@{id=$_;level='SOURCE_EXPORTED';expected='Bloqueo sin llamadas de escritura';actual='No ejecutado';passed=$false} })
    $result=[pscustomobject]@{status='Pending';cases=$cases;attachments=@();reason='Gradle local compatible no disponible.'}
    $toolchain=Get-BridgeField $BridgeCandidate 'toolchain'
    $gradleDescription=Get-BridgeField $toolchain 'gradle'
    $versionMatch=[regex]::Match($gradleDescription,'(?:^|\s)Gradle ([0-9]+(?:\.[0-9]+)+)(?:\s|$)')
    if (-not $versionMatch.Success) { return $result }
    # No usar el wrapper: podria descargar la distribucion incluso con --offline.
    $command=Get-Command gradle -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) { return $result }
    $version=@(& $command.Source --version --offline --no-daemon 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($version -join "`n") -notmatch ('(?m)^Gradle '+[regex]::Escape($versionMatch.Groups[1].Value)+'\s*$')) { return $result }
    Assert-BridgeExportArchive $BridgeCandidate $Root
    # La extraccion vive bajo el candidato: mantener la ruta corta en Windows
    # evita superar MAX_PATH al incluir los nombres largos del arbol exportado.
    $folder='s-'+[guid]::NewGuid().ToString('N').Substring(0,12)
    $directory=Join-Path $Root $folder
    if (Test-Path -LiteralPath $directory) { throw 'Directorio de fuente ya existente.' }
    $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $export=Join-Path $directory 'e'
    $archive=Assert-BridgeFile $Root (Get-BridgeField $BridgeCandidate 'sourceArchivePath') (Get-BridgeField $BridgeCandidate 'sourceArchiveSha256')
    [IO.Compression.ZipFile]::ExtractToDirectory($archive,$export)
    $fixture=Join-Path $PSScriptRoot 'bridge/BridgeExportedAssertions.java'
    $target=Join-Path $export 'src/test/java/com/brenis/SpringWebFlux/services/impls/BridgeExportedAssertions.java'
    $parent=Split-Path -Parent $target
    $null=New-Item -ItemType Directory -Path $parent -Force
    if (Test-Path -LiteralPath $target) { throw 'La fuente exportada ya contiene la clase del harness; se conserva.' }
    $inputStream=[IO.File]::OpenRead($fixture)
    try {
        $outputStream=[IO.File]::Open($target,[IO.FileMode]::CreateNew)
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
    if ((Get-BridgeHash $target) -ine (Get-BridgeHash $fixture)) { throw 'Fixture exportada alterada.' }
    Push-Location $export
    try {
        # Solo se ejecuta la clase propietaria del puente; no Testcontainers ni bootJar.
        $null=& $command.Source test --offline --no-daemon -Dorg.gradle.java.installations.auto-download=false --rerun-tasks --no-build-cache --tests com.brenis.SpringWebFlux.services.impls.BridgeExportedAssertions 2>&1
        $exitCode=$LASTEXITCODE
    } finally { Pop-Location }
    $result.status='Failed';$result.reason='Pruebas de fuente exportada fallidas o sin resultado verificable.'
    $xmlRelative=$folder+'/e/build/test-results/test/TEST-com.brenis.SpringWebFlux.services.impls.BridgeExportedAssertions.xml'
    if ($exitCode -ne 0) { return $result }
    $xmlPath=Get-BridgeSafeFile $Root $xmlRelative
    $settings=[Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($xmlPath,$settings)
    try { $document=[Xml.XmlDocument]::new();$document.XmlResolver=$null;$document.Load($reader) } finally { $reader.Dispose() }
    $suite=$document.DocumentElement
    if ($suite.Name -cne 'testsuite' -or $suite.GetAttribute('tests') -cne '4' -or
        $suite.GetAttribute('failures') -cne '0' -or $suite.GetAttribute('errors') -cne '0' -or
        $suite.GetAttribute('skipped') -cne '0') { return $result }
    $nodes=@($suite.SelectNodes('testcase'))
    if ($nodes.Count -ne 4) { return $result }
    foreach ($case in $cases) {
        $method=$case.id.Replace('-','_')
        $matching=@($nodes | Where-Object { $_.GetAttribute('name') -ceq ($method+'()') -and $_.GetAttribute('classname') -ceq 'com.brenis.SpringWebFlux.services.impls.BridgeExportedAssertions' })
        if ($matching.Count -ne 1 -or $matching[0].SelectNodes('failure|error|skipped').Count -ne 0) { return $result }
    }
    # Revalidar el archive; el JAR original no es un resultado de esta compilacion.
    Assert-BridgeExportArchive $BridgeCandidate $Root
    foreach ($case in $cases) { $case.actual=$case.expected;$case.passed=$true }
    $result.status='Passed';$result.reason=''
    $result.attachments=@(@{path=$xmlRelative;sha256=(Get-BridgeHash $xmlPath)},@{path=($folder+'/e/src/test/java/com/brenis/SpringWebFlux/services/impls/BridgeExportedAssertions.java');sha256=(Get-BridgeHash $target)})
    return $result
}
