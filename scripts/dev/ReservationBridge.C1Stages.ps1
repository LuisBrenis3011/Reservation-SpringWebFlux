# Casos historicos en un arbol nuevo: scripts identicos, politica doble y sin transporte.
function Invoke-BridgeC1HistoricalRejection([string]$Directory,[string]$Mode,[string]$Stage,[string]$State) {
    if($Mode -cnotin @('DEFAULT','COMBINATIONS','SHIFTS') -or $Stage -cnotin @('PREPARE','STARTPREVIOUS','PREVIOUS','CURRENT') -or $State -cnotin @('NOCUT','CUT','READFAIL')){throw 'Caso historico no soportado.'}
    $sandbox=Join-Path $Directory ('c1-stage-'+[guid]::NewGuid().ToString('N'))
    $scripts=Join-Path $sandbox 'scripts/dev';$private=Join-Path $sandbox 'secrets/local-identity'
    [IO.Directory]::CreateDirectory($scripts)|Out-Null
    [IO.Directory]::CreateDirectory($private)|Out-Null
    foreach($name in @('Test-LocalVersionRollback.ps1','LocalIdentity.Common.ps1','ManagedReservations.Common.ps1','read-managed-reservation-policy.js','mongo-backup-manifest.js')) {
        $source=Get-BridgeSafeFile $PSScriptRoot $name
        $destination=Join-Path $scripts $name
        [IO.File]::Copy($source,$destination,$false)
        if((Get-BridgeHash $source) -ine (Get-BridgeHash $destination)){throw 'Copia de script C1 alterada.'}
    }
    [IO.File]::WriteAllText((Join-Path $sandbox '.env'),"MONGODB_HOST=localhost`nMONGODB_PORT=27018`nMONGODB_DATABASE=c1_synthetic`n",[Text.UTF8Encoding]::new($false))
    $sessionName=switch($Mode){'DEFAULT'{'rollback-session.json'}'COMBINATIONS'{'combinations-rollback-session.json'}'SHIFTS'{'shifts-rollback-session.json'}}
    $session=Join-Path $private $sessionName
    $folder=Join-Path $sandbox 'backups/availability-rollback/synthetic'
    [IO.Directory]::CreateDirectory($folder)|Out-Null
    $jar=Join-Path $folder 'previous.jar';[IO.File]::WriteAllText($jar,'fixture')
    [IO.File]::WriteAllText((Join-Path $folder 'database-before.json'),'{}')
    $sessionValue=@{folder=$folder;jar=$jar;jarSha256=(Get-BridgeHash $jar);targetCommit='81f0e6145fbf8c82fd81fae7669aa82d3c9660f5';database='c1_synthetic';previousStartedUtc=$null;previousVerifiedUtc=$null}
    [IO.File]::WriteAllText($session,($sessionValue|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $backup=Join-Path $sandbox 'backups/availability/synthetic'
    [IO.Directory]::CreateDirectory($backup)|Out-Null
    if($Mode -ceq 'COMBINATIONS' -or $Mode -ceq 'SHIFTS'){
        $number=if($Mode -ceq 'COMBINATIONS'){'002'}else{'003'}
        $checkpoint=if($Mode -ceq 'COMBINATIONS'){'combinations-http-checkpoint.json'}else{'shifts-http-checkpoint.json'}
        [IO.File]::WriteAllText((Join-Path $backup ('spec-'+$number+'-validation.json')),('{"spec":"SPEC-'+$number+'","restoreVerified":false}'))
        [IO.File]::WriteAllText((Join-Path $private $checkpoint),'{}')
    }
    $before=Get-BridgeHash $session
    if($null -ne (Get-Variable BridgeC1SyntheticProbe -Scope Global -ErrorAction SilentlyContinue)){throw 'Sonda C1 ya activa; no se comparte estado.'}
    $module=New-Module -ArgumentList $State -ScriptBlock {
        param($stateValue)
        $global:BridgeC1SyntheticProbe=[pscustomobject]@{state=$stateValue;policyReads=0;blockedActions=0;manifestBoundary=0}
        function docker {
            if($global:BridgeC1SyntheticProbe.policyReads -gt 0){$global:BridgeC1SyntheticProbe.manifestBoundary++;throw 'C1_LIMITE_MANIFIESTO'}
            $global:BridgeC1SyntheticProbe.policyReads++
            if($global:BridgeC1SyntheticProbe.state -ceq 'READFAIL'){throw 'C1_DOBLE_LECTURA_FALLIDA'}
            $global:LASTEXITCODE=0
            if($global:BridgeC1SyntheticProbe.state -ceq 'NOCUT'){return '{"verified":true,"retired":false}'}
            return '{"verified":true,"retired":true}'
        }
        function git { $global:BridgeC1SyntheticProbe.blockedActions++;throw 'C1_ACCION_EXTERNA_PROHIBIDA' }
        function java { $global:BridgeC1SyntheticProbe.blockedActions++;throw 'C1_ACCION_EXTERNA_PROHIBIDA' }
        function Invoke-WebRequest { $global:BridgeC1SyntheticProbe.blockedActions++;throw 'C1_ACCION_EXTERNA_PROHIBIDA' }
        function Invoke-RestMethod { $global:BridgeC1SyntheticProbe.blockedActions++;throw 'C1_ACCION_EXTERNA_PROHIBIDA' }
        function Get-NetTCPConnection { return @() }
        function Get-CimInstance { $global:BridgeC1SyntheticProbe.blockedActions++;throw 'C1_ACCION_EXTERNA_PROHIBIDA' }
        function Start-Process { $global:BridgeC1SyntheticProbe.blockedActions++;throw 'C1_ACCION_EXTERNA_PROHIBIDA' }
        function Invoke-HistoricalEntry([string]$Path,[string]$Mode,[string]$Stage,[string]$Backup) {
            $argsMap=@{Stage=$Stage;WritersStopped=$true}
            if($Mode -ceq 'COMBINATIONS'){$argsMap.IncludeCombinations=$true}
            if($Mode -ceq 'SHIFTS'){$argsMap.IncludeShifts=$true}
            if($Mode -cne 'DEFAULT'){$argsMap.BackupDirectory=$Backup}
            $failure='';try { & $Path @argsMap } catch { $failure=$_.Exception.Message }
            return [pscustomobject]@{failure=$failure;policyReads=$global:BridgeC1SyntheticProbe.policyReads;blockedActions=$global:BridgeC1SyntheticProbe.blockedActions;manifestBoundary=$global:BridgeC1SyntheticProbe.manifestBoundary}
        }
        Export-ModuleMember -Function Invoke-HistoricalEntry
    }
    $lastExitVariable=Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $hadExit=$null -ne $lastExitVariable
    if($hadExit){$previousExit=$lastExitVariable.Value}
    try {
        $stageName=@{PREPARE='Prepare';STARTPREVIOUS='StartPrevious';PREVIOUS='Previous';CURRENT='Current'}[$Stage]
        $result=& $module {param($p,$m,$s,$b) Invoke-HistoricalEntry $p $m $s $b} (Join-Path $scripts 'Test-LocalVersionRollback.ps1') $Mode $stageName $backup
    } finally {
        Remove-Module $module -Force -ErrorAction SilentlyContinue
        Remove-Variable BridgeC1SyntheticProbe -Scope Global -ErrorAction SilentlyContinue
        if($hadExit){$global:LASTEXITCODE=$previousExit}else{Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue}
    }
    $expected=if($State -ceq 'CUT'){'Corte persistente activo'}elseif($State -ceq 'READFAIL'){'C1_DOBLE_LECTURA_FALLIDA'}elseif($Mode -cne 'DEFAULT'){'Respaldo o checkpoints de SPEC-00'}elseif($Stage -ceq 'PREPARE'){'Ya existe una sesion de reversion'}elseif($Stage -ceq 'STARTPREVIOUS'){'C1_LIMITE_MANIFIESTO'}else{'Se requiere una unica aplicacion escuchando'}
    $preserved=(Get-BridgeHash $session) -ieq $before
    $passed=($result.failure -like ('*'+$expected+'*')) -and $result.policyReads -eq 1 -and $result.blockedActions -eq 0 -and $preserved
    return [pscustomobject]@{passed=$passed;policyReads=$result.policyReads;blockedActions=$result.blockedActions;sessionPreserved=$preserved;rejection=$result.failure;manifestBoundary=$result.manifestBoundary;sandbox=$sandbox}
}

# La fixture v2 se fabrica en scope separado; el consumidor ejercitado es el real.
# Nunca se transportan las fixtures sintéticas como evidencia de aislamiento real.
function Invoke-BridgeC1AlterationCases {
    $fixtureRoot=& { . (Join-Path $PSScriptRoot 'Test-ReservationBridgeReviewAssertions.ps1'); $reviewFixtureRoot }
    $entry=Join-Path $PSScriptRoot 'Test-LocalManagedReservationRollback.ps1'
    $module=New-Module -ArgumentList $entry,$fixtureRoot -ScriptBlock {
        param($entryPath,$fixturePath)
        . $entryPath -Stage StartPrevious
        $script:ManagedBridgeCatalog=Join-Path $fixturePath 'catalog.md'
        $script:ManagedBridgeScripts=Join-Path $fixturePath 'current-scripts'
        $script:IdentityRoot=Join-Path $fixturePath 'c1-managed-root'
        $script:IdentityPrivate=Join-Path $script:IdentityRoot 'secrets/local-identity'
        [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
        $script:Stage='StartPrevious';$script:BridgeEvidence=Join-Path $fixturePath 'bridge-evidence.json'
        $script:BridgeCommit='';$script:BackupDirectory='';$script:WritersStopped=$true
        $bridge=Assert-ManagedBridge $script:BridgeEvidence
        $folder=Join-Path $script:IdentityRoot 'backups/managed-rollback/synthetic'
        [IO.Directory]::CreateDirectory($folder)|Out-Null
        $jar=Join-Path $folder 'bridge-certified.jar'
        [IO.File]::Copy($bridge.jarPath,$jar,$false)
        $session=[pscustomobject]@{schemaVersion=2;spec='SPEC-005';bridgeCommit=$bridge.commit;currentCommit=('a'*40);backupDirectory='unused';backupProofSha256=('a'*64);folder=$folder;jar=$jar;jarSha256=$bridge.jarSha256;bridgeEvidencePath=$bridge.path;bridgeEvidenceSha256=$bridge.sha256;catalogSha256=$bridge.catalogSha256;candidateSha256=$bridge.candidateSha256;reportHashes=$bridge.reportHashes;previousStarted=$false;previousVerified=$false;currentVerified=$false}
        $sessionPath=Join-Path $script:IdentityPrivate 'managed-reservations-rollback-session.json'
        [IO.File]::WriteAllText($sessionPath,($session|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
        $script:c1BoundaryCalls=0
        function Initialize-ManagedMode { $script:c1BoundaryCalls++;throw 'C1_LIMITE_CONTROL_POSITIVO' }
        function Invoke-C1Entry { try{Invoke-ManagedRollback;return ''}catch{return $_.Exception.Message} }
        function Invoke-C1Alterations {
            $baseline=Invoke-C1Entry
            if($baseline -cne 'C1_LIMITE_CONTROL_POSITIVO' -or $script:c1BoundaryCalls -ne 1){throw ('Control positivo de sesion no llego al limite: '+$baseline)}
            $script:c1BoundaryCalls=0
            $originalJar=[IO.File]::ReadAllBytes($jar)
            try{[IO.File]::WriteAllText($jar,'JAR distinto, mismo commit');$jarFailure=Invoke-C1Entry}finally{[IO.File]::WriteAllBytes($jar,$originalJar)}
            $jarPassed=$jarFailure -like '*JAR de sesion ausente, ajeno o alterado*' -and $script:c1BoundaryCalls -eq 0
            $originalEvidence=[IO.File]::ReadAllBytes($script:BridgeEvidence)
            try{[IO.File]::AppendAllText($script:BridgeEvidence,' ');$evidenceFailure=Invoke-C1Entry}finally{[IO.File]::WriteAllBytes($script:BridgeEvidence,$originalEvidence)}
            $evidencePassed=$evidenceFailure -like '*evidencia o sus referencias cambiaron*' -and $script:c1BoundaryCalls -eq 0
            return [pscustomobject]@{jar=[pscustomobject]@{passed=$jarPassed;reason=$jarFailure;boundaryCalls=$script:c1BoundaryCalls};evidence=[pscustomobject]@{passed=$evidencePassed;reason=$evidenceFailure;boundaryCalls=$script:c1BoundaryCalls};fixture=$fixturePath}
        }
        Export-ModuleMember -Function Invoke-C1Alterations
    }
    try{return (& $module {Invoke-C1Alterations})}finally{Remove-Module $module -Force -ErrorAction SilentlyContinue}
}
