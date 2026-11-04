[CmdletBinding()]
param([switch]$WritersStopped,[switch]$IncludeCombinations,[switch]$IncludeShifts,[switch]$IncludeManagedReservations,[string[]]$CheckpointPaths=@())
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
. (Join-Path $PSScriptRoot 'ManagedReservations.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationReplacement.Assertions.ps1')
Initialize-ManagedMode ([bool]$IncludeManagedReservations) ([bool]$IncludeCombinations) ([bool]$IncludeShifts)
$managedHashes=[ordered]@{}
if($IncludeManagedReservations){
 if(!$CheckpointPaths.Count){$CheckpointPaths=@(Get-ChildItem $script:IdentityPrivate -Filter '*checkpoint.json' -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName)}
 $managedHashes=Get-ManagedCheckpointHashes $CheckpointPaths
 if((Read-ManagedPolicy).retired -and !$managedHashes.Count){throw 'Tras corte exige checkpoints de los ensayos; no se inventa evidencia.'}
 if((Read-ManagedPolicy).retired){
  $required=[IO.Path]::GetFullPath((Join-Path $script:IdentityPrivate 'reservation-confirmation-http-checkpoint.json'))
  if(!$managedHashes.Contains($required)){throw 'Falta hash del recorrido de confirmacion.'}
  $confirmationProof=Get-Content $required -Raw|ConvertFrom-Json
  if($confirmationProof.spec -cne 'SPEC-005' -or $null -eq $confirmationProof.final -or $confirmationProof.pendingName -or @($confirmationProof.restart).Count -eq 0){throw 'Falta confirmacion HTTP/reinicio completos; no se acredita restauracion del lote.'}
 }
}

