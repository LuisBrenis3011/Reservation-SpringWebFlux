# Preparacion exclusivamente local del ensayo. Cargar este archivo no ejecuta Docker.
function Get-BridgeEnvironmentInspection([string]$Id) {
    if ($Id -cnotmatch '^[a-f0-9]{64}$') { throw 'Identificador de entorno invalido.' }
    $items=@((@(Invoke-BridgeIsolationDocker @('inspect',$Id)) -join "`n" | ConvertFrom-Json -ErrorAction Stop))
    if($items.Count -ne 1 -or $items[0].Id -cne $Id){throw 'Inspeccion de entorno incompleta.'}
    return $items[0]
}
function Assert-BridgeImageEnvironment($Entries) {
    $safe='^(PATH|HOME|LANG|LANGUAGE|LC_ALL|TERM|TZ|JAVA_HOME|JAVA_VERSION|JAVA_RUNTIME_VERSION|JAVA_TOOL_OPTIONS|JDK_JAVA_OPTIONS|_JAVA_OPTIONS|PYTHON_VERSION|PYTHON_SHA256|PYTHON_PIP_VERSION|PYTHON_SETUPTOOLS_VERSION|PYTHON_GET_PIP_URL|PYTHON_GET_PIP_SHA256|PYTHONUNBUFFERED|GPG_KEY|GOSU_VERSION|MONGO_MAJOR|MONGO_VERSION|MONGO_PACKAGE|MONGO_REPO|JSYAML_VERSION|REDIS_VERSION|REDIS_DOWNLOAD_URL|REDIS_DOWNLOAD_SHA)='
    foreach($entry in @($Entries)) {
        if($entry -cmatch '^JSYAML_CHECKSUM=[a-f0-9]{64}$' -or $entry -ceq 'GLIBC_TUNABLES=glibc.pthread.rseq=0') { continue }
        if($entry -cnotmatch $safe){throw 'Variable heredada de imagen no autorizada.'}
    }
}
function Assert-BridgeEnvironmentImage([string]$Image) {
    if(-not (Test-BridgeImageReference $Image)){throw 'Imagen por digest requerida.'}
    $items=@((@(Invoke-BridgeIsolationDocker @('image','inspect',$Image)) -join "`n" | ConvertFrom-Json -ErrorAction Stop))
    if($items.Count -ne 1 -or $items[0].Os -cne 'linux'){throw 'Imagen Linux local por digest no acreditada.'}
    if($Image -cmatch '^sha256:[a-f0-9]{64}$') { if($items[0].Id -cne $Image){throw 'Imagen Linux local por digest no acreditada.'} }
    elseif(-not (@($items[0].RepoDigests) -ccontains $Image)){throw 'Imagen Linux local por digest no acreditada.'}
    Assert-BridgeImageEnvironment $items[0].Config.Env
    return $items[0].Id
}
function New-BridgeEnvironmentContainer($Context,[string]$Role,[string]$Image,[string]$Entry,[string[]]$Command,[string[]]$Tmpfs=@()) {
    $name='bridge-'+$Context.resourceRunId.ToLowerInvariant()+'-'+$Role.ToLowerInvariant()
    $arguments=@('create','--pull','never','--no-healthcheck','--name',$name,'--network',$Context.Plan.network,'--label',('eats.bridge.run='+$Context.resourceRunId),'--cap-drop','ALL','--security-opt','no-new-privileges','--sysctl','net.ipv6.conf.all.disable_ipv6=1','--entrypoint',$Entry)
    foreach($destination in $Tmpfs){$arguments+=@('--tmpfs',($destination+':rw,nosuid,nodev'))}
    $arguments+=@($Image)+$Command
    $created=@(Invoke-BridgeIsolationDocker $arguments)
    if($created.Count -ne 1 -or "$($created[0])" -cnotmatch '^[a-f0-9]{64}$'){throw 'Identidad de contenedor no acreditada.'}
    $id="$($created[0])";$Context.containers[$Role]=$id
    $inspection=Get-BridgeEnvironmentInspection $id
    Assert-BridgeLocalImageIdentity $inspection $Image
    if($inspection.Name -cne ('/'+$name) -or $inspection.Config.Labels.'eats.bridge.run' -cne $Context.resourceRunId -or $inspection.State.Running){throw 'Contenedor inesperado o iniciado prematuramente.'}
    $mounts=@($inspection.Mounts)
    foreach($mount in $mounts){if($mount.Type -cne 'tmpfs' -or -not ($Tmpfs -ccontains $mount.Destination)){throw 'Montaje no sintetico en servicio.'}}
    # Los tmpfs declarados nunca se convierten en una excepcion para bind/volume.
    $saved=$inspection.Mounts;$inspection.Mounts=@()
    try{Assert-BridgeContainerInspection $inspection $name $Context.Plan.network $false}finally{$inspection.Mounts=$saved}
    Assert-BridgeEffectiveNetworks $inspection $Context.Plan.network
    if(@($inspection.HostConfig.CapDrop).Count -ne 1 -or $inspection.HostConfig.CapDrop[0] -cne 'ALL' -or @($inspection.HostConfig.CapAdd | Where-Object {$null -ne $_}).Count){throw 'Capacidades de servicio no autorizadas.'}
    return $id
}
function ConvertTo-BridgeBase64Url([byte[]]$Bytes){return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_')}
function New-BridgeEnvironmentIdentity([string]$Issuer,[string]$Restaurant,[string]$OtherRestaurant) {
    $rsa=[Security.Cryptography.RSACryptoServiceProvider]::new(2048);$rsa.PersistKeyInCsp=$false
    try{
        $public=$rsa.ExportParameters($false)
        $jwks=@{keys=@(@{kty='RSA';use='sig';alg='RS256';kid='bridge';n=(ConvertTo-BridgeBase64Url $public.Modulus);e=(ConvertTo-BridgeBase64Url $public.Exponent)})}
        $tokens=@{};$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $profiles=@{
            owner=@{sub='bridge-owner';roles=@('CUSTOMER');restaurant_ids=@()}
            otherCustomer=@{sub='bridge-other';roles=@('CUSTOMER');restaurant_ids=@()}
            manager=@{sub='bridge-manager';roles=@('RESTAURANT_MANAGER');restaurant_ids=@($Restaurant)}
            otherManager=@{sub='bridge-other-manager';roles=@('RESTAURANT_MANAGER');restaurant_ids=@($OtherRestaurant)}
        }
        foreach($name in $profiles.Keys){
            $claim=$profiles[$name];$claim.iss=$Issuer;$claim.aud=@('eats-hub-catalog');$claim.iat=$now-5;$claim.nbf=$now-5;$claim.exp=$now+7200
            $header=ConvertTo-BridgeBase64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT","kid":"bridge"}'))
            $payload=ConvertTo-BridgeBase64Url ([Text.Encoding]::UTF8.GetBytes(($claim|ConvertTo-Json -Depth 8 -Compress)))
            $unsigned=$header+'.'+$payload
            $signature=$rsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned),[Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'))
            $tokens[$name]=$unsigned+'.'+(ConvertTo-BridgeBase64Url $signature)
        }
        $tokens.customer=$tokens.owner
        return [pscustomobject]@{jwks=$jwks;tokens=$tokens}
    }finally{$rsa.Dispose()}
}
function Invoke-BridgeEnvironmentManifest($Context) {
    $output=@(Invoke-BridgeIsolationDocker @('exec','-e','EATS_BACKUP_DATABASE=bridge','-e','EATS_BACKUP_SOURCE=false',$Context.containers.MONGO,'mongosh','--quiet','mongodb://127.0.0.1:27017/?directConnection=true&serverSelectionTimeoutMS=2000','--file','/opt/environment_manifest.js'))
    $manifest=$output -join "`n" | ConvertFrom-Json -ErrorAction Stop
    $path=Join-Path $Context.directory ('manifest-'+[guid]::NewGuid().ToString('N')+'.json')
    Write-BridgeNewJson $path $manifest
    if($null -eq $Context.PSObject.Properties['manifestRefs']){$Context|Add-Member -NotePropertyName manifestRefs -NotePropertyValue @()}
    $Context.manifestRefs+=@([pscustomobject]@{path=$path.Substring($Context.root.Length+1).Replace('\','/');sha256=(Get-BridgeHash $path)})
    return $manifest
}
function Assert-BridgeApplicationProcess($Context) {
    $shell='pid=$(cat /tmp/bridge-java.pid) || exit 2; case "$pid" in ""|*[!0-9]*) exit 3;; esac; tr "\000" "\n" < "/proc/$pid/cmdline"'
    $actual=@(Invoke-BridgeIsolationDocker @('exec',$Context.containers.APP,'/bin/sh','-c',$shell))
    $expected=@(New-BridgeApplicationArguments $Context.endpoints ([bool]$Context.gate))
    if($actual.Count -ne $expected.Count+1 -or $actual[0] -notmatch '(^|/)java$'){throw 'Proceso Java no corresponde al JAR del ensayo.'}
    for($i=0;$i -lt $expected.Count;$i++){if($actual[$i+1] -cne $expected[$i]){throw 'Configuracion efectiva Java discordante.'}}
    $path=Join-Path $Context.directory ('java-config-'+[guid]::NewGuid().ToString('N')+'.json')
    Write-BridgeNewJson $path @{runId=$Context.runId;containerId=$Context.containers.APP;arguments=$expected;gate=$Context.gate;verifiedAtUtc=[DateTime]::UtcNow.ToString('o')}
    if($null -eq $Context.PSObject.Properties['configurationRefs']){$Context|Add-Member -NotePropertyName configurationRefs -NotePropertyValue @()}
    $Context.configurationRefs+=@([pscustomobject]@{path=$path.Substring($Context.root.Length+1).Replace('\','/');sha256=(Get-BridgeHash $path)})
}
function Stop-BridgeEnvironmentApplication($Context) {
    if(-not $Context.containers.ContainsKey('APP')){return}
    $script=@'
if [ -f /tmp/bridge-java.pid ]; then
  pid=$(cat /tmp/bridge-java.pid)
  case "$pid" in ''|*[!0-9]*) exit 11;; esac
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" || exit 12
    n=0
    while kill -0 "$pid" 2>/dev/null; do
      n=$((n+1)); [ "$n" -lt 100 ] || exit 13
      sleep 0.1
    done
  fi
  rm -f /tmp/bridge-java.pid
fi
'@
    $null=Invoke-BridgeIsolationDocker @('exec',$Context.containers.APP,'/bin/sh','-c',$script)
    if($null -ne $Context.PSObject.Properties['Observation'] -and $null -ne $Context.Observation.PSObject.Properties['activeTraceId']){$Context.Observation.activeTraceId=$null}
}
function Start-BridgeEnvironmentApplication($Context,[bool]$Gate) {
    if($Context.observationReady -isnot [bool] -or -not $Context.observationReady){throw 'Observacion/autocomprobacion no acreditada: no iniciar JAR.'}
    Stop-BridgeEnvironmentApplication $Context
    $mounted=@(Invoke-BridgeIsolationDocker @('exec',$Context.containers.APP,'sha256sum','/opt/bridge.jar'))
    if($mounted.Count -ne 1 -or (($mounted[0] -split '\s+')[0]) -ine $Context.Plan.resources[4].mounts[0].sha256){throw 'Hash del JAR efectivo discordante antes de arrancar.'}
    $args=@(New-BridgeApplicationArguments $Context.endpoints $Gate)
    $traceId=[guid]::NewGuid().ToString('N');$marker='bridge-trace-'+$Context.runId+'-'+$traceId
    $script='echo $$ > /tmp/bridge-java.pid; kill -STOP $$; exec java "$@" > /tmp/bridge-java.log 2>&1'
    $null=Invoke-BridgeIsolationDocker (@('exec','-d',$Context.containers.APP,'/bin/sh','-c',$script,$marker)+$args)
    $deadline=[DateTime]::UtcNow.AddSeconds(10);$pidValue=0
    do{try{$pidText=@(Invoke-BridgeIsolationDocker @('exec',$Context.containers.APP,'cat','/tmp/bridge-java.pid'));if($pidText.Count -eq 1){$pidValue=[int]$pidText[0]}}catch{};if($pidValue -le 1){Start-Sleep -Milliseconds 100}}while($pidValue -le 1 -and [DateTime]::UtcNow -lt $deadline)
    if($pidValue -le 1){throw 'Java detenido no identificable antes de trazar.'}
    Start-BridgeTraceTarget $Context.Observation $traceId $pidValue 'java'
    $Context.Observation.activeTraceId=$traceId
    $Context.gate=$Gate
}
function Stop-BridgeEnvironment($Context) {
    foreach($id in @($Context.containers.Values)){
        $inspection=Get-BridgeEnvironmentInspection $id
        if($inspection.Config.Labels.'eats.bridge.run' -cne $Context.resourceRunId){throw 'No detener recurso ajeno.'}
        if($inspection.State.Running){$null=Invoke-BridgeIsolationDocker @('stop','--time','10',$id)}
    }
}
function Invoke-BridgeEnvironment($CandidateValue,[string]$Root,$Images,[string]$Actor,[string]$AttemptDirectory='') {
    Assert-BridgeText $Actor 'ExecutedBy';Assert-BridgeCandidate $CandidateValue $Root
    foreach($role in @('mongo','redis','java','tools')){$null=Assert-BridgeEnvironmentImage (Get-BridgeField $Images $role)}
    $os=@(Invoke-BridgeIsolationDocker @('info','--format','{{.OSType}}'))
    if($os.Count -ne 1 -or $os[0] -cne 'linux'){throw 'Se requieren contenedores Linux.'}
    $attemptId=[guid]::NewGuid().ToString('N')
    $directory=if($AttemptDirectory){Join-Path $AttemptDirectory 'environment'}else{Join-Path $Root ('isolated-'+$attemptId)}
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')+[IO.Path]::DirectorySeparatorChar
    $directoryFull=[IO.Path]::GetFullPath($directory)
    if(-not $directoryFull.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){throw 'Directorio de entorno fuera del candidato.'}
    $null=New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $ctx=[pscustomobject]@{runId=$CandidateValue.runId;attemptId=$attemptId;resourceRunId=$attemptId;root=$Root;directory=$directory;relativeDirectory=$directoryFull.Substring($rootFull.Length).Replace('\','/');Plan=$null;networkId='';Images=$Images;containers=@{};endpoints=$null;services=@();tokens=@{};fixtures=$null;appAddress='';toolsAddress='';baseUri='';issuer='';observationReady=$false;gate=$false}
    try{
        $platform=@(Invoke-BridgeIsolationDocker @('version','--format','{{json .}}')) -join "`n" | ConvertFrom-Json -ErrorAction Stop
        Write-BridgeNewJson (Join-Path $directory 'platform.json') @{clientVersion=$platform.Client.Version;engineVersion=$platform.Server.Version;os=$platform.Server.Os;backend=$platform.Server.Platform.Name;images=$Images}
        $jar=Get-BridgeSafeFile $Root $CandidateValue.jarPath
        $ctx.Plan=New-BridgeIsolationResourcePlan $attemptId $jar $CandidateValue.jarSha256
        $networkId=New-BridgeIsolatedNetwork $ctx.Plan
        $ctx.networkId=$networkId
        $ctx.containers.MONGO=New-BridgeEnvironmentContainer $ctx 'MONGO' $Images.mongo '/bin/sh' @('-c','while :; do sleep 3600; done') @('/data/db','/data/configdb')
        $ctx.containers.REDIS=New-BridgeEnvironmentContainer $ctx 'REDIS' $Images.redis '/bin/sh' @('-c','while :; do sleep 3600; done') @('/data')
        foreach($role in @('JWKS','DNS')){$ctx.containers[$role]=New-BridgeEnvironmentContainer $ctx $role $Images.tools '/bin/sh' @('-c','while :; do sleep 3600; done')}
        $ctx.containers.APP=New-BridgeIsolatedApplication $ctx.Plan $Images.java
        $ctx.containers.TOOLS=New-BridgeEnvironmentContainer $ctx 'TOOLS' $Images.tools '/bin/sh' @('-c','while :; do sleep 3600; done')
        foreach($role in @('MONGO','REDIS','JWKS','DNS','APP','TOOLS')){
            $inspection=Get-BridgeEnvironmentInspection $ctx.containers[$role]
            Assert-BridgeEffectiveNetworks $inspection $ctx.Plan.network
            $network=Get-BridgeField $inspection.NetworkSettings.Networks $ctx.Plan.network
            $address=$network.IPAddress
            # Algunos engines asignan IP solo tras start: obtenerla despues para servicios.
            if(-not $address){$null=Invoke-BridgeIsolationDocker @('start',$ctx.containers[$role]);$inspection=Get-BridgeEnvironmentInspection $ctx.containers[$role];$network=Get-BridgeField $inspection.NetworkSettings.Networks $ctx.Plan.network;$address=$network.IPAddress}
            if([string]::IsNullOrWhiteSpace($address)){throw 'Direccion aislada no asignada.'}
            $port=switch($role){MONGO{27017} REDIS{6379} JWKS{8081} DNS{53} default{8080}}
            $ctx.services+= [pscustomobject]@{id=$ctx.containers[$role];address=$address;role=$(if($role -ceq 'TOOLS'){'HARNESS'}else{$role});port=$port}
        }
        $ctx.appAddress=(@($ctx.services|Where-Object role -CEQ 'APP')[0]).address
        $ctx.toolsAddress=(@($ctx.services|Where-Object role -CEQ 'HARNESS')[0]).address
        $ctx.baseUri='http://'+$ctx.appAddress+':8080/catalog'
        $ep=@{};foreach($role in @('MONGO','REDIS','JWKS')){$s=@($ctx.services|Where-Object role -CEQ $role)[0];$ep[$role]=[pscustomobject]@{address=$s.address;port=$s.port}}
        $ctx.endpoints=[pscustomobject]$ep;$null=New-BridgeApplicationArguments $ctx.endpoints $false
        $ctx.issuer='http://'+$ep.JWKS.address+':8081'
        $fixtures=[pscustomobject]@{restaurantId=[guid]::NewGuid().ToString();otherRestaurantId=[guid]::NewGuid().ToString();legacyId=[guid]::NewGuid().ToString();confirmedId=[guid]::NewGuid().ToString();cancelledId=[guid]::NewGuid().ToString();tableId=[guid]::NewGuid().ToString();shiftId=[guid]::NewGuid().ToString();issuer=$ctx.issuer;localStart='2019-01-01T18:00';localEnd='2019-01-01T19:00';startInstant='2019-01-01T18:00:00Z';endInstant='2019-01-01T19:00:00Z';createdAt='2018-12-01T00:00:00Z'}
        $identity=New-BridgeEnvironmentIdentity $ctx.issuer $fixtures.restaurantId $fixtures.otherRestaurantId;$ctx.tokens=$identity.tokens;$ctx.fixtures=$fixtures
        foreach($which in @('Confirmed','Cancelled')){
            $id=if($which -ceq 'Confirmed'){$fixtures.confirmedId}else{$fixtures.cancelledId}
            $state=if($which -ceq 'Confirmed'){'CONFIRMED'}else{'CANCELLED'}
            $projection=[ordered]@{kind='MANAGED';id=$id;restaurantId=$fixtures.restaurantId;owner=@{issuer=$ctx.issuer;subject='bridge-owner'};shiftId=$fixtures.shiftId;partySize=2;notes='bridge-managed-secret';status=$state;version=1;tableIds=@($fixtures.tableId);combinationId=$null;assignedCapacity=4;localStart=$fixtures.localStart;localEnd=$fixtures.localEnd;zoneId='UTC';startInstant=$fixtures.startInstant;endInstant=$fixtures.endInstant;createdAt=$fixtures.createdAt;updatedAt=$fixtures.createdAt;cancelledAt=$(if($which -ceq 'Cancelled'){$fixtures.createdAt}else{$null})}
            $fixtures | Add-Member -NotePropertyName ('expected'+$which) -NotePropertyValue ([pscustomobject]$projection)
        }
        $publicConfigs=@{JWKS=@{role='JWKS';jwks=$identity.jwks};DNS=@{role='DNS';hosts=@{}}}
        foreach($s in $ctx.services){$publicConfigs.DNS.hosts[$s.role.ToLowerInvariant()+'.bridge.test']=$s.address}
        foreach($role in @('JWKS','DNS')){
            $config=Join-Path $directory ($role.ToLowerInvariant()+'-config.json');Write-BridgeNewJson $config $publicConfigs[$role]
            $null=Invoke-BridgeIsolationDocker @('cp',(Join-Path $PSScriptRoot 'bridge/environment_service.py'),($ctx.containers[$role]+':/opt/environment_service.py'))
            $null=Invoke-BridgeIsolationDocker @('cp',$config,($ctx.containers[$role]+':/opt/environment-config.json'))
        }
        $fixtures|Add-Member -NotePropertyName mongoAddress -NotePropertyValue $ep.MONGO.address
        $fixtureFile=Join-Path $directory 'fixture.json';Write-BridgeNewJson $fixtureFile $fixtures
        $generated=@{
            'redis.conf'="port 6379`nsave `"`"`nappendonly no`n"
            'replica-init.js'='const f=JSON.parse(require("fs").readFileSync("/opt/environment-fixture.json","utf8"));rs.initiate({_id:"bridgeRs",members:[{_id:0,host:f.mongoAddress+":27017"}]});'
        }
        foreach($name in $generated.Keys){
            $file=Join-Path $directory $name
            $bytes=[Text.UTF8Encoding]::new($false).GetBytes($generated[$name])
            $stream=[IO.File]::Open($file,[IO.FileMode]::CreateNew)
            try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
            $target=if($name -ceq 'redis.conf'){$ctx.containers.REDIS}else{$ctx.containers.MONGO}
            $null=Invoke-BridgeIsolationDocker @('cp',$file,($target+':/opt/'+$name))
        }
        foreach($mapping in @(@{source=$fixtureFile;target='environment-fixture.json'},@{source=(Join-Path $PSScriptRoot 'bridge/environment_seed.js');target='environment_seed.js'},@{source=(Join-Path $PSScriptRoot 'mongo-backup-manifest.js');target='environment_manifest.js'})){$null=Invoke-BridgeIsolationDocker @('cp',$mapping.source,($ctx.containers.MONGO+':/opt/'+$mapping.target))}
        foreach($role in @('MONGO','REDIS','JWKS','DNS','APP','TOOLS')){$null=Invoke-BridgeIsolationDocker @('start',$ctx.containers[$role])}
        $null=Invoke-BridgeIsolationDocker @('exec','-d',$ctx.containers.MONGO,'mongod','--replSet','bridgeRs','--bind_ip_all','--port','27017','--dbpath','/data/db')
        $null=Invoke-BridgeIsolationDocker @('exec','-d',$ctx.containers.REDIS,'redis-server','/opt/redis.conf')
        foreach($role in @('JWKS','DNS')){$null=Invoke-BridgeIsolationDocker @('exec','-d',$ctx.containers[$role],'python3','/opt/environment_service.py','/opt/environment-config.json')}
        $mongoUri='mongodb://127.0.0.1:27017/?directConnection=true&serverSelectionTimeoutMS=2000'
        $ready=$false;for($i=0;$i -lt 30;$i++){try{$null=Invoke-BridgeIsolationDocker @('exec',$ctx.containers.MONGO,'mongosh','--quiet',$mongoUri,'--eval','if(!db.adminCommand({ping:1}).ok)quit(2)');$ready=$true;break}catch{Start-Sleep -Milliseconds 250}}
        if(-not $ready){throw 'Mongo sintetico no disponible.'}
        $null=Invoke-BridgeIsolationDocker @('exec',$ctx.containers.MONGO,'mongosh','--quiet',$mongoUri,'--file','/opt/replica-init.js')
        $primary=$false;for($i=0;$i -lt 40;$i++){try{$null=Invoke-BridgeIsolationDocker @('exec',$ctx.containers.MONGO,'mongosh','--quiet',$mongoUri,'--eval','if(!db.hello().isWritablePrimary)quit(2)');$primary=$true;break}catch{Start-Sleep -Milliseconds 250}}
        if(-not $primary){throw 'Replica sintetica no es PRIMARY.'}
        $null=Invoke-BridgeIsolationDocker @('exec',$ctx.containers.MONGO,'mongosh','--quiet',$mongoUri,'--file','/opt/environment_seed.js')
        $dns=(@($ctx.services|Where-Object role -CEQ 'DNS')[0]).address
        foreach($role in @('APP','TOOLS')){$null=Invoke-BridgeIsolationDocker @('exec',$ctx.containers[$role],'/bin/sh','-c',('printf "nameserver '+$dns+'\noptions ndots:0\n" > /etc/resolv.conf'))}
        foreach($role in @('APP','TOOLS')){
            $routes=@(Invoke-BridgeIsolationDocker @('exec',$ctx.containers[$role],'cat','/proc/net/route'))
            foreach($line in ($routes|Select-Object -Skip 1)){if(($line -split '\s+')[1] -ceq '00000000'){throw 'Ruta predeterminada no permitida en el ensayo.'}}
            $resolver=@(Invoke-BridgeIsolationDocker @('exec',$ctx.containers[$role],'cat','/etc/resolv.conf'))
            if(($resolver -join "`n") -cne ("nameserver "+$dns+"`noptions ndots:0")){throw 'DNS efectivo no coincide.'}
        }
        $sanitized=@{runId=$ctx.runId;resourceRunId=$ctx.resourceRunId;networkId=$networkId;containers=$ctx.containers;services=$ctx.services;endpoints=$ctx.endpoints;images=$Images;fixturePath='fixture.json';jarSha256=$CandidateValue.jarSha256}
        Write-BridgeNewJson (Join-Path $directory 'environment.json') $sanitized
        return $ctx
    }catch{
        Write-BridgeNewJson (Join-Path $directory 'environment-failed.json') @{runId=$ctx.runId;resourceRunId=$ctx.resourceRunId;containers=$ctx.containers;status='Failed';reason='Preparacion del entorno incompleta; conservar recursos.'}
        try{Stop-BridgeEnvironment $ctx}catch{}
        throw
    }
}
