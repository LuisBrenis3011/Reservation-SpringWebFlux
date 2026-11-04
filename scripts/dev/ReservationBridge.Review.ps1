# Revision exclusivamente local. Ninguna funcion ejecuta servicios o pruebas.
function Get-BridgeReviewRelativePath([string]$Root,[string]$Path) {
    Assert-BridgeText $Path 'Reports'
    if([IO.Path]::IsPathRooted($Path)){
        $prefix=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')+[IO.Path]::DirectorySeparatorChar
        $full=[IO.Path]::GetFullPath($Path)
        if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Reporte fuera de raiz del candidato.'}
        $Path=$full.Substring($prefix.Length)
    }
    $null=Get-BridgeSafeFile $Root $Path
    return $Path.Replace('\','/')
}

function Assert-BridgeReviewScripts($Reports,[string]$Root,[string]$ScriptRoot) {
    $required=@('ManagedReservations.Common.ps1','Test-LocalMongoRestore.ps1','Test-LocalVersionRollback.ps1','Test-LocalManagedReservationRollback.ps1','read-managed-reservation-policy.js','LocalIdentity.Common.ps1','ReservationReplacement.Assertions.ps1','ReservationCancellation.Assertions.ps1','ReservationBridge.Catalog.ps1','ReservationBridge.C1Stages.ps1','ReservationBridge.C1Remaining.ps1','mongo-backup-manifest.js','mongo-cancellation-confirmation-manifest.js')
    $isolationRequired=@('ReservationBridge.Common.ps1','ReservationBridge.Execution.ps1','ReservationBridge.Observation.ps1','ReservationBridge.Environment.ps1','ReservationBridge.Isolation.ps1','ReservationBridge.Runtime.ps1','bridge/bridge_observer.py','bridge/bridge_trace.py','bridge/bridge_probe.py','bridge/bridge_sentinel.py','bridge/observer-seccomp.json')
    foreach($report in $Reports){
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($ref in (Get-BridgeField $report 'scriptHashes')){
            $path=(Get-BridgeField $ref 'path').Replace('\','/')
            $marker=$path.LastIndexOf('/scripts/',[StringComparison]::Ordinal)
            if($marker -ge 0){$relative=$path.Substring($marker+9)}
            elseif($path.StartsWith('scripts/',[StringComparison]::Ordinal)){$relative=$path.Substring(8)}
            else{throw 'Referencia de script sin snapshot identificable.'}
            if(-not $seen.Add($relative)){throw 'Script evaluado duplicado.'}
            $null=Assert-BridgeFile $Root $path (Get-BridgeField $ref 'sha256')
            $current=Get-BridgeSafeFile $ScriptRoot $relative
            if((Get-BridgeHash $current) -ine (Get-BridgeField $ref 'sha256')){throw 'Script actual distinto del evaluado.'}
        }
        if((Get-BridgeField $report 'groupId') -ceq 'rollbackControlsVerified'){
            foreach($name in $required){if(-not $seen.Contains($name)){throw 'Falta script operativo C1 evaluado.'}}
        }else{
            foreach($name in $isolationRequired){if(-not $seen.Contains($name)){throw 'Falta script de aislamiento evaluado.'}}
        }
    }
}

function Assert-BridgeReviewIndependentProof($Isolation,[string]$Root) {
    $sentinel=Get-BridgeField $Isolation 'sentinelProof'
    $document=Read-BridgeJson $Root $sentinel.path $sentinel.sha256
    $record=(Get-BridgeField $document 'records')[0]
    $ref=Get-BridgeField $record 'proofRef'
    $proof=Read-BridgeJson $Root $ref.path $ref.sha256
    Assert-BridgeTrue (Get-BridgeField $proof 'blocked') 'independent.blocked'
    Assert-BridgeText (Get-BridgeField $proof 'independence') 'independence'
    if($proof.runId -cne $Isolation.runId -or $proof.correlationId -cne $record.correlationId -or
        $proof.sentinelInspectionId -cne $record.destinationId){throw 'Prueba independiente de otro intento.'}
    $before=Get-BridgeField $proof 'positiveBefore';$after=Get-BridgeField $proof 'positiveAfter';$probe=Get-BridgeField $proof 'probe'
    foreach($control in @($before,$after)){
        Assert-BridgeTrue (Get-BridgeField $control 'connected') 'positive.connected'
        Assert-BridgeTrue (Get-BridgeField $control 'acknowledged') 'positive.acknowledged'
        Assert-BridgeText (Get-BridgeField $control 'correlationId') 'positive.correlationId'
    }
    if($before.correlationId -ceq $after.correlationId -or $before.correlationId -ceq $record.correlationId -or $after.correlationId -ceq $record.correlationId){throw 'Controles positivos no independientes del intento.'}
    foreach($control in @($before,$after,$probe)){
        Assert-BridgeUtc (Get-BridgeField $control 'startedUtc') 'probe.startedUtc'
        Assert-BridgeUtc (Get-BridgeField $control 'finishedUtc') 'probe.finishedUtc'
        if([DateTimeOffset]$control.startedUtc -gt [DateTimeOffset]$control.finishedUtc){throw 'Ventana de sonda invalida.'}
    }
    foreach($name in @('connected','acknowledged')){
        $value=Get-BridgeField $probe $name
        if($value -isnot [bool] -or $value){throw 'El centinela no acredita conexion bloqueada.'}
    }
    $probeError=Get-BridgeField $probe 'errorCode'
    if(($probeError -isnot [int] -and $probeError -isnot [long]) -or $probeError -le 0){throw 'Sonda sin error de conexion verificable.'}
    if($probe.correlationId -cne $record.correlationId -or $probe.address -cne $record.address -or $probe.port -ne $record.port -or
        [DateTimeOffset]$before.finishedUtc -gt [DateTimeOffset]$probe.startedUtc -or
        [DateTimeOffset]$probe.finishedUtc -gt [DateTimeOffset]$after.startedUtc -or
        [DateTimeOffset]$probe.startedUtc -lt [DateTimeOffset]$Isolation.preflightStartedUtc -or
        [DateTimeOffset]$probe.finishedUtc -gt [DateTimeOffset]$Isolation.preflightFinishedUtc){throw 'Sonda independiente no correlacionada.'}
    $observation=Read-BridgeJson $Root $Isolation.observation.path $Isolation.observation.sha256
    $events=@($observation.records[0].events|Where-Object{$_.correlationId -ceq $record.correlationId})
    if($events.Count -ne 1 -or [DateTimeOffset]$events[0].timestampUtc -lt [DateTimeOffset]$probe.startedUtc -or
        [DateTimeOffset]$events[0].timestampUtc -gt [DateTimeOffset]$probe.finishedUtc){throw 'Intento capturado fuera de ventana de sonda.'}
    $records=Get-BridgeField $proof 'listenerRecords'
    if($records -isnot [array]){throw 'Registros independientes ausentes.'}
    if(@($records|Where-Object{$_.correlationId -ceq $record.correlationId}).Count){throw 'El servidor recibio el intento bloqueado.'}
    foreach($control in @($before,$after)){
        if(@($records|Where-Object{$_.correlationId -ceq $control.correlationId}).Count -ne 1){throw 'Falta control positivo en el servidor independiente.'}
    }
}

function Assert-BridgeReviewChain($Evidence,[string]$Root,[string]$CatalogPath,[string]$CatalogHash,[string]$ScriptRoot) {
    Assert-BridgeEvidenceObject $Evidence $Root $CatalogPath $CatalogHash
    $reports=@()
    foreach($ref in $Evidence.reports){$reports+=Read-BridgeJson $Root $ref.path $ref.sha256}
    Assert-BridgeReviewScripts $reports $Root $ScriptRoot
    $candidateForDates=Read-BridgeJson $Root $Evidence.candidate.path $Evidence.candidate.sha256
    foreach($report in $reports){
        if([DateTimeOffset]$report.startedAtUtc -lt [DateTimeOffset]$candidateForDates.preparedAtUtc){throw 'Reporte anterior al candidato.'}
        if($report.groupId -cne 'rollbackControlsVerified'){
            $iso=Read-BridgeJson $Root $report.isolation.path $report.isolation.sha256
            Assert-BridgeReviewIndependentProof $iso $Root
        }
    }
}

function Get-BridgeReviewLockFiles($Evidence,[string]$Root,[string]$CatalogPath,[string]$ScriptRoot) {
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $null=$paths.Add([IO.Path]::GetFullPath($CatalogPath))
    $candidate=Read-BridgeJson $Root $Evidence.candidate.path $Evidence.candidate.sha256
    $null=$paths.Add((Get-BridgeSafeFile $Root $Evidence.candidate.path))
    foreach($prefix in @('jar','sourceArchive','sourceFilesManifest','buildRecipe')){$null=$paths.Add((Get-BridgeSafeFile $Root (Get-BridgeField $candidate ($prefix+'Path'))))}
    foreach($ref in $Evidence.reports){
        $null=$paths.Add((Get-BridgeSafeFile $Root $ref.path))
        $report=Read-BridgeJson $Root $ref.path $ref.sha256
        foreach($attachment in @($report.attachments)+@($report.scriptHashes)){$null=$paths.Add((Get-BridgeSafeFile $Root $attachment.path))}
        foreach($script in $report.scriptHashes){
            $path=$script.path.Replace('\','/');$marker=$path.LastIndexOf('/scripts/',[StringComparison]::Ordinal)
            $relative=if($marker -ge 0){$path.Substring($marker+9)}else{$path.Substring(8)}
            $null=$paths.Add((Get-BridgeSafeFile $ScriptRoot $relative))
        }
        if($report.groupId -cne 'rollbackControlsVerified'){
            $null=$paths.Add((Get-BridgeSafeFile $Root $report.isolation.path))
            $iso=Read-BridgeJson $Root $report.isolation.path $report.isolation.sha256
            foreach($field in @('topology','allowlist','observation','sentinelProof','syscallCoverage')){
                $isoRef=Get-BridgeField $iso $field
                $null=$paths.Add((Get-BridgeSafeFile $Root $isoRef.path))
            }
            $sentinel=Read-BridgeJson $Root $iso.sentinelProof.path $iso.sentinelProof.sha256
            $null=$paths.Add((Get-BridgeSafeFile $Root $sentinel.records[0].proofRef.path))
        }
    }
    return @($paths)
}

function Invoke-BridgeReview([string]$CandidatePath,[string[]]$ReportPaths,[string]$Reviewer,[string]$CatalogPath,[string]$ScriptRoot=$PSScriptRoot) {
    Assert-BridgeText $Reviewer 'ReviewedBy'
    if($null -eq $ReportPaths -or $ReportPaths.Count -ne 4){throw 'Review requiere exactamente cuatro reportes.'}
    $item=Get-Item -LiteralPath $CandidatePath -ErrorAction Stop
    if($item.PSIsContainer -or $item.Name -cne 'candidate.json'){throw 'Review requiere candidate.json.'}
    $root=$item.Directory.FullName
    $candidateHash=Get-BridgeHash (Get-BridgeSafeFile $root 'candidate.json')
    $candidateValue=Read-BridgeJson $root 'candidate.json' $candidateHash
    Assert-BridgeCandidate $candidateValue $root
    $catalogHash=Get-BridgeHash $CatalogPath
    $references=@();$paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $ReportPaths){
        $relative=Get-BridgeReviewRelativePath $root $path
        if(-not $paths.Add($relative)){throw 'Reporte de Review duplicado.'}
        $hash=Get-BridgeHash (Get-BridgeSafeFile $root $relative)
        $report=Read-BridgeJson $root $relative $hash
        $references+=[pscustomobject]@{path=$relative;sha256=$hash;groupId=(Get-BridgeField $report 'groupId')}
    }
    $evidence=[pscustomobject][ordered]@{
        schemaVersion=2;kind='reservation-bridge-review';catalogVersion='1.4.0';catalogSha256=$catalogHash
        runId=$candidateValue.runId;commit=$candidateValue.commit;jarPath=$candidateValue.jarPath;jarSha256=$candidateValue.jarSha256
        candidate=[pscustomobject]@{path='candidate.json';sha256=$candidateHash};reports=$references
        author=$Reviewer;reviewedAtUtc=[DateTime]::UtcNow.ToString('o');reviewScope='local-isolated'
        legacyReadsAuthorized=$true;v2ReadsVerified=$true;legacyBarrierVerified=$true;rollbackControlsVerified=$true
    }
    # Los true son derivados: el objeto no se publica si alguna validacion falla.
    Assert-BridgeReviewChain $evidence $root $CatalogPath $catalogHash $ScriptRoot
    $destination=Join-Path $root 'bridge-evidence.json'
    if(Test-Path -LiteralPath $destination){throw 'No se sobrescribe bridge-evidence.json existente.'}
    $locks=[Collections.Generic.List[IO.FileStream]]::new()
    try {
        foreach($file in @(Get-BridgeReviewLockFiles $evidence $root $CatalogPath $ScriptRoot)){
            $locks.Add([IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
        }
        Assert-BridgeReviewChain $evidence $root $CatalogPath $catalogHash $ScriptRoot
        $staging=Join-Path $root ('.review-'+[guid]::NewGuid().ToString('N')+'.tmp')
        Write-BridgeNewJson $staging $evidence
        $durable=[IO.File]::Open($staging,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try{$durable.Flush($true)}finally{$durable.Dispose()}
        $hash=Get-BridgeHash $staging
        $serialized=Read-BridgeJson $root ([IO.Path]::GetFileName($staging)) $hash
        Assert-BridgeReviewChain $serialized $root $CatalogPath $catalogHash $ScriptRoot
        # Move sin overwrite publica el archivo completo; ante interrupcion queda
        # staging privado conservado. Los insumos siguen bloqueados para escritura.
        if((Get-BridgeHash $staging) -ine $hash){throw 'Staging de Review alterado.'}
        [IO.File]::Move($staging,$destination)
    } finally { foreach($stream in $locks){$stream.Dispose()} }
    return [pscustomobject]@{path=$destination;sha256=(Get-BridgeHash $destination);state='Reviewed';reviewScope='local-isolated'}
}