$combinationExpectationsBase64=$null
$checkpointHashes=@{}
if($IncludeCombinations){
    $httpPath=Join-Path $script:IdentityPrivate 'combinations-http-checkpoint.json'
    $gatePath=Join-Path $script:IdentityPrivate 'combinations-gate-checkpoint.json'
    foreach($path in @($httpPath,$gatePath)){
        if(!(Test-Path -LiteralPath $path)){throw 'Completa HTTP, reinicio y ambos gates de SPEC-002 antes del respaldo.'}
        $checkpointHashes[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    $http=Get-Content -LiteralPath $httpPath -Raw | ConvertFrom-Json
    $gate=Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json
    if($http.schemaVersion -ne 1 -or $http.spec -cne 'SPEC-002' -or !$http.httpCompleted -or
        !$http.restart.operatorDeclaredRestart -or !$http.restart.dataAndRevisionPreserved -or
        $http.baseUrl -cne ('http://localhost:8082/catalog/restaurants/'+$script:RestaurantA+'/table-combinations') -or
        $gate.schemaVersion -ne 1 -or $gate.spec -cne 'SPEC-002' -or $gate.runId -cne $http.runId -or
        $gate.baselineSha256 -cne $checkpointHashes[$httpPath] -or @($gate.attempts).Count -eq 0){throw 'Checkpoints de combinaciones incompatibles o incompletos.'}
    $enabled=@($gate.attempts)[-1]
    $disabled=@($gate.attempts | Where-Object {$_.stage -eq 'Disabled' -and $_.attemptId -ceq $enabled.disabledAttemptId})
    if($enabled.stage -cne 'Enabled' -or !$enabled.dataPreservedAfterReactivation -or
        @($enabled.checks).Count -ne 6 -or @($enabled.checks | Where-Object {!$_.passed}).Count -or
        $disabled.Count -ne 1 -or @($disabled[0].checks).Count -ne 3 -or
        @($disabled[0].checks | Where-Object {!$_.passed}).Count -or $enabled.revision -ne $http.final.revision){throw 'El ultimo ciclo del gate no esta completo y reactivado.'}
    $receipts=@{}
    foreach($step in $http.steps.PSObject.Properties){
        $entry=$step.Value
        if($entry.intent.method -in @('Post','Put') -and $null -ne $entry.response -and
            $entry.response.status -in @(200,201)){
            $receipts[$entry.intent.key]=[pscustomobject]@{key=$entry.intent.key;status=$entry.response.status;
                location=$entry.response.location;body=($entry.response.content | ConvertFrom-Json)}
        }
    }
    if($receipts.Count -ne 7 -or @($http.final.combinations).Count -lt 2){throw 'El checkpoint no contiene los siete comandos aceptados y las combinaciones del ensayo.'}
    $combinationExpectations=([pscustomobject]@{restaurantId=$script:RestaurantA;revision=$http.final.revision;
        tables=@($http.final.tables);combinations=@($http.final.combinations);
        receipts=@($receipts.Values | Sort-Object key)} | ConvertTo-Json -Depth 30 -Compress)
    # Base64 evita que Windows PowerShell 5.1 altere las comillas JSON al
    # construir los argumentos de docker.exe. No es cifrado ni se imprime.
    $combinationExpectationsBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($combinationExpectations))
}
if($IncludeShifts -and $IncludeCombinations){throw 'Usa cada modo por separado: los checkpoints de SPEC-002 conservan una revision historica distinta.'}
$shiftExpectationsBase64=$null
if($IncludeShifts){
    $shiftHttpPath=Join-Path $script:IdentityPrivate 'shifts-http-checkpoint.json'
    $shiftGatePath=Join-Path $script:IdentityPrivate 'shifts-gate-checkpoint.json'
    foreach($path in @($shiftHttpPath,$shiftGatePath)){
        if(!(Test-Path -LiteralPath $path)){throw 'Faltan HTTP y gates de SPEC-003.'}
        $checkpointHashes[$path]=(Get-FileHash $path -Algorithm SHA256).Hash
    }
    $shiftHttp=Get-Content $shiftHttpPath -Raw|ConvertFrom-Json
    $shiftGate=Get-Content $shiftGatePath -Raw|ConvertFrom-Json
    if($shiftHttp.schemaVersion -ne 1 -or $shiftHttp.spec -cne 'SPEC-003' -or !$shiftHttp.httpCompleted -or
        !$shiftHttp.restart.operatorDeclaredRestart -or !$shiftHttp.restart.dataAndRevisionPreserved -or
        $shiftHttp.baseUrl -cne ('http://localhost:8082/catalog/restaurants/'+$script:RestaurantA+'/shifts') -or
        $shiftGate.schemaVersion -ne 1 -or $shiftGate.spec -cne 'SPEC-003' -or
        $shiftGate.runId -cne $shiftHttp.runId -or $shiftGate.baselineSha256 -cne $checkpointHashes[$shiftHttpPath] -or
        @($shiftGate.attempts).Count -eq 0){throw 'Checkpoints de turnos incompatibles o incompletos.'}
    $last=@($shiftGate.attempts)[-1]
    $prior=@($shiftGate.attempts|Where-Object{$_.stage -ceq 'Disabled' -and $_.attemptId -ceq $last.disabledAttemptId})
    if($last.stage -cne 'Enabled' -or !$last.dataPreservedAfterReactivation -or $last.revision -ne $shiftHttp.final.revision -or
        @($last.checks).Count -ne 11 -or @($last.checks|Where-Object{!$_.passed}).Count -ne 0 -or
        $prior.Count -ne 1 -or @($prior[0].checks).Count -ne 5 -or @($prior[0].checks|Where-Object{!$_.passed}).Count -ne 0){throw 'Ciclo del gate de turnos incompleto.'}
    $shiftReceipts=@{}
    foreach($step in $shiftHttp.steps.PSObject.Properties){
        $entry=$step.Value
        if($null -eq $entry.response -or $entry.response.status -ne $entry.intent.status){throw 'Etapa HTTP incompleta.'}
        if($entry.intent.method -in @('Post','Put') -and $entry.response.status -in @(200,201)){
            $receipt=[pscustomobject]@{key=$entry.intent.key;status=$entry.response.status;location=$entry.response.location;body=($entry.response.content|ConvertFrom-Json)}
            if($shiftReceipts.ContainsKey($receipt.key) -and
                ($shiftReceipts[$receipt.key]|ConvertTo-Json -Depth 20 -Compress) -cne ($receipt|ConvertTo-Json -Depth 20 -Compress)){throw 'Replay distinto del recibo original.'}
            $shiftReceipts[$receipt.key]=$receipt
        }
    }
    if($shiftReceipts.Count -ne 7 -or @($shiftHttp.final.resources).Count -ne 2){throw 'Faltan siete comandos o dos turnos.'}
    $shiftExpected=[pscustomobject]@{restaurantId=$script:RestaurantA;revision=$shiftHttp.final.revision;
        zone=($shiftHttp.final.zone.content|ConvertFrom-Json);shifts=@($shiftHttp.final.resources|ForEach-Object{$_.response.content|ConvertFrom-Json});receipts=@($shiftReceipts.Values|Sort-Object key)}
    $shiftExpectationsBase64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($shiftExpected|ConvertTo-Json -Depth 30 -Compress)))
}
if (!$WritersStopped) { throw 'Deten Eats Hub y TODOS los clientes que escriban en Mongo. Luego usa -WritersStopped para confirmar esa parada.' }
function Assert-WritersStopped {
    $listeners=@(Get-NetTCPConnection -State Listen -LocalPort 8082 -ErrorAction SilentlyContinue)
    if ($listeners.Count -gt 0) { throw '8082 sigue escuchando. Deten Eats Hub en IntelliJ antes de continuar.' }
}
Assert-WritersStopped
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env')
if ($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018') {
    throw 'Solo se permite el Mongo local de 27018.'
}
if ($values.ContainsKey('MONGODB_URI') -and ![string]::IsNullOrWhiteSpace($values['MONGODB_URI'])) {
    throw 'MONGODB_URI personalizado requiere revision manual; este ensayo usa la configuracion local por campos.'
}
$database=$values['MONGODB_DATABASE']
if ($database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')) { throw 'Base no permitida.' }
$source='eats-availability-mongodb-replica-1'
$sourceRaw=& docker inspect $source
Assert-DockerSuccess 'inspeccionar el contenedor origen'
$sourceInfo=@(($sourceRaw -join "`n") | ConvertFrom-Json)[0]
if (!$sourceInfo.State.Running -or $sourceInfo.Config.Image -ne 'mongo:8.0.8') {
    throw 'Se requiere el contenedor origen activo con mongo:8.0.8.'
}
$binding=$sourceInfo.NetworkSettings.Ports.PSObject.Properties['27018/tcp']
if ($null -eq $binding -or @($binding.Value | Where-Object { $_.HostIp -eq '127.0.0.1' -and $_.HostPort -eq '27018' }).Count -ne 1) {
    throw 'El origen no tiene el enlace local 27018 esperado.'
}
$runId=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N')
$target='eats-restore-check-'+$runId.ToLowerInvariant()
$volume=$target+'-data'
$folder=Join-Path $script:IdentityRoot ('backups/availability/'+$runId)
$archive=Join-Path $folder 'database.archive.gz'
$containerArchive='/tmp/eats-backup-'+$runId+'.archive.gz'
$manifestScript=Join-Path $PSScriptRoot 'mongo-backup-manifest.js'

function Read-BackupManifest([string]$Container,[int]$Port,[bool]$IsSource) {
    $oldEncoding=$OutputEncoding
    try {
        $OutputEncoding=[Text.UTF8Encoding]::new($false)
        $sourceFlag=if($IsSource){'true'}else{'false'}
        $output=Get-Content -LiteralPath $manifestScript -Raw | & docker exec -i -e ("EATS_BACKUP_DATABASE="+$database) -e ("EATS_BACKUP_SOURCE="+$sourceFlag) $Container mongosh --quiet --port $Port --file /dev/stdin
        Assert-DockerSuccess 'leer manifiesto sin modificar documentos'
        $manifest=($output -join "`n") | ConvertFrom-Json
        if($IncludeCombinations){
            $proofScript=Join-Path $PSScriptRoot 'read-combination-backup-requirements.js'
            $proofOutput=Get-Content -LiteralPath $proofScript -Raw | & docker exec -i -e ("EATS_BACKUP_DATABASE="+$database) -e ("EATS_BACKUP_SOURCE="+$sourceFlag) -e ("EATS_COMBINATION_EXPECTATIONS_BASE64="+$combinationExpectationsBase64) $Container mongosh --quiet --port $Port --file /dev/stdin
            Assert-DockerSuccess 'verificar combinaciones, indice, revision y recibos del ensayo'
            $manifest | Add-Member -NotePropertyName combinationsProof -NotePropertyValue (($proofOutput -join "`n") | ConvertFrom-Json)
        }
        if($IncludeShifts){
            $proofScript=Join-Path $PSScriptRoot 'read-shift-backup-requirements.js'
            $proofOutput=Get-Content -LiteralPath $proofScript -Raw | & docker exec -i -e ("EATS_BACKUP_DATABASE="+$database) -e ("EATS_BACKUP_SOURCE="+$sourceFlag) -e ("EATS_SHIFT_EXPECTATIONS_BASE64="+$shiftExpectationsBase64) $Container mongosh --quiet --port $Port --file /dev/stdin
            Assert-DockerSuccess 'verificar zona, turnos, indices, revision y recibos'
            $manifest | Add-Member -NotePropertyName shiftsProof -NotePropertyValue (($proofOutput -join "`n")|ConvertFrom-Json)
        }
        if($IncludeManagedReservations){
            $manifest|Add-Member -NotePropertyName managedProof -NotePropertyValue (Read-ManagedPolicy $Container $Port $IsSource $true)
        }
        return $manifest
    } finally { $OutputEncoding=$oldEncoding }
}
function Compare-BackupManifest($Expected,$Actual,[string]$Step) {
    if (($Expected | ConvertTo-Json -Depth 30 -Compress) -cne ($Actual | ConvertTo-Json -Depth 30 -Compress)) {
        throw "$Step : cambian colecciones, conteos, documentos BSON, indices u opciones. No se acredita restauracion. Conserva los archivos para revisar."
    }
}
[IO.Directory]::CreateDirectory($folder) | Out-Null
Write-Host 'Leyendo origen; no iniciar writers hasta terminar el ensayo.'
$null=Assert-LiveManagedMode
$before=Read-BackupManifest $source 27018 $true
if (@($before.collections).Count -eq 0) { throw 'El origen esta vacio; no acredita el respaldo de Eats Hub.' }
Write-PrivateText (Join-Path $folder 'source-before.json') ($before | ConvertTo-Json -Depth 30)
Assert-WritersStopped
# El binario se escribe dentro del contenedor y se copia con docker cp: no se
# redirige un archive binario a traves del pipeline de Windows PowerShell.
$dumpCommand='exec mongodump --host 127.0.0.1 --port 27018 --authenticationDatabase admin --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --db "$EATS_BACKUP_DATABASE" --archive="$EATS_BACKUP_ARCHIVE" --gzip'
$null=Assert-LiveManagedMode
$null=& docker exec -e ("EATS_BACKUP_DATABASE="+$database) -e ("EATS_BACKUP_ARCHIVE="+$containerArchive) $source sh -c $dumpCommand
Assert-DockerSuccess 'crear archive comprimido de la base de aplicacion'
& docker cp ($source+':'+$containerArchive) $archive
Assert-DockerSuccess 'copiar archive al respaldo privado'
if (!(Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $archive).Length -eq 0) { throw 'Archive ausente o vacio.' }
$after=Read-BackupManifest $source 27018 $true
Write-PrivateText (Join-Path $folder 'source-after.json') ($after | ConvertTo-Json -Depth 30)
Compare-BackupManifest $before $after 'Origen durante respaldo'
Assert-WritersStopped

Write-Host 'Restaurando en contenedor nuevo sin red externa ni puertos publicados...'
# Image ID del origen: misma imagen instalada, sin actualizar versiones.
& docker volume create --label 'eats-hub.purpose=restore-check' $volume | Out-Null
Assert-DockerSuccess 'crear volumen aislado nuevo'
& docker run -d --name $target --network none --label 'eats-hub.purpose=restore-check' --mount ("type=volume,source="+$volume+",target=/data/db") --tmpfs /data/configdb $sourceInfo.Image mongod --bind_ip 127.0.0.1 --port 27017 | Out-Null
Assert-DockerSuccess 'crear Mongo aislado para restauracion'
Write-PrivateText (Join-Path $folder 'restore-target.json') (@{container=$target;volume=$volume;source=$source;database=$database} | ConvertTo-Json)
$ready=$false
for($attempt=0;$attempt -lt 45;$attempt++) {
    $previousPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & docker exec $target mongosh --quiet --eval 'quit(db.adminCommand({ping:1}).ok ? 0 : 1)' 2>&1 | Out-Null
        $pingExitCode=$LASTEXITCODE
    } finally { $ErrorActionPreference=$previousPreference }
    if($pingExitCode -eq 0){$ready=$true;break}
    Start-Sleep -Seconds 1
}
if(!$ready){throw 'El destino aislado no arranco. Se conserva para inspeccion.'}
# El destino vacio aun no contiene combinaciones; solo verificar su vaciedad.
$savedManaged=$IncludeManagedReservations
$savedMode=$IncludeCombinations
$savedShiftMode=$IncludeShifts
try{$IncludeManagedReservations=$false;$IncludeShifts=$false; $IncludeCombinations=$false; $empty=Read-BackupManifest $target 27017 $false}
finally{$IncludeManagedReservations=$savedManaged;$IncludeCombinations=$savedMode;$IncludeShifts=$savedShiftMode}
if(@($empty.collections).Count -ne 0){throw 'El destino no esta vacio. No se restaura sobre datos existentes.'}
& docker cp $archive ($target+':/tmp/database.archive.gz')
Assert-DockerSuccess 'copiar archive al destino aislado'
$null=Assert-LiveManagedMode
$null=& docker exec $target mongorestore --host 127.0.0.1 --port 27017 --archive=/tmp/database.archive.gz --gzip ("--nsInclude="+$database+'.*') --stopOnError
Assert-DockerSuccess 'restaurar exclusivamente en el destino nuevo'
$restored=Read-BackupManifest $target 27017 $false
Write-PrivateText (Join-Path $folder 'restored.json') ($restored | ConvertTo-Json -Depth 30)
Compare-BackupManifest $before $restored 'Datos restaurados'
Assert-WritersStopped
$final=Read-BackupManifest $source 27018 $true
Compare-BackupManifest $before $final 'Origen al finalizar'
if($IncludeCombinations -or $IncludeShifts){
    foreach($path in $checkpointHashes.Keys){if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $checkpointHashes[$path]){throw 'Cambio un checkpoint durante el respaldo. No se acredita la validacion.'}}
}
$result=[ordered]@{timestampUtc=[DateTime]::UtcNow.ToString('o');database=$database;source=$source;
    isolatedContainer=$target;isolatedVolume=$volume;archiveSha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash;
    collections=@($before.collections).Count;writersStoppedDeclared=$true;sourceUnchanged=$true;restoreVerified=$true;
    note='Solo base de aplicacion; no acredita migracion de 27017, auth/usuarios del servidor ni reversion de version.'}
