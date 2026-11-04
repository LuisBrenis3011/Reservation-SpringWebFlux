# Ejecutores del catalogo 1.4.0. Cargar funciones no realiza operaciones externas.
. (Join-Path $PSScriptRoot 'ReservationBridge.C1Stages.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.C1Remaining.ps1')
function New-BridgeCatalogCases([string]$Group) {
    $map=Get-BridgeCases $Group
    return @($map.Keys | ForEach-Object { [pscustomobject]@{id=$_;level=$map[$_];expected=$true;actual=$false;passed=$false;executed=$false;executionStatus='Pending';observed=$null} })
}

function Set-BridgeCatalogCase($Cases,[string]$Id,[bool]$Passed,$Observed) {
    $matches=@($Cases | Where-Object { $_.id -ceq $Id })
    if ($matches.Count -ne 1) { throw 'Caso del catalogo ausente o duplicado.' }
    $matches[0].actual=$Passed;$matches[0].passed=$Passed;$matches[0].executed=$true;$matches[0].observed=$Observed
    $matches[0].executionStatus=if($Passed){'Passed'}else{'Failed'}
}

function ConvertTo-BridgeCanonicalJson($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [array]) { return '['+((@($Value | ForEach-Object { ConvertTo-BridgeCanonicalJson $_ })) -join ',')+']' }
    if ($Value -is [Collections.IDictionary]) {
        return '{'+((@($Value.Keys | Sort-Object -CaseSensitive | ForEach-Object { (ConvertTo-Json -InputObject ([string]$_) -Compress)+':'+(ConvertTo-BridgeCanonicalJson $Value[$_]) })) -join ',')+'}'
    }
    if ($Value -is [pscustomobject]) {
        return '{'+((@($Value.PSObject.Properties | Sort-Object Name -CaseSensitive | ForEach-Object { (ConvertTo-Json -InputObject $_.Name -Compress)+':'+(ConvertTo-BridgeCanonicalJson $_.Value) })) -join ',')+'}'
    }
    return ConvertTo-Json -InputObject $Value -Depth 40 -Compress
}

function Test-BridgeJsonEqual($Left,$Right) { return (ConvertTo-BridgeCanonicalJson $Left) -ceq (ConvertTo-BridgeCanonicalJson $Right) }

function Invoke-BridgeCatalogDockerInput([string[]]$Arguments,[string]$InputText) {
    $previous=$OutputEncoding
    try {
        $OutputEncoding=[Text.UTF8Encoding]::new($false)
        $output=@($InputText | & docker @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) { throw 'Transporte aislado fallo; no se acreditan casos HTTP.' }
        return $output
    } finally { $OutputEncoding=$previous }
}

function Invoke-BridgeCatalogRequest($Context,$Observation,[string]$Method,[string]$Path,$Token,$Body=$null) {
    Assert-BridgeObservationAlive $Observation
    $request=@{baseUri=$Context.baseUri;method=$Method;path=$Path;token=$Token;body=$Body}|ConvertTo-Json -Depth 30 -Compress
    $raw=@(Invoke-BridgeCatalogDockerInput @('exec','-i',$Context.containers.TOOLS,'python3','/opt/bridge_http.py') $request)
    Assert-BridgeObservationAlive $Observation
    $response=($raw -join "`n")|ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $response -or $null -ne $response.PSObject.Properties['transportError']) { throw 'Respuesta de transporte aislado invalida.' }
    return $response
}

function Test-BridgeCatalogError($Response,[int]$Status,[string]$Code) {
    if ($Response.status -ne $Status -or $null -eq $Response.body -or $Response.body -is [array]) { return $false }
    $body=$Response.body
    foreach($required in @('code','message','status','operationId','timestamp')) { if ($null -eq $body.PSObject.Properties[$required]) { return $false } }
    # Un error solo expone el contrato de error, nunca campos de una reserva.
    foreach($p in $body.PSObject.Properties) { if (@('code','message','status','operationId','timestamp') -cnotcontains $p.Name) { return $false } }
    return $body.code -ceq $Code -and $body.status -eq $Status -and $null -ne $body.PSObject.Properties['operationId'] -and $null -ne $body.PSObject.Properties['timestamp']
}

function Test-BridgeManagedResponse($Response,$Expected) {
    return $Response.status -eq 200 -and $Response.etag -ceq ('"'+$Expected.version+'"') -and (Test-BridgeJsonEqual $Response.body $Expected)
}

function Get-BridgeSanitizedEtag($Value) { if ($Value -is [string] -and $Value -cmatch '^"[0-9]+"$') { return $Value };return $null }

