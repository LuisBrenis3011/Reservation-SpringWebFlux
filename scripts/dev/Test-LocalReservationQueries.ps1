[CmdletBinding()]
param([guid]$ReservationId=[guid]::Empty,[string]$LegacyRef,[string]$OrphanLegacyRef,
      [switch]$AfterRestart,[switch]$AllowDatabaseReads)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
if(!$AllowDatabaseReads){throw 'Declara -AllowDatabaseReads para comparar manifiestos de Mongo sin escribir.'}
$root='http://localhost:8082/catalog'
$path=Join-Path $script:IdentityPrivate 'reservation-queries-http-checkpoint.json'
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env');$database=$values['MONGODB_DATABASE']
if($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018' -or
    $database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')){throw 'Solo Mongo local 27018 y base de aplicacion.'}
function Save-Queries {
    $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp';Write-PrivateText $temp ($script:checkpoint|ConvertTo-Json -Depth 45)
    if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
}
function Read-QueryManifest {
    $old=$OutputEncoding
    try{$OutputEncoding=[Text.UTF8Encoding]::new($false)
        $raw=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mongo-backup-manifest.js') -Raw |
            & docker exec -i -e ('EATS_BACKUP_DATABASE='+$database) -e EATS_BACKUP_SOURCE=true eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin
        Assert-DockerSuccess 'leer manifiesto de consultas';return (($raw -join "`n")|ConvertFrom-Json)
    }finally{$OutputEncoding=$old}
}
function Query-Equal($a,$b,[string]$name){if(($a|ConvertTo-Json -Depth 40 -Compress) -cne ($b|ConvertTo-Json -Depth 40 -Compress)){throw ($name+': datos distintos; conserva el checkpoint y revisa otras escrituras.')}}
function Query-Fields($body,[string[]]$names){
    if((@($body.PSObject.Properties.Name|Sort-Object) -join ',') -cne (@($names|Sort-Object) -join ',')){throw 'Proyeccion con campos inesperados o incompletos.'}
}
function Query-Token([string]$name){
    $token=[Environment]::GetEnvironmentVariable($name,'Process');if([string]::IsNullOrWhiteSpace($token)){throw ('Falta '+$name+' en esta terminal.')}
    $claims=ConvertFrom-JwtPayload $token
    if($claims.iss -cne $script:IdentityIssuer -or @($claims.aud) -notcontains 'eats-hub-catalog' -or
        [string]::IsNullOrWhiteSpace($claims.sub) -or [long]$claims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+30){throw ('Token invalido o expirado: '+$name)}
    return $token
}
function Query-Get([string]$name,[string]$uri,[string]$actor,[int]$expected){
    $headers=@{};if($actor){$headers.Authorization='Bearer '+(Query-Token $actor)}
    $response=Invoke-LocalHttp -Uri $uri -Headers $headers
    if($response.Status -ne $expected){throw ($name+': se esperaba HTTP '+$expected+' y se recibio '+$response.Status+'. No se cambia el gate ni la identidad automaticamente.')}
    $body=$response.Content|ConvertFrom-Json;$etag='';if($null -ne $response.Headers['ETag']){$etag=[string](@($response.Headers['ETag'])[0])}
    $entry=[pscustomobject]@{name=$name;uri=$uri;actorVariable=$actor;status=$response.Status;etag=$etag;body=$body}
    $script:checks.Add($entry);Write-Host ('OK: '+$name+' -> HTTP '+$expected);return $entry
}
function Query-Managed($row){
    Query-Fields $row @('kind','id','restaurantId','owner','shiftId','partySize','notes','status','version','tableIds','combinationId','assignedCapacity','localStart','localEnd','zoneId','startInstant','endInstant','createdAt','updatedAt','cancelledAt')
    Query-Fields $row.owner @('issuer','subject')
    if($row.kind -cne 'MANAGED' -or $row.status -notin @('CONFIRMED','CANCELLED') -or $row.version -lt 1){throw 'Reserva gestionada invalida.'}
}
function Query-Legacy($row){
    Query-Fields $row @('kind','legacyRef','restaurantId','status','customerName','date','time','partySize','notes')
    if($row.kind -cne 'LEGACY' -or $row.restaurantId -cne $script:RestaurantA){throw 'Legado ajeno o reinterpretado.'}
}
function Query-List($entry,[string]$actor,[bool]$manager){
    Query-Fields $entry.body @('items','page','size');if($entry.etag){throw 'Una lista no debe tener ETag.'}
    $claims=ConvertFrom-JwtPayload (Query-Token $actor)
    foreach($row in @($entry.body.items)){
        if($row.kind -eq 'MANAGED'){Query-Managed $row
            if(!$manager -and ($row.owner.issuer -cne $claims.iss -or $row.owner.subject -cne $claims.sub)){throw 'La lista propia contiene otro titular.'}
        }elseif($manager){Query-Legacy $row}else{throw 'El legado no debe aparecer en /me.'}
        if($manager -and $row.restaurantId -cne $script:RestaurantA){throw 'Lista de local contiene otro restaurante.'}
    }
}
$lock=$null
try{
    [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
    $lock=[IO.File]::Open(($path+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if(Test-Path -LiteralPath $path){
        $script:checkpoint=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($script:checkpoint.schemaVersion -ne 1 -or $script:checkpoint.spec -cne 'SPEC-006'){throw 'Checkpoint ajeno; no se sobrescribe.'}
        if($ReservationId -ne [guid]::Empty -and $ReservationId.ToString() -cne $script:checkpoint.reservationId){throw 'Conserva la reserva del ensayo existente.'}
        if($PSBoundParameters.ContainsKey('LegacyRef') -and $LegacyRef -cne $script:checkpoint.legacyRef){throw 'Referencia distinta del checkpoint.'}
        if($PSBoundParameters.ContainsKey('OrphanLegacyRef') -and $OrphanLegacyRef -cne $script:checkpoint.orphanLegacyRef){throw 'Referencia huerfana distinta.'}
    }else{
        if($AfterRestart -or $ReservationId -eq [guid]::Empty){throw 'Primero indica -ReservationId de una reserva real de cliente-a en A.'}
        $script:checkpoint=[pscustomobject]@{schemaVersion=1;spec='SPEC-006';runId=[guid]::NewGuid().ToString();reservationId=$ReservationId.ToString();legacyRef=$LegacyRef;orphanLegacyRef=$OrphanLegacyRef;baseline=$null;attempts=@()}
        Save-Queries
    }
    if($AfterRestart -and $null -eq $script:checkpoint.baseline){throw 'Falta Baseline completo.'}
    if(!$AfterRestart -and $null -ne $script:checkpoint.baseline){throw 'Baseline ya registrado; no se reemplaza. Usa -AfterRestart despues de reiniciar manualmente.'}
    Write-Host 'Solo GET. Evita otras escrituras durante el recorrido; no se crean reservas ni legado.'
    $before=Read-QueryManifest;$script:checks=[Collections.Generic.List[object]]::new()
    $collection=$root+'/restaurants/'+$script:RestaurantA+'/reservations';$resource=$collection+'/'+$script:checkpoint.reservationId
    $null=Query-Get 'sin-token' ($root+'/me/reservations') '' 401
    $own=Query-Get 'detalle-titular' $resource 'EATS_HUB_TOKEN_CUSTOMER_A' 200;Query-Managed $own.body
    $claims=ConvertFrom-JwtPayload (Query-Token 'EATS_HUB_TOKEN_CUSTOMER_A')
    if($own.body.restaurantId -cne $script:RestaurantA -or $own.body.owner.subject -cne $claims.sub -or $own.body.owner.issuer -cne $claims.iss -or
        $own.etag -cne ('"'+[string]$own.body.version+'"')){throw 'Titular, local o ETag inesperados.'}
    $null=Query-Get 'otro-cliente' $resource 'EATS_HUB_TOKEN_CUSTOMER_B' 404
    $null=Query-Get 'encargado-ajeno' $collection 'EATS_HUB_TOKEN_B' 403
    $null=Query-Get 'encargado-sin-perfil-cliente' ($root+'/me/reservations') 'EATS_HUB_TOKEN_A' 403
    $local=Query-Get 'encargado-local' $resource 'EATS_HUB_TOKEN_A' 200;Query-Equal $own.body $local.body 'Snapshot para encargado'
    $dual=Query-Get 'cuenta-dual' $resource 'EATS_HUB_TOKEN_DUAL' 200;Query-Equal $own.body $dual.body 'Snapshot para cuenta dual'
    foreach($actor in @('EATS_HUB_TOKEN_CUSTOMER_A','EATS_HUB_TOKEN_CUSTOMER_B','EATS_HUB_TOKEN_DUAL')){
        $entry=Query-Get ('mis-reservas-'+$actor) ($root+'/me/reservations') $actor 200;Query-List $entry $actor $false
    }
    $list=Query-Get 'lista-local' $collection 'EATS_HUB_TOKEN_A' 200;Query-List $list 'EATS_HUB_TOKEN_A' $true
    $old=Query-Get 'GET-antiguo-protegido' ($root+'/reservation/'+$script:checkpoint.reservationId) 'EATS_HUB_TOKEN_A' 200
    $null=Query-Get 'GET-antiguo-no-cliente' ($root+'/reservation/'+$script:checkpoint.reservationId) 'EATS_HUB_TOKEN_CUSTOMER_A' 403
    Query-Equal $own.body $old.body 'Snapshot del adaptador antiguo'
    if($old.etag -cne $own.etag -or $local.etag -cne $own.etag -or $dual.etag -cne $own.etag){throw 'ETag de recurso distinto segun actor.'}
    if($script:checkpoint.legacyRef){
        $uri=$collection+'/legacy/'+[Uri]::EscapeDataString($script:checkpoint.legacyRef)
        $legacy=Query-Get 'legado-local' $uri 'EATS_HUB_TOKEN_A' 200;Query-Legacy $legacy.body
        if($legacy.etag){throw 'Legado no debe incluir ETag.'}
        $null=Query-Get 'legado-no-es-propio' $uri 'EATS_HUB_TOKEN_CUSTOMER_A' 403
    }
    if($script:checkpoint.orphanLegacyRef){$null=Query-Get 'huerfana-no-expuesta' ($collection+'/legacy/'+[Uri]::EscapeDataString($script:checkpoint.orphanLegacyRef)) 'EATS_HUB_TOKEN_A' 404}
    $after=Read-QueryManifest;Query-Equal $before $after 'Documentos, indices, revisiones y recibos durante GET'
    if($AfterRestart){
        # Los errores tienen operationId/timestamp nuevos; su estado se valida en cada petición.
        $prior=@($script:checkpoint.baseline.checks|Where-Object {$_.status -eq 200})
        $current=@($script:checks.ToArray()|Where-Object {$_.status -eq 200})
        Query-Equal $prior $current 'Respuestas y snapshots tras reinicio declarado'
    }
    $entry=[pscustomobject]@{timestampUtc=[DateTime]::UtcNow.ToString('o');operatorDeclaredRestart=[bool]$AfterRestart;checks=@($script:checks.ToArray());before=$before;after=$after;dataPreserved=$true;
        coverage=[pscustomobject]@{legacy=[bool]$script:checkpoint.legacyRef;orphan=[bool]$script:checkpoint.orphanLegacyRef;cancelled=($own.body.status -eq 'CANCELLED');historicalSnapshotCompared=[bool]$AfterRestart}}
    if(!$AfterRestart){$script:checkpoint.baseline=$entry};$script:checkpoint.attempts=@($script:checkpoint.attempts)+@($entry);Save-Queries
    Write-Host 'OK: consultas autorizadas, proyeccion y Mongo conservados; checkpoint sin JWT.'
    Write-Host 'Solo se acreditan casos realmente observados. Legado/huerfanas ausentes, historia de zona distinta, gates, restore, reversion y cierre siguen pendientes.'
}finally{if($null -ne $lock){$lock.Dispose()}}
