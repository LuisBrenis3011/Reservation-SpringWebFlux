# Reportes explícitamente pendientes. No ejecuta servicios ni declara Passed.
function Write-BridgePendingReports($BridgeCandidate, [string]$CandidateHash, [string]$Root, [string]$Actor, [string]$CatalogPath, $SourceResult=$null) {
    Assert-BridgeText $Actor 'executedBy'
    Assert-BridgeHash $CandidateHash 'candidateSha256'
    $catalogHash=Get-BridgeHash $CatalogPath
    $candidateHashBefore=Get-BridgeHash (Get-BridgeSafeFile $Root 'candidate.json')
    if ($candidateHashBefore -ine $CandidateHash) { throw 'Candidato cambio antes del reporte.' }
    $attempt='pending-'+[guid]::NewGuid().ToString('N')
    $directory=Join-Path $Root $attempt
    $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $scriptDirectory=Join-Path $directory 'scripts'
    $null=New-Item -ItemType Directory -Path $scriptDirectory -ErrorAction Stop
    $scriptRefs=@()
    foreach ($name in @('ManagedReservations.Common.ps1','Test-LocalMongoRestore.ps1','Test-LocalVersionRollback.ps1','Test-LocalManagedReservationRollback.ps1','read-managed-reservation-policy.js')) {
        $source=Join-Path $PSScriptRoot $name
        $item=Get-Item -LiteralPath $source -Force -ErrorAction Stop
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Script C1 no permitido.' }
        $before=Get-BridgeHash $item.FullName
        $dest=Join-Path $scriptDirectory $name
        $inputStream=[IO.File]::OpenRead($item.FullName)
        try {
            $outputStream=[IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
        } finally { $inputStream.Dispose() }
        if ((Get-BridgeHash $item.FullName) -ine $before -or (Get-BridgeHash $dest) -ine $before) { throw 'Script C1 cambio durante captura.' }
        $scriptRefs+=@{path=($attempt+'/scripts/'+$name);sha256=$before}
    }
    if ((Get-BridgeHash (Get-BridgeSafeFile $Root 'candidate.json')) -ine $CandidateHash -or
        (Get-BridgeHash $CatalogPath) -ine $catalogHash) { throw 'Candidato o catalogo cambio durante la preparacion.' }
    $at=[DateTime]::UtcNow.ToString('o')
    $refs=@()
    foreach ($group in @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified','rollbackControlsVerified')) {
        $caseMap=Get-BridgeCases $group
        $cases=@(foreach($id in $caseMap.Keys) {
            [pscustomobject]@{id=$id;level=$caseMap[$id];expected='Comprobacion del catalogo';actual='No ejecutado';passed=$false}
        })
        $status='Pending';$attachments=@()
        if ($group -ceq 'legacyBarrierVerified' -and $null -ne $SourceResult) {
            foreach ($sourceCase in $SourceResult.cases) {
                $matches=@($cases | Where-Object { $_.id -ceq $sourceCase.id -and $_.level -ceq 'SOURCE_EXPORTED' })
                if ($matches.Count -ne 1 -or $sourceCase.passed -isnot [bool]) { throw 'Resultado SOURCE_EXPORTED invalido.' }
                $matches[0].expected=$sourceCase.expected;$matches[0].actual=$sourceCase.actual;$matches[0].passed=$sourceCase.passed
            }
            if ($SourceResult.status -ceq 'Failed') { $status='Failed' }
            $attachments=@($SourceResult.attachments)
        }
        $report=[ordered]@{
            schemaVersion=2;kind='reservation-bridge-verification';catalogVersion='1.4.0';catalogSha256=$catalogHash
            runId=(Get-BridgeField $BridgeCandidate 'runId');candidateSha256=$CandidateHash
            commit=(Get-BridgeField $BridgeCandidate 'commit');jarSha256=(Get-BridgeField $BridgeCandidate 'jarSha256')
            groupId=$group;executedBy=$Actor;startedAtUtc=$at;finishedAtUtc=$at;status=$status
            isolation=$null;scriptHashes=$scriptRefs;cases=$cases;attachments=$attachments
            pendingReason='El grupo no acredita ejecucion completa del catalogo; el recorrido HTTP y su aislamiento estan pendientes.'
        }
        $file=$group+'.json'
        $output=Join-Path $directory $file
        Write-BridgeNewJson $output $report
        $refs+=@{path=($attempt+'/'+$file);sha256=(Get-BridgeHash $output);groupId=$group}
    }
    return $refs
}