function Wait-BridgeCatalogApplication($Context,$Observation) {
    $deadline=[DateTime]::UtcNow.AddSeconds(60)
    do {
        Assert-BridgeObservationAlive $Observation
        try {
            $response=Invoke-BridgeCatalogRequest $Context $Observation 'GET' ('/reservation/'+$Context.fixtures.legacyId) $null
            if(Test-BridgeCatalogError $response 401 'UNAUTHENTICATED'){Assert-BridgeApplicationProcess $Context;return}
        } catch { Assert-BridgeObservationAlive $Observation }
        Start-Sleep -Milliseconds 250
    } while([DateTime]::UtcNow -lt $deadline)
    throw 'La aplicacion no completo arranque autorizado dentro del plazo.'
}

function Invoke-BridgeHttpCatalog($Context,$Observation) {
    $legacy=New-BridgeCatalogCases 'legacyReadsAuthorized'
    $v2=New-BridgeCatalogCases 'v2ReadsVerified'
    $barrier=@(New-BridgeCatalogCases 'legacyBarrierVerified' | Where-Object { $_.level -cne 'SOURCE_EXPORTED' })
    $helper=Join-Path $PSScriptRoot 'bridge/bridge_http.py'
    $null=Invoke-BridgeIsolationDocker @('cp',$helper,($Context.containers.TOOLS+':/opt/bridge_http.py'))
    $fixture=$Context.fixtures;$tokens=$Context.tokens
    Assert-BridgeObservationAlive $Observation
    Start-BridgeEnvironmentApplication $Context $true
    Wait-BridgeCatalogApplication $Context $Observation
    Assert-BridgeObservationAlive $Observation
    $before=Invoke-BridgeEnvironmentManifest $Context
    $path='/reservation/'+$fixture.legacyId
    $r=Invoke-BridgeCatalogRequest $Context $Observation 'GET' $path $tokens.manager
    $valid=$r.status -eq 200 -and $r.body.kind -ceq 'LEGACY' -and $r.body.restaurantId -ceq $fixture.restaurantId -and
        $r.body.status -ceq 'PENDING' -and $r.body.customerName -ceq 'Bridge legacy' -and
        $r.body.partySize -eq 2 -and $r.body.notes -ceq 'bridge-legacy-secret' -and
        $r.body.date -ceq '2019-01-01' -and $r.body.time -ceq '18:00'
    try {
        $encoded=$r.body.legacyRef.Replace('-','+').Replace('_','/')
        $encoded=$encoded.PadRight($encoded.Length+((4-$encoded.Length%4)%4),'=')
        $decoded=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))|ConvertFrom-Json -ErrorAction Stop
        $valid=$valid -and $decoded._id -ceq $fixture.legacyId -and @($decoded.PSObject.Properties).Count -eq 1
    } catch { $valid=$false }
    # Proyeccion exacta cuando el entorno la proporciona; siempre rechazar campos privados.
    if ($null -ne $fixture.PSObject.Properties['expectedLegacy']) { $valid=$valid -and (Test-BridgeJsonEqual $r.body $fixture.expectedLegacy) }
    if ($null -ne $r.body) { foreach($p in $r.body.PSObject.Properties) { if (@('kind','legacyRef','restaurantId','status','customerName','date','time','partySize','notes') -cnotcontains $p.Name) { $valid=$false } } }
    Set-BridgeCatalogCase $legacy 'LEG-01' $valid @{status=$r.status}
    $r=Invoke-BridgeCatalogRequest $Context $Observation 'GET' $path $null
    Set-BridgeCatalogCase $legacy 'LEG-02' (Test-BridgeCatalogError $r 401 'UNAUTHENTICATED') @{status=$r.status}
    $r=Invoke-BridgeCatalogRequest $Context $Observation 'GET' $path $tokens.owner
    Set-BridgeCatalogCase $legacy 'LEG-03' (Test-BridgeCatalogError $r 403 'FORBIDDEN') @{status=$r.status}
    $r=Invoke-BridgeCatalogRequest $Context $Observation 'GET' $path $tokens.otherManager
    Set-BridgeCatalogCase $legacy 'LEG-04' (Test-BridgeCatalogError $r 404 'NOT_FOUND') @{status=$r.status}
    $after=Invoke-BridgeEnvironmentManifest $Context
    $preserved=Test-BridgeJsonEqual $before $after
    Set-BridgeCatalogCase $legacy 'LEG-05' $preserved @{manifestPreserved=$preserved}
    if (-not $preserved) { throw 'Lecturas antiguas alteraron el manifiesto.' }

    $before=Invoke-BridgeEnvironmentManifest $Context
    $path='/restaurants/'+$fixture.restaurantId+'/reservations/'
    $confirmed=Invoke-BridgeCatalogRequest $Context $Observation 'GET' ($path+$fixture.confirmedId) $tokens.owner
    Set-BridgeCatalogCase $v2 'V2-01' (Test-BridgeManagedResponse $confirmed $fixture.expectedConfirmed) @{status=$confirmed.status;etag=(Get-BridgeSanitizedEtag $confirmed.etag)}
    $cancelled=Invoke-BridgeCatalogRequest $Context $Observation 'GET' ($path+$fixture.cancelledId) $tokens.owner
    Set-BridgeCatalogCase $v2 'V2-02' (Test-BridgeManagedResponse $cancelled $fixture.expectedCancelled) @{status=$cancelled.status;etag=(Get-BridgeSanitizedEtag $cancelled.etag)}
    $snapshotValid=(Test-BridgeManagedResponse $confirmed $fixture.expectedConfirmed) -and (Test-BridgeManagedResponse $cancelled $fixture.expectedCancelled)
    Set-BridgeCatalogCase $v2 'V2-03' $snapshotValid @{historicalProjectionsPreserved=$snapshotValid}
    $r=Invoke-BridgeCatalogRequest $Context $Observation 'GET' ($path+$fixture.confirmedId) $tokens.otherCustomer
    Set-BridgeCatalogCase $v2 'V2-04' (Test-BridgeCatalogError $r 404 'NOT_FOUND') @{status=$r.status}
    $manager=Invoke-BridgeCatalogRequest $Context $Observation 'GET' ($path+$fixture.confirmedId) $tokens.manager
    $otherManager=Invoke-BridgeCatalogRequest $Context $Observation 'GET' ($path+$fixture.confirmedId) $tokens.otherManager
    Set-BridgeCatalogCase $v2 'V2-05' ((Test-BridgeManagedResponse $manager $fixture.expectedConfirmed) -and (Test-BridgeCatalogError $otherManager 403 'FORBIDDEN')) @{localStatus=$manager.status;foreignStatus=$otherManager.status}
    $after=Invoke-BridgeEnvironmentManifest $Context
    $preserved=Test-BridgeJsonEqual $before $after
    Set-BridgeCatalogCase $v2 'V2-06' $preserved @{manifestPreserved=$preserved}
    if (-not $preserved) { throw 'Lecturas v2 alteraron el manifiesto.' }

    foreach($gate in @('OFF','ON')) {
        Assert-BridgeObservationAlive $Observation
        Start-BridgeEnvironmentApplication $Context ($gate -ceq 'ON')
        Wait-BridgeCatalogApplication $Context $Observation
        Assert-BridgeObservationAlive $Observation
        foreach($method in @('POST','PUT','DELETE')) {
            $before=Invoke-BridgeEnvironmentManifest $Context
            $route=if($method -ceq 'POST'){'/reservation'}else{'/reservation/'+$fixture.legacyId}
            $body=if($method -ceq 'DELETE'){$null}else{@{restaurantId=$fixture.restaurantId;customerName='Sintetico';partySize=2;notes='bridge-only';date='2035-01-01';time='12:00:00'}}
            $r=Invoke-BridgeCatalogRequest $Context $Observation $method $route $tokens.manager $body
            $after=Invoke-BridgeEnvironmentManifest $Context
            $preserved=Test-BridgeJsonEqual $before $after
            Set-BridgeCatalogCase $barrier ('BARRIER-HTTP-'+$method+'-'+$gate) ((Test-BridgeCatalogError $r 410 'LEGACY_WRITES_RETIRED') -and $preserved) @{status=$r.status;manifestPreserved=$preserved}
            if (-not $preserved) { throw 'Escritura antigua altero el manifiesto pese al corte.' }
        }
    }
    Assert-BridgeObservationAlive $Observation
    $trace=[ordered]@{kind='reservation-bridge-http-catalog';runId=$Context.runId;legacy=$legacy;v2=$v2;barrier=$barrier}
    $tracePath=Join-Path $Context.directory 'http-catalog.json'
    Write-BridgeNewJson $tracePath $trace
    $relative=$tracePath.Substring($Context.root.TrimEnd([char[]]'\/').Length+1).Replace('\','/')
    return [pscustomobject]@{groups=@{legacyReadsAuthorized=$legacy;v2ReadsVerified=$v2;legacyBarrierVerified=$barrier};attachments=@(@{path=$relative;sha256=(Get-BridgeHash $tracePath)})}
}

