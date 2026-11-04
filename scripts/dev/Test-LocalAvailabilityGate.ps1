[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Disabled','Enabled')][string]$Stage)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
$baselinePath=Join-Path $script:IdentityPrivate 'http-validation.json'
if (!(Test-Path -LiteralPath $baselinePath)) { throw 'Falta el recorrido HTTP previo; no se crearan mesas.' }
$baseline=Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
if ($baseline.table.restaurantId -ne $script:RestaurantA) { throw 'La evidencia no pertenece al restaurante de prueba A.' }
$root='http://localhost:8082/catalog'
$tables=$root+'/restaurants/'+$script:RestaurantA+'/tables'
$checks=[Collections.Generic.List[object]]::new()
function Check-GateResponse($Response,[int]$Expected,[string]$Name) {
    if ($Response.Status -ne $Expected) { throw "$Name : se esperaba HTTP $Expected y se recibio $($Response.Status). Revisa el gate y reinicia IntelliJ." }
    $checks.Add([pscustomobject]@{name=$Name;status=$Response.Status;passed=$true})
    Write-Host ("OK: $Name -> HTTP $Expected")
}
$disabledPath=Join-Path $script:IdentityPrivate 'gate-disabled-validation.json'
if ($Stage -eq 'Enabled') {
    if (!(Test-Path -LiteralPath $disabledPath)) { throw 'Primero verificar Disabled despues de desactivar y reiniciar.' }
    $disabled=Get-Content -LiteralPath $disabledPath -Raw | ConvertFrom-Json
    if ($disabled.baselineTimestampUtc -ne $baseline.timestampUtc -or $disabled.tableId -ne $baseline.table.id) {
        throw 'La evidencia Disabled corresponde a otro recorrido. Repite el ciclo usando la misma mesa.'
    }
    $token=$env:EATS_HUB_TOKEN_A
    if ([string]::IsNullOrWhiteSpace($token)) { throw 'Obten un token de encargado-a en esta PowerShell.' }
    $claims=ConvertFrom-JwtPayload $token
    if ([long]$claims.exp -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+20) { throw 'Token expirado: renueva encargado-a.' }
}
Check-GateResponse (Invoke-LocalHttp -Uri ($root+'/restaurants')) 200 'Catalogo antiguo accesible'
if ($Stage -eq 'Disabled') {
    Check-GateResponse (Invoke-LocalHttp -Uri $tables) 404 'Coleccion de mesas oculta'
    Check-GateResponse (Invoke-LocalHttp -Uri ($tables+'/'+$baseline.table.id)) 404 'Mesa oculta'
} else {
    Check-GateResponse (Invoke-LocalHttp -Uri $tables) 401 'Autenticacion requerida al reactivar'
    $response=Invoke-LocalHttp -Uri ($tables+'/'+$baseline.table.id) -Headers @{Authorization=('Bearer '+$token)}
    Check-GateResponse $response 200 'Mesa recuperada al reactivar'
    $current=$response.Content | ConvertFrom-Json
    foreach($field in @('id','restaurantId','label','capacity','revision')) {
        if ($current.$field -ne $baseline.table.$field) { throw "Se altero $field durante el ciclo de gate." }
    }
    $etag=$response.Headers['ETag']
    if ($null -eq $etag -or [string](@($etag)[0]) -ne ('"'+[string]$current.revision+'"')) { throw 'ETag incoherente.' }
    Write-Host 'Misma mesa, datos y revision; ETag coherente.'
}
$result=[ordered]@{timestampUtc=[DateTime]::UtcNow.ToString('o');stage=$Stage;
    baselineTimestampUtc=$baseline.timestampUtc;tableId=$baseline.table.id;checks=$checks.ToArray();
    note='Solo GET. No acredita rutas antiguas de escritura, conservacion de recibos, respaldo/restauracion ni reversion de version.'}
$outputPath=if($Stage -eq 'Disabled') {$disabledPath} else {Join-Path $script:IdentityPrivate 'gate-enabled-validation.json'}
Write-PrivateText $outputPath ($result | ConvertTo-Json -Depth 10)
Write-Host 'Comprobacion registrada. El usuario debe cambiar el gate y reiniciar manualmente entre etapas.'
