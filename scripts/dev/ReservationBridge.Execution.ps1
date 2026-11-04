# Orquestacion del ensayo. Cargar el archivo no inicia ninguna etapa.
function New-BridgeUnexecutedCases([string]$Group, [string]$Reason) {
    $map=Get-BridgeCases $Group
    foreach($id in $map.Keys) {
        [pscustomobject]@{id=$id;level=$map[$id];expected='Satisfacer '+$id;actual=$Reason;passed=$false;executionStatus='Pending'}
    }
}

function Merge-BridgeExecutionCases([string]$Group, $Results) {
    $map=Get-BridgeCases $Group
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($case in @($Results)) {
        $id=Get-BridgeField $case 'id'
        if (-not (@($map.Keys) -ccontains $id) -or -not $seen.Add($id)) { throw 'Caso ejecutado desconocido o duplicado.' }
        if ((Get-BridgeField $case 'level') -cne $map[$id]) { throw 'Nivel ejecutado discordante.' }
        $passed=Get-BridgeField $case 'passed'
        if ($passed -isnot [bool]) { throw 'Resultado ejecutado no booleano.' }
        $status=Get-BridgeField $case 'executionStatus'
        if (-not (@('Passed','Failed','Pending') -ccontains $status) -or ($status -ceq 'Passed') -ne $passed) { throw 'Estado de caso incoherente.' }
        if ($passed) {
            $e=Get-BridgeField $case 'expected';$a=Get-BridgeField $case 'actual'
            if ($null -eq $e -or $null -eq $a -or ($e|ConvertTo-Json -Depth 30 -Compress) -cne ($a|ConvertTo-Json -Depth 30 -Compress)) { throw 'Caso aprobado con resultados discordantes.' }
        }
        $case
    }
    if ($seen.Count -ne $map.Count) { throw 'Casos ejecutados incompletos.' }
}

function Get-BridgeExecutionStatus($Cases) {
    if (@($Cases | Where-Object { $_.executionStatus -ceq 'Failed' }).Count -gt 0) { return 'Failed' }
    if (@($Cases | Where-Object { $_.executionStatus -ceq 'Pending' }).Count -gt 0) { return 'Pending' }
    return 'Passed'
}

function New-BridgeScriptSnapshot([string]$Root, [string]$Directory) {
    $folder=Join-Path $Directory 'scripts'
    $null=New-Item -ItemType Directory -Path $folder -ErrorAction Stop
    $files=@(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {
        $_.Name -like '*Bridge*.ps1' -or $_.Name -in @('LocalIdentity.Common.ps1','ManagedReservations.Common.ps1','ReservationReplacement.Assertions.ps1','ReservationCancellation.Assertions.ps1','Test-LocalMongoRestore.ps1','Test-LocalVersionRollback.ps1','Test-LocalManagedReservationRollback.ps1','read-managed-reservation-policy.js','mongo-backup-manifest.js','mongo-cancellation-confirmation-manifest.js')
    })
    $files+=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'bridge') -File -Recurse | Where-Object { $_.Extension -in @('.py','.java','.js','.json') })
    $snapshots=@()
    foreach($file in $files) {
        $relative=$file.FullName.Substring($PSScriptRoot.Length+1)
        $source=Get-BridgeSafeFile $PSScriptRoot $relative
        $dest=Join-Path $folder $relative
        $parent=Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $parent)) { $null=New-Item -ItemType Directory -Path $parent -Force }
        $before=Get-BridgeHash $source
        $inputStream=[IO.File]::OpenRead($source)
        try {
            $outputStream=[IO.File]::Open($dest,[IO.FileMode]::CreateNew)
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
        } finally { $inputStream.Dispose() }
        if ((Get-BridgeHash $dest) -ine $before -or (Get-BridgeHash $source) -ine $before) { throw 'Script cambio durante snapshot.' }
        $snapshots+=[pscustomobject]@{path=$dest.Substring($Root.Length+1).Replace('\','/');sha256=$before;source=$source}
    }
    return $snapshots
}

function Assert-BridgeScriptSnapshot($Snapshots, [string]$Root) {
    foreach($ref in $Snapshots) {
        $null=Assert-BridgeFile $Root $ref.path $ref.sha256
        if ((Get-BridgeHash $ref.source) -ine $ref.sha256) { throw 'Script evaluado cambio durante el ensayo.' }
    }
}