function Invoke-BridgeC1Catalog($Context) {
    $cases=New-BridgeCatalogCases 'rollbackControlsVerified'
    $helper=Join-Path $PSScriptRoot 'ManagedReservations.Common.ps1'
    # El modulo aísla variables script y el lector doble. Cargar el helper no
    # invoca Initialize-ManagedMode ni lee .env, sesiones o transportes del origen.
    $module=New-Module -ArgumentList $helper -ScriptBlock {
        param($HelperPath)
        . $HelperPath
        function Read-ManagedPolicy {
            if ($script:BridgeC1ReadFailure) { throw 'Fallo sintetico de lectura C1' }
            return $script:BridgeC1Policy
        }
        function Invoke-BridgeC1Guard([bool]$Managed,[string]$State,[bool]$Race) {
            $script:ManagedMode=$Managed;$script:ManagedExpectedRetired=$null
            $script:BridgeC1ReadFailure=$false;$script:BridgeC1Actions=0
            if ($Race) {
                $script:BridgeC1Policy=[pscustomobject]@{verified=$true;retired=$false}
                $null=Assert-LiveManagedMode
                $script:ManagedExpectedRetired=$false
            }
            $script:BridgeC1ReadFailure=$State -ceq 'READFAIL'
            $script:BridgeC1Policy=[pscustomobject]@{verified=$true;retired=($State -ceq 'CUT')}
            $rejected=$false
            try {
                $null=Assert-LiveManagedMode
                $script:BridgeC1Actions++ # acción instrumentada; nunca proceso/compilación/escritura
            } catch { $rejected=$true }
            return [pscustomobject]@{rejected=$rejected;instrumentedActions=$script:BridgeC1Actions;externalCommands=0}
        }
        Export-ModuleMember -Function Invoke-BridgeC1Guard
    }
    try {
        foreach($case in $cases) {
            $guardFailed=$false
            $match=[regex]::Match($case.id,'^C1-(DEFAULT|COMBINATIONS|SHIFTS|MANAGED)-(PREPARE|STARTPREVIOUS|PREVIOUS|CURRENT)-(NOCUT|CUT|READFAIL)$')
            if ($match.Success) {
                $mode=$match.Groups[1].Value;$state=$match.Groups[3].Value
                $diagnostic=& $module {param($Managed,$State) Invoke-BridgeC1Guard $Managed $State $false} ($mode -ceq 'MANAGED') $state
                $case.observed=[pscustomobject]@{guardRejected=$diagnostic.rejected;instrumentedActions=$diagnostic.instrumentedActions;externalCommands=$diagnostic.externalCommands;stage=$match.Groups[2].Value}
                $expectedReject=$state -ceq 'READFAIL' -or ($state -ceq 'CUT' -and $mode -cne 'MANAGED')
                $expectedActions=if($expectedReject){0}else{1}
                $guardFailed=$diagnostic.rejected -ne $expectedReject -or $diagnostic.instrumentedActions -ne $expectedActions -or $diagnostic.externalCommands -ne 0
                # El guard es real, pero su llamada aislada NO acredita que cada
                # etapa operativa valide sesión/respaldo/evidencia v2 antes de actuar.
                $case.actual=if($mode -ceq 'MANAGED' -and $state -ceq 'NOCUT'){'Guard ejercitado; falta acreditar rechazo de la etapa gestionada sin corte'}else{'Guard ejercitado; etapa operativa y evidencia v2 no acreditadas'}
            } elseif ($case.id -cmatch '^C1-RACE-(DEFAULT|COMBINATIONS|SHIFTS)$' -or $case.id -ceq 'C1-SESSION-HISTORY') {
                $diagnostic=& $module {Invoke-BridgeC1Guard $false 'CUT' $true}
                $case.observed=[pscustomobject]@{guardRejected=$diagnostic.rejected;instrumentedActions=$diagnostic.instrumentedActions;externalCommands=$diagnostic.externalCommands}
                $guardFailed=-not $diagnostic.rejected -or $diagnostic.instrumentedActions -ne 0
                $case.actual='Transicion del guard ejercitada; sesion y etapa real no acreditadas'
            } else {
                $case.actual='Consumidor operativo de evidencia v2 pendiente; alteracion no acreditada'
            }
            $case.expected='Etapa operativa C1 completa conforme al catalogo'
            $case.executed=$null -ne $case.observed
            $case.executionStatus='Pending';$case.passed=$false
            if($guardFailed){$case.executionStatus='Failed';$case.actual='Regresion del guard real o accion alcanzada tras rechazo'}
            if(-not $guardFailed -and $match.Success -and $mode -cne 'MANAGED' -and $state -cin @('NOCUT','CUT','READFAIL')) {
                try {
                    $stageResult=Invoke-BridgeC1HistoricalRejection $Context.directory $mode $match.Groups[2].Value $state
                    $case.observed=$stageResult;$case.expected=$true;$case.actual=[bool]$stageResult.passed
                    $case.executed=$true;$case.passed=[bool]$stageResult.passed
                    $case.executionStatus=if($stageResult.passed){'Passed'}else{'Failed'}
                } catch { $case.actual='Etapa historica no acreditada: '+$_.Exception.Message;$case.executionStatus='Pending';$case.passed=$false }
            }
        }
        try {
            $alterations=Invoke-BridgeC1AlterationCases
            foreach($item in @(@{id='C1-JAR-ALTERED';result=$alterations.jar},@{id='C1-EVIDENCE-ALTERED';result=$alterations.evidence})) {
                $case=@($cases|Where-Object {$_.id -ceq $item.id})
                if($case.Count -ne 1){throw 'Caso de alteracion ausente o duplicado.'}
                $case[0].observed=$item.result;$case[0].expected=$true;$case[0].actual=[bool]$item.result.passed
                $case[0].executed=$true;$case[0].passed=[bool]$item.result.passed
                $case[0].executionStatus=if($item.result.passed){'Passed'}else{'Failed'}
            }
        } catch {
            foreach($id in @('C1-JAR-ALTERED','C1-EVIDENCE-ALTERED')) {
                $case=@($cases|Where-Object {$_.id -ceq $id})
                if($case.Count -eq 1 -and $case[0].executionStatus -cne 'Failed'){$case[0].actual='Alteracion no acreditada: '+$_.Exception.Message;$case[0].passed=$false;$case[0].executionStatus='Pending'}
            }
        }
        # Se ejecuta cada etapa con sus prerrequisitos: nunca derivar Passed del
        # diagnostico del guard ni de la cantidad de casos.
        $remaining=@{}
        if($null -ne (Get-Variable alterations -Scope Local -ErrorAction SilentlyContinue) -and $null -ne $alterations){
            try{$managed=Invoke-BridgeC1ManagedCases $alterations.fixture;foreach($id in $managed.Keys){$remaining[$id]=$managed[$id]}}
            catch{foreach($case in @($cases|Where-Object {$_.id -clike 'C1-MANAGED-*' -and $_.executionStatus -cne 'Failed'})){$case.actual='Preparacion gestionada no acreditada: '+$_.Exception.Message}}
        }
        try{$historical=Invoke-BridgeC1HistoryCases $Context.directory;foreach($id in $historical.Keys){$remaining[$id]=$historical[$id]}}
        catch{foreach($case in @($cases|Where-Object {($_.id -clike 'C1-RACE-*' -or $_.id -ceq 'C1-SESSION-HISTORY') -and $_.executionStatus -cne 'Failed'})){$case.actual='Sesion historica no acreditada: '+$_.Exception.Message}}
        foreach($id in $remaining.Keys){
            $case=@($cases|Where-Object {$_.id -ceq $id})
            if($case.Count -ne 1){throw 'Resultado restante C1 ajeno al catalogo.'}
            if($case[0].executionStatus -ceq 'Failed'){continue}
            $result=$remaining[$id];$pending=$null -ne $result.PSObject.Properties['pending'] -and $result.pending
            $case[0].observed=$result;$case[0].expected=$true;$case[0].actual=[bool]$result.passed
            $case[0].executed=-not $pending;$case[0].passed=[bool]$result.passed -and -not $pending
            $case[0].executionStatus=if($pending){'Pending'}elseif($case[0].passed){'Passed'}else{'Failed'}
        }
    } finally { Remove-Module $module -Force -ErrorAction SilentlyContinue }
    $path=Join-Path $Context.directory 'c1-catalog.json'
    Write-BridgeNewJson $path @{kind='reservation-bridge-c1-synthetic';runId=$Context.runId;scope='operational-entries-with-synthetic-transports';cases=$cases}
    $relative=$path.Substring($Context.root.TrimEnd([char[]]'\/').Length+1).Replace('\','/')
    return [pscustomobject]@{groups=@{rollbackControlsVerified=$cases};attachments=@(@{path=$relative;sha256=(Get-BridgeHash $path)})}
}
