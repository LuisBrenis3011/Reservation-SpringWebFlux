[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
$baselinePath=Join-Path $script:IdentityPrivate 'http-validation.json'
$gatePath=Join-Path $script:IdentityPrivate 'gate-enabled-validation.json'
if (!(Test-Path $baselinePath) -or !(Test-Path $gatePath)) { throw 'Primero completar HTTP y las dos etapas del gate.' }
$baseline=Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$gate=Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json
if ($gate.stage -ne 'Enabled' -or $gate.tableId -ne $baseline.table.id -or
    $gate.baselineTimestampUtc -ne $baseline.timestampUtc -or @($gate.checks | Where-Object {!$_.passed}).Count) {
    throw 'Evidencia del gate incompatible con la mesa original.'
}
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env')
if ($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018' -or
    ($values.ContainsKey('MONGODB_URI') -and ![string]::IsNullOrWhiteSpace($values['MONGODB_URI']))) { throw 'Configuracion de Mongo no compatible con este recorrido local.' }
$database=$values['MONGODB_DATABASE']
if ($database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')) { throw 'Base no permitida.' }
$token=$env:EATS_HUB_TOKEN_A
if ([string]::IsNullOrWhiteSpace($token)) { throw 'Obten un token de encargado-a en esta terminal.' }
$claims=ConvertFrom-JwtPayload $token
if ([long]$claims.exp -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+20) { throw 'Token expirado; renueva encargado-a.' }
$source='eats-availability-mongodb-replica-1'
function Read-ReplayInput([string]$File) {
    $oldEncoding=$OutputEncoding
    try {
        $OutputEncoding=[Text.UTF8Encoding]::new($false)
        $output=Get-Content -LiteralPath (Join-Path $PSScriptRoot $File) -Raw |
            & docker exec -i -e ("EATS_BACKUP_DATABASE="+$database) -e 'EATS_BACKUP_SOURCE=true' -e ("EATS_REPLAY_TABLE="+$baseline.table.id) $source mongosh --quiet --port 27018 --file /dev/stdin
        Assert-DockerSuccess 'leer comprobacion local de replay'
        return (($output -join "`n") | ConvertFrom-Json)
    } finally { $OutputEncoding=$oldEncoding }
}
function Assert-ReplayTable($Expected,$Actual) {
    foreach($field in @('id','restaurantId','label','capacity','revision')) {
        if ($Expected.$field -ne $Actual.$field) { throw "Valor inesperado de $field; no se acredita replay." }
    }
}
function Replay-Header($Response,[string]$Name) {
    $value=$Response.Headers[$Name]
    if ($null -eq $value) { throw "Falta $Name" }
    return [string](@($value)[0])
}
$base='http://localhost:8082/catalog/restaurants/'+$script:RestaurantA+'/tables'
$headers=@{Authorization=('Bearer '+$token)}
Write-Host 'Comprobando el recibo original y la mesa actual; evita otras escrituras durante este recorrido.'
$before=Read-ReplayInput 'mongo-backup-manifest.js'
$receipt=Read-ReplayInput 'read-local-replay-receipt.js'
$current=Invoke-LocalHttp -Uri ($base+'/'+$baseline.table.id) -Headers $headers
if($current.Status -ne 200){throw 'No se pudo consultar la mesa; comprueba app en 8082 y token.'}
Assert-ReplayTable $baseline.table ($current.Content | ConvertFrom-Json)
$headers['Idempotency-Key']=$receipt.key
$response=Invoke-LocalHttp -Uri $base -Method Post -Headers $headers -Body $receipt.requestBody
if($response.Status -ne 201){throw ('Replay esperaba 201 y recibio '+$response.Status)}
Assert-ReplayTable $receipt.expected ($response.Content | ConvertFrom-Json)
if ((Replay-Header $response 'Location') -ne $receipt.location -or
    (Replay-Header $response 'ETag') -ne ('"'+[string]$receipt.expected.revision+'"')) { throw 'Replay no conserva Location/ETag original.' }
$currentAfter=Invoke-LocalHttp -Uri ($base+'/'+$baseline.table.id) -Headers @{Authorization=('Bearer '+$token)}
if($currentAfter.Status -ne 200){throw 'No se pudo consultar la mesa despues del replay.'}
Assert-ReplayTable $baseline.table ($currentAfter.Content | ConvertFrom-Json)
if((Replay-Header $currentAfter 'ETag') -ne (Replay-Header $current 'ETag')){throw 'Replay cambio el ETag actual.'}
$after=Read-ReplayInput 'mongo-backup-manifest.js'
if (($before | ConvertTo-Json -Depth 30 -Compress) -cne ($after | ConvertTo-Json -Depth 30 -Compress)) {
    throw 'Hubo cambios en Mongo durante el replay; conserva los datos y revisa antes de acreditar el resultado.'
}
$evidence=[ordered]@{timestampUtc=[DateTime]::UtcNow.ToString('o');tableId=$baseline.table.id;
    baselineTimestampUtc=$baseline.timestampUtc;gateTimestampUtc=$gate.timestampUtc;
    replayStatus=201;originalBodyLocationEtagPreserved=$true;currentTableAndRevisionUnchanged=$true;
    databaseManifestUnchanged=$true;note='Recibo POST original leido en memoria. Sin JWT ni clave de idempotencia en evidencia.'}
Write-PrivateText (Join-Path $script:IdentityPrivate 'receipt-replay-validation.json') ($evidence | ConvertTo-Json -Depth 10)
$receipt=$null
$headers=$null
Write-Host 'OK: replay original HTTP 201, cuerpo/Location/ETag originales y mesa actual sin cambios.'
Write-Host 'OK: Mongo conserva documentos, revisiones, recibos e indices durante el recorrido.'
