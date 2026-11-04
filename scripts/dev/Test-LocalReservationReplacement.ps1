[CmdletBinding()]
param([guid]$ReservationId=[guid]::Empty,[guid]$FreeShiftId=[guid]::Empty,[guid]$OccupiedShiftId=[guid]::Empty,
      [guid]$NearStartReservationId=[guid]::Empty,[switch]$AfterRestart,[switch]$AllowFixtureWrites,
      [switch]$AllowDatabaseReads,[switch]$DedicatedReservations,[switch]$ActivationPrerequisitesConfirmed)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationReplacement.Assertions.ps1')
if(!$ActivationPrerequisitesConfirmed){throw 'Primero verificar las cinco funcionalidades, T129, corte persistente, respaldo restaurable y version puente. Este script no activa gates.'}
if(!$AllowDatabaseReads){throw 'Declara -AllowDatabaseReads para comparar Mongo sin escribir directamente en la base.'}
if(!$AfterRestart -and (!$AllowFixtureWrites -or !$DedicatedReservations)){throw 'Declara -AllowFixtureWrites y -DedicatedReservations; solo reservas dedicadas a este ensayo.'}
$root='http://localhost:8082/catalog';$collection=$root+'/restaurants/'+$script:RestaurantA+'/reservations'
$path=Join-Path $script:IdentityPrivate 'reservation-replacement-http-checkpoint.json'
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env');$database=$values['MONGODB_DATABASE']
if($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018' -or
    $database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')){throw 'Solo Mongo local 27018 y base de aplicacion.'}
function Save-Replacement {
    $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp';Write-PrivateText $temp ($script:cp|ConvertTo-Json -Depth 50)
    if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}
}
function Equal-Replacement($a,$b,[string]$name){if(($a|ConvertTo-Json -Depth 45 -Compress) -cne ($b|ConvertTo-Json -Depth 45 -Compress)){throw ($name+': diferencia; conserva el checkpoint y evita otras escrituras.')}}
function Replacement-Token([string]$name){
    $token=[Environment]::GetEnvironmentVariable($name,'Process');if([string]::IsNullOrWhiteSpace($token)){throw ('Falta '+$name)}
    $claims=ConvertFrom-JwtPayload $token
    if($claims.iss -cne $script:IdentityIssuer -or @($claims.aud) -notcontains 'eats-hub-catalog' -or
        [string]::IsNullOrWhiteSpace($claims.sub) -or [long]$claims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+30){throw ('Renueva '+$name)}
    return $token
}
function Replacement-Manifest {
    $old=$OutputEncoding
    try{$OutputEncoding=[Text.UTF8Encoding]::new($false)
        $raw=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mongo-backup-manifest.js') -Raw |
            & docker exec -i -e ('EATS_BACKUP_DATABASE='+$database) -e EATS_BACKUP_SOURCE=true eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin
        Assert-DockerSuccess 'leer manifiesto de modificacion';return (($raw -join "`n")|ConvertFrom-Json)
    }finally{$OutputEncoding=$old}
}
function Replacement-Request([string]$uri,[string]$method,[string]$actor,[string]$body,[string]$match,[string]$key,[int]$expected){
    if(!$uri.StartsWith($root+'/',[StringComparison]::Ordinal)){throw 'Destino fuera de Eats Hub local.'}
    $headers=@{};if($actor){$headers.Authorization='Bearer '+(Replacement-Token $actor)}
    if($match){$headers['If-Match']=$match};if($key){$headers['Idempotency-Key']=$key}
    $requestArgs=@{Uri=$uri;Method=$method;Headers=$headers};if($method -eq 'Put'){$requestArgs.Body=$body}
    $response=Invoke-LocalHttp @requestArgs
    if($response.Status -ne $expected){throw ('Esperado HTTP '+$expected+', recibido '+$response.Status+'. No repitas con otra clave; conserva el checkpoint.')}
    $etag='';$location='';if($null -ne $response.Headers['ETag']){$etag=[string](@($response.Headers['ETag'])[0])}
    if($null -ne $response.Headers['Location']){$location=[string](@($response.Headers['Location'])[0])}
    return [pscustomobject]@{status=$response.Status;body=($response.Content|ConvertFrom-Json);etag=$etag;location=$location}
}
function Replacement-Get([string]$uri,[string]$actor='EATS_HUB_TOKEN_CUSTOMER_A'){
    return Replacement-Request $uri 'Get' $actor '' '' '' 200
}
function Replacement-Identity([string]$actor){
    if(!$actor){return $null}
    $claims=ConvertFrom-JwtPayload (Replacement-Token $actor)
    return [pscustomobject]@{issuer=$claims.iss;subject=$claims.sub}
}
function Check-ReplacementIdentity($identity,[string]$actor){
    if($actor){$claims=ConvertFrom-JwtPayload (Replacement-Token $actor);Assert-ReplacementIdentity $identity $claims ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())}
}
function Replacement-DeltaManifest($entry){
    $expectations=[pscustomobject]@{restaurantId=$script:RestaurantA;reservationId=($entry.uri.Split('/')[-1]);issuer=$entry.identity.issuer;subject=$entry.identity.subject;key=$entry.key;body=($entry.body|ConvertFrom-Json);match=$entry.match}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($expectations|ConvertTo-Json -Compress)))
    $old=$OutputEncoding
    try{$OutputEncoding=[Text.UTF8Encoding]::new($false)
        $raw=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mongo-replacement-manifest.js') -Raw |
            & docker exec -i -e ('EATS_BACKUP_DATABASE='+$database) -e ('EATS_REPLACEMENT_EXPECTATIONS_BASE64='+$encoded) eats-availability-mongodb-replica-1 mongosh --quiet --port 27018 --file /dev/stdin
        Assert-DockerSuccess 'leer delta de modificacion';return (($raw -join "`n")|ConvertFrom-Json)
    }finally{$OutputEncoding=$old}
}
function Replacement-Step([string]$name,[string]$uri,[string]$actor,$body,[string]$match,[int]$expected,[bool]$unchanged){
    $step=@($script:cp.steps|Where-Object {$_.name -ceq $name})
    if($step.Count -eq 0){
        $entry=[pscustomobject]@{name=$name;uri=$uri;actor=$actor;identity=(Replacement-Identity $actor);body=($body|ConvertTo-Json -Compress);match=$match;key=($script:cp.runId+'-'+$name);expected=$expected;unchanged=$unchanged;before=$null;original=$null;shift=$null;after=$null;response=$null}
        $script:cp.steps=@($script:cp.steps)+@($entry);Save-Replacement
    }else{$entry=$step[0]}
    Check-ReplacementIdentity $entry.identity $entry.actor
    if($null -ne $entry.response){Write-Host ('Checkpoint: '+$name+' ya comprobado');return $entry.response}
    if($null -eq $entry.before){
        if($entry.unchanged){$entry.before=Replacement-Manifest}
        else{
            $entry.original=Replacement-Get $entry.uri $entry.actor
            if($entry.original.etag -cne $entry.match){throw 'La version previa no coincide; revisar checkpoint antes de escribir.'}
            $intent=$entry.body|ConvertFrom-Json
            $entry.shift=(Replacement-Get ($root+'/restaurants/'+$script:RestaurantA+'/shifts/'+$intent.shiftId) 'EATS_HUB_TOKEN_A').body
            $entry.before=Replacement-DeltaManifest $entry
        }
        Save-Replacement
    }
    $result=Replacement-Request $entry.uri 'Put' $entry.actor $entry.body $entry.match $entry.key $entry.expected
    if($entry.unchanged){$after=Replacement-Manifest;Equal-Replacement $entry.before $after $name}
    else{
        $intent=$entry.body|ConvertFrom-Json
        Assert-ReplacementSuccess $entry.original $result $intent $entry.shift @($script:cp.config[0].body.items) @($script:cp.config[1].body.items)
        $after=Replacement-DeltaManifest $entry;Assert-ReplacementDelta $entry.before $after
        Assert-ReplacementDatabase $after $result @($script:cp.config[0].body.items)
    }
    $entry.after=$after;$entry.response=$result;Save-Replacement;Write-Host ('OK: '+$name+' -> HTTP '+$entry.expected);return $result
}
function Replacement-Replay([string]$name){
    $entry=@($script:cp.steps|Where-Object {$_.name -ceq $name})[0];$before=Replacement-Manifest
    Check-ReplacementIdentity $entry.identity $entry.actor
    $result=Replacement-Request $entry.uri 'Put' $entry.actor $entry.body $entry.match $entry.key $entry.expected
    Equal-Replacement $entry.response $result ('Replay '+$name);Equal-Replacement $before (Replacement-Manifest) ('Mongo durante replay '+$name)
    Write-Host ('OK: replay '+$name+' conserva estado/cuerpo/Location/ETag y Mongo')
}
$lock=$null
try{
    [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
    $lock=[IO.File]::Open(($path+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if(Test-Path -LiteralPath $path){
        $script:cp=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if($script:cp.schemaVersion -ne 1 -or $script:cp.spec -cne 'SPEC-007'){throw 'Checkpoint ajeno.'}
        if($null -eq $script:cp.PSObject.Properties['comparisonVersion']){
            if(@($script:cp.steps).Count -gt 0 -or $null -ne $script:cp.final){throw 'Checkpoint anterior con evidencia: se conserva intacto. Requiere revision explicita; no se ejecuta HTTP ni se reinicia el ensayo.'}
            $script:cp|Add-Member -NotePropertyName comparisonVersion -NotePropertyValue 2
            $script:cp|Add-Member -NotePropertyName nearSnapshot -NotePropertyValue $null
            $script:cp|Add-Member -NotePropertyName nearFinal -NotePropertyValue $null
        }
        if($script:cp.comparisonVersion -ne 2){throw 'Version de comparadores desconocida; checkpoint intacto.'}
        foreach($pair in @(@('ReservationId','reservationId'),@('FreeShiftId','freeShiftId'),@('OccupiedShiftId','occupiedShiftId'),@('NearStartReservationId','nearStartId'))){
            if($PSBoundParameters.ContainsKey($pair[0]) -and (Get-Variable $pair[0] -ValueOnly).ToString() -cne $script:cp.($pair[1])){throw 'Parametros distintos al checkpoint; no se reemplaza.'}
        }
    }else{
        if($AfterRestart -or $ReservationId -eq [guid]::Empty -or $FreeShiftId -eq [guid]::Empty -or $OccupiedShiftId -eq [guid]::Empty){throw 'Primero indica reserva dedicada, FreeShiftId y OccupiedShiftId.'}
        if($FreeShiftId -eq $OccupiedShiftId){throw 'Los turnos libre y ocupado deben ser distintos.'}
        if($NearStartReservationId -eq $ReservationId){throw 'La reserva cercana debe ser otra fixture dedicada.'}
        foreach($file in (Get-ChildItem -LiteralPath $script:IdentityPrivate -Filter '*checkpoint.json')){
            $other=Get-Content -LiteralPath $file.FullName -Raw|ConvertFrom-Json
            $property=$other.PSObject.Properties['reservationId']
            if($null -ne $property -and $property.Value -in @($ReservationId.ToString(),$NearStartReservationId.ToString())){throw 'Reserva usada en otro checkpoint; prepara una dedicada.'}
        }
        foreach($token in @('EATS_HUB_TOKEN_CUSTOMER_A','EATS_HUB_TOKEN_CUSTOMER_B','EATS_HUB_TOKEN_A','EATS_HUB_TOKEN_B','EATS_HUB_TOKEN_DUAL')){$null=Replacement-Token $token}
        $initial=Replacement-Get ($collection+'/'+$ReservationId)
        $claims=ConvertFrom-JwtPayload (Replacement-Token 'EATS_HUB_TOKEN_CUSTOMER_A')
        if($initial.body.kind -cne 'MANAGED' -or $initial.body.status -cne 'CONFIRMED' -or $initial.body.restaurantId -cne $script:RestaurantA -or
            $initial.body.owner.issuer -cne $claims.iss -or $initial.body.owner.subject -cne $claims.sub){throw 'Se exige confirmada v2 propia de cliente-a en A.'}
        if([DateTimeOffset]::Parse($initial.body.startInstant) -lt [DateTimeOffset]::UtcNow.AddHours(2).AddMinutes(5)){throw 'Reserva original sin margen de 2h + 5min para completar el ensayo.'}
        if($initial.body.shiftId -in @($FreeShiftId.ToString(),$OccupiedShiftId.ToString())){throw 'Original y destinos deben ser distintos.'}
        foreach($choice in @(@($FreeShiftId,'AVAILABLE'),@($OccupiedShiftId,'UNAVAILABLE'))){
            $shift=Replacement-Get ($root+'/restaurants/'+$script:RestaurantA+'/shifts/'+$choice[0]) 'EATS_HUB_TOKEN_A'
            $date=([string]$shift.body.localStart).Substring(0,10)
            $view=Replacement-Get ($root+'/restaurants/'+$script:RestaurantA+'/availability?date='+$date+'&partySize='+$initial.body.partySize) ''
            $item=@($view.body.items|Where-Object {$_.shiftId -ceq $choice[0].ToString()})
            if($item.Count -ne 1 -or $item[0].bookingWindow -cne 'OPEN' -or $item[0].availability -cne $choice[1]){throw 'Destino sin disponibilidad/plazo esperados; no se escribe.'}
        }
        $config=@();foreach($resource in @('tables','table-combinations','time-zone','shifts')){$config+=@(Replacement-Get ($root+'/restaurants/'+$script:RestaurantA+'/'+$resource) 'EATS_HUB_TOKEN_A')}
        $script:cp=[pscustomobject]@{schemaVersion=1;comparisonVersion=2;spec='SPEC-007';runId=[guid]::NewGuid().ToString('N');reservationId=$ReservationId.ToString();freeShiftId=$FreeShiftId.ToString();occupiedShiftId=$OccupiedShiftId.ToString();nearStartId=$NearStartReservationId.ToString();initial=$initial;config=$config;steps=@();final=$null;manifest=$null;restart=@();temporalNearStart=$false;nearSnapshot=$null;nearFinal=$null}
        Save-Replacement
    }
    $resource=$collection+'/'+$script:cp.reservationId
    if($AfterRestart){
        if($null -eq $script:cp.final){throw 'Falta completar el recorrido inicial.'}
        $before=Replacement-Manifest;$current=Replacement-Get $resource
        Equal-Replacement $script:cp.final $current 'Reserva/identidad/asignacion/snapshot/version/ETag tras reinicio declarado'
        if($null -ne $script:cp.nearFinal){Assert-ReplacementStored $script:cp.nearFinal (Replacement-Get $script:cp.nearSnapshot.uri)}
        Equal-Replacement $script:cp.manifest $before 'Mongo desde fin del recorrido'
        Equal-Replacement $before (Replacement-Manifest) 'Lectura tras reinicio'
        $script:cp.restart=@($script:cp.restart)+@([pscustomobject]@{timestampUtc=[DateTime]::UtcNow.ToString('o');operatorDeclaredRestart=$true;preserved=$true});Save-Replacement
        Write-Host 'OK: reinicio declarado; reserva, snapshot, version, ETag y Mongo conservados. T175/aprobacion pendientes.';return
    }
    if($null -ne $script:cp.final){throw 'Recorrido completo; reinicia manualmente y usa -AfterRestart.'}
    Write-Host 'Evita otras escrituras. La reserva dedicada cambiara notas/turno y se conservara; no se borran datos ni se cambia configuracion.'
    $initial=$script:cp.initial;$base=@{shiftId=$initial.body.shiftId;partySize=$initial.body.partySize;notes=('SPEC-007 '+$script:cp.runId)}
    $null=Replacement-Step 'sin-token' $resource '' $base $initial.etag 401 $true
    $null=Replacement-Step 'encargado-ajeno' $resource 'EATS_HUB_TOKEN_B' $base $initial.etag 403 $true
    $null=Replacement-Step 'otro-cliente' $resource 'EATS_HUB_TOKEN_CUSTOMER_B' $base $initial.etag 404 $true
    $notes=Replacement-Step 'notas-Q1' $resource 'EATS_HUB_TOKEN_CUSTOMER_A' $base $initial.etag 200 $false
    if([long]$notes.body.version -ne [long]$initial.body.version+1 -or $notes.etag -cne ('"'+$notes.body.version+'"') -or $notes.location){throw 'Version/ETag/Location inesperados en PUT.'}
    Replacement-Replay 'notas-Q1'
    $null=Replacement-Step 'If-Match-ausente' $resource 'EATS_HUB_TOKEN_CUSTOMER_A' $base '' 400 $true
    $null=Replacement-Step 'If-Match-obsoleto' $resource 'EATS_HUB_TOKEN_CUSTOMER_A' $base $initial.etag 412 $true
    $busy=@{shiftId=$script:cp.occupiedShiftId;partySize=$initial.body.partySize;notes=$base.notes}
    $busyResult=Replacement-Step 'destino-ocupado' $resource 'EATS_HUB_TOKEN_CUSTOMER_A' $busy $notes.etag 409 $true
    if($busyResult.body.code -cne 'NO_AVAILABILITY'){throw 'El conflicto no acredita destino ocupado; revisa fixture y conserva checkpoint.'}
    $before=Replacement-Manifest;$entry=@($script:cp.steps|Where-Object {$_.name -ceq 'notas-Q1'})[0]
    $conflict=Replacement-Request $resource 'Put' $entry.actor ($busy|ConvertTo-Json -Compress) $entry.match $entry.key 409
    if($conflict.body.code -cne 'IDEMPOTENCY_CONFLICT'){throw 'No se acredito conflicto de clave.'}
    Equal-Replacement $before (Replacement-Manifest) 'Conflicto de clave'
    $move=@{shiftId=$script:cp.freeShiftId;partySize=$initial.body.partySize;notes=$base.notes}
    $moved=Replacement-Step 'reasignar' $resource 'EATS_HUB_TOKEN_CUSTOMER_A' $move $notes.etag 200 $false
    if($moved.body.shiftId -cne $script:cp.freeShiftId -or $moved.body.id -cne $initial.body.id -or [long]$moved.body.version -ne [long]$notes.body.version+1){throw 'Movimiento/version inesperados.'}
    Replacement-Replay 'notas-Q1';Replacement-Replay 'reasignar'
    # Igual contenido con otra intencion debe incrementar version; valida al encargado local.
    $manager=Replacement-Step 'encargado-local' $resource 'EATS_HUB_TOKEN_A' $move $moved.etag 200 $false
    if([long]$manager.body.version -ne [long]$moved.body.version+1){throw 'PUT equivalente no incremento version.'}
    if($script:cp.nearStartId -ne ([guid]::Empty).ToString()){
        if($null -eq $script:cp.nearSnapshot){
            $nearUri=$collection+'/'+$script:cp.nearStartId;$near=Replacement-Get $nearUri
            $script:cp.nearSnapshot=New-ReplacementNearSnapshot $near $nearUri ('SPEC-007 near '+$script:cp.runId) ([DateTimeOffset]::UtcNow)
            Save-Replacement
        }
        $frozen=$script:cp.nearSnapshot
        $late=Replacement-Step 'cliente-fuera-plazo' $frozen.uri 'EATS_HUB_TOKEN_CUSTOMER_A' $frozen.body $frozen.match 409 $true
        if($late.body.code -cne 'RESERVATION_WINDOW_CLOSED'){throw 'No se acredito rechazo temporal del cliente.'}
        $acceptedNear=Replacement-Step 'dual-dentro-plazo-encargado' $frozen.uri 'EATS_HUB_TOKEN_DUAL' $frozen.body $frozen.match 200 $false
        Replacement-Replay 'dual-dentro-plazo-encargado'
        $script:cp.nearFinal=Replacement-Get $frozen.uri
        Assert-ReplacementStored $acceptedNear $script:cp.nearFinal
        $script:cp.temporalNearStart=$true;Save-Replacement
    }
    $config=@();foreach($item in @('tables','table-combinations','time-zone','shifts')){$config+=@(Replacement-Get ($root+'/restaurants/'+$script:RestaurantA+'/'+$item) 'EATS_HUB_TOKEN_A')}
    # Tablas/listas exponen revision global nueva; comparar configuracion sin ese metadato.
    for($i=0;$i -lt $config.Count;$i++){
        $a=$script:cp.config[$i].body|ConvertTo-Json -Depth 40|ConvertFrom-Json;$b=$config[$i].body|ConvertTo-Json -Depth 40|ConvertFrom-Json
        $a.PSObject.Properties.Remove('revision');$b.PSObject.Properties.Remove('revision')
        if($null -ne $a.PSObject.Properties['items']){foreach($row in @($a.items)){$row.PSObject.Properties.Remove('revision')};foreach($row in @($b.items)){$row.PSObject.Properties.Remove('revision')}}
        Equal-Replacement $a $b 'Configuracion previa'
    }
    $script:cp.final=Replacement-Get $resource;Assert-ReplacementStored $manager $script:cp.final
    $script:cp.manifest=Replacement-Manifest;Save-Replacement
    Write-Host 'OK: PUT, Q1, destino ocupado, permisos, If-Match y replay. Checkpoint propio sin JWT.'
    Write-Host 'Reinicia manualmente en IntelliJ (8082) y usa -AfterRestart. Limites exactos 2h/90d solo automatizados; casos sin fixture, gates, restore, reversion y cierre pendientes.'
}finally{if($null -ne $lock){$lock.Dispose()}}