function Write-BridgeVerificationReports($CandidateValue,[string]$CandidateHash,[string]$Root,[string]$Directory,[string]$Actor,[string]$CatalogHash,$Snapshots,$Groups,$IsolationReference,$Attachments,[string]$Started) {
    Assert-BridgeScriptSnapshot $Snapshots $Root
    $refs=@()
    foreach($group in @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified','rollbackControlsVerified')) {
        $cases=@(Merge-BridgeExecutionCases $group $Groups[$group])
        $status=Get-BridgeExecutionStatus $cases
        if ($group -cne 'rollbackControlsVerified' -and $status -ceq 'Passed' -and $null -eq $IsolationReference) { throw 'Reporte HTTP sin aislamiento acreditado.' }
        $report=[pscustomobject][ordered]@{
            schemaVersion=2;kind='reservation-bridge-verification';catalogVersion='1.4.0';catalogSha256=$CatalogHash
            runId=$CandidateValue.runId;candidateSha256=$CandidateHash;commit=$CandidateValue.commit;jarSha256=$CandidateValue.jarSha256
            groupId=$group;executedBy=$Actor;startedAtUtc=$Started;finishedAtUtc=[DateTime]::UtcNow.ToString('o');status=$status
            isolation=$(if($group -ceq 'rollbackControlsVerified'){$null}else{$IsolationReference})
            scriptHashes=@($Snapshots | ForEach-Object { [pscustomobject]@{path=$_.path;sha256=$_.sha256} })
            cases=$cases;attachments=@($Attachments)
        }
        foreach($attachment in @($Attachments)) { $null=Assert-BridgeFile $Root $attachment.path $attachment.sha256 }
        if ($status -ceq 'Passed') { Assert-BridgeReport $report $CandidateValue $CandidateHash $CatalogHash $Root }
        $path=Join-Path $Directory ($group+'.json')
        Write-BridgeNewJson $path $report
        $refs+=[pscustomobject]@{path=$path.Substring($Root.Length+1).Replace('\','/');sha256=(Get-BridgeHash $path);groupId=$group;status=$status}
    }
    return $refs
}

function Invoke-BridgeVerificationExecution($CandidateValue,[string]$CandidateHash,[string]$Root,$Images,[string]$Actor,[string]$CatalogPath) {
    $started=[DateTime]::UtcNow.ToString('o')
    $catalogHash=Get-BridgeHash $CatalogPath
    $directory=Join-Path $Root ('verification-'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $snapshots=@(New-BridgeScriptSnapshot $Root $directory)
    $groups=@{}
    foreach($g in @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified','rollbackControlsVerified')) {
        $groups[$g]=@(New-BridgeUnexecutedCases $g 'No ejecutado')
    }
    $attachments=@();$isoRef=$null;$context=$null;$observation=$null;$stage='SOURCE_EXPORTED';$fault=$null
    try {
        $source=Invoke-BridgeExportedAssertions $CandidateValue $Root
        foreach($item in @($source.cases)) {
            $copy=$item | ConvertTo-Json -Depth 30 | ConvertFrom-Json
            $copy | Add-Member -NotePropertyName executionStatus -NotePropertyValue $source.status -Force
            $groups.legacyBarrierVerified=@($groups.legacyBarrierVerified | Where-Object { $_.id -cne $copy.id })+@($copy)
        }
        $attachments+=@($source.attachments)
        $stage='C1'
        $c1=Invoke-BridgeC1Catalog ([pscustomobject]@{runId=$CandidateValue.runId;directory=$directory;root=$Root})
        $groups.rollbackControlsVerified=@($c1.groups['rollbackControlsVerified'])
        $attachments+=@($c1.attachments)
        $stage='ENVIRONMENT'
        $context=Invoke-BridgeEnvironment $CandidateValue $Root $Images $Actor -AttemptDirectory $directory
        $stage='AUTOCOMPROBACION'
        $observation=Start-BridgeObservation $context
        # Esta bandera solo se establece DESPUES de la prueba independiente.
        $context.observationReady=$true
        $stage='HTTP_JAR'
        $http=Invoke-BridgeHttpCatalog $context $observation
        foreach($g in @('legacyReadsAuthorized','v2ReadsVerified')) { $groups[$g]=@($http.groups[$g]) }
        $internal=@($groups.legacyBarrierVerified | Where-Object { $_.level -ceq 'SOURCE_EXPORTED' })
        $groups.legacyBarrierVerified=@($http.groups.legacyBarrierVerified)+$internal
        $attachments+=@($http.attachments)
        $stage='ISOLATION'
        Stop-BridgeEnvironmentApplication $context
        $iso=Complete-BridgeObservation $observation $context
        Assert-BridgeIsolation $iso $Root
        $isoPath=Join-Path $directory 'isolation.json'
        Write-BridgeNewJson $isoPath $iso
        $isoRef=[pscustomobject]@{path=$isoPath.Substring($Root.Length+1).Replace('\','/');sha256=(Get-BridgeHash $isoPath)}
        $attachments+=@($isoRef)
    } catch {
        $fault=[pscustomobject]@{stage=$stage;errorType=$_.Exception.GetType().FullName;innerErrorType=$(if($_.Exception.InnerException){$_.Exception.InnerException.GetType().FullName}else{''});scriptLine=$_.InvocationInfo.ScriptLineNumber;status='Failed'}
        # Una comprobacion HTTP sin observacion final no puede conservar Passed.
        foreach($g in @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified')) {
            foreach($case in $groups[$g]) {
                if ($case.level -ne 'SOURCE_EXPORTED') {
                    $case.passed=$false;$case.executionStatus='Failed';$case.actual='Ensayo invalidado en '+$stage
                }
            }
        }
    } finally {
        if ($null -ne $context) {
            if ($null -eq $observation -and $null -ne $context.PSObject.Properties['Observation']) { $observation=$context.Observation }
            if ($null -ne $observation) {
                if($null -ne $fault){
                    try {
                        $partial=Update-BridgeObservationState $observation
                        $partialRef=Add-BridgeObservationAttachment $context 'observation-failed.json' $partial
                        $attachments+=@($partialRef)
                    } catch { }
                }
                try { Stop-BridgeObservation $observation $context } catch { $fault=[pscustomobject]@{stage='STOP_OBSERVATION';status='Failed';errorType=$_.Exception.GetType().FullName} }
            }
            try { Stop-BridgeEnvironment $context } catch { $fault=[pscustomobject]@{stage='STOP_ENVIRONMENT';status='Failed';errorType=$_.Exception.GetType().FullName} }
        }
    }
    if($null -ne $context){
        foreach($field in @('manifestRefs','configurationRefs')){
            if($null -ne $context.PSObject.Properties[$field]){$attachments+=@($context.$field)}
        }
    }
    # Sellado: identidad del candidato/catalogo/scripts no cambia entre etapas.
    try {
        Assert-BridgeCandidate $CandidateValue $Root
        if ((Get-BridgeHash (Get-BridgeSafeFile $Root 'candidate.json')) -ine $CandidateHash -or
            (Get-BridgeHash $CatalogPath) -ine $catalogHash) { throw 'Identidad de evidencia alterada.' }
        Assert-BridgeScriptSnapshot $snapshots $Root
    } catch {
        Write-BridgeNewJson (Join-Path $directory 'invalidated.json') @{status='Failed';stage='SEAL';reason='Cambio de identidad o procedencia; reportes no emitidos.'}
        throw 'Ensayo invalidado durante sellado; se conservan recursos y adjuntos.'
    }
    if ($null -ne $fault) {
        $faultPath=Join-Path $directory 'failure.json'
        Write-BridgeNewJson $faultPath $fault
        $attachments+=@([pscustomobject]@{path=$faultPath.Substring($Root.Length+1).Replace('\','/');sha256=(Get-BridgeHash $faultPath)})
        foreach($g in @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified')) {
            foreach($case in $groups[$g]) { if($case.level -ne 'SOURCE_EXPORTED'){$case.passed=$false;$case.executionStatus='Failed';$case.actual='Ensayo invalidado en '+$fault.stage} }
        }
    }
    $reports=@(Write-BridgeVerificationReports $CandidateValue $CandidateHash $Root $directory $Actor $catalogHash $snapshots $groups $isoRef $attachments $started)
    $status=if(@($reports|Where-Object{$_.status -ceq 'Failed'}).Count){'Failed'}elseif(@($reports|Where-Object{$_.status -ceq 'Pending'}).Count){'Pending'}else{'Passed'}
    Write-BridgeNewJson (Join-Path $directory 'verification.json') @{kind='reservation-bridge-execution';schemaVersion=2;status=$status;reports=$reports;runId=$CandidateValue.runId;candidateSha256=$CandidateHash}
    return [pscustomobject]@{status=$status;directory=$directory;reports=$reports}
}