$null=Assert-LiveManagedMode
Write-PrivateText (Join-Path $folder 'validation.json') ($result | ConvertTo-Json -Depth 10)
if($IncludeCombinations){
    # Evidencia adicional propia de SPEC-002; no modifica checkpoints HTTP/gate.
    $specResult=[ordered]@{spec='SPEC-002';timestampUtc=$result.timestampUtc;runId=$http.runId;
        httpCheckpointSha256=$checkpointHashes[$httpPath];gateCheckpointSha256=$checkpointHashes[$gatePath];
        database=$database;source=$source;isolatedContainer=$target;isolatedVolume=$volume;
        archiveSha256=$result.archiveSha256;proof=$before.combinationsProof;writersStoppedDeclared=$true;
        sourceUnchanged=$true;restoreVerified=$true;
        note='Comparacion completa de base y prueba especifica de combinaciones/recibos. No acredita reversion de version ni cierre.'}
    Write-PrivateText (Join-Path $folder 'spec-002-validation.json') ($specResult | ConvertTo-Json -Depth 12)
}
if($IncludeShifts){
    foreach($path in $checkpointHashes.Keys){if((Get-FileHash $path -Algorithm SHA256).Hash -cne $checkpointHashes[$path]){throw 'Cambio un checkpoint de SPEC-003.'}}
    $shiftResult=[ordered]@{spec='SPEC-003';timestampUtc=$result.timestampUtc;runId=$shiftHttp.runId;
        httpCheckpointSha256=$checkpointHashes[$shiftHttpPath];gateCheckpointSha256=$checkpointHashes[$shiftGatePath];
        database=$database;source=$source;isolatedContainer=$target;isolatedVolume=$volume;
        archiveSha256=$result.archiveSha256;proof=$before.shiftsProof;writersStoppedDeclared=$true;
        sourceUnchanged=$true;restoreVerified=$true;note='No acredita reversion ni cierre.'}
    Write-PrivateText (Join-Path $folder 'spec-003-validation.json') ($shiftResult|ConvertTo-Json -Depth 12)
    Write-Host 'SPEC-003: zona, dos turnos, indices, revision y siete recibos verificados; reversion y cierre pendientes.'
}
if($IncludeManagedReservations){
    $nowHashes=Get-ManagedCheckpointHashes @($managedHashes.Keys)
    Assert-ReplacementEqual $managedHashes $nowHashes 'Hashes de checkpoints'
    $managedResult=[ordered]@{spec='SPEC-005';validation=$result;checkpointHashes=$managedHashes;proof=$before.managedProof}
    Write-PrivateText (Join-Path $folder 'managed-validation.json') ($managedResult|ConvertTo-Json -Depth 35)
}
Write-Host ('OK: respaldo y restauracion aislada coinciden; origen sin cambios. Evidencia: '+$folder)
Write-Host ('Destino conservado: '+$target+'. No se elimino ningun contenedor ni volumen.')
if($IncludeCombinations){Write-Host 'SPEC-002: combinaciones, indice unico, revision y siete recibos verificados. T060 y reversion siguen pendientes de revision humana.'}
Write-Host 'Puedes iniciar nuevamente Eats Hub en IntelliJ en 8082. Ninguna spec se cierra automaticamente.'
