# Descripcion pura de recursos nuevos. No invoca Docker ni crea archivos.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReservationBridge.Runtime.ps1')
function New-BridgeIsolationResourcePlan([string]$RunId,[string]$JarPath,[string]$JarSha256) {
    if ($RunId -cnotmatch '^[a-zA-Z0-9-]{1,80}$') { throw 'RunId de aislamiento invalido.' }
    Assert-BridgeHash $JarSha256 'jarSha256'
    Assert-BridgeText $JarPath 'jarPath'
    if (-not [IO.Path]::IsPathRooted($JarPath) -or $JarPath.Contains(',')) { throw 'Ruta JAR absoluta requerida, sin comas.' }
    $prefix='bridge-'+$RunId.ToLowerInvariant()
    $plan=[pscustomobject]@{
        runId=$RunId;network=($prefix+'-internal');internal=$true
        resources=@(
            [pscustomobject]@{name=($prefix+'-mongo');role='MONGO';ports=@();mounts=@()},
            [pscustomobject]@{name=($prefix+'-redis');role='REDIS';ports=@();mounts=@()},
            [pscustomobject]@{name=($prefix+'-jwks');role='JWKS';ports=@();mounts=@()},
            [pscustomobject]@{name=($prefix+'-dns');role='DNS';ports=@();mounts=@()},
            [pscustomobject]@{name=($prefix+'-app');role='APP';ports=@();mounts=@([pscustomobject]@{source=$JarPath;target='/opt/bridge.jar';readOnly=$true;sha256=$JarSha256})},
            [pscustomobject]@{name=($prefix+'-observer');role='OBSERVER';ports=@();mounts=@()}
        )
    }
    return $plan
}
function Assert-BridgeIsolationResourcePlan($Plan) {
    Assert-BridgeText (Get-BridgeField $Plan 'runId') 'runId'
    Assert-BridgeText (Get-BridgeField $Plan 'network') 'network'
    Assert-BridgeTrue (Get-BridgeField $Plan 'internal') 'internal'
    $resources=Get-BridgeField $Plan 'resources'
    if ($resources -isnot [array] -or $resources.Count -ne 6) { throw 'Recursos de aislamiento incompletos.' }
    $roles=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($resource in $resources) {
        $name=Get-BridgeField $resource 'name';$role=Get-BridgeField $resource 'role'
        Assert-BridgeText $name 'name'
        if (-not (@('MONGO','REDIS','JWKS','DNS','APP','OBSERVER') -ccontains $role) -or -not $roles.Add($role) -or -not $names.Add($name)) { throw 'Rol o nombre duplicado/invalido.' }
        $ports=Get-BridgeField $resource 'ports'
        if ($ports -isnot [array] -or $ports.Count -ne 0) { throw 'Puertos publicados no permitidos.' }
        $mounts=Get-BridgeField $resource 'mounts'
        if ($mounts -isnot [array]) { throw 'Montajes invalidos.' }
        if ($role -cne 'APP' -and $mounts.Count -ne 0) { throw 'Montaje ajeno no permitido.' }
        if ($role -ceq 'APP') {
            if ($mounts.Count -ne 1) { throw 'Se requiere un solo JAR.' }
            $mount=$mounts[0]
            Assert-BridgeTrue (Get-BridgeField $mount 'readOnly') 'readOnly'
            Assert-BridgeHash (Get-BridgeField $mount 'sha256') 'jarSha256'
            if ((Get-BridgeField $mount 'target') -cne '/opt/bridge.jar') { throw 'Destino JAR invalido.' }
        }
    }
}


# Compara una inspeccion Docker ya obtenida con el plan. No consulta Docker.
function Assert-BridgeNetworkInspection($Inspection, [string]$ExpectedName) {
    if ((Get-BridgeField $Inspection 'Name') -cne $ExpectedName) { throw 'Red inesperada.' }
    Assert-BridgeTrue (Get-BridgeField $Inspection 'Internal') 'network.Internal'
    $driver=Get-BridgeField $Inspection 'Driver'
    if ($driver -cne 'bridge') { throw 'Driver de red no permitido.' }
    $ipv6=Get-BridgeField $Inspection 'EnableIPv6'
    if ($ipv6 -isnot [bool] -or $ipv6) { throw 'IPv6 de ensayo no permitido.' }
    $options=Get-BridgeField $Inspection 'Options'
    if ((Get-BridgeField $options 'com.docker.network.bridge.gateway_mode_ipv4') -cne 'isolated') { throw 'Gateway del host no aislado.' }
}

