[CmdletBinding()]
param([switch]$AllowFixtureWrites,[switch]$AllowZoneChanges,[switch]$AfterRestart)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
$root='http://localhost:8082/catalog/restaurants/'
$zone=$root+$script:RestaurantA+'/time-zone'
$shifts=$root+$script:RestaurantA+'/shifts'
$tables=$root+$script:RestaurantA+'/tables'
$combinations=$root+$script:RestaurantA+'/table-combinations'
$otherZone=$root+$script:RestaurantB+'/time-zone'
$otherShifts=$root+$script:RestaurantB+'/shifts'
$checkpointPath=Join-Path $script:IdentityPrivate 'shifts-http-checkpoint.json'

function Save-Checkpoint {
    $temp=$checkpointPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    Write-PrivateText $temp ($script:checkpoint | ConvertTo-Json -Depth 50)
    # En Windows PowerShell 5.1, $null se convierte en string vacio para este
    # argumento string. NullString entrega null real: no se solicita un backup.
    if(Test-Path -LiteralPath $checkpointPath){[IO.File]::Replace($temp,$checkpointPath,[System.Management.Automation.Language.NullString]::Value)}
    else{[IO.File]::Move($temp,$checkpointPath)}
}
function Read-Token([string]$Name) {
    $value=[Environment]::GetEnvironmentVariable($Name,'Process')
    if([string]::IsNullOrWhiteSpace($value)){throw "Falta $Name. Obten los tokens en esta misma PowerShell."}
    $claims=ConvertFrom-JwtPayload $value
    if($null -eq $claims.PSObject.Properties['sub'] -or [string]::IsNullOrWhiteSpace([string]$claims.sub)){
        throw "Token de $Name sin sub. Reparar identidad y obtenerlo nuevamente."
    }
    if([long]$claims.exp -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+30){throw "Token de $Name expirado o por expirar; renovarlo."}
    return $value
}
function Header($Response,[string]$Name) {
    $value=$Response.Headers[$Name]
    if($null -eq $value){return ''}
    return [string](@($value)[0])
}
function Check-Status($Response,[int]$Expected,[string]$Name,[string]$Code='') {
    if($Response.status -ne $Expected){
        throw "$Name : se esperaba HTTP $Expected y se recibio $($Response.status). Conserva el checkpoint; no cambies claves ni repitas con otro ensayo. Revisa app/gate/tokens."
    }
    if($Code -and (($Response.content | ConvertFrom-Json).code -cne $Code)){throw "$Name : codigo de dominio inesperado."}
}
function Send-Request([string]$Uri,[string]$Method,[string]$Actor,[string]$Body,[string]$Key,[string]$Match) {
    $headers=@{}
    if($Actor){$headers.Authorization='Bearer '+(Read-Token $Actor)}
    if($Key){$headers['Idempotency-Key']=$Key}
    if($Match){$headers['If-Match']=$Match}
    $arguments=@{Uri=$Uri;Method=$Method;Headers=$headers}
    if($Method -in @('Post','Put')){$arguments.Body=$Body}
    $response=Invoke-LocalHttp @arguments
    return [pscustomobject]@{status=$response.Status;content=[string]$response.Content;
        etag=(Header $response 'ETag');location=(Header $response 'Location')}
}
# Journal de solicitudes: nunca persiste Authorization, JWT ni contrasenas.
# Una solicitud pendiente se reenvia exactamente con su clave/body/If-Match originales.
function Step([string]$Name,[string]$Uri,[string]$Method='Get',[string]$Actor='EATS_HUB_TOKEN_A',
        [string]$Body='',[string]$Key='',[string]$Match='',[int]$Status=200,[string]$Code='') {
    $intent=[pscustomobject]@{uri=$Uri;method=$Method;actor=$Actor;body=$Body;key=$Key;match=$Match;status=$Status;code=$Code}
    $property=$script:checkpoint.steps.PSObject.Properties[$Name]
    if($null -eq $property){
        $entry=[pscustomobject]@{intent=$intent;response=$null;timestampUtc=$null}
        $script:checkpoint.steps | Add-Member -NotePropertyName $Name -NotePropertyValue $entry
        Save-Checkpoint
    }else{
        $entry=$property.Value
        if(($entry.intent | ConvertTo-Json -Compress) -cne ($intent | ConvertTo-Json -Compress)){
            throw "Checkpoint incompatible con $Name. No se sobrescribe ni se generan otras claves."
        }
    }
    if($null -eq $entry.response){
        # Cada rechazo compara el estado real antes/despues, no solo el estado final.
        if($Status -ge 400){$beforeZone=Fresh $zone;$beforeList=Fresh $shifts}
        $response=Send-Request $Uri $Method $Actor $Body $Key $Match
        Check-Status $response $Status $Name $Code
        if($Status -ge 400){
            $afterZone=Fresh $zone;$afterList=Fresh $shifts
            Same-Reply $beforeZone $afterZone ($Name+' conserva zona')
            Same-Reply $beforeList $afterList ($Name+' conserva turnos')
            $entry | Add-Member -NotePropertyName conservation -NotePropertyValue ([pscustomobject]@{
                zoneBefore=$beforeZone;zoneAfter=$afterZone;shiftsBefore=$beforeList;shiftsAfter=$afterList}) -Force
        }
        $entry.response=$response
        $entry.timestampUtc=[DateTime]::UtcNow.ToString('o')
        Save-Checkpoint
        Write-Host "OK: $Name -> HTTP $Status"
    }else{Write-Host "Checkpoint: $Name ya comprobado -> HTTP $Status"}
    return $entry.response
}
function Body($Response){return ($Response.content | ConvertFrom-Json)}
function Equal-Value($Expected,$Actual,[string]$Name) {
    if(($Expected | ConvertTo-Json -Depth 40 -Compress) -cne ($Actual | ConvertTo-Json -Depth 40 -Compress)){
        throw "$Name : datos distintos. Evita otras escrituras y conserva el checkpoint para revisar."
    }
}
function Check-Revision($Response,[long]$Revision) {
    if([long](Body $Response).revision -ne $Revision -or $Response.etag -cne ('"'+$Revision+'"')){
        throw 'Revision/ETag inesperados: puede haber otras escrituras. No se acredita el recorrido.'
    }
}
function Same-Reply($Expected,$Actual,[string]$Name) {
    Equal-Value $Expected.status $Actual.status $Name
    Equal-Value (Body $Expected) (Body $Actual) $Name
    Equal-Value $Expected.etag $Actual.etag $Name
    Equal-Value $Expected.location $Actual.location $Name
}
function Check-CreatedGet($Created,$Actual) {
    Check-Status $Actual 200 'GET turno creado'
    Equal-Value (Body $Created) (Body $Actual) 'GET turno creado: cuerpo'
    Equal-Value $Created.etag $Actual.etag 'GET turno creado: ETag'
    if($Actual.location){throw 'GET turno creado no debe devolver Location.'}
}

