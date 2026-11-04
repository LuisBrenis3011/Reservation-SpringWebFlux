[CmdletBinding()]
param([ValidateSet('Baseline','AfterRestart','AfterCompetingReservation','Uncertain')][string]$Stage='Baseline',
      [string]$Date,[ValidateRange(1,20)][int]$PartySize=2,[guid]$ShiftId=[guid]::Empty,
      [switch]$AllowDatabaseReads)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
if(!$AllowDatabaseReads){throw 'Declara -AllowDatabaseReads para comparar Mongo antes/despues sin escribir datos.'}
$path=Join-Path $script:IdentityPrivate 'reservation-availability-http-checkpoint.json'
$root='http://localhost:8082/catalog'
$owner=$script:RestaurantA
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env')
$database=$values['MONGODB_DATABASE']
if($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018' -or
    $database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')){throw 'Solo Mongo local 27018 y base de aplicacion.'}
function Save-Availability {
    $temporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    Write-PrivateText $temporary ($script:checkpoint|ConvertTo-Json -Depth 40)
    if(Test-Path -LiteralPath $path){[IO.File]::Replace($temporary,$path,[System.Management.Automation.Language.NullString]::Value)}
    else{[IO.File]::Move($temporary,$path)}
}
function Read-Manifest {
    $encoding=$OutputEncoding
    try{
        $OutputEncoding=[Text.UTF8Encoding]::new($false)
        $raw=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mongo-backup-manifest.js') -Raw |
            & docker exec -i -e ('EATS_BACKUP_DATABASE='+$database) -e EATS_BACKUP_SOURCE=true eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin
        Assert-DockerSuccess 'leer manifiesto de disponibilidad'
        return (($raw -join "`n")|ConvertFrom-Json)
    }finally{$OutputEncoding=$encoding}
}
function Equal-Data($a,$b,[string]$name){if(($a|ConvertTo-Json -Depth 40 -Compress) -cne ($b|ConvertTo-Json -Depth 40 -Compress)){throw ($name+': datos cambiaron; conserva el checkpoint y revisa otras escrituras.')}}
function Public-Get([string]$uri,[int]$expected){
    # Deliberadamente sin Authorization, incluso si hay tokens en la terminal.
    $response=Invoke-LocalHttp -Uri $uri
    if($response.Status -ne $expected){throw ('Se esperaba HTTP '+$expected+' y se recibio '+$response.Status+'. Revisar gate y dependencias; no se activan automaticamente.')}
    if($null -ne $response.Headers['ETag']){throw 'Disponibilidad publica no debe exponer ETag.'}
    return ($response.Content|ConvertFrom-Json)
}
function Assert-Fields($value,[string[]]$names){
    $actual=@($value.PSObject.Properties.Name|Sort-Object);$expected=@($names|Sort-Object)
    if(($actual -join ',') -cne ($expected -join ',')){throw 'La proyeccion publica expone campos inesperados o incompletos.'}
}
function Check-List($body){
    Assert-Fields $body @('restaurantId','date','partySize','observedAt','items')
    if($body.restaurantId -cne $owner -or $body.date -cne $script:checkpoint.date -or $body.partySize -ne $script:checkpoint.partySize){throw 'Consulta/respuesta incompatibles.'}
    $now=[DateTimeOffset]::Parse($body.observedAt)
    $ids=@{};$last=$null
    foreach($item in @($body.items)){
        Assert-Fields $item @('shiftId','localStart','localEnd','zoneId','startInstant','endInstant','bookingWindow','availability','reservable')
        $start=[DateTimeOffset]::Parse($item.startInstant);$end=[DateTimeOffset]::Parse($item.endInstant)
        $id=([guid]$item.shiftId).ToString()
        if($item.localStart -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$' -or $item.localEnd -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'){throw 'Formato de extremos locales invalido.'}
        if($ids.ContainsKey($id) -or $start -le $now -or $end -le $start -or !$item.localStart.StartsWith($body.date+'T')){throw 'Turno duplicado, no futuro o fuera de la fecha local.'}
        if($null -ne $last -and $start -lt $last){throw 'Turnos desordenados.'};$last=$start;$ids[$id]=$true
        $window=if($start -lt $now.AddHours(2)){'TOO_SOON'}elseif($start -gt $now.AddDays(90)){'TOO_FAR'}else{'OPEN'}
        if($item.bookingWindow -cne $window -or $item.availability -notin @('AVAILABLE','UNAVAILABLE','UNDETERMINED') -or
            [bool]$item.reservable -ne ($window -eq 'OPEN' -and $item.availability -eq 'AVAILABLE')){throw 'Ventana, ocupacion o reservable incoherentes.'}
    }
}
$lock=$null
try{
    [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
    $lock=[IO.File]::Open(($path+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if(Test-Path -LiteralPath $path){
        $script:checkpoint=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($script:checkpoint.schemaVersion -ne 1 -or $script:checkpoint.spec -cne 'SPEC-004' -or $script:checkpoint.restaurantId -cne $owner){throw 'Checkpoint ajeno o incompatible; no se sobrescribe.'}
        if($Date -and $Date -cne $script:checkpoint.date){throw 'Conserva la fecha del ensayo existente.'}
        if($PSBoundParameters.ContainsKey('PartySize') -and $PartySize -ne $script:checkpoint.partySize){throw 'Conserva el grupo del ensayo existente.'}
    }else{
        if($Stage -ne 'Baseline' -or $Date -notmatch '^\d{4}-\d{2}-\d{2}$'){throw 'Primero Baseline con -Date YYYY-MM-DD de turnos futuros existentes.'}
        $null=[datetime]::ParseExact($Date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
        $script:checkpoint=[pscustomobject]@{schemaVersion=1;spec='SPEC-004';runId=[guid]::NewGuid().ToString();restaurantId=$owner;date=$Date;partySize=$PartySize;baseline=$null;attempts=@();pending=@('gate','restore','rollback','formalApproval')}
        Save-Availability
    }
    if($Stage -eq 'Baseline' -and $null -ne $script:checkpoint.baseline){throw 'Baseline ya existe; usa las etapas posteriores. No se reemplaza la evidencia.'}
    if($Stage -ne 'Baseline' -and $null -eq $script:checkpoint.baseline){throw 'Falta Baseline completo.'}
    $uri=$root+'/restaurants/'+$owner+'/availability?date='+$script:checkpoint.date+'&partySize='+$script:checkpoint.partySize
    Write-Host 'Evita otras escrituras durante estas consultas; el script no crea fixtures ni modifica configuracion.'
    $before=Read-Manifest
    $body=Public-Get $uri 200;Check-List $body
    if($Stage -eq 'Baseline'){
        foreach($query in @('date=incorrecta&partySize=2',('date='+$script:checkpoint.date+'&partySize=x'))){$null=Public-Get ($root+'/restaurants/'+$owner+'/availability?'+$query) 400}
        foreach($size in @(0,21)){$null=Public-Get ($root+'/restaurants/'+$owner+'/availability?date='+$script:checkpoint.date+'&partySize='+$size) 422}
    }
    if($Stage -eq 'AfterRestart'){
        # observedAt y ventanas se verifican de nuevo; no son datos persistidos.
        $prior=@($script:checkpoint.attempts[-1].body.items|Select-Object shiftId,localStart,localEnd,zoneId,startInstant,endInstant,availability)
        $current=@($body.items|Select-Object shiftId,localStart,localEnd,zoneId,startInstant,endInstant,availability)
        Equal-Data $prior $current 'Turnos/oferta tras reinicio declarado'
    }
    if($Stage -eq 'AfterCompetingReservation'){
        if($ShiftId -eq [guid]::Empty){throw 'Indica -ShiftId del turno antes disponible y ahora ocupado por una reserva real autorizada.'}
        $prior=@($script:checkpoint.baseline.body.items|Where-Object {$_.shiftId -eq $ShiftId.ToString()})
        $current=@($body.items|Where-Object {$_.shiftId -eq $ShiftId.ToString()})
        if($prior.Count -ne 1 -or $current.Count -ne 1 -or $prior[0].availability -cne 'AVAILABLE' -or $current[0].availability -cne 'UNAVAILABLE'){throw 'No se acredito AVAILABLE antes y UNAVAILABLE despues. No se crean reservas automaticamente.'}
    }
    if($Stage -eq 'Uncertain' -and @($body.items|Where-Object {$_.availability -eq 'UNDETERMINED'}).Count -eq 0){throw 'El estado real no muestra incertidumbre; comprobacion pendiente, no se inyecta legado.'}
    $after=Read-Manifest;Equal-Data $before $after 'GET conserva documentos/indices/revisiones/recibos'
    $entry=[pscustomobject]@{stage=$Stage;timestampUtc=[DateTime]::UtcNow.ToString('o');body=$body;before=$before;after=$after;dataPreserved=$true;operatorDeclaredRestart=($Stage -eq 'AfterRestart');
        coverage=[pscustomobject]@{publicWithoutToken=$true;privacy=$true;outsideWindow=(@($body.items|Where-Object {$_.bookingWindow -ne 'OPEN'}).Count -gt 0);uncertain=(@($body.items|Where-Object {$_.availability -eq 'UNDETERMINED'}).Count -gt 0);nonRetention=($Stage -eq 'AfterCompetingReservation')}}
    if($Stage -eq 'Baseline'){$script:checkpoint.baseline=$entry}
    $script:checkpoint.attempts=@($script:checkpoint.attempts)+@($entry);Save-Availability
    Write-Host ('OK: '+$Stage+', consulta publica, privacidad, ventanas y Mongo sin cambios durante GET.')
    Write-Host 'Solo se acreditan casos observados. Gate, incertidumbre/ocupacion ausentes, restore, rollback y cierre siguen pendientes.'
}finally{if($null -ne $lock){$lock.Dispose()}}
