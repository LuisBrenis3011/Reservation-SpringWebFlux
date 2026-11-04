[CmdletBinding()]
param([switch]$AfterRestart)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
$base='http://localhost:8082/catalog/restaurants/'+$script:RestaurantA+'/tables'
$evidencePath=Join-Path $script:IdentityPrivate 'http-validation.json'
$checks=[Collections.Generic.List[object]]::new()

function Check-Response($Response,[int]$Status,[string]$Name,[string]$Code) {
    if ($Response.Status -ne $Status) {
        throw ("$Name : se esperaba HTTP $Status y se recibio "+$Response.Status+
            '. Si mesas devuelve 404 antes de autenticar, reinicia IntelliJ para cargar la configuracion.')
    }
    if (![string]::IsNullOrWhiteSpace($Code)) {
        $errorBody=$Response.Content | ConvertFrom-Json
        if ($errorBody.code -ne $Code) { throw "$Name : codigo de dominio inesperado." }
    }
    $checks.Add([pscustomobject]@{name=$Name;status=$Response.Status;expected=$Status;passed=$true})
    Write-Host ("OK: "+$Name+" -> HTTP "+$Status)
}
function Header-Value($Response,[string]$Name) {
    $value=$Response.Headers[$Name]
    if ($null -eq $value) { throw "Falta cabecera $Name" }
    return [string](@($value)[0])
}
function Same-Table($Left,$Right) {
    foreach($field in @('id','restaurantId','label','capacity','revision')) {
        if ($Left.$field -ne $Right.$field) { throw "El replay altero $field" }
    }
}
function Token-For([string]$Variable) {
    $token=[Environment]::GetEnvironmentVariable($Variable,'Process')
    if ([string]::IsNullOrWhiteSpace($token)) { throw "Falta $Variable en esta terminal. Ejecutar Get-LocalToken.ps1." }
    $claims=ConvertFrom-JwtPayload $token
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ([long]$claims.exp -lt $now+20) { throw "Token de $Variable expirado o por expirar; renovarlo." }
    return $token
}
$manager=@{Authorization='Bearer '+(Token-For 'EATS_HUB_TOKEN_A')}
if ($AfterRestart) {
    if (!(Test-Path $evidencePath)) { throw 'Primero ejecutar la validacion normal.' }
    $previous=[IO.File]::ReadAllText($evidencePath) | ConvertFrom-Json
    $response=Invoke-LocalHttp -Uri ($base+'/'+$previous.table.id) -Headers $manager
    Check-Response $response 200 'GET tras reinicio declarado por el usuario'
    $current=$response.Content | ConvertFrom-Json
    foreach($field in @('id','restaurantId','label','capacity')) {
        if ($current.$field -ne $previous.table.$field) { throw "No se conservo $field tras el reinicio." }
    }
    if ((Header-Value $response 'ETag') -ne ('"'+[string]$current.revision+'"')) { throw 'ETag incoherente.' }
    $result=[ordered]@{timestampUtc=[DateTime]::UtcNow.ToString('o');operatorDeclaredRestart=$true;
        table=$current;checks=$checks.ToArray();note='El script compara datos; el reinicio debe realizarlo el usuario.'}
    Write-PrivateText (Join-Path $script:IdentityPrivate 'restart-validation.json') ($result | ConvertTo-Json -Depth 12)
    Write-Host 'Datos conservados. Este resultado solo acredita reinicio si realmente reiniciaste antes la aplicacion.'
    return
}

$foreign=@{Authorization='Bearer '+(Token-For 'EATS_HUB_TOKEN_B')}
$noRole=@{Authorization='Bearer '+(Token-For 'EATS_HUB_TOKEN_NO_ROLE')}
Check-Response (Invoke-LocalHttp -Uri $base) 401 'Sin token' 'UNAUTHENTICATED'
Check-Response (Invoke-LocalHttp -Uri $base -Headers $foreign) 403 'Encargado ajeno' 'FORBIDDEN'
Check-Response (Invoke-LocalHttp -Uri $base -Headers $noRole) 403 'Usuario sin rol' 'FORBIDDEN'
Check-Response (Invoke-LocalHttp -Uri $base -Headers $manager) 200 'Consulta propia'

