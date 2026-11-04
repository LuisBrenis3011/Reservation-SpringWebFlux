[CmdletBinding()]
param([switch]$AllowFixtureWrites,[switch]$AfterRestart)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
$root='http://localhost:8082/catalog/restaurants/'
$tables=$root+$script:RestaurantA+'/tables'
$combinations=$root+$script:RestaurantA+'/table-combinations'
$other=$root+$script:RestaurantB+'/table-combinations'
$checkpointPath=Join-Path $script:IdentityPrivate 'combinations-http-checkpoint.json'

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
        $response=Send-Request $Uri $Method $Actor $Body $Key $Match
        Check-Status $response $Status $Name $Code
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
function Combination($Response,[string]$Id,[object[]]$Members,[long]$Capacity,[long]$Revision) {
    $value=Body $Response
    if($value.id -ne $Id -or $value.restaurantId -ne $script:RestaurantA -or [long]$value.capacity -ne $Capacity){
        throw 'No se conservaron identidad, propietario o capacidad derivada.'
    }
    Equal-Value @($Members | Sort-Object) @($value.tableIds | Sort-Object) 'Integrantes'
    Check-Revision $Response $Revision
}
function Item-Snapshot($Response,[string]$Kind) {
    $items=(Body $Response).items
    return @($items | Sort-Object id | ForEach-Object {
        if($Kind -eq 'tables'){
            [pscustomobject]@{id=$_.id;restaurantId=$_.restaurantId;label=$_.label;capacity=$_.capacity}
        }else{
            [pscustomobject]@{id=$_.id;restaurantId=$_.restaurantId;tableIds=@($_.tableIds | Sort-Object);capacity=$_.capacity}
        }
    })
}

