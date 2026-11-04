[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Prepare','StartPrevious','Previous','Current')][string]$Stage,
      [switch]$WritersStopped,[switch]$IncludeCombinations,[switch]$IncludeShifts,[string]$BackupDirectory,[switch]$IncludeManagedReservations,[string]$BridgeCommit,[string]$BridgeEvidence)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
. (Join-Path $PSScriptRoot 'ManagedReservations.Common.ps1')
function Invoke-LocalRollbackBuild { & .\gradlew.bat bootJar }
function Invoke-HistoricalRollback {
if($IncludeManagedReservations){
 Assert-ManagedOptions $true ([bool]$IncludeCombinations) ([bool]$IncludeShifts)
 & (Join-Path $PSScriptRoot 'Test-LocalManagedReservationRollback.ps1') -Stage $Stage -WritersStopped:$WritersStopped -BackupDirectory $BackupDirectory -BridgeCommit $BridgeCommit -BridgeEvidence $BridgeEvidence
 return
}
if($BridgeCommit -or $BridgeEvidence){throw 'BridgeCommit y BridgeEvidence solo admiten modo gestionado.'}
Initialize-ManagedMode $false ([bool]$IncludeCombinations) ([bool]$IncludeShifts)
$targetCommit='81f0e6145fbf8c82fd81fae7669aa82d3c9660f5'
$sessionPath=Join-Path $script:IdentityPrivate 'rollback-session.json'
$backupRoot=[IO.Path]::GetFullPath((Join-Path $script:IdentityRoot 'backups/availability-rollback'))
function Manifest-Data($Value){return [pscustomobject]@{database=$Value.database;collections=@($Value.collections)}}
function Same-Manifest($Left,$Right){
    if(((Manifest-Data $Left)|ConvertTo-Json -Depth 40 -Compress) -cne ((Manifest-Data $Right)|ConvertTo-Json -Depth 40 -Compress)){
        throw 'Mongo o el manifiesto difiere del respaldo validado; no se acredita reversion.'
    }
}
if($IncludeCombinations -and $IncludeShifts){throw 'Usa un solo modo de spec.'}
$extendedMode=$IncludeCombinations -or $IncludeShifts
$modeSpec='SPEC-002';if($IncludeShifts){$modeSpec='SPEC-003'}
$backupProofHash=$null
if($IncludeCombinations){
    $targetCommit='72fa5311a0d724582381dd968e226daca6f3d311'
    $sessionPath=Join-Path $script:IdentityPrivate 'combinations-rollback-session.json'
    if(!$BackupDirectory -and $Stage -ne 'Prepare' -and (Test-Path -LiteralPath $sessionPath)){
        $BackupDirectory=(Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json).backupDirectory
    }
    if(!$BackupDirectory){throw 'Prepare requiere -BackupDirectory con el respaldo validado de SPEC-002.'}
    if(![IO.Path]::IsPathRooted($BackupDirectory)){$BackupDirectory=Join-Path $script:IdentityRoot $BackupDirectory}
    $BackupDirectory=[IO.Path]::GetFullPath($BackupDirectory)
    $allowed=[IO.Path]::GetFullPath((Join-Path $script:IdentityRoot 'backups/availability'))+[IO.Path]::DirectorySeparatorChar
    if(!$BackupDirectory.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Respaldo fuera de backups/availability.'}
    $proofPath=Join-Path $BackupDirectory 'spec-002-validation.json'
    $backupProof=Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
    $backupProofHash=(Get-FileHash -LiteralPath $proofPath).Hash
    $combinationCheckpoint=Get-Content (Join-Path $script:IdentityPrivate 'combinations-http-checkpoint.json') -Raw | ConvertFrom-Json
    if($backupProof.spec -cne 'SPEC-002' -or !$backupProof.restoreVerified -or !$backupProof.sourceUnchanged -or
        !$backupProof.writersStoppedDeclared -or $backupProof.runId -cne $combinationCheckpoint.runId -or
        $backupProof.proof.acceptedReceipts -ne 7 -or $backupProof.proof.uniqueIndex -cne 'restaurant_combination_members_unique' -or
        $backupProof.proof.revision -ne $combinationCheckpoint.final.revision -or
        (Get-FileHash (Join-Path $BackupDirectory 'database.archive.gz')).Hash -cne $backupProof.archiveSha256 -or
        (Get-FileHash (Join-Path $script:IdentityPrivate 'combinations-http-checkpoint.json')).Hash -cne $backupProof.httpCheckpointSha256 -or
        (Get-FileHash (Join-Path $script:IdentityPrivate 'combinations-gate-checkpoint.json')).Hash -cne $backupProof.gateCheckpointSha256){throw 'Respaldo o checkpoints de SPEC-002 no coinciden.'}
    $backupManifest=Get-Content (Join-Path $BackupDirectory 'source-before.json') -Raw | ConvertFrom-Json
    foreach($file in @('source-after.json','restored.json')){
        $other=Get-Content (Join-Path $BackupDirectory $file) -Raw | ConvertFrom-Json
        if(($backupManifest|ConvertTo-Json -Depth 40 -Compress) -cne ($other|ConvertTo-Json -Depth 40 -Compress)){throw 'Manifiestos del respaldo no coinciden.'}
    }
    if(($backupManifest.combinationsProof|ConvertTo-Json -Compress) -cne ($backupProof.proof|ConvertTo-Json -Compress)){throw 'Prueba especifica del respaldo incoherente.'}
}elseif($IncludeShifts){
    $targetCommit='5031d8e878045637ceee9e197c3cf80da5475a4e'
    $sessionPath=Join-Path $script:IdentityPrivate 'shifts-rollback-session.json'
    if(!$BackupDirectory -and $Stage -ne 'Prepare' -and (Test-Path -LiteralPath $sessionPath)){
        $BackupDirectory=(Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json).backupDirectory
    }
    if(!$BackupDirectory){throw 'Prepare requiere -BackupDirectory con el respaldo validado de SPEC-003.'}
    if(![IO.Path]::IsPathRooted($BackupDirectory)){$BackupDirectory=Join-Path $script:IdentityRoot $BackupDirectory}
    $BackupDirectory=[IO.Path]::GetFullPath($BackupDirectory)
    $allowed=[IO.Path]::GetFullPath((Join-Path $script:IdentityRoot 'backups/availability'))+[IO.Path]::DirectorySeparatorChar
    if(!$BackupDirectory.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Respaldo fuera de backups/availability.'}
    $proofPath=Join-Path $BackupDirectory 'spec-003-validation.json'
    $backupProof=Get-Content -LiteralPath $proofPath -Raw | ConvertFrom-Json
    $backupProofHash=(Get-FileHash -LiteralPath $proofPath).Hash
    $shiftCheckpoint=Get-Content (Join-Path $script:IdentityPrivate 'shifts-http-checkpoint.json') -Raw | ConvertFrom-Json
    if($backupProof.spec -cne 'SPEC-003' -or !$backupProof.restoreVerified -or !$backupProof.sourceUnchanged -or
        !$backupProof.writersStoppedDeclared -or $backupProof.runId -cne $shiftCheckpoint.runId -or
        $backupProof.proof.acceptedReceipts -ne 7 -or $backupProof.proof.shifts -ne 2 -or $backupProof.proof.zoneIndex -cne '_id_' -or $backupProof.proof.shiftIndex -cne 'restaurant_shift_interval' -or
        $backupProof.proof.revision -ne $shiftCheckpoint.final.revision -or
        (Get-FileHash (Join-Path $BackupDirectory 'database.archive.gz')).Hash -cne $backupProof.archiveSha256 -or
        (Get-FileHash (Join-Path $script:IdentityPrivate 'shifts-http-checkpoint.json')).Hash -cne $backupProof.httpCheckpointSha256 -or
        (Get-FileHash (Join-Path $script:IdentityPrivate 'shifts-gate-checkpoint.json')).Hash -cne $backupProof.gateCheckpointSha256){throw 'Respaldo o checkpoints de SPEC-003 no coinciden.'}
    $backupManifest=Get-Content (Join-Path $BackupDirectory 'source-before.json') -Raw | ConvertFrom-Json
    foreach($file in @('source-after.json','restored.json')){
        $other=Get-Content (Join-Path $BackupDirectory $file) -Raw | ConvertFrom-Json
        if(($backupManifest|ConvertTo-Json -Depth 40 -Compress) -cne ($other|ConvertTo-Json -Depth 40 -Compress)){throw 'Manifiestos del respaldo no coinciden.'}
    }
    if(($backupManifest.shiftsProof|ConvertTo-Json -Compress) -cne ($backupProof.proof|ConvertTo-Json -Compress)){throw 'Prueba especifica del respaldo incoherente.'}
}elseif($BackupDirectory){throw '-BackupDirectory requiere -IncludeCombinations o -IncludeShifts.'}

function Assert-RollbackCommand([string]$Action) {
    if($LASTEXITCODE -ne 0){throw ("No se pudo "+$Action+". No se acredita la reversion.")}
}
function Listening-Process {
    return @(Get-NetTCPConnection -State Listen -LocalPort 8082 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
}
function Assert-ApplicationStopped {
    if(@(Listening-Process).Count){throw '8082 sigue escuchando. Deten la aplicacion antes de continuar.'}
}
function Read-RollbackManifest {
    $oldEncoding=$OutputEncoding
    try {
        $OutputEncoding=[Text.UTF8Encoding]::new($false)
        $out=Get-Content (Join-Path $PSScriptRoot 'mongo-backup-manifest.js') -Raw |
            & docker exec -i -e ("EATS_BACKUP_DATABASE="+$database) -e EATS_BACKUP_SOURCE=true eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin
        Assert-RollbackCommand 'leer manifiesto del origen'
        return (($out -join "`n") | ConvertFrom-Json)
    } finally {$OutputEncoding=$oldEncoding}
}
function Assert-RollbackPath([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    if(!$full.StartsWith($backupRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Ruta de ensayo fuera de backups/availability-rollback.'
    }
}
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env')
if($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018' -or
    ($values.ContainsKey('MONGODB_URI') -and ![string]::IsNullOrWhiteSpace($values['MONGODB_URI']))){throw 'Solo admite el Mongo local 27018 configurado por campos.'}
$database=$values['MONGODB_DATABASE']
if($database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')){throw 'Base no permitida.'}
if($extendedMode -and $backupProof.database -cne $database){throw 'Base distinta del respaldo.'}
function Assert-CurrentCode([string]$ExpectedCommit){
    Push-Location $script:IdentityRoot
    try{
        $head=& git rev-parse HEAD; Assert-RollbackCommand 'leer HEAD actual'
        if($ExpectedCommit -and [string]$head -cne $ExpectedCommit){throw 'HEAD cambio desde Prepare.'}
        & git diff --quiet HEAD -- src/main/java src/main/resources build.gradle settings.gradle gradle gradlew gradlew.bat
        Assert-RollbackCommand 'comprobar codigo productivo actual'
        $extra=@(& git ls-files --others --exclude-standard -- src/main/java src/main/resources)
        Assert-RollbackCommand 'comprobar fuentes no versionadas'
        if($extra.Count){throw 'Hay fuentes productivas no versionadas.'}
    }finally{Pop-Location}
}

if($Stage -eq 'Prepare') {
    if(!$WritersStopped){throw 'Deten IntelliJ y todos los writers; despues usa -WritersStopped.'}
    Assert-ApplicationStopped
    if(Test-Path -LiteralPath $sessionPath){throw 'Ya existe una sesion de reversion. Revisala; no se reemplaza automaticamente.'}
    if(!$extendedMode){foreach($name in @('legacy-disabled-validation.json','legacy-enabled-validation.json')){
        $proof=Get-Content (Join-Path $script:IdentityPrivate $name) -Raw | ConvertFrom-Json
        if(!$proof.createdFixtureRemoved -or !$proof.restaurantAUnchanged -or
            $proof.finalRevision -ne $proof.initialRevision+3 -or @($proof.checks).Count -ne 6 -or
            @($proof.checks | Where-Object {!$_.passed}).Count){throw 'Falta evidencia aprobada de writers antiguos.'}
    }}
    Push-Location $script:IdentityRoot
    try {
        $resolved=& git rev-parse --verify ($targetCommit+'^{commit}')
        Assert-RollbackCommand 'resolver el commit anterior'
        if([string]$resolved -cne $targetCommit){throw 'Commit anterior inesperado.'}
        $currentCommit=& git rev-parse HEAD
        Assert-RollbackCommand 'identificar el commit actual'
        if($extendedMode){Assert-CurrentCode ([string]$currentCommit)}
        & git diff --quiet HEAD -- src/main/java src/main/resources build.gradle settings.gradle
        Assert-RollbackCommand 'confirmar codigo productivo sin diferencias locales frente a HEAD'
        $run=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
        $folder=Join-Path $backupRoot $run
        Assert-RollbackPath $folder
        if(Test-Path -LiteralPath $folder){throw 'La carpeta del ensayo ya existe; no se sobrescribe.'}
        [IO.Directory]::CreateDirectory($folder) | Out-Null
        $zip=Join-Path $folder 'previous-source.zip'
        $export=Join-Path $folder 'src'
        $baseline=Read-RollbackManifest
        if($extendedMode){Same-Manifest $backupManifest $baseline}
        Write-PrivateText (Join-Path $folder 'database-before.json') ($baseline | ConvertTo-Json -Depth 30)
        & git archive --format=zip ('--output='+$zip) $targetCommit
        Assert-RollbackCommand 'exportar el commit sin cambiar checkout ni indice'
        Expand-Archive -LiteralPath $zip -DestinationPath $export
        Push-Location $export
        try {
            $null=Assert-LiveManagedMode
            Invoke-LocalRollbackBuild
            Assert-RollbackCommand 'compilar bootJar anterior sin suites'
        } finally {Pop-Location}
        $jars=@(Get-ChildItem -LiteralPath (Join-Path $export 'build/libs') -Filter '*.jar' | Where-Object {$_.Name -notlike '*-plain.jar'})
        if($jars.Count -ne 1){throw 'No se encontro un unico bootJar anterior.'}
        Assert-ApplicationStopped
        $after=Read-RollbackManifest
        if(($baseline|ConvertTo-Json -Depth 30 -Compress) -cne ($after|ConvertTo-Json -Depth 30 -Compress)){throw 'Mongo cambio durante la preparacion; detener y revisar.'}
        $session=[ordered]@{preparedUtc=[DateTime]::UtcNow.ToString('o');run=$run;folder=$folder;
            targetCommit=$targetCommit;currentCommit=[string]$currentCommit;database=$database;jar=$jars[0].FullName;
            jarSha256=(Get-FileHash -LiteralPath $jars[0].FullName -Algorithm SHA256).Hash;writersStoppedDeclared=$true;
            previousStartedUtc=$null;previousVerifiedUtc=$null}
        if($extendedMode){$session.backupDirectory=$BackupDirectory;$session.backupProofSha256=$backupProofHash;$session.spec=$modeSpec}
        Write-PrivateText $sessionPath ($session|ConvertTo-Json -Depth 10)
        Write-Host 'OK: JAR anterior preparado y Mongo sin cambios. No se arranco la version anterior.'
        Write-Host 'En otra PowerShell ejecuta este script con -Stage StartPrevious y dejala abierta.'
    } finally {Pop-Location}
    return
}

if(!(Test-Path -LiteralPath $sessionPath)){throw 'Primero ejecutar Prepare con los writers detenidos.'}
$session=Get-Content -LiteralPath $sessionPath -Raw | ConvertFrom-Json
Assert-RollbackPath $session.folder
Assert-RollbackPath $session.jar
if($session.targetCommit -cne $targetCommit -or $session.database -ne $database -or
    (Get-FileHash -LiteralPath $session.jar -Algorithm SHA256).Hash -ne $session.jarSha256){throw 'Sesion o JAR anterior no coincide con la preparacion.'}
if($extendedMode){
    if($session.spec -cne $modeSpec -or $session.backupDirectory -cne $BackupDirectory -or $session.backupProofSha256 -cne $backupProofHash){throw 'Sesion de SPEC-002 incompatible con el respaldo.'}
    Assert-CurrentCode $session.currentCommit
    Same-Manifest $backupManifest (Get-Content (Join-Path $session.folder 'database-before.json') -Raw | ConvertFrom-Json)
}
if($Stage -eq 'StartPrevious') {
    Assert-ApplicationStopped
    if($null -ne $session.previousVerifiedUtc){throw 'La version anterior ya fue validada; continua con la vuelta a IntelliJ.'}
    $baseline=Get-Content (Join-Path $session.folder 'database-before.json') -Raw|ConvertFrom-Json
    $beforeStart=Read-RollbackManifest
    if(($baseline|ConvertTo-Json -Depth 30 -Compress) -cne ($beforeStart|ConvertTo-Json -Depth 30 -Compress)){throw 'Mongo cambio desde Prepare; no se arranca la version anterior.'}
    $session.previousStartedUtc=[DateTime]::UtcNow.ToString('o')
    Write-PrivateText $sessionPath ($session|ConvertTo-Json -Depth 10)
    Push-Location $script:IdentityRoot
    try {
        Write-Host 'Arrancando SOLO el JAR anterior en 8082, gate=false por argumento. Deja esta terminal abierta.'
        $null=Assert-LiveManagedMode
        & java -jar $session.jar --server.port=8082 --availability.enabled=false --logging.level.org.springframework.data.mongodb=INFO
        Assert-RollbackCommand 'ejecutar el JAR anterior'
    } finally {Pop-Location}
    return
}

$owners=@(Listening-Process)
if($owners.Count -ne 1){throw 'Se requiere una unica aplicacion escuchando en 8082.'}
$ownerProcess=Get-CimInstance Win32_Process -Filter ('ProcessId='+$owners[0])
$isPrevious=$null -ne $ownerProcess.CommandLine -and $ownerProcess.CommandLine.Contains([string]$session.jar)
if($Stage -eq 'Previous' -and (!$isPrevious -or $null -eq $session.previousStartedUtc)){throw '8082 no corresponde al JAR anterior preparado.'}
if($Stage -eq 'Current' -and ($isPrevious -or $null -eq $session.previousVerifiedUtc)){throw 'Primero validar Previous, detener su JVM y reiniciar la version actual en IntelliJ.'}
$checks=[Collections.Generic.List[object]]::new()
function Check-RollbackHttp($Response,[int]$Expected,[string]$Name) {
    if($Response.Status -ne $Expected){throw "$Name : se esperaba $Expected y se recibio $($Response.Status)."}
    $checks.Add([pscustomobject]@{name=$Name;status=$Response.Status;passed=$true})
    Write-Host ("OK: $Name -> HTTP $Expected")
}
$root='http://localhost:8082/catalog'
$tables=$root+'/restaurants/'+$script:RestaurantA+'/tables'
$combinations=$root+'/restaurants/'+$script:RestaurantA+'/table-combinations'
if($IncludeCombinations){$combinationResource=$combinations+'/'+([guid]$combinationCheckpoint.final.combinationId).ToString()}
$shiftTargets=@()
if($IncludeShifts){
    $shiftBase=$root+'/restaurants/'+$script:RestaurantA
    $shiftTargets=@([pscustomobject]@{uri=($shiftBase+'/time-zone');expected=$shiftCheckpoint.final.zone},
        [pscustomobject]@{uri=($shiftBase+'/shifts');expected=$shiftCheckpoint.final.list})
    foreach($row in $shiftCheckpoint.final.resources){$shiftTargets+=([pscustomobject]@{uri=($shiftBase+'/shifts/'+([guid]$row.id).ToString());expected=$row.response})}
    if($shiftTargets.Count -ne 4){throw 'Se requieren zona, coleccion y ambos turnos.'}
}
Check-RollbackHttp (Invoke-LocalHttp -Uri ($root+'/restaurants')) 200 'Catalogo accesible'
if($Stage -eq 'Previous') {
    Check-RollbackHttp (Invoke-LocalHttp -Uri $tables) 404 'Version anterior con nuevas rutas desactivadas'
    if($IncludeShifts){foreach($item in $shiftTargets){Check-RollbackHttp (Invoke-LocalHttp -Uri $item.uri) 404 'Zona/turno oculto en version anterior'}}
    if($IncludeCombinations){
        Check-RollbackHttp (Invoke-LocalHttp -Uri $combinations) 404 'Combinaciones ocultas en version anterior'
        Check-RollbackHttp (Invoke-LocalHttp -Uri $combinationResource) 404 'Recurso oculto en version anterior'
    }
} else {
    Check-RollbackHttp (Invoke-LocalHttp -Uri $tables) 401 'Version actual exige autenticacion'
    $token=$env:EATS_HUB_TOKEN_A
    if([string]::IsNullOrWhiteSpace($token)){throw 'Renueva encargado-a en esta PowerShell.'}
    $claims=ConvertFrom-JwtPayload $token
    if([long]$claims.exp -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+20){throw 'Token expirado; renueva encargado-a.'}
    if($IncludeCombinations){
        Check-RollbackHttp (Invoke-LocalHttp -Uri $combinations) 401 'Combinaciones exigen autenticacion'
        Check-RollbackHttp (Invoke-LocalHttp -Uri $combinationResource) 401 'Recurso exige autenticacion'
        $response=Invoke-LocalHttp -Uri $combinationResource -Headers @{Authorization=('Bearer '+$token)}
        Check-RollbackHttp $response 200 'Combinacion conservada al volver'
        if(($response.Content|ConvertFrom-Json|ConvertTo-Json -Depth 20 -Compress) -cne ($combinationCheckpoint.final.resource.content|ConvertFrom-Json|ConvertTo-Json -Depth 20 -Compress)) {throw 'Combinacion o revision distintas.'}
        $etag=$response.Headers['ETag']
        if($null -eq $etag -or [string](@($etag)[0]) -cne $combinationCheckpoint.final.resource.etag){throw 'ETag de combinacion distinto.'}
        $list=Invoke-LocalHttp -Uri $combinations -Headers @{Authorization=('Bearer '+$token)}
        Check-RollbackHttp $list 200 'Coleccion conservada al volver'
        if([long]($list.Content|ConvertFrom-Json).revision -ne [long]$combinationCheckpoint.final.revision){throw 'Revision de coleccion distinta.'}
    }elseif($IncludeShifts){
        foreach($item in $shiftTargets){
            Check-RollbackHttp (Invoke-LocalHttp -Uri $item.uri) 401 'Zona/turno requiere autenticacion'
            $response=Invoke-LocalHttp -Uri $item.uri -Headers @{Authorization=('Bearer '+$token)}
            Check-RollbackHttp $response 200 'Zona/turno conservado al volver'
            if(($response.Content|ConvertFrom-Json|ConvertTo-Json -Depth 30 -Compress) -cne ($item.expected.content|ConvertFrom-Json|ConvertTo-Json -Depth 30 -Compress)){throw 'Snapshot temporal o revision distintos.'}
            $etag=$response.Headers['ETag']
            if($null -eq $etag -or [string](@($etag)[0]) -cne $item.expected.etag){throw 'ETag temporal distinto.'}
        }
    }else{
    $expected=Get-Content (Join-Path $script:IdentityPrivate 'http-validation.json') -Raw | ConvertFrom-Json
    $response=Invoke-LocalHttp -Uri ($tables+'/'+$expected.table.id) -Headers @{Authorization=('Bearer '+$token)}
    Check-RollbackHttp $response 200 'Mesa conservada al volver a la version actual'
    $actual=$response.Content|ConvertFrom-Json
    foreach($field in @('id','restaurantId','label','capacity','revision')){if($actual.$field -ne $expected.table.$field){throw ('Cambio inesperado de '+$field)}}
    $etag=$response.Headers['ETag']
    if($null -eq $etag -or [string](@($etag)[0]) -ne ('"'+[string]$actual.revision+'"')){throw 'ETag incoherente.'}
    }
}
$baseline=Get-Content (Join-Path $session.folder 'database-before.json') -Raw|ConvertFrom-Json
$current=Read-RollbackManifest
if(($baseline|ConvertTo-Json -Depth 30 -Compress) -cne ($current|ConvertTo-Json -Depth 30 -Compress)){throw 'Mongo difiere del estado previo; no se acredita reversion sin perdida.'}
if($extendedMode){Same-Manifest $backupManifest $current}
$timestamp=[DateTime]::UtcNow.ToString('o')
$evidence=[ordered]@{timestampUtc=$timestamp;stage=$Stage;run=$session.run;targetCommit=$targetCommit;
    preparedCurrentCommit=$session.currentCommit;previousJarSha256=$session.jarSha256;processId=$owners[0];
    databaseUnchanged=$true;checks=$checks.ToArray();operatorDeclaredCurrentRestart=($Stage -eq 'Current');
    note='Ensayo local de version anterior compatible con guard, sin writes ni restauracion de una copia vieja. No acredita volver a una version sin guard.'}
if($extendedMode){
    $evidence.spec=$modeSpec;$evidence.backupDirectory=$BackupDirectory
    $evidence.backupProofSha256=$backupProofHash
    if($IncludeShifts){$evidence.shiftsZoneIndexRevisionReceiptsPreserved=$true}else{$evidence.combinationsIndexRevisionReceiptsPreserved=$true}
}
$null=Assert-LiveManagedMode
Write-PrivateText (Join-Path $session.folder ($Stage.ToLowerInvariant()+'-validation.json')) ($evidence|ConvertTo-Json -Depth 12)
if($Stage -eq 'Previous'){
    $session.previousVerifiedUtc=$timestamp
    Write-PrivateText $sessionPath ($session|ConvertTo-Json -Depth 10)
    Write-Host 'OK: version anterior comprobada; Mongo conserva documentos, revisiones, recibos e indices.'
    Write-Host 'Deten el JAR anterior con Ctrl+C en SU terminal. Despues inicia la version actual en IntelliJ en 8082.'
} elseif($IncludeShifts){Write-Host 'OK: zona, turnos y ETag conservados; manifiesto completo identico al respaldo. T087 y aprobacion pendientes.'}
elseif($IncludeCombinations){Write-Host 'OK: combinaciones/ETag conservados; documentos, indices, revisiones y recibos identicos al respaldo. T060 requiere revision y aprobacion formal.'}
else {Write-Host 'OK: vuelta a version actual comprobada, mesa/ETag conservados y Mongo sin cambios. T040 requiere aprobacion formal.'}
}
if($MyInvocation.InvocationName -ne '.') { Invoke-HistoricalRollback }