function Assert-BridgeEffectiveNetworks($Inspection, [string]$NetworkName) {
    # NetworkMode refleja la configuracion inicial, no redes conectadas despues.
    $networkSettings=Get-BridgeField $Inspection 'NetworkSettings'
    $networks=Get-BridgeField $networkSettings 'Networks'
    if ($null -eq $networks) { throw 'Redes efectivas ausentes.' }
    $entries=@($networks.PSObject.Properties)
    if ($entries.Count -ne 1 -or $entries[0].Name -cne $NetworkName) { throw 'Redes efectivas inesperadas.' }
    $hostConfig=Get-BridgeField $Inspection 'HostConfig'
    foreach ($field in @('ExtraHosts','Links','VolumesFrom')) {
        $value=Get-BridgeField $hostConfig $field
        if ($null -ne $value -and @($value).Count -gt 0) { throw "Configuracion de host no permitida: $field" }
    }
}

function Assert-BridgeContainerInspection($Inspection, [string]$ExpectedName, [string]$NetworkName, [bool]$AllowJar) {
    $name=Get-BridgeField $Inspection 'Name'
    if ($name -cne ('/'+$ExpectedName)) { throw 'Contenedor inesperado.' }
    $hostConfig=Get-BridgeField $Inspection 'HostConfig'
    if ((Get-BridgeField $hostConfig 'NetworkMode') -cne $NetworkName) { throw 'Modo de red no permitido.' }
    $privileged=Get-BridgeField $hostConfig 'Privileged'
    if ($privileged -isnot [bool] -or $privileged) { throw 'Contenedor privilegiado.' }
    $bindings=Get-BridgeField $hostConfig 'PortBindings'
    if ($null -ne $bindings -and @($bindings.PSObject.Properties).Count -ne 0) { throw 'Puertos publicados no permitidos.' }
    $mounts=Get-BridgeField $Inspection 'Mounts'
    if ($mounts -isnot [array]) { throw 'Inspeccion de montajes invalida.' }
    if (-not $AllowJar -and $mounts.Count -ne 0) { throw 'Montaje ajeno detectado.' }
    if ($AllowJar) {
        if ($mounts.Count -ne 1) { throw 'Cantidad de montajes invalida.' }
        $mount=$mounts[0]
        if ((Get-BridgeField $mount 'Destination') -cne '/opt/bridge.jar') { throw 'Destino de montaje invalido.' }
        $rw=Get-BridgeField $mount 'RW'
        if ($rw -isnot [bool] -or $rw) { throw 'JAR no esta en solo lectura.' }
    }
    # Una inspeccion estatica no acredita identidad del origen ni captura continua.
}