function Payload([string]$Start,[string]$End) {
    return ([ordered]@{localStart=$Start;localEnd=$End} | ConvertTo-Json -Compress)
}
function Zone-Payload([string]$Id) {return ([ordered]@{zoneId=$Id}|ConvertTo-Json -Compress)}
function Fresh([string]$Uri,[string]$Actor='EATS_HUB_TOKEN_A') {
    $reply=Send-Request $Uri 'Get' $Actor '' '' ''
    Check-Status $reply 200 'Lectura actual'
    return $reply
}
function Items($Response) {
    return @((Body $Response).items | Sort-Object id | ForEach-Object {
        $copy=$_.PSObject.Copy();$copy.PSObject.Properties.Remove('revision');$copy
    })
}
function Check-Shift($Reply,[string]$Id,[string]$Start,[string]$End,[string]$ZoneId,[long]$Revision) {
    $value=Body $Reply
    if($value.id -cne $Id -or $value.restaurantId -cne $script:RestaurantA -or
        $value.localStart -cne $Start -or $value.localEnd -cne $End -or $value.zoneId -cne $ZoneId){throw 'Snapshot temporal inesperado.'}
    # Solo se derivan instantes manualmente para Lima/UTC, lejos de cambios estacionales.
    $offset='-05:00';if($ZoneId -ceq 'UTC'){$offset='+00:00'}
    if($ZoneId -notin @('America/Lima','UTC')){throw 'Zona no prevista en la comprobacion de instantes.'}
    $culture=[Globalization.CultureInfo]::InvariantCulture
    $expectedStart=[DateTimeOffset]::Parse(($Start+$offset),$culture)
    $expectedEnd=[DateTimeOffset]::Parse(($End+$offset),$culture)
    Equal-Value $expectedStart.UtcDateTime ([DateTimeOffset]::Parse([string]$value.startInstant,$culture).UtcDateTime) 'Instante inicio'
    Equal-Value $expectedEnd.UtcDateTime ([DateTimeOffset]::Parse([string]$value.endInstant,$culture).UtcDateTime) 'Instante fin'
    Check-Revision $Reply $Revision
}
function Check-Zone($Reply,[string]$ZoneId,[long]$Revision) {
    $value=Body $Reply
    if($value.restaurantId -cne $script:RestaurantA -or $value.zoneId -cne $ZoneId){throw 'Zona inesperada.'}
    Check-Revision $Reply $Revision
}
function Same-OwnState($Final) {
    Same-Reply $Final.zone (Fresh $zone) 'Zona conservada'
    Same-Reply $Final.list (Fresh $shifts) 'Lista de turnos conservada'
    foreach($entry in $Final.resources){Same-Reply $entry.response (Fresh ($shifts+'/'+$entry.id)) 'Turno conservado'}
    Same-Reply $Final.tables (Fresh $tables) 'Mesas conservadas'
    Same-Reply $Final.combinations (Fresh $combinations) 'Combinaciones conservadas'
}

