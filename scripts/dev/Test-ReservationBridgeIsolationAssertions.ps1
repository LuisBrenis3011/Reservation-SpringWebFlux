$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Prepare-LocalReservationBridge.ps1')
function Expect-IsolationFailure([scriptblock]$Action,[string]$Expected) {
    $message=$null
    try { & $Action } catch { $message=$_.Exception.Message }
    if ($null -eq $message -or $message -notmatch $Expected) { throw "Error inesperado: $message; esperado $Expected" }
}
Assert-BridgeImageEnvironment @('PATH=/usr/bin',('JSYAML_CHECKSUM='+('a'*64)),'GLIBC_TUNABLES=glibc.pthread.rseq=0')
Expect-IsolationFailure { Assert-BridgeImageEnvironment @('GLIBC_TUNABLES=glibc.malloc.check=3') } 'Variable heredada de imagen no autorizada'
Expect-IsolationFailure { Assert-BridgeImageEnvironment @('JSYAML_CHECKSUM=invalid') } 'Variable heredada de imagen no autorizada'
Expect-IsolationFailure { Assert-BridgeImageEnvironment @('MONGO_INITDB_ROOT_PASSWORD=secret') } 'Variable heredada de imagen no autorizada'
& {
    $script:BridgeSyntheticImageId='sha256:'+('a'*64)
    function Invoke-BridgeIsolationDocker([string[]]$Arguments) {
        if($Arguments[0] -cne 'image' -or $Arguments[1] -cne 'inspect'){throw 'Llamada sintetica inesperada'}
        return (@(@{Id=$script:BridgeSyntheticImageId;Os='linux';RepoDigests=@();Config=@{Env=@('PATH=/usr/bin')}})|ConvertTo-Json -Depth 8 -Compress)
    }
    $wanted='sha256:'+('a'*64)
    if((Assert-BridgeEnvironmentImage $wanted) -cne $wanted){throw 'Identidad local no acreditada'}
    $script:BridgeSyntheticImageId='sha256:'+('b'*64)
    Expect-IsolationFailure { Assert-BridgeEnvironmentImage $wanted } 'Imagen Linux local por digest no acreditada'
}
Expect-IsolationFailure { Assert-BridgeIsolationInput '' 'tester' $true } 'Texto invalido: Candidate'
Expect-IsolationFailure { Assert-BridgeIsolationInput 'candidate.json' '' $true } 'Texto invalido: ExecutedBy'
Expect-IsolationFailure { Assert-BridgeIsolationInput 'candidate.json' 'tester' $false } 'requiere -AllowIsolatedExecution'
Assert-BridgeIsolationInput 'candidate.json' 'tester' $true
$endpoints=[pscustomobject]@{
    MONGO=[pscustomobject]@{address='172.29.0.2';port=27017}
    REDIS=[pscustomobject]@{address='172.29.0.3';port=6379}
    JWKS=[pscustomobject]@{address='172.29.0.4';port=8081}
}
$appArguments=@(New-BridgeApplicationArguments $endpoints $true)
foreach($required in @('--spring.config.import=','--spring.profiles.active=','--reservations.enabled=true',
    '--mongodb.uri=mongodb://172.29.0.2:27017/bridge?replicaSet=bridgeRs',
    '--spring.mongodb.uri=mongodb://172.29.0.2:27017/bridge?replicaSet=bridgeRs',
    '--spring.data.mongodb.uri=mongodb://172.29.0.2:27017/bridge?replicaSet=bridgeRs')) {
    if (-not ($appArguments -ccontains $required)) { throw 'Configuracion explicita incompleta.' }
}
$endpoints.MONGO.port=27018
Expect-IsolationFailure { New-BridgeApplicationArguments $endpoints $true } 'Puerto aislado invalido'
$endpoints.MONGO.port=27017;$endpoints.MONGO.address='127.0.0.1'
Expect-IsolationFailure { New-BridgeApplicationArguments $endpoints $true } 'Endpoint aislado invalido'
$holder=[pscustomobject]@{Config=[pscustomobject]@{Entrypoint=@('/bin/sh');Cmd=@('-c','while :; do sleep 3600; done')}}
Assert-BridgeApplicationHolder $holder
$holder.Config.Entrypoint=@('java')
Expect-IsolationFailure { Assert-BridgeApplicationHolder $holder } 'proceso de espera esperado'
Expect-IsolationFailure { Read-BridgeIsolationImages '' } 'Texto invalido: IsolationImages'
$imageFixtureDir=Join-Path ([IO.Path]::GetTempPath()) ('bridge-images-synthetic-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $imageFixtureDir
$imageFixture=Join-Path $imageFixtureDir 'images.json'
$digest='a'*64
$images=[ordered]@{mongo=('mongo@sha256:'+$digest);redis=('redis@sha256:'+$digest);java=('java@sha256:'+$digest);tools=('tools@sha256:'+$digest)}
[IO.File]::WriteAllText($imageFixture,($images | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$loaded=Read-BridgeIsolationImages $imageFixture
if ($loaded.mongo -cne $images.mongo) { throw 'Manifiesto de imagenes alterado.' }
$images.tools='sha256:'+('b'*64)
[IO.File]::WriteAllText($imageFixture,($images | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$loaded=Read-BridgeIsolationImages $imageFixture
if ($loaded.tools -cne $images.tools) { throw 'ID local alterado.' }
Assert-BridgeLocalImageIdentity ([pscustomobject]@{Image=$images.tools}) $images.tools
Expect-IsolationFailure { Assert-BridgeLocalImageIdentity ([pscustomobject]@{Image=('sha256:'+('c'*64))}) $images.tools } 'Identidad de imagen del contenedor distinta'
$images.tools='sha256:abc'
[IO.File]::WriteAllText($imageFixture,($images | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Expect-IsolationFailure { Read-BridgeIsolationImages $imageFixture } 'Imagen por digest invalida: tools'
$images.tools='tools@sha256:'+$digest
$images.mongo='mongo:latest'
[IO.File]::WriteAllText($imageFixture,($images | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Expect-IsolationFailure { Read-BridgeIsolationImages $imageFixture } 'Imagen por digest invalida: mongo'
$images.mongo='mongo@sha256:'+$digest
$images['extra']='unexpected@sha256:'+$digest
[IO.File]::WriteAllText($imageFixture,($images | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Expect-IsolationFailure { Read-BridgeIsolationImages $imageFixture } 'Roles de imagenes incompletos o desconocidos'
Write-Host "Fixtures de imagenes conservadas: $imageFixtureDir"
Write-Host 'OK: preflight de entradas sintetico; no acredita ejecucion ni aislamiento real.'

. (Join-Path $PSScriptRoot 'ReservationBridge.Isolation.ps1')
$plan=New-BridgeIsolationResourcePlan 'synthetic' (Join-Path $PSScriptRoot 'synthetic.jar') ('a'*64)
Assert-BridgeIsolationResourcePlan $plan
$plan.internal=$false
Expect-IsolationFailure { Assert-BridgeIsolationResourcePlan $plan } 'Booleano verdadero requerido'
$plan.internal=$true
$plan.resources[0].ports=@(27018)
Expect-IsolationFailure { Assert-BridgeIsolationResourcePlan $plan } 'Puertos publicados no permitidos'
$plan.resources[0].ports=@()
$plan.resources[5].mounts=@('origen')
Expect-IsolationFailure { Assert-BridgeIsolationResourcePlan $plan } 'Montaje ajeno no permitido'
Write-Host 'OK: plan de recursos sintetico. No acredita recursos Docker ni observacion.'

$network=[pscustomobject]@{Name='bridge-synthetic-internal';Internal=$true;Driver='bridge';EnableIPv6=$false;Options=[pscustomobject]@{'com.docker.network.bridge.gateway_mode_ipv4'='isolated'}}
Assert-BridgeNetworkInspection $network 'bridge-synthetic-internal'
$network.Internal=$false
Expect-IsolationFailure { Assert-BridgeNetworkInspection $network 'bridge-synthetic-internal' } 'Booleano verdadero requerido'
$inspection=[pscustomobject]@{Name='/bridge-synthetic-mongo';HostConfig=[pscustomobject]@{NetworkMode='bridge-synthetic-internal';Privileged=$false;PortBindings=$null};Mounts=@()}
Assert-BridgeContainerInspection $inspection 'bridge-synthetic-mongo' 'bridge-synthetic-internal' $false
$inspection.HostConfig.Privileged=$true
Expect-IsolationFailure { Assert-BridgeContainerInspection $inspection 'bridge-synthetic-mongo' 'bridge-synthetic-internal' $false } 'Contenedor privilegiado'
$inspection.HostConfig.Privileged=$false
$inspection.HostConfig.NetworkMode='host'
Expect-IsolationFailure { Assert-BridgeContainerInspection $inspection 'bridge-synthetic-mongo' 'bridge-synthetic-internal' $false } 'Modo de red no permitido'
Write-Host 'OK: comparadores sinteticos de inspecciones; no se consulto Docker.'

$effective=[pscustomobject]@{
    HostConfig=[pscustomobject]@{ExtraHosts=$null;Links=$null;VolumesFrom=$null}
    NetworkSettings=[pscustomobject]@{Networks=[pscustomobject]@{'bridge-synthetic-internal'=[pscustomobject]@{}}}
}
Assert-BridgeEffectiveNetworks $effective 'bridge-synthetic-internal'
$effective.NetworkSettings.Networks | Add-Member -NotePropertyName 'foreign' -NotePropertyValue ([pscustomobject]@{})
Expect-IsolationFailure { Assert-BridgeEffectiveNetworks $effective 'bridge-synthetic-internal' } 'Redes efectivas inesperadas'
$effective.NetworkSettings.Networks.PSObject.Properties.Remove('foreign')
$effective.HostConfig.ExtraHosts=@('host.docker.internal:host-gateway')
Expect-IsolationFailure { Assert-BridgeEffectiveNetworks $effective 'bridge-synthetic-internal' } 'Configuracion de host no permitida: ExtraHosts'
$effective.HostConfig.ExtraHosts=$null
$effective.HostConfig.VolumesFrom=@('foreign-container')
Expect-IsolationFailure { Assert-BridgeEffectiveNetworks $effective 'bridge-synthetic-internal' } 'Configuracion de host no permitida: VolumesFrom'

# Doble: no invoca Docker. Se verifica create antes de inspect y falla cerrada.
$script:BridgeDockerCalls=@()
function Invoke-BridgeIsolationDocker([string[]]$Arguments) {
    $script:BridgeDockerCalls+=,($Arguments -join ' ')
    if ($Arguments[0] -ceq 'network' -and $Arguments[1] -ceq 'create') { return ('a'*64) }
    if ($Arguments[0] -ceq 'network' -and $Arguments[1] -ceq 'inspect') {
        return ('[{"Name":"bridge-synthetic-internal","Id":"' + ('a'*64) + '","Internal":true,"Driver":"bridge","EnableIPv6":false,"Options":{"com.docker.network.bridge.gateway_mode_ipv4":"isolated"},"Labels":{"eats.bridge.run":"synthetic"}}]')
    }
    throw 'Operacion Docker inesperada.'
}
$plan.resources[5].mounts=@()
$id=New-BridgeIsolatedNetwork $plan
if ($id -cne ('a'*64) -or $script:BridgeDockerCalls.Count -ne 2) { throw 'Creacion de red no comprobada.' }
$plan.internal=$false
$script:BridgeDockerCalls=@()
Expect-IsolationFailure { New-BridgeIsolatedNetwork $plan } 'Booleano verdadero requerido'
if ($script:BridgeDockerCalls.Count -ne 0) { throw 'Docker invocado pese a plan invalido.' }
Write-Host 'OK: creacion e inspeccion de red con doble sintetico; no se ejecuto Docker.'


# Preflight de servicios con doble; las entradas inválidas no llaman Docker.
$plan.internal=$true
$script:BridgeDockerCalls=@()
Expect-IsolationFailure { New-BridgeIsolatedService $plan 'MONGO' 'mongo:latest' } 'Imagen por digest requerido'
if ($script:BridgeDockerCalls.Count -ne 0) { throw 'Docker invocado con imagen invalida.' }
Expect-IsolationFailure { New-BridgeIsolatedService $plan 'APP' ('example@sha256:'+('a'*64)) } 'Rol de servicio no permitido'
if ($script:BridgeDockerCalls.Count -ne 0) { throw 'Docker invocado con rol invalido.' }
Write-Host 'OK: rechazo de parametros de servicio con doble; no se ejecuto Docker.'


# Camino exitoso simulado: el doble devuelve un contenedor detenido e inspeccionado.
function Invoke-BridgeIsolationDocker([string[]]$Arguments) {
    $script:BridgeDockerCalls+=,($Arguments -join ' ')
    if ($Arguments[0] -ceq 'create') { return ('b'*64) }
    if ($Arguments[0] -ceq 'inspect') {
        return ('[{"Id":"' + ('b'*64) + '","Name":"/bridge-synthetic-mongo","HostConfig":{"NetworkMode":"bridge-synthetic-internal","Privileged":false,"PortBindings":null,"ExtraHosts":null,"Links":null,"VolumesFrom":null},"NetworkSettings":{"Networks":{"bridge-synthetic-internal":{}}},"Mounts":[],"Config":{"Labels":{"eats.bridge.run":"synthetic"}},"State":{"Running":false}}]')
    }
    throw 'Operacion Docker inesperada.'
}
$script:BridgeDockerCalls=@()
$serviceId=New-BridgeIsolatedService $plan 'MONGO' ('mongo@sha256:'+('a'*64))
if ($serviceId -cne ('b'*64) -or $script:BridgeDockerCalls.Count -ne 2) { throw 'Servicio no fue creado e inspeccionado por el doble.' }
if ($script:BridgeDockerCalls[0] -notmatch '--cap-drop ALL' -or
    $script:BridgeDockerCalls[0] -notmatch '--security-opt no-new-privileges' -or
    $script:BridgeDockerCalls[0] -notmatch '--pull never' -or
    $script:BridgeDockerCalls[0] -notmatch '--network bridge-synthetic-internal') {
    throw 'Faltan restricciones de servicio.'
}
Write-Host 'OK: creacion e inspeccion de servicio con doble; no se ejecuto Docker.'


$observerInspection=[pscustomobject]@{
    Name='/bridge-synthetic-observer'
    HostConfig=[pscustomobject]@{NetworkMode=('container:'+('c'*64));PidMode=('container:'+('c'*64));Privileged=$false;CapAdd=@('NET_RAW','SYS_PTRACE');CapDrop=@('ALL');PortBindings=$null;SecurityOpt=@('no-new-privileges',('seccomp='+((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bridge/observer-seccomp.json') -Raw|ConvertFrom-Json)|ConvertTo-Json -Depth 30 -Compress)))}
    Mounts=@()
}
Assert-BridgeObserverInspection $observerInspection 'bridge-synthetic-observer' ('c'*64)
$observerInspection.HostConfig.CapAdd=@('NET_RAW','NET_ADMIN')
Expect-IsolationFailure { Assert-BridgeObserverInspection $observerInspection 'bridge-synthetic-observer' ('c'*64) } 'Capacidades del observador invalidas'
$observerInspection.HostConfig.CapAdd=@('NET_RAW','SYS_PTRACE')
$observerInspection.HostConfig.NetworkMode='host'
Expect-IsolationFailure { Assert-BridgeObserverInspection $observerInspection 'bridge-synthetic-observer' ('c'*64) } 'Espacio de red del observador incorrecto'
$observerInspection.HostConfig.NetworkMode=('container:'+('c'*64))
$savedSecurity=$observerInspection.HostConfig.SecurityOpt
$observerInspection.HostConfig.SecurityOpt=,@($savedSecurity)
Expect-IsolationFailure {Assert-BridgeObserverInspection $observerInspection 'bridge-synthetic-observer' ('c'*64)} 'Seccomp/privilegios del observador incorrectos'
$observerInspection.HostConfig.SecurityOpt='no-new-privileges'
Expect-IsolationFailure {Assert-BridgeObserverInspection $observerInspection 'bridge-synthetic-observer' ('c'*64)} 'Seccomp/privilegios del observador incorrectos'
$observerInspection.HostConfig.SecurityOpt=$savedSecurity
Assert-BridgeObserverInspection $observerInspection 'bridge-synthetic-observer' ('c'*64)
Write-Host 'OK: inspeccion sintetica del observador; no se ejecuto captura ni Docker.'