# Acceso Docker aislado mediante argumentos separados; las pruebas lo sustituyen.
function Invoke-BridgeIsolationDocker([string[]]$Arguments) {
    $output=@(& docker @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Docker rechazo la operacion de aislamiento.' }
    return $output
}
function New-BridgeIsolatedNetwork($Plan) {
    Assert-BridgeIsolationResourcePlan $Plan
    $name=Get-BridgeField $Plan 'network'
    $runId=Get-BridgeField $Plan 'runId'
    if ($name -cne ('bridge-'+$runId.ToLowerInvariant()+'-internal')) { throw 'Nombre de red incompatible con el ensayo.' }
    # Docker falla si ya existe: no reutilizar, borrar ni modificar redes previas.
    $created=@(Invoke-BridgeIsolationDocker @('network','create','--driver','bridge','--internal','--ipv6=false',
        '--opt','com.docker.network.bridge.gateway_mode_ipv4=isolated','--label',('eats.bridge.run='+$runId),$name))
    if ($created.Count -ne 1 -or "$($created[0])" -cnotmatch '^[a-f0-9]{64}$') { throw 'Docker no devolvio identificador de red valido.' }
    $id="$($created[0])"
    $raw=@(Invoke-BridgeIsolationDocker @('network','inspect',$id))
    $parsed=$raw -join [Environment]::NewLine | ConvertFrom-Json -ErrorAction Stop
    if ($parsed -is [array]) { $inspection=$parsed } else { $inspection=@($parsed) }
    if ($inspection -isnot [array] -or $inspection.Count -ne 1) { throw 'Inspeccion de red incompleta.' }
    Assert-BridgeNetworkInspection $inspection[0] $name
    if ((Get-BridgeField $inspection[0] 'Id') -cne $id) { throw 'Identidad de red no coincide.' }
    $labels=Get-BridgeField $inspection[0] 'Labels'
    if ((Get-BridgeField $labels 'eats.bridge.run') -cne $runId) { throw 'Etiqueta de red no coincide.' }
    return $id
}


function Test-BridgeImageReference([string]$Image) {
    return $Image -cmatch '^(sha256:[a-f0-9]{64}|[a-z0-9][a-z0-9./_-]*@sha256:[a-f0-9]{64})$'
}
function Assert-BridgeLocalImageIdentity($Inspection,[string]$Image) {
    if($Image -cmatch '^sha256:[a-f0-9]{64}$' -and (Get-BridgeField $Inspection 'Image') -cne $Image) { throw 'Identidad de imagen del contenedor distinta.' }
}
function New-BridgeIsolatedService($Plan, [string]$Role, [string]$Image) {
    Assert-BridgeIsolationResourcePlan $Plan
    if (-not (@('MONGO','REDIS','JWKS','DNS') -ccontains $Role)) { throw 'Rol de servicio no permitido.' }
    if (-not (Test-BridgeImageReference $Image)) { throw 'Imagen por digest requerido.' }
    $resources=Get-BridgeField $Plan 'resources'
    $matches=@($resources | Where-Object { $_.role -ceq $Role })
    if ($matches.Count -ne 1) { throw 'Servicio no encontrado.' }
    $name=Get-BridgeField $matches[0] 'name'
    $network=Get-BridgeField $Plan 'network'
    $runId=Get-BridgeField $Plan 'runId'
    if ($network -cne ('bridge-'+$runId.ToLowerInvariant()+'-internal') -or
        $name -cne ('bridge-'+$runId.ToLowerInvariant()+'-'+$Role.ToLowerInvariant())) { throw 'Nombre de recurso incompatible.' }
    $arguments=@('create','--pull','never','--name',$name,'--network',$network,'--label',('eats.bridge.run='+$runId),'--cap-drop','ALL','--security-opt','no-new-privileges',$Image)
    $created=@(Invoke-BridgeIsolationDocker $arguments)
    if ($created.Count -ne 1 -or "$($created[0])" -cnotmatch '^[a-f0-9]{64}$') { throw 'Identificador de contenedor invalido.' }
    $id="$($created[0])"
    $raw=@(Invoke-BridgeIsolationDocker @('inspect',$id))
    $parsed=$raw -join [Environment]::NewLine | ConvertFrom-Json -ErrorAction Stop
    if ($parsed -is [array]) { $items=$parsed } else { $items=@($parsed) }
    if ($items.Count -ne 1) { throw 'Inspeccion de contenedor incompleta.' }
    $item=$items[0]
    Assert-BridgeLocalImageIdentity $item $Image
    Assert-BridgeContainerInspection $item $name $network $false
    Assert-BridgeEffectiveNetworks $item $network
    if ((Get-BridgeField $item 'Id') -cne $id) { throw 'Identidad de contenedor no coincide.' }
    $config=Get-BridgeField $item 'Config'
    $labels=Get-BridgeField $config 'Labels'
    if ((Get-BridgeField $labels 'eats.bridge.run') -cne $runId) { throw 'Etiqueta de contenedor no coincide.' }
    $state=Get-BridgeField $item 'State'
    $running=Get-BridgeField $state 'Running'
    if ($running -isnot [bool] -or $running) { throw 'Contenedor iniciado antes de inspeccion.' }
    return $id
}


function Assert-BridgeObserverInspection($Inspection,[string]$ExpectedName,[string]$ApplicationId) {
    if ((Get-BridgeField $Inspection 'Name') -cne ('/'+$ExpectedName)) { throw 'Observador inesperado.' }
    $hostConfig=Get-BridgeField $Inspection 'HostConfig'
    if ((Get-BridgeField $hostConfig 'NetworkMode') -cne ('container:'+$ApplicationId)) { throw 'Espacio de red del observador incorrecto.' }
    $privileged=Get-BridgeField $hostConfig 'Privileged'
    if ($privileged -isnot [bool] -or $privileged) { throw 'Observador privilegiado.' }
    $capAdd=Get-BridgeField $hostConfig 'CapAdd'
    if ($capAdd -isnot [array] -or $capAdd.Count -ne 2 -or -not ($capAdd -ccontains 'NET_RAW') -or -not ($capAdd -ccontains 'SYS_PTRACE')) { throw 'Capacidades del observador invalidas.' }
    if((Get-BridgeField $hostConfig 'PidMode') -cne ('container:'+$ApplicationId)){throw 'Namespace PID del observador incorrecto.'}
    $security=Get-BridgeField $hostConfig 'SecurityOpt'
    if($security -isnot [array]){throw 'Seccomp/privilegios del observador incorrectos.'}
    $profiles=@($security|Where-Object {$_ -clike 'seccomp=*'})
    if($security.Count -ne 2 -or $profiles.Count -ne 1 -or -not (@($security|Where-Object {$_ -ceq 'no-new-privileges' -or $_ -ceq 'no-new-privileges=true'}).Count -eq 1)){throw 'Seccomp/privilegios del observador incorrectos.'}
    $actualProfile=$profiles[0].Substring(8)|ConvertFrom-Json -ErrorAction Stop
    $expectedProfile=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bridge/observer-seccomp.json') -Raw|ConvertFrom-Json
    if(-not (Test-BridgeJsonEqual $actualProfile $expectedProfile)){throw 'Perfil seccomp del observador distinto.'}
    $capDrop=Get-BridgeField $hostConfig 'CapDrop'
    if ($capDrop -isnot [array] -or $capDrop.Count -ne 1 -or $capDrop[0] -cne 'ALL') { throw 'Capacidades base no eliminadas.' }
    $mounts=Get-BridgeField $Inspection 'Mounts'
    if ($mounts -isnot [array] -or $mounts.Count -ne 0) { throw 'Montajes de observador no permitidos.' }
    $bindings=Get-BridgeField $hostConfig 'PortBindings'
    if ($null -ne $bindings -and @($bindings.PSObject.Properties).Count -ne 0) { throw 'Puertos de observador no permitidos.' }
}

function New-BridgeIsolatedObserver($Plan,[string]$ApplicationId,[string]$Image) {
    Assert-BridgeIsolationResourcePlan $Plan
    if ($ApplicationId -cnotmatch '^[a-f0-9]{64}$') { throw 'Identidad de aplicacion invalida.' }
    if (-not (Test-BridgeImageReference $Image)) { throw 'Imagen por digest requerido.' }
    $runId=Get-BridgeField $Plan 'runId'
    $resources=Get-BridgeField $Plan 'resources'
    $observers=@($resources | Where-Object { $_.role -ceq 'OBSERVER' })
    if ($observers.Count -ne 1) { throw 'Observador no encontrado.' }
    $name=Get-BridgeField $observers[0] 'name'
    if ($name -cne ('bridge-'+$runId.ToLowerInvariant()+'-observer')) { throw 'Nombre de observador incompatible.' }
    # Crear detenido. La captura y su prueba de cobertura se implementan por separado.
    $profile=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bridge/observer-seccomp.json'))
    $args=@('create','--pull','never','--no-healthcheck','--user','0:0','--name',$name,'--network',('container:'+$ApplicationId),'--pid',('container:'+$ApplicationId),'--label',('eats.bridge.run='+$runId),
        '--cap-drop','ALL','--cap-add','NET_RAW','--cap-add','SYS_PTRACE','--security-opt','no-new-privileges','--security-opt',('seccomp='+$profile),'--entrypoint','python3',$Image,'-c','import time;time.sleep(2147483647)')
    $created=@(Invoke-BridgeIsolationDocker $args)
    if ($created.Count -ne 1 -or "$($created[0])" -cnotmatch '^[a-f0-9]{64}$') { throw 'Identificador de observador invalido.' }
    $id="$($created[0])"
    $raw=@(Invoke-BridgeIsolationDocker @('inspect',$id))
    $parsed=$raw -join [Environment]::NewLine | ConvertFrom-Json -ErrorAction Stop
    if ($parsed -is [array]) { $items=$parsed } else { $items=@($parsed) }
    if ($items.Count -ne 1) { throw 'Inspeccion de observador incompleta.' }
    $item=$items[0]
    Assert-BridgeLocalImageIdentity $item $Image
    Assert-BridgeObserverInspection $item $name $ApplicationId
    if ((Get-BridgeField $item 'Id') -cne $id) { throw 'Identidad de observador no coincide.' }
    $labels=Get-BridgeField (Get-BridgeField $item 'Config') 'Labels'
    if ((Get-BridgeField $labels 'eats.bridge.run') -cne $runId) { throw 'Etiqueta de observador no coincide.' }
    $running=Get-BridgeField (Get-BridgeField $item 'State') 'Running'
    if ($running -isnot [bool] -or $running) { throw 'Observador iniciado antes de inspeccion.' }
    return $id
}


function New-BridgeIsolatedApplication($Plan,[string]$Image) {
    Assert-BridgeIsolationResourcePlan $Plan
    if (-not (Test-BridgeImageReference $Image)) { throw 'Imagen por digest requerido.' }
    $runId=Get-BridgeField $Plan 'runId'
    $network=Get-BridgeField $Plan 'network'
    $apps=@((Get-BridgeField $Plan 'resources') | Where-Object { $_.role -ceq 'APP' })
    if ($apps.Count -ne 1) { throw 'Aplicacion no encontrada.' }
    $app=$apps[0]; $name=Get-BridgeField $app 'name'
    if ($name -cne ('bridge-'+$runId.ToLowerInvariant()+'-app') -or
        $network -cne ('bridge-'+$runId.ToLowerInvariant()+'-internal')) { throw 'Nombre de aplicacion incompatible.' }
    $mount=(Get-BridgeField $app 'mounts')[0]
    $jar=Get-BridgeField $mount 'source'; $hash=Get-BridgeField $mount 'sha256'
    Assert-BridgeText $jar 'jar'
    if (-not [IO.Path]::IsPathRooted($jar) -or $jar.Contains(',')) { throw 'Ruta JAR no permitida.' }
    Assert-BridgeHash $hash 'jarSha256'
    if ((Get-FileHash -LiteralPath $jar -Algorithm SHA256 -ErrorAction Stop).Hash -ine $hash) { throw 'Hash JAR distinto.' }
    # Crear detenido; no iniciar la aplicacion ni su JAR en este paso.
    $args=@('create','--pull','never','--no-healthcheck','--user','0:0','--name',$name,'--network',$network,'--label',('eats.bridge.run='+$runId),
        '--sysctl','net.ipv6.conf.all.disable_ipv6=1',
        '--cap-drop','ALL','--security-opt','no-new-privileges',
        '--env','JAVA_TOOL_OPTIONS=','--env','JDK_JAVA_OPTIONS=','--env','_JAVA_OPTIONS=',
        '--entrypoint','/bin/sh','--mount',("type=bind,src=$jar,dst=/opt/bridge.jar,readonly"),
        $Image,'-c','while :; do sleep 3600; done')
    $created=@(Invoke-BridgeIsolationDocker $args)
    if ($created.Count -ne 1 -or "$($created[0])" -cnotmatch '^[a-f0-9]{64}$') { throw 'Identificador de aplicacion invalido.' }
    $id="$($created[0])"
    $raw=@(Invoke-BridgeIsolationDocker @('inspect',$id))
    $parsed=$raw -join [Environment]::NewLine | ConvertFrom-Json -ErrorAction Stop
    if ($parsed -is [array]) { $items=$parsed } else { $items=@($parsed) }
    if ($items.Count -ne 1) { throw 'Inspeccion de aplicacion incompleta.' }
    $item=$items[0]
    Assert-BridgeLocalImageIdentity $item $Image
    Assert-BridgeContainerInspection $item $name $network $true
    Assert-BridgeApplicationHolder $item
    Assert-BridgeEffectiveNetworks $item $network
    $actualMount=(Get-BridgeField $item 'Mounts')[0]
    $actualSource=Get-BridgeField $actualMount 'Source'
    Assert-BridgeText $actualSource 'mount.Source'
    if ((Get-BridgeField $actualMount 'Type') -cne 'bind' -or
        [IO.Path]::GetFullPath($actualSource) -ine [IO.Path]::GetFullPath($jar)) { throw 'Origen de montaje JAR distinto.' }
    if ((Get-FileHash -LiteralPath $jar -Algorithm SHA256 -ErrorAction Stop).Hash -ine $hash) { throw 'JAR cambio durante preparacion.' }
    $hostConfig=Get-BridgeField $item 'HostConfig'
    $capDrop=Get-BridgeField $hostConfig 'CapDrop'
    if ($capDrop -isnot [array] -or $capDrop.Count -ne 1 -or $capDrop[0] -cne 'ALL') { throw 'Aplicacion conserva capacidades.' }
    $capAdd=Get-BridgeField $hostConfig 'CapAdd'
    if ($null -ne $capAdd -and @($capAdd).Count -ne 0) { throw 'Aplicacion con capacidades adicionales.' }

    if ((Get-BridgeField $item 'Id') -cne $id) { throw 'Identidad de aplicacion no coincide.' }
    $labels=Get-BridgeField (Get-BridgeField $item 'Config') 'Labels'
    if ((Get-BridgeField $labels 'eats.bridge.run') -cne $runId) { throw 'Etiqueta de aplicacion no coincide.' }
    $running=Get-BridgeField (Get-BridgeField $item 'State') 'Running'
    if ($running -isnot [bool] -or $running) { throw 'Aplicacion iniciada antes de inspeccion.' }
    return $id
}