[IO.Directory]::CreateDirectory($script:IdentityPrivate) | Out-Null
$lock=$null
try {
    try{$lock=[IO.File]::Open(($checkpointPath+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch{throw 'Ya hay un recorrido de turnos usando este checkpoint.'}
    if(Test-Path -LiteralPath $checkpointPath){
        $script:checkpoint=[IO.File]::ReadAllText($checkpointPath) | ConvertFrom-Json
        if($script:checkpoint.schemaVersion -ne 1 -or $script:checkpoint.spec -cne 'SPEC-003' -or
            $script:checkpoint.baseUrl -cne $shifts){throw 'Checkpoint ajeno o incompatible; se conserva.'}
    }else{
        if($AfterRestart){throw 'No existe checkpoint; completa primero el recorrido.'}
        if(!$AllowFixtureWrites -or !$AllowZoneChanges){throw 'Requiere -AllowFixtureWrites -AllowZoneChanges: crea 2 turnos y prueba Lima/UTC/Nueva York; termina en Lima.'}
        $year=[DateTime]::UtcNow.Year+2
        $march=[DateTime]::new($year,3,1)
        $november=[DateTime]::new($year,11,1)
        $gap=$march.AddDays(((7-[int]$march.DayOfWeek)%7)+7).ToString('yyyy-MM-dd')
        $overlap=$november.AddDays((7-[int]$november.DayOfWeek)%7).ToString('yyyy-MM-dd')
        $script:checkpoint=[pscustomobject]@{schemaVersion=1;spec='SPEC-003';baseUrl=$shifts;
            runId=[guid]::NewGuid().ToString('N');startedUtc=[DateTime]::UtcNow.ToString('o');
            dates=[pscustomobject]@{first=('{0}-01-15' -f $year);next=('{0}-01-16' -f $year);gap=$gap;overlap=$overlap};
            steps=[pscustomobject]@{};httpCompleted=$false;final=$null;restart=$null}
        Save-Checkpoint
    }
    if($AfterRestart){
        if(!$script:checkpoint.httpCompleted){throw 'Recorrido incompleto; reanuda primero con ambos permisos.'}
        Same-OwnState $script:checkpoint.final
        $script:checkpoint.restart=[pscustomobject]@{timestampUtc=[DateTime]::UtcNow.ToString('o');
            operatorDeclaredRestart=$true;dataAndRevisionPreserved=$true}
        Save-Checkpoint
        Write-Host 'OK: GET 200 tras reinicio declarado; zona, turnos, ambos extremos, revisiones y ETag conservados.'
        Write-Host 'El reinicio es manual; gates, respaldo/restauracion, reversion y cierre siguen pendientes.'
        return
    }
    if($script:checkpoint.httpCompleted){Write-Host 'Recorrido ya terminado. No se crean mas datos; reinicia IntelliJ y usa -AfterRestart.';return}
    if(!$AllowFixtureWrites -or !$AllowZoneChanges){throw 'Para reanudar usa -AllowFixtureWrites -AllowZoneChanges. No borres el checkpoint.'}
    foreach($name in @('EATS_HUB_TOKEN_A','EATS_HUB_TOKEN_B','EATS_HUB_TOKEN_NO_ROLE')){Read-Token $name|Out-Null}
    Write-Host 'Evita otras escrituras en A/B durante el recorrido y hasta comprobar el reinicio.'
    Write-Host 'El ensayo configura temporalmente A en Lima, UTC y Nueva York y termina en Lima; conserva 2 turnos propios.'
    $run=$script:checkpoint.runId;$dates=$script:checkpoint.dates
    $start=$dates.first+'T22:00:00';$end=$dates.next+'T02:00:00'
    $laterEnd=$dates.next+'T03:00:00';$editedStart=$dates.first+'T21:00:00'
    $originalPayload=Payload $start $end;$editPayload=Payload $editedStart $end
    $initialZone=Step 'zona-inicial-A' $zone
    $initialList=Step 'turnos-iniciales-A' $shifts
    $initialTables=Step 'mesas-iniciales-A' $tables
    $initialCombinations=Step 'combinaciones-iniciales-A' $combinations
    $initialOtherZone=Step 'zona-inicial-B' $otherZone -Actor 'EATS_HUB_TOKEN_B'
    $initialOtherList=Step 'turnos-iniciales-B' $otherShifts -Actor 'EATS_HUB_TOKEN_B'
    $v=[long](Body $initialZone).revision
    foreach($r in @($initialList,$initialTables,$initialCombinations)){Check-Revision $r $v}
    if(@((Body $initialList).items).Count -ne 0){throw 'A ya tiene turnos previos: no se modifico la zona ni se crearon fixtures. Revisa el caso sin borrar datos/checkpoint.'}
    $priorZone=(Body $initialZone).zoneId
    if($null -ne $priorZone -and $priorZone -cne 'America/Lima'){throw 'A tiene una zona distinta de Lima. No se cambia su configuracion; conserva checkpoint y revisa antes de continuar.'}
    if($null -eq $priorZone){Write-Host 'A no tenia zona: con el permiso explicito quedara configurada en America/Lima; no existe DELETE de zona.'}
    foreach($uri in @($zone,$shifts)){
        $kind='zona';if($uri -eq $shifts){$kind='turnos'}
        Step ($kind+'-sin-token') $uri -Actor '' -Status 401 -Code 'UNAUTHENTICATED'|Out-Null
        Step ($kind+'-ajeno') $uri -Actor 'EATS_HUB_TOKEN_B' -Status 403 -Code 'FORBIDDEN'|Out-Null
        Step ($kind+'-sin-rol') $uri -Actor 'EATS_HUB_TOKEN_NO_ROLE' -Status 403 -Code 'FORBIDDEN'|Out-Null
    }
    if($null -eq $priorZone){Step 'alta-sin-zona' $shifts -Method Post -Body $originalPayload -Key ($run+'-no-zone') -Status 422 -Code 'VALIDATION_ERROR'|Out-Null}
    Step 'zona-desconocida' $zone -Method Put -Body (Zone-Payload 'Not/AZone') -Key ($run+'-invalid-zone') -Match $initialZone.etag -Status 422 -Code 'VALIDATION_ERROR'|Out-Null
    $configured=Step 'configurar-Lima' $zone -Method Put -Body (Zone-Payload 'America/Lima') -Key ($run+'-zone-lima') -Match $initialZone.etag
    Check-Zone $configured 'America/Lima' ($v+1)
    Same-Reply $configured (Step 'replay-zona' $zone -Method Put -Body (Zone-Payload 'America/Lima') -Key ($run+'-zone-lima') -Match $initialZone.etag) 'Replay zona'
    $created=Step 'alta-medianoche' $shifts -Method Post -Body $originalPayload -Key ($run+'-post') -Status 201
    $id=([guid](Body $created).id).ToString();$resource=$shifts+'/'+$id
    Check-Shift $created $id $start $end 'America/Lima' ($v+2)
    if($created.location -cne ('/catalog/restaurants/'+$script:RestaurantA+'/shifts/'+$id)){throw 'Location incorrecto.'}
    Same-Reply $created (Step 'replay-POST' $shifts -Method Post -Body $originalPayload -Key ($run+'-post') -Status 201) 'Replay POST'
    Check-CreatedGet $created (Step 'GET-turno' $resource)
    $adjacent=Step 'alta-adyacente' $shifts -Method Post -Body (Payload $end $laterEnd) -Key ($run+'-adjacent') -Status 201
    $adjacentId=([guid](Body $adjacent).id).ToString()
    Check-Shift $adjacent $adjacentId $end $laterEnd 'America/Lima' ($v+3)
    foreach($actor in @('','EATS_HUB_TOKEN_B','EATS_HUB_TOKEN_NO_ROLE')){
        $status=403;$code='FORBIDDEN';if(!$actor){$status=401;$code='UNAUTHENTICATED'}
        foreach($kind in @('post','put','zone','get-resource')){
            $uri=$resource;$method='Put';$payload=$editPayload
            if($kind -eq 'post'){$uri=$shifts;$method='Post'}
            if($kind -eq 'zone'){$uri=$zone;$payload=Zone-Payload 'UTC'}
            if($kind -eq 'get-resource'){$method='Get';$payload=''}
            Step ('permiso-'+$kind+'-'+$status+'-'+$actor) $uri -Method $method -Actor $actor -Body $payload -Key ($run+'-perm-'+$kind+'-'+$actor) -Match $adjacent.etag -Status $status -Code $code|Out-Null
        }
    }
    Step 'alta-superpuesta' $shifts -Method Post -Body $originalPayload -Key ($run+'-overlap') -Status 409 -Code 'SHIFT_OVERLAP'|Out-Null
    Step 'duracion-cero' $shifts -Method Post -Body (Payload $start $start) -Key ($run+'-zero') -Status 422 -Code 'VALIDATION_ERROR'|Out-Null
    Step 'inicio-pasado' $shifts -Method Post -Body (Payload '2000-01-01T12:00:00' '2000-01-01T13:00:00') -Key ($run+'-past') -Status 409 -Code 'SHIFT_ALREADY_STARTED'|Out-Null
    Step 'If-Match-ausente' $resource -Method Put -Body $editPayload -Key ($run+'-missing') -Status 400 -Code 'INVALID_REQUEST'|Out-Null
    Step 'If-Match-obsoleto' $resource -Method Put -Body $editPayload -Key ($run+'-stale') -Match $created.etag -Status 412 -Code 'REVISION_MISMATCH'|Out-Null
    Step 'PUT-superpuesto' $resource -Method Put -Body (Payload $end $laterEnd) -Key ($run+'-put-overlap') -Match $adjacent.etag -Status 409 -Code 'SHIFT_OVERLAP'|Out-Null
    $updated=Step 'editar-turno' $resource -Method Put -Body $editPayload -Key ($run+'-put') -Match $adjacent.etag
    Check-Shift $updated $id $editedStart $end 'America/Lima' ($v+4)
    if($updated.location){throw 'PUT no debe devolver Location.'}
    Same-Reply $updated (Step 'replay-PUT' $resource -Method Put -Body $editPayload -Key ($run+'-put') -Match $adjacent.etag) 'Replay PUT'
    Step 'conflicto-clave-POST' $shifts -Method Post -Body $editPayload -Key ($run+'-post') -Status 409 -Code 'IDEMPOTENCY_CONFLICT'|Out-Null
    Step 'conflicto-clave-PUT' $resource -Method Put -Body $originalPayload -Key ($run+'-put') -Match $adjacent.etag -Status 409 -Code 'IDEMPOTENCY_CONFLICT'|Out-Null
    Step 'zona-If-Match-ausente' $zone -Method Put -Body (Zone-Payload 'UTC') -Key ($run+'-zone-missing') -Status 400 -Code 'INVALID_REQUEST'|Out-Null
    Step 'zona-If-Match-obsoleto' $zone -Method Put -Body (Zone-Payload 'UTC') -Key ($run+'-zone-stale') -Match $configured.etag -Status 412 -Code 'REVISION_MISMATCH'|Out-Null
    Step 'zona-conflicto-clave' $zone -Method Put -Body (Zone-Payload 'UTC') -Key ($run+'-zone-lima') -Match $initialZone.etag -Status 409 -Code 'IDEMPOTENCY_CONFLICT'|Out-Null
    $utc=Step 'cambiar-UTC' $zone -Method Put -Body (Zone-Payload 'UTC') -Key ($run+'-utc') -Match $updated.etag
    Check-Zone $utc 'UTC' ($v+5)
    Check-Shift (Step 'GET-recalculado-UTC' $resource) $id $editedStart $end 'UTC' ($v+5)
    Check-Shift (Step 'GET-adyacente-UTC' ($shifts+'/'+$adjacentId)) $adjacentId $end $laterEnd 'UTC' ($v+5)
    $ny=Step 'cambiar-Nueva-York' $zone -Method Put -Body (Zone-Payload 'America/New_York') -Key ($run+'-ny') -Match $utc.etag
    Check-Zone $ny 'America/New_York' ($v+6)
    $invalid=@(
        @{name='gap-inicio';start=($dates.gap+'T02:30:00');end=($dates.gap+'T04:00:00');message='La hora local no existe en la zona del restaurante.'},
        @{name='gap-fin';start=($dates.gap+'T01:00:00');end=($dates.gap+'T02:30:00');message='La hora local no existe en la zona del restaurante.'},
        @{name='repetida-inicio';start=($dates.overlap+'T01:30:00');end=($dates.overlap+'T03:00:00');message='La hora local es ambigua porque se repite en la zona del restaurante.'},
        @{name='repetida-fin';start=($dates.overlap+'T00:30:00');end=($dates.overlap+'T01:30:00');message='La hora local es ambigua porque se repite en la zona del restaurante.'})
    foreach($case in $invalid){
        foreach($method in @('Post','Put')){
            $uri=$shifts;if($method -eq 'Put'){$uri=$resource}
            $reply=Step ($case.name+'-'+$method) $uri -Method $method -Body (Payload $case.start $case.end) -Key ($run+'-'+$case.name+'-'+$method) -Match $ny.etag -Status 422 -Code 'VALIDATION_ERROR'
            Equal-Value $case.message (Body $reply).message 'Explicacion temporal'
        }
    }
    # Volver a Lima es una etapa explicita del journal, nunca una limpieza oculta.
    $restored=Step 'volver-Lima' $zone -Method Put -Body (Zone-Payload 'America/Lima') -Key ($run+'-restore-lima') -Match $ny.etag
    Check-Zone $restored 'America/Lima' ($v+7)
    Same-Reply $created (Step 'replay-POST-historico' $shifts -Method Post -Body $originalPayload -Key ($run+'-post') -Status 201) 'Replay POST historico'
    Same-Reply $updated (Step 'replay-PUT-historico' $resource -Method Put -Body $editPayload -Key ($run+'-put') -Match $adjacent.etag) 'Replay PUT historico'
    Same-Reply $configured (Step 'replay-zona-historico' $zone -Method Put -Body (Zone-Payload 'America/Lima') -Key ($run+'-zone-lima') -Match $initialZone.etag) 'Replay zona historico'
    $finalZone=Fresh $zone;$finalList=Fresh $shifts;$finalTables=Fresh $tables;$finalCombinations=Fresh $combinations
    foreach($r in @($finalZone,$finalList,$finalTables,$finalCombinations)){Check-Revision $r ($v+7)}
    Check-Zone $finalZone 'America/Lima' ($v+7)
    $current=Fresh $resource;$currentAdjacent=Fresh ($shifts+'/'+$adjacentId)
    Check-Shift $current $id $editedStart $end 'America/Lima' ($v+7)
    Check-Shift $currentAdjacent $adjacentId $end $laterEnd 'America/Lima' ($v+7)
    if(@((Body $finalList).items).Count -ne 2){throw 'Cantidad inesperada; no se acredita el recorrido.'}
    Equal-Value @($id,$adjacentId|Sort-Object) @((Body $finalList).items.id|Sort-Object) 'Identidades finales'
    Equal-Value @(Items $initialTables) @(Items $finalTables) 'Mesas previas'
    Equal-Value @(Items $initialCombinations) @(Items $finalCombinations) 'Combinaciones previas'
    Same-Reply $initialOtherZone (Fresh $otherZone 'EATS_HUB_TOKEN_B') 'Zona B sin cambios'
    Same-Reply $initialOtherList (Fresh $otherShifts 'EATS_HUB_TOKEN_B') 'Turnos B sin cambios'
    $script:checkpoint.final=[pscustomobject]@{timestampUtc=[DateTime]::UtcNow.ToString('o');revision=($v+7);
        zone=$finalZone;list=$finalList;tables=$finalTables;combinations=$finalCombinations;
        resources=@([pscustomobject]@{id=$id;response=$current},[pscustomobject]@{id=$adjacentId;response=$currentAdjacent});
        originalZone=$priorZone;finalZone='America/Lima';acceptedWrites=7}
    $script:checkpoint.httpCompleted=$true
    Save-Checkpoint
    Write-Host 'OK: zona y POST/GET/PUT de turnos, permisos, tiempos, If-Match, idempotencia y replay. Datos previos conservados.'
    Write-Host 'Siete escrituras aceptadas; replay y rechazos no incrementaron revision. A queda en Lima con dos turnos del ensayo.'
    Write-Host 'Checkpoint propio sin JWT: secrets/local-identity/shifts-http-checkpoint.json.'
    Write-Host 'Reinicia manualmente Eats Hub en IntelliJ (8082) y ejecuta este script con -AfterRestart.'
    Write-Host 'No se borraron datos. T087, gates, respaldo/restauracion, reversion y cierre siguen pendientes.'
} finally {if($null -ne $lock){$lock.Dispose()}}