[IO.Directory]::CreateDirectory($script:IdentityPrivate) | Out-Null
$lock=$null
try {
    try{$lock=[IO.File]::Open(($checkpointPath+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch{throw 'Ya hay un recorrido de combinaciones usando este checkpoint. No ejecutes dos a la vez.'}
    if(Test-Path -LiteralPath $checkpointPath){
        $script:checkpoint=[IO.File]::ReadAllText($checkpointPath) | ConvertFrom-Json
        if($script:checkpoint.schemaVersion -ne 1 -or $script:checkpoint.spec -cne 'SPEC-002' -or
            $script:checkpoint.baseUrl -cne $combinations){throw 'Checkpoint ajeno o incompatible; se conserva sin modificar.'}
    }else{
        if($AfterRestart){throw 'Primero completa el recorrido normal; no existe checkpoint de combinaciones.'}
        if(!$AllowFixtureWrites){throw 'El recorrido crea 3 mesas y 2 combinaciones. Usa -AllowFixtureWrites para ejecutarlo manualmente.'}
        $script:checkpoint=[pscustomobject]@{schemaVersion=1;spec='SPEC-002';baseUrl=$combinations;
            runId=[guid]::NewGuid().ToString('N');startedUtc=[DateTime]::UtcNow.ToString('o');
            steps=[pscustomobject]@{};httpCompleted=$false;final=$null;restart=$null}
        Save-Checkpoint
    }
    if($AfterRestart){
        if(!$script:checkpoint.httpCompleted){throw 'Recorrido HTTP incompleto. Reanuda primero con -AllowFixtureWrites.'}
        $final=$script:checkpoint.final
        $current=Send-Request ($combinations+'/'+$final.combinationId) 'Get' 'EATS_HUB_TOKEN_A' '' '' ''
        Check-Status $current 200 'GET tras reinicio declarado por el usuario'
        Same-Reply $final.resource $current 'Combinacion tras reinicio'
        $list=Send-Request $combinations 'Get' 'EATS_HUB_TOKEN_A' '' '' ''
        Check-Status $list 200 'Coleccion tras reinicio'
        Check-Revision $list $final.revision
        Equal-Value @($final.combinations) @(Item-Snapshot $list 'combinations') 'Coleccion conservada'
        $tableList=Send-Request $tables 'Get' 'EATS_HUB_TOKEN_A' '' '' ''
        Check-Status $tableList 200 'Mesas tras reinicio'
        Check-Revision $tableList $final.revision
        Equal-Value @($final.tables) @(Item-Snapshot $tableList 'tables') 'Mesas conservadas'
        $script:checkpoint.restart=[pscustomobject]@{timestampUtc=[DateTime]::UtcNow.ToString('o');
            operatorDeclaredRestart=$true;dataAndRevisionPreserved=$true;note='El usuario debe haber reiniciado realmente IntelliJ.'}
        Save-Checkpoint
        Write-Host 'OK: GET HTTP 200 tras reinicio declarado; misma combinacion, mesas, capacidad, revision y ETag.'
        Write-Host 'El reinicio es manual. Gates, respaldo/restauracion, reversion y cierre siguen pendientes.'
        return
    }
    if($script:checkpoint.httpCompleted){
        Write-Host 'Este recorrido ya termino. No se crean mas datos. Reinicia IntelliJ y usa -AfterRestart.'
        return
    }
    if(!$AllowFixtureWrites){throw 'Para reanudar el mismo recorrido usa -AllowFixtureWrites; no borres el checkpoint.'}
    foreach($variable in @('EATS_HUB_TOKEN_A','EATS_HUB_TOKEN_B','EATS_HUB_TOKEN_NO_ROLE')){Read-Token $variable | Out-Null}
    Write-Host 'Evita otras escrituras en A/B hasta terminar el recorrido y la comprobacion tras reinicio.'
    $run=$script:checkpoint.runId
    Step 'sin-token' $combinations -Actor '' -Status 401 -Code 'UNAUTHENTICATED' | Out-Null
    Step 'encargado-ajeno' $combinations -Actor 'EATS_HUB_TOKEN_B' -Status 403 -Code 'FORBIDDEN' | Out-Null
    Step 'sin-rol' $combinations -Actor 'EATS_HUB_TOKEN_NO_ROLE' -Status 403 -Code 'FORBIDDEN' | Out-Null
    $initial=Step 'lista-inicial-A' $combinations
    $initialTables=Step 'mesas-iniciales-A' $tables
    $initialB=Step 'lista-inicial-B' $other -Actor 'EATS_HUB_TOKEN_B'
    $version=[long](Body $initial).revision
    Check-Revision $initial $version
    Check-Revision $initialTables $version
    $ids=@()
    $capacities=@(4,2,3)
    for($i=0;$i -lt 3;$i++){
        $payload=@{label=('SPEC002 '+$run+' '+($i+1));capacity=$capacities[$i]} | ConvertTo-Json -Compress
        $table=Step ('mesa-'+$i) $tables -Method Post -Body $payload -Key ($run+'-mesa-'+$i) -Status 201
        Check-Revision $table ($version+$i+1)
        $value=Body $table
        if($value.restaurantId -ne $script:RestaurantA -or [long]$value.capacity -ne $capacities[$i] -or $value.label -cne ('SPEC002 '+$run+' '+($i+1))){throw 'Fixture de mesa inesperada.'}
        $ids+=([guid]$value.id).ToString()
    }
    $ab=@{tableIds=@($ids[0],$ids[1])} | ConvertTo-Json -Compress
    $ba=@{tableIds=@($ids[1],$ids[0])} | ConvertTo-Json -Compress
    $bc=@{tableIds=@($ids[1],$ids[2])} | ConvertTo-Json -Compress
    $ac=@{tableIds=@($ids[0],$ids[2])} | ConvertTo-Json -Compress
    $ca=@{tableIds=@($ids[2],$ids[0])} | ConvertTo-Json -Compress
    $created=Step 'crear-AB' $combinations -Method Post -Body $ab -Key ($run+'-post-AB') -Status 201
    $id=([guid](Body $created).id).ToString()
    $resource=$combinations+'/'+$id
    Combination $created $id @($ids[0],$ids[1]) 6 ($version+4)
    if(!$created.location.EndsWith('/restaurants/'+$script:RestaurantA+'/table-combinations/'+$id)){throw 'Location de alta incorrecta.'}
    $replay=Step 'replay-POST' $combinations -Method Post -Body $ab -Key ($run+'-post-AB') -Status 201
    Same-Reply $created $replay 'Replay POST'
    $second=Step 'crear-BC' $combinations -Method Post -Body $bc -Key ($run+'-post-BC') -Status 201
    $secondId=([guid](Body $second).id).ToString()
    Combination $second $secondId @($ids[1],$ids[2]) 5 ($version+5)
    Step 'duplicado-POST' $combinations -Method Post -Body $ba -Key ($run+'-duplicate-post') -Status 409 -Code 'DUPLICATE_COMBINATION' | Out-Null
    foreach($actor in @('','EATS_HUB_TOKEN_B','EATS_HUB_TOKEN_NO_ROLE')){
        $status=403; $code='FORBIDDEN'; if(!$actor){$status=401;$code='UNAUTHENTICATED'}
        foreach($method in @('Post','Put')){
            $uri=$combinations; if($method -eq 'Put'){$uri=$resource}
            Step ('permiso-'+$method+'-'+$status+'-'+$actor) $uri -Method $method -Actor $actor -Body $ac -Key ($run+'-permission-'+$method+'-'+$actor) -Match $second.etag -Status $status -Code $code | Out-Null
        }
    }
    $updated=Step 'reemplazar-AC' $resource -Method Put -Body $ac -Key ($run+'-put-AC') -Match $second.etag
    Combination $updated $id @($ids[0],$ids[2]) 7 ($version+6)
    if($updated.location){throw 'PUT no debe emitir Location de alta.'}
    $putReplay=Step 'replay-PUT' $resource -Method Put -Body $ac -Key ($run+'-put-AC') -Match $second.etag
    Same-Reply $updated $putReplay 'Replay PUT'
    $equivalent=Step 'PUT-equivalente' $resource -Method Put -Body $ca -Key ($run+'-put-equivalent') -Match $updated.etag
    Combination $equivalent $id @($ids[0],$ids[2]) 7 ($version+7)
    Step 'duplicado-PUT' $resource -Method Put -Body $bc -Key ($run+'-duplicate-put') -Match $equivalent.etag -Status 409 -Code 'DUPLICATE_COMBINATION' | Out-Null
    Step 'If-Match-obsoleto' $resource -Method Put -Body $ac -Key ($run+'-stale') -Match $second.etag -Status 412 -Code 'REVISION_MISMATCH' | Out-Null
    Step 'If-Match-ausente' $resource -Method Put -Body $ac -Key ($run+'-missing-match') -Status 400 -Code 'INVALID_REQUEST' | Out-Null
    Step 'conflicto-clave-PUT' $resource -Method Put -Body $bc -Key ($run+'-put-AC') -Match $second.etag -Status 409 -Code 'IDEMPOTENCY_CONFLICT' | Out-Null
    Step 'conflicto-clave-POST' $combinations -Method Post -Body $ac -Key ($run+'-post-AB') -Status 409 -Code 'IDEMPOTENCY_CONFLICT' | Out-Null
    $latePost=Step 'replay-POST-tras-PUT' $combinations -Method Post -Body $ab -Key ($run+'-post-AB') -Status 201
    Same-Reply $created $latePost 'Replay POST historico'
    $latePut=Step 'replay-PUT-tras-otro-write' $resource -Method Put -Body $ac -Key ($run+'-put-AC') -Match $second.etag
    Same-Reply $updated $latePut 'Replay PUT historico'
    # Lecturas finales siempre nuevas, incluso al reanudar un ensayo parcial.
    $current=Send-Request $resource 'Get' 'EATS_HUB_TOKEN_A' '' '' ''
    Check-Status $current 200 'Consulta final'
    Same-Reply $equivalent $current 'Rechazos y replay no alteran recurso/revision'
    $list=Send-Request $combinations 'Get' 'EATS_HUB_TOKEN_A' '' '' ''
    $tableList=Send-Request $tables 'Get' 'EATS_HUB_TOKEN_A' '' '' ''
    $otherList=Send-Request $other 'Get' 'EATS_HUB_TOKEN_B' '' '' ''
    Check-Status $list 200 'Lista final A'; Check-Revision $list ($version+7)
    Check-Status $tableList 200 'Mesas finales A'; Check-Revision $tableList ($version+7)
    Check-Status $otherList 200 'Lista final B'
    Same-Reply $initialB $otherList 'Restaurante B sin cambios'
    $all=@(Item-Snapshot $list 'combinations')
    $allTables=@(Item-Snapshot $tableList 'tables')
    $prior=@($all | Where-Object {$_.id -notin @($id,$secondId)})
    Equal-Value @(Item-Snapshot $initial 'combinations') $prior 'Combinaciones previas conservadas'
    Equal-Value @(Item-Snapshot $initialTables 'tables') @($allTables | Where-Object {$_.id -notin $ids}) 'Mesas previas conservadas'
    if($all.Count -ne @(Item-Snapshot $initial 'combinations').Count+2 -or $allTables.Count -ne @(Item-Snapshot $initialTables 'tables').Count+3){throw 'Cantidad inesperada de fixtures.'}
    $secondCurrent=Send-Request ($combinations+'/'+$secondId) 'Get' 'EATS_HUB_TOKEN_A' '' '' ''
    Check-Status $secondCurrent 200 'Segunda combinacion conservada'
    Combination $secondCurrent $secondId @($ids[1],$ids[2]) 5 ($version+7)
    $script:checkpoint.final=[pscustomobject]@{timestampUtc=[DateTime]::UtcNow.ToString('o');combinationId=$id;
        revision=($version+7);resource=$current;combinations=$all;tables=$allTables;
        note='Siete writes aceptados: tres mesas, dos altas y dos PUT. Replay y rechazos no incrementan revision.'}
    $script:checkpoint.httpCompleted=$true
    Save-Checkpoint
    Write-Host 'OK: POST/GET/PUT, permisos, duplicados, If-Match, idempotencia, replay y datos previos conservados.'
    Write-Host 'Checkpoint propio guardado en secrets/local-identity/combinations-http-checkpoint.json; sin JWT.'
    Write-Host 'Reinicia manualmente Eats Hub en IntelliJ (8082) y ejecuta este script con -AfterRestart.'
    Write-Host 'No se borraron fixtures. T060 y el cierre siguen pendientes hasta revisar evidencia.'
} finally {if($null -ne $lock){$lock.Dispose()}}