$label='Mesa validacion '+[guid]::NewGuid().ToString('N')
$payload=@{label=$label;capacity=4} | ConvertTo-Json -Compress
$createHeaders=@{Authorization=$manager.Authorization;'Idempotency-Key'=[guid]::NewGuid().ToString()}
$created=Invoke-LocalHttp -Uri $base -Method Post -Headers $createHeaders -Body $payload
Check-Response $created 201 'Registrar mesa'
$table=$created.Content | ConvertFrom-Json
if ($table.restaurantId -ne $script:RestaurantA) { throw 'Restaurante incorrecto en el alta.' }
if ((Header-Value $created 'ETag') -ne ('"'+[string]$table.revision+'"')) { throw 'ETag de alta incoherente.' }
$replay=Invoke-LocalHttp -Uri $base -Method Post -Headers $createHeaders -Body $payload
Check-Response $replay 201 'Replay de POST'
Same-Table $table ($replay.Content | ConvertFrom-Json)
foreach($field in @('Location','ETag')) {
    if ((Header-Value $created $field) -ne (Header-Value $replay $field)) { throw "Replay no conserva $field" }
}
$different=@{label=$label+' diferente';capacity=4} | ConvertTo-Json -Compress
Check-Response (Invoke-LocalHttp -Uri $base -Method Post -Headers $createHeaders -Body $different) 409 'Clave con otro payload' 'IDEMPOTENCY_CONFLICT'

$resource=$base+'/'+$table.id
$patchHeaders=@{Authorization=$manager.Authorization;'Idempotency-Key'=[guid]::NewGuid().ToString();'If-Match'=(Header-Value $created 'ETag')}
$patchBody=@{label=$label+' nueva';capacity=6} | ConvertTo-Json -Compress
$patched=Invoke-LocalHttp -Uri $resource -Method Patch -Headers $patchHeaders -Body $patchBody
Check-Response $patched 200 'Actualizar mesa'
$expected=$patched.Content | ConvertFrom-Json
$patchReplay=Invoke-LocalHttp -Uri $resource -Method Patch -Headers $patchHeaders -Body $patchBody
Check-Response $patchReplay 200 'Replay de PATCH'
Same-Table $expected ($patchReplay.Content | ConvertFrom-Json)
if ((Header-Value $patched 'ETag') -ne (Header-Value $patchReplay 'ETag')) { throw 'ETag de replay PATCH distinto.' }
$stale=@{Authorization=$manager.Authorization;'Idempotency-Key'=[guid]::NewGuid().ToString();'If-Match'=$patchHeaders['If-Match']}
Check-Response (Invoke-LocalHttp -Uri $resource -Method Patch -Headers $stale -Body $patchBody) 412 'Revision obsoleta' 'REVISION_MISMATCH'

$invalid=@{Authorization=$manager.Authorization;'Idempotency-Key'=[guid]::NewGuid().ToString()}
Check-Response (Invoke-LocalHttp -Uri $base -Method Post -Headers $invalid -Body '{"label":"X","capacity":4,"unknown":true}') 400 'Campo desconocido' 'INVALID_REQUEST'
$invalid['Idempotency-Key']=[guid]::NewGuid().ToString()
Check-Response (Invoke-LocalHttp -Uri $base -Method Post -Headers $invalid -Body '{"label":"X","capacity":0}') 422 'Capacidad invalida' 'VALIDATION_ERROR'
$invalid['Idempotency-Key']=[guid]::NewGuid().ToString()
Check-Response (Invoke-LocalHttp -Uri $base -Method Post -Headers $invalid -Body $patchBody) 409 'Etiqueta duplicada' 'DUPLICATE_LABEL'
Check-Response (Invoke-LocalHttp -Uri ($base+'/00000000-0000-4000-8000-000000000000') -Headers $manager) 404 'Mesa inexistente' 'NOT_FOUND'
$last=Invoke-LocalHttp -Uri $resource -Headers $manager
Check-Response $last 200 'Consultar mesa actualizada'
$final=$last.Content | ConvertFrom-Json
Same-Table $expected $final
if ((Header-Value $last 'ETag') -ne ('"'+[string]$final.revision+'"')) { throw 'ETag final incoherente.' }
$evidence=[ordered]@{timestampUtc=[DateTime]::UtcNow.ToString('o');baseUrl=$base;table=$final;
    checks=$checks.ToArray();restartVerified=$false;note='Solo IDs tecnicos; sin JWT ni contrasenas.'}
Write-PrivateText $evidencePath ($evidence | ConvertTo-Json -Depth 12)
Write-Host 'Validacion HTTP terminada. Reinicia manualmente en IntelliJ y ejecuta este script con -AfterRestart.'
