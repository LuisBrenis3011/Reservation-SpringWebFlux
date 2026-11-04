[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Disabled','Enabled')][string]$Stage,
      [switch]$AllowFixtureWrites)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
if (!$AllowFixtureWrites) { throw 'Este recorrido crea, actualiza y elimina SOLO su reserva ficticia de B. Usa -AllowFixtureWrites para ejecutarlo.' }
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env')
if ($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018' -or
    ($values.ContainsKey('MONGODB_URI') -and ![string]::IsNullOrWhiteSpace($values['MONGODB_URI']))) { throw 'Solo admite Mongo local 27018 configurado por campos.' }
$database=$values['MONGODB_DATABASE']
if ($database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')) { throw 'Base no permitida.' }
$source='eats-availability-mongodb-replica-1'
$run=[guid]::NewGuid().ToString('N')
$customerId=[guid]::NewGuid().ToString()
$marker='T040 local legacy '+$run
$reservationId=''
$root='http://localhost:8082/catalog'
$checks=[Collections.Generic.List[object]]::new()
$checkpoint=Join-Path $script:IdentityPrivate ('legacy-fixture-'+$run+'.json')
function Check-Legacy($Response,[int]$Expected,[string]$Name) {
    if ($Response.Status -ne $Expected) { throw "$Name : se esperaba $Expected y se recibio $($Response.Status). No repitas escrituras sin revisar el checkpoint local." }
    $checks.Add([pscustomobject]@{name=$Name;status=$Response.Status;passed=$true})
    Write-Host ("OK: $Name -> HTTP $Expected")
}
function Read-LegacyState {
    $oldEncoding=$OutputEncoding
    try {
        $OutputEncoding=[Text.UTF8Encoding]::new($false)
        $result=Get-Content (Join-Path $PSScriptRoot 'read-local-legacy-state.js') -Raw |
            & docker exec -i -e ("EATS_BACKUP_DATABASE="+$database) -e ("EATS_LEGACY_RESERVATION_ID="+$reservationId) -e ("EATS_LEGACY_CUSTOMER_ID="+$customerId) -e ("EATS_LEGACY_MARKER="+$marker) $source mongosh --quiet --port 27018 --file /dev/stdin
        Assert-DockerSuccess 'consultar estado de la reserva ficticia'
        return (($result -join "`n") | ConvertFrom-Json)
    } finally { $OutputEncoding=$oldEncoding }
}
function Save-LegacyCheckpoint([string]$Phase) {
    Write-PrivateText $checkpoint (@{run=$run;stage=$Stage;phase=$Phase;reservationId=$reservationId;
        restaurantId=$script:RestaurantB;customerId=$customerId;marker=$marker} | ConvertTo-Json)
}
function Assert-LegacyState($State,[int]$Delta,[int]$Count) {
    if ($State.revision -ne $before.revision+$Delta -or $State.reservationCount -ne $Count -or
        $State.restaurantASha256 -ne $before.restaurantASha256) { throw 'Revision/conteo inesperado o cambios en A. Conserva el checkpoint y revisa.' }
}
function Assert-LegacyBody($Response,[int]$PartySize,[string]$DateTime) {
    $body=$Response.Content | ConvertFrom-Json
    if ($body.restaurantId -ne $script:RestaurantB -or $body.customerName -ne $payload.customerName -or
        $body.partySize -ne $PartySize -or $body.dateTime -ne $DateTime) { throw 'La respuesta no conserva los datos ficticios esperados.' }
}
$expectedGate=if($Stage -eq 'Disabled'){404}else{401}
Check-Legacy (Invoke-LocalHttp -Uri ($root+'/restaurants/'+$script:RestaurantB+'/tables')) $expectedGate 'Gate de la etapa'
Check-Legacy (Invoke-LocalHttp -Uri ($root+'/restaurants')) 200 'Catalogo antiguo'
$before=Read-LegacyState
if ($before.reservationCount -ne 0) { throw 'B ya tiene reservas: no se modifica ninguna. Revisa ejecuciones anteriores antes de continuar.' }
$date=[DateTime]::UtcNow.AddDays(7).ToString('yyyy-MM-dd')
$payload=[ordered]@{restaurantId=$script:RestaurantB;customerId=$customerId;
    customerName=('T040 Demo '+$run.Substring(0,6));customerEmail='t040@example.test';
    dateTime=($date+',12:00');partySize=2;comment=$marker}
Save-LegacyCheckpoint 'before-create'
$created=Invoke-LocalHttp -Uri ($root+'/reservation') -Method Post -Body ($payload | ConvertTo-Json -Compress)
Check-Legacy $created 201 'Crear reserva ficticia'
$resource=[string](($created.Content | ConvertFrom-Json).Resource)
if ($resource -notmatch '^/reservations/([0-9a-fA-F-]{36})$') { throw 'Respuesta de alta inesperada; revisar antes de repetir.' }
$reservationId=[guid]::Parse($Matches[1]).ToString()
Save-LegacyCheckpoint 'created'
$state=Read-LegacyState
Assert-LegacyState $state 1 1
if($null -eq $state.fixture -or $state.fixture.partySize -ne 2 -or $state.fixture.time -ne '12:00' -or $state.fixture.status -ne 'PENDING'){throw 'Fixture creada inesperada; no se elimina automaticamente.'}
# El contrato antiguo devuelve /reservations/... pero la ruta implementada es /reservation/{id}.
$uri=$root+'/reservation/'+$reservationId
$read=Invoke-LocalHttp -Uri $uri
Check-Legacy $read 200 'Consultar reserva ficticia'
Assert-LegacyBody $read 2 ($date+',12:00')
$payload.partySize=3
$payload.dateTime=$date+',12:30'
$updated=Invoke-LocalHttp -Uri $uri -Method Put -Body ($payload | ConvertTo-Json -Compress)
Check-Legacy $updated 200 'Actualizar reserva ficticia'
Assert-LegacyBody $updated 3 ($date+',12:30')
Save-LegacyCheckpoint 'updated'
$state=Read-LegacyState
Assert-LegacyState $state 2 1
if($null -eq $state.fixture -or $state.fixture.partySize -ne 3 -or $state.fixture.date -ne $date -or $state.fixture.time -ne '12:30'){throw 'Fixture actualizada inesperada; no se elimina automaticamente.'}
# El lector acaba de verificar ID, restaurante, cliente y marcador antes del DELETE.
$deleted=Invoke-LocalHttp -Uri $uri -Method Delete
Check-Legacy $deleted 204 'Eliminar solo la reserva de este ensayo'
Save-LegacyCheckpoint 'delete-returned'
$final=Read-LegacyState
Assert-LegacyState $final 3 0
if($null -ne $final.fixture){throw 'La reserva ficticia sigue presente.'}
Save-LegacyCheckpoint 'completed'
$evidence=[ordered]@{timestampUtc=[DateTime]::UtcNow.ToString('o');stage=$Stage;run=$run;
    restaurantId=$script:RestaurantB;reservationId=$reservationId;checks=$checks.ToArray();
    initialRevision=$before.revision;finalRevision=$final.revision;createdFixtureRemoved=$true;
    restaurantAUnchanged=$true;note='Recorrido secuencial de rutas antiguas; Planner es el simulador actual, no una integracion externa ni una prueba de concurrencia.'}
Write-PrivateText (Join-Path $script:IdentityPrivate ('legacy-'+$Stage.ToLowerInvariant()+'-validation.json')) ($evidence | ConvertTo-Json -Depth 12)
Write-Host 'OK: create/update/delete incrementaron una revision cada uno; A sin cambios y fixture eliminada.'
