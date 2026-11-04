# Controlador de observacion. Cargar este archivo no ejecuta Docker.
function Assert-BridgeDeniedProbeObservable($Probe){
    if($null -eq $Probe -or $Probe.connected -isnot [bool] -or $Probe.acknowledged -isnot [bool]){throw 'Sonda de centinela incompleta.'}
    if($Probe.connected -or $Probe.acknowledged){throw 'El intento de centinela establecio conexion; aislamiento fallido.'}
    if($null -eq $Probe.errorCode -or ($Probe.errorCode -isnot [int] -and $Probe.errorCode -isnot [long]) -or $Probe.errorCode -le 0){throw 'Sonda sin resultado de error verificable.'}
    # El error no prueba observacion: el evento SYSCALL correlacionado se exige
    # por separado. Un no-route es admisible solo con esa prueba de cobertura.
}
function Start-BridgeTraceTarget($Observation,[string]$Id,[int]$TargetPid,[string]$Kind,[string]$Correlation=''){
    Set-BridgeObservationJson $Observation.observerId '/opt/bridge-trace-request.json' @{id=$Id;pid=$TargetPid;kind=$Kind;correlationId=$Correlation}
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    do{
        $state=Update-BridgeObservationState $Observation
        if($state.status -cne 'RUNNING'){throw 'Observador no disponible al conectar strace.'}
        $targets=@($state.traceTargets|Where-Object {$_.id -ceq $Id -and $_.pid -eq $TargetPid -and $_.kind -ceq $Kind -and $_.ready -eq $true})
        if($targets.Count -eq 1){return}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    throw 'No se verifico strace antes de ejecutar el objetivo.'
}
function Invoke-BridgeTracedObservationProbe($Observation,[string]$Address,[int]$Port,[int]$SourcePort,[string]$Correlation){
    $id=[guid]::NewGuid().ToString('N');$prefix='/opt/bridge-probe-'+$id
    $marker='bridge-trace-'+$Observation.runId+'-'+$id
    $shell='echo $$ > '+$prefix+'.pid; kill -STOP $$; exec python3 /opt/bridge_probe.py "$@" > '+$prefix+'.json'
    $null=Invoke-BridgeIsolationDocker @('exec','-d',$Observation.observerId,'/bin/sh','-c',$shell,$marker,$Address,[string]$Port,[string]$SourcePort,$Correlation)
    $deadline=[DateTime]::UtcNow.AddSeconds(10);$pidValue=0
    do{
        try{$raw=@(Invoke-BridgeIsolationDocker @('exec',$Observation.observerId,'cat',($prefix+'.pid')));if($raw.Count -eq 1){$pidValue=[int]$raw[0]}}catch{}
        if($pidValue -le 1){Start-Sleep -Milliseconds 100}
    }while($pidValue -le 1 -and [DateTime]::UtcNow -lt $deadline)
    if($pidValue -le 1){throw 'Sonda detenida no identificable.'}
    Start-BridgeTraceTarget $Observation $id $pidValue 'probe' $Correlation
    do{
        try{$result=Get-BridgeObservationJson $Observation.observerId ($prefix+'.json');return $result}catch{}
        $state=Update-BridgeObservationState $Observation
        if($state.status -cne 'RUNNING'){throw 'Observacion de sonda interrumpida.'}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    throw 'Sonda trazada sin resultado verificable.'
}
function Get-BridgeObservationJson([string]$Container,[string]$Path) {
    $raw=@(Invoke-BridgeIsolationDocker @('exec',$Container,'python3','-c',"import sys;print(open(sys.argv[1],encoding='utf-8-sig').read())",$Path))
    return ($raw -join "`n" | ConvertFrom-Json -ErrorAction Stop)
}
function Set-BridgeObservationJson([string]$Container,[string]$Path,$Value) {
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 30 -Compress)))
    $null=Invoke-BridgeIsolationDocker @('exec',$Container,'python3','-c',"import base64,sys,os;p=sys.argv[1];open(p+'.new','wb').write(base64.b64decode(sys.argv[2]));os.replace(p+'.new',p)",$Path,$encoded)
}
function Get-BridgeObservationInspection([string]$Id) {
    $raw=@(Invoke-BridgeIsolationDocker @('inspect',$Id))
    $items=@($raw -join "`n" | ConvertFrom-Json -ErrorAction Stop)
    if ($items.Count -ne 1 -or $items[0].Id -cne $Id) { throw 'Inspeccion de observacion incompleta.' }
    return $items[0]
}
function Assert-BridgeObservationOwned($Item,$Context) {
    if ($Item.Config.Labels.'eats.bridge.run' -cne $Context.Plan.runId) { throw 'Recurso de observacion ajeno.' }
}
function Stop-BridgeObservation($Observation,$Context) {
    if ($null -eq $Observation) { return }
    foreach($id in @($Observation.observerId,$Observation.sentinelId)) {
        if ($id) {
            $item=Get-BridgeObservationInspection $id
            Assert-BridgeObservationOwned $item $Context
            if ($item.State.Running) { $null=Invoke-BridgeIsolationDocker @('stop','--time','5',$id) }
        }
    }
}
function Add-BridgeObservationAttachment($Context,[string]$Name,$Value) {
    $path=Join-Path $Context.directory $Name
    Write-BridgeNewJson $path $Value
    return [pscustomobject]@{path=($Context.relativeDirectory+'/'+$Name);sha256=(Get-BridgeHash $path)}
}
function Update-BridgeObservationState($Observation) {
    $state=Get-BridgeObservationJson $Observation.observerId '/opt/bridge-observation.json'
    if ($state.runId -cne $Observation.runId) { throw 'Run de captura distinto.' }
    $Observation.state=$state
    return $state
}
function Assert-BridgeObservationAlive($Observation) {
    try {
        $state=Update-BridgeObservationState $Observation
        if ($state.status -cne 'RUNNING' -or $state.droppedEvents -isnot [int] -or $state.droppedEvents -ne 0 -or
            ([DateTimeOffset]::UtcNow-[DateTimeOffset]$state.heartbeatUtc).TotalSeconds -gt 5) { throw 'Captura detenida, sin latido o con eventos perdidos.' }
        if ($state.phase -cne 'RECORRIDO') { throw 'La captura no esta en RECORRIDO.' }
        if($Observation.activeTraceId){
            $target=@($state.traceTargets|Where-Object {$_.id -ceq $Observation.activeTraceId -and $_.kind -ceq 'java' -and $_.ready -eq $true -and $null -eq $_.finishedUtc})
            if($target.Count -ne 1){throw 'Cobertura de syscalls Java interrumpida.'}
        }
    } catch {
        # El fallo bloquea la siguiente accion y detiene el holder/JAR propio.
        $app=Get-BridgeObservationInspection $Observation.Context.containers.APP
        Assert-BridgeObservationOwned $app $Observation.Context
        if ($app.State.Running) { $null=Invoke-BridgeIsolationDocker @('stop','--time','1',$app.Id) }
        throw
    }
}
function Wait-BridgeObservationState($Observation,[string]$Expected,[int]$Seconds=10) {
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        try {
            $state=Update-BridgeObservationState $Observation
            if ($state.status -ceq 'ERROR') { throw ('Observador rechazo captura: '+$state.reason) }
            if ($state.status -ceq $Expected) { return $state }
        } catch {
            # El archivo aun no existe durante la inicializacion. Otros fallos
            # no se convierten en aprobacion; el limite temporal detiene el ensayo.
            if ($_.Exception.Message -match 'Observador rechazo') { throw }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'No se pudo verificar el estado del observador dentro del plazo.'
}
function Invoke-BridgeObservationProbe([string]$Container,[string]$Address,[int]$Port,[int]$SourcePort,[string]$Correlation) {
    $raw=@(Invoke-BridgeIsolationDocker @('exec',$Container,'python3','/opt/bridge_probe.py',$Address,[string]$Port,[string]$SourcePort,$Correlation))
    return ($raw -join "`n" | ConvertFrom-Json -ErrorAction Stop)
}
function Start-BridgeObservation($Context) {
    $observation=[pscustomobject]@{Context=$Context;runId=$Context.runId;observerId=$null;sentinelId=$null;sentinelNetworkId=$null;state=$null;activeTraceId=$null;preflightStartedUtc=$null;preflightFinishedUtc=$null;proof=$null;allowed=@();topology=$null;correlationId=('sentinel-'+[guid]::NewGuid().ToString('N'))}
    $Context | Add-Member -NotePropertyName Observation -NotePropertyValue $observation -Force
    $run=$Context.Plan.runId
    $networkName='bridge-'+$run+'-sentinel'
    $created=@(Invoke-BridgeIsolationDocker @('network','create','--driver','bridge','--internal','--label',('eats.bridge.run='+$run),$networkName))
    if ($created.Count -ne 1 -or $created[0] -cnotmatch '^[a-f0-9]{64}$') { throw 'Red del centinela no creada.' }
    $observation.sentinelNetworkId=[string]$created[0]
    $created=@(Invoke-BridgeIsolationDocker @('create','--pull','never','--no-healthcheck','--name',('bridge-'+$run+'-sentinel'),'--network',$networkName,'--label',('eats.bridge.run='+$run),'--cap-drop','ALL','--security-opt','no-new-privileges','--entrypoint','python3',$Context.Images.tools,'-c','import time;time.sleep(2147483647)'))
    if ($created.Count -ne 1 -or $created[0] -cnotmatch '^[a-f0-9]{64}$') { throw 'Centinela no creado.' }
    $observation.sentinelId=[string]$created[0]
    $observation.observerId=New-BridgeIsolatedObserver $Context.Plan $Context.containers.APP $Context.Images.tools
    foreach($id in @($observation.sentinelId,$observation.observerId)) {
        $item=Get-BridgeObservationInspection $id
        Assert-BridgeLocalImageIdentity $item $Context.Images.tools
        Assert-BridgeObservationOwned $item $Context
        if ($item.State.Running -or $item.Mounts.Count -ne 0) { throw 'Observador o centinela iniciado prematuramente o con montajes.' }
        if ($id -ceq $observation.observerId) {
            Assert-BridgeObserverInspection $item ('bridge-'+$run+'-observer') $Context.containers.APP
            if($item.HostConfig.PidMode -cne ('container:'+$Context.containers.APP)){throw 'PID namespace del observador no corresponde al ensayo.'}
        }
        else { Assert-BridgeContainerInspection $item ('bridge-'+$run+'-sentinel') $networkName $false;Assert-BridgeEffectiveNetworks $item $networkName }
        foreach($name in @('bridge_probe.py','bridge_sentinel.py','bridge_observer.py','bridge_trace.py')) {
            $null=Invoke-BridgeIsolationDocker @('cp',(Join-Path $PSScriptRoot ('bridge/'+$name)),($id+':/opt/'+$name))
        }
        $null=Invoke-BridgeIsolationDocker @('start',$id)
    }
    $sentinelItem=Get-BridgeObservationInspection $observation.sentinelId
    $sentinelAddress=$sentinelItem.NetworkSettings.Networks.PSObject.Properties[$networkName].Value.IPAddress
    $parsed=[Net.IPAddress]::None
    if (-not [Net.IPAddress]::TryParse($sentinelAddress,[ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Direccion del centinela invalida.' }
    $null=Invoke-BridgeIsolationDocker @('exec','-d',$observation.sentinelId,'python3','/opt/bridge_sentinel.py','/opt/bridge-sentinel.json')
    $deadline=[DateTime]::UtcNow.AddSeconds(10);$sentinelReady=$false
    do {
        try { $sentinelReady=(Get-BridgeObservationJson $observation.sentinelId '/opt/bridge-sentinel.json').ready -eq $true } catch { }
        if (-not $sentinelReady) { Start-Sleep -Milliseconds 100 }
    } while (-not $sentinelReady -and [DateTime]::UtcNow -lt $deadline)
    if (-not $sentinelReady) { throw 'Centinela no disponible.' }
    $positiveBefore=Invoke-BridgeObservationProbe $observation.sentinelId '127.0.0.1' 18081 0 ('positive-before-'+$observation.correlationId)
    if (-not $positiveBefore.connected -or -not $positiveBefore.acknowledged) { throw 'Control positivo previo del centinela fallido.' }
    $allowed=@()
    foreach($service in $Context.services) {
        if ($service.role -cin @('HARNESS','APP')) { continue }
        foreach($protocol in $(if($service.role -ceq 'DNS'){@('TCP','UDP')}else{@('TCP')})) {
            $allowed+=@{sourceId=$Context.containers.APP;destinationId=$service.id;sourceAddress=$Context.appAddress;address=$service.address;protocol=$protocol;port=[int]$service.port}
        }
    }
    $allowed+=@{sourceId=$Context.containers.TOOLS;destinationId=$Context.containers.APP;sourceAddress=$Context.toolsAddress;address=$Context.appAddress;protocol='TCP';port=8080}
    $observation.allowed=$allowed
    $sourcePort=Get-Random -Minimum 30000 -Maximum 60000
    $sentinel=@{sourceId=$Context.containers.APP;destinationId=$observation.sentinelId;sourceAddress=$Context.appAddress;address=$sentinelAddress;protocol='TCP';port=18081;sourcePort=$sourcePort;correlationId=$observation.correlationId}
    Set-BridgeObservationJson $observation.observerId '/opt/bridge-config.json' @{runId=$Context.runId;appId=$Context.containers.APP;appAddress=$Context.appAddress;allowed=$allowed;sentinel=$sentinel}
    Set-BridgeObservationJson $observation.observerId '/opt/bridge-control.json' @{phase='AUTOCOMPROBACION'}
    $null=Invoke-BridgeIsolationDocker @('exec','-d',$observation.observerId,'python3','/opt/bridge_observer.py','/opt/bridge-config.json','/opt/bridge-control.json','/opt/bridge-observation.json')
    $state=Wait-BridgeObservationState $observation 'RUNNING'
    $observation.preflightStartedUtc=[DateTime]::UtcNow.ToString('o')
    $mongo=@($Context.services | Where-Object {$_.role -ceq 'MONGO'})[0]
    $allowedProbe=Invoke-BridgeTracedObservationProbe $observation $mongo.address ([int]$mongo.port) 0 ('allowed-'+$observation.correlationId)
    if (-not $allowedProbe.connected) { throw 'Sonda permitida no establecio conexion.' }
    $negativeProbe=Invoke-BridgeTracedObservationProbe $observation $sentinelAddress 18081 $sourcePort $observation.correlationId
    $probeRef=Add-BridgeObservationAttachment $Context 'sentinel-probe.json' $negativeProbe
    $Context.configurationRefs+=@($probeRef)
    try{Assert-BridgeDeniedProbeObservable $negativeProbe}catch{
        $visibilityRef=Add-BridgeObservationAttachment $Context 'sentinel-visibility.json' @{status='Failed';reason='SENTINEL_PROBE_REJECTED';method='AF_PACKET+STRACE-v1';probe=$probeRef;errorCode=$negativeProbe.errorCode;jarStarted=$false}
        $Context.configurationRefs+=@($visibilityRef)
        throw
    }
    $positiveAfter=Invoke-BridgeObservationProbe $observation.sentinelId '127.0.0.1' 18081 0 ('positive-after-'+$observation.correlationId)
    $independent=Get-BridgeObservationJson $observation.sentinelId '/opt/bridge-sentinel.json'
    if (-not $positiveAfter.connected -or -not $positiveAfter.acknowledged -or -not $independent.ready) { throw 'Control positivo posterior del centinela fallido.' }
    $arrivals=@($independent.records | Where-Object {$_.correlationId -ceq $observation.correlationId -or ($_.address -ceq $Context.appAddress -and $_.port -eq $sourcePort)})
    if ($arrivals.Count -ne 0) { throw 'El centinela recibio el intento que debia estar bloqueado.' }
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do{
        $state=Update-BridgeObservationState $observation
        if ($state.status -cne 'RUNNING' -or $state.droppedEvents -ne 0) { throw 'Captura incompleta durante autocomprobacion.' }
        $foreign=@($state.events | Where-Object {$_.correlationId -ceq $observation.correlationId})
        if($foreign.Count -eq 1 -and @($state.events|Where-Object {$_.correlationId -ceq 'allowed'}).Count -gt 0){break}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    if ($foreign.Count -ne 1 -or $foreign[0].channel -cne 'SYSCALL' -or @($state.events | Where-Object {$_.correlationId -ceq 'allowed'}).Count -eq 0) { throw 'No se observaron syscalls y paquetes de control; no iniciar JAR.' }
    $observation.proof=@{runId=$Context.runId;correlationId=$observation.correlationId;positiveBefore=$positiveBefore;positiveAfter=$positiveAfter;probe=$negativeProbe;sentinelInspectionId=$observation.sentinelId;listenerRecords=$independent.records;blocked=$true;independence='Sonda de socket y servidor centinela separado; no derivado de la captura AF_PACKET.'}
    Set-BridgeObservationJson $observation.observerId '/opt/bridge-control.json' @{phase='RECORRIDO'}
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do { $state=Update-BridgeObservationState $observation;if($state.status -cne 'RUNNING'){throw 'Captura fallida al cambiar fase.'};if($state.phase -cne 'RECORRIDO'){Start-Sleep -Milliseconds 100} } while($state.phase -cne 'RECORRIDO' -and [DateTime]::UtcNow -lt $deadline)
    if ($state.phase -cne 'RECORRIDO' -or -not $state.phaseStartedUtc) { throw 'No se pudo establecer RECORRIDO continuo.' }
    $observation.preflightFinishedUtc=$state.phaseStartedUtc
    return $observation
}

function Complete-BridgeObservation($Observation,$Context) {
    Assert-BridgeObservationAlive $Observation
    $runFinished=[DateTime]::UtcNow.ToString('o')
    # Mantener holder/namespace y captura mientras se inspecciona topologia final.
    $network=@((@(Invoke-BridgeIsolationDocker @('network','inspect',$Context.networkId)) -join "`n"|ConvertFrom-Json))[0]
    Assert-BridgeNetworkInspection $network $Context.Plan.network
    if($network.Id -cne $Context.networkId){throw 'Red del ensayo alterada.'}
    $app=Get-BridgeObservationInspection $Context.containers.APP
    Assert-BridgeObservationOwned $app $Context
    Assert-BridgeContainerInspection $app ('bridge-'+$Context.resourceRunId+'-app') $Context.Plan.network $true
    Assert-BridgeEffectiveNetworks $app $Context.Plan.network
    $mount=@($app.Mounts)[0]
    $jar=$Context.Plan.resources[4].mounts[0]
    if($mount.Type -cne 'bind' -or [IO.Path]::GetFullPath($mount.Source) -ine [IO.Path]::GetFullPath($jar.source) -or
        (Get-BridgeHash $jar.source) -ine $jar.sha256){throw 'JAR montado alterado.'}
    $mounted=@(Invoke-BridgeIsolationDocker @('exec',$Context.containers.APP,'sha256sum','/opt/bridge.jar'))
    if($mounted.Count -ne 1 -or (($mounted[0] -split '\s+')[0]) -ine $jar.sha256){throw 'Hash del JAR efectivo discordante despues del ensayo.'}
    foreach($id in $Context.containers.Values){
        $item=Get-BridgeObservationInspection $id
        Assert-BridgeObservationOwned $item $Context
        Assert-BridgeEffectiveNetworks $item $Context.Plan.network
        if($item.HostConfig.Privileged -or @($item.HostConfig.CapAdd|Where-Object{$null -ne $_}).Count){throw 'Capacidades inesperadas durante ensayo.'}
    }
    $observer=Get-BridgeObservationInspection $Observation.observerId
    Assert-BridgeObserverInspection $observer ('bridge-'+$Context.resourceRunId+'-observer') $Context.containers.APP
    if($observer.HostConfig.PidMode -cne ('container:'+$Context.containers.APP)){throw 'Namespace PID alterado.'}
    $negativeConfig=$Context.endpoints|ConvertTo-Json -Depth 10|ConvertFrom-Json
    $negativeConfig.MONGO.port=27018
    $rejected=$false;try{$null=New-BridgeApplicationArguments $negativeConfig $true}catch{$rejected=$true}
    if(-not $rejected){throw 'No se rechazo configuracion Mongo ajena.'}
    $badApp=$app|ConvertTo-Json -Depth 40|ConvertFrom-Json
    $badApp.HostConfig.NetworkMode='host'
    $rejected=$false;try{Assert-BridgeContainerInspection $badApp $badApp.Name.TrimStart('/') $Context.Plan.network $true}catch{$rejected=$true}
    if(-not $rejected){throw 'No se rechazo red host.'}
    $badApp.HostConfig.NetworkMode=$Context.Plan.network
    $badApp.HostConfig.ExtraHosts=@('host.docker.internal:host-gateway')
    $rejected=$false;try{Assert-BridgeEffectiveNetworks $badApp $Context.Plan.network}catch{$rejected=$true}
    if(-not $rejected){throw 'No se rechazo host-gateway.'}
    $badApp.HostConfig.ExtraHosts=$null
    $badApp.Mounts+=@([pscustomobject]@{Type='volume';Destination='/foreign';RW=$false})
    $rejected=$false;try{Assert-BridgeContainerInspection $badApp $badApp.Name.TrimStart('/') $Context.Plan.network $true}catch{$rejected=$true}
    if(-not $rejected){throw 'No se rechazo montaje ajeno.'}
    Set-BridgeObservationJson $Observation.observerId '/opt/bridge-control.json' @{stop=$true}
    $state=Wait-BridgeObservationState $Observation 'STOPPED'
    $runFinished=$state.finishedUtc
    if($state.droppedEvents -ne 0 -or -not $state.finishedUtc -or -not $state.startedUtc){throw 'Cierre de captura no acreditado.'}
    $events=@($state.events)
    $sentinel=@($events|Where-Object{$_.correlationId -ceq $Observation.correlationId})
    if($sentinel.Count -ne 1 -or $sentinel[0].phase -cne 'AUTOCOMPROBACION' -or -not $Observation.proof.blocked){throw 'Correlacion independiente incompleta.'}
    # BLOCKED se deriva de sonda+servidor independientes, nunca solo del paquete.
    $sentinel[0].outcome='BLOCKED'
    $top=[pscustomobject]@{
        networkId=$Context.networkId;appContainerId=$Context.containers.APP;observerContainerId=$Observation.observerId;appAddress=$Context.appAddress
        internal=$true;hostNetwork=$false;hostGateway=$false;observerPrivileged=$false;appExtraCapabilities=$false;sourceMounts=$false
        services=@($Context.services|Where-Object{$_.role -cne 'APP'}|ForEach-Object{[pscustomobject]@{id=$_.id;address=$_.address;role=$_.role}})
    }
    $refs=@{}
    $records=@{
        topology=@($top)
        allowlist=@($Observation.allowed|ForEach-Object{[pscustomobject]@{sourceId=$_.sourceId;destinationId=$_.destinationId;address=$_.address;protocol=$_.protocol;port=[int]$_.port}})
        observation=@([pscustomobject]@{observerContainerId=$Observation.observerId;startedUtc=$state.startedUtc;finishedUtc=$state.finishedUtc;continuous=$true;droppedEvents=0;events=$events})
    }
    $coverageRef=Add-BridgeObservationAttachment $Context 'syscall-coverage.json' @{schemaVersion=1;kind='reservation-bridge-isolation-syscallCoverage';runId=$Context.runId;records=@(@{method='AF_PACKET+STRACE-v1';traceVersion=$state.traceVersion;capabilities=@('NET_RAW','SYS_PTRACE');pidMode=('container:'+$Context.containers.APP);seccompSha256=(Get-BridgeHash (Join-Path $PSScriptRoot 'bridge/observer-seccomp.json'));targets=@($state.traceTargets)})}
    $proofRef=Add-BridgeObservationAttachment $Context 'sentinel-independent.json' $Observation.proof
    $event=$sentinel[0]
    $records.sentinelProof=@([pscustomobject]@{correlationId=$event.correlationId;sourceId=$event.sourceId;destinationId=$event.destinationId;address=$event.address;protocol=$event.protocol;port=[int]$event.port;blocked=$true;proofRef=$proofRef})
    foreach($name in @('topology','allowlist','observation','sentinelProof')){
        $refs[$name]=Add-BridgeObservationAttachment $Context ($name+'.json') @{schemaVersion=1;kind=('reservation-bridge-isolation-'+$name);runId=$Context.runId;records=@($records[$name])}
    }
    $cases=@(New-BridgeCatalogCases 'isolation')
    foreach($case in $cases){Set-BridgeCatalogCase $cases $case.id $true @{verified=$true}}
    return [pscustomobject]@{
        kind='reservation-bridge-isolation';status='Passed';runId=$Context.runId;observerVersion='AF_PACKET+STRACE-v1'
        observerContinuous=$true;observerSawAllowed=$true;observerSawDenied=$true;sentinelBlocked=$true;preflightComplete=$true;runNoForeignDestinations=$true
        sentinelCorrelationId=$Observation.correlationId;preflightStartedUtc=$Observation.preflightStartedUtc;preflightFinishedUtc=$Observation.preflightFinishedUtc
        runStartedUtc=$state.phaseStartedUtc;runFinishedUtc=$runFinished;cases=$cases
        topology=$refs.topology;allowlist=$refs.allowlist;observation=$refs.observation;sentinelProof=$refs.sentinelProof;syscallCoverage=$coverageRef
    }
}
