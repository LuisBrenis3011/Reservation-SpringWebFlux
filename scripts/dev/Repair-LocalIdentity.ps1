[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')

# El archivo importado no actualiza un realm que Keycloak ya conoce.
# Reparar exclusivamente la asociacion del scope mediante la API administrativa.
Sync-LocalIdentityImport
$credentials = Read-IdentityCredentials
$adminToken = $null
$headers = $null
try {
    $adminToken = Invoke-RestMethod -Method Post -Uri 'http://localhost:8180/realms/master/protocol/openid-connect/token' -Body @{
        client_id='admin-cli'; grant_type='password'; username=$credentials.adminUser; password=$credentials.adminPassword
    } -TimeoutSec 10
    $headers = @{ Authorization=('Bearer '+$adminToken.access_token) }
    $adminBase = 'http://localhost:8180/admin/realms/eats-hub-local'
    $clients = Invoke-RestMethod -Uri ($adminBase+'/clients?clientId=eats-hub-cli') -Headers $headers -TimeoutSec 10
    $clients = @($clients | Where-Object { $_.clientId -ceq 'eats-hub-cli' })
    if ($clients.Count -ne 1 -or $clients[0].protocol -ne 'openid-connect') {
        throw 'No se encontro un unico cliente OIDC eats-hub-cli.'
    }
    $scopes = Invoke-RestMethod -Uri ($adminBase+'/client-scopes') -Headers $headers -TimeoutSec 10
    $basic = @($scopes | Where-Object { $_.name -ceq 'basic' -and $_.protocol -eq 'openid-connect' })
    if ($basic.Count -ne 1) { throw 'Falta el scope OIDC basic del realm; no se crean sustitutos.' }
    $clientPath = $adminBase+'/clients/'+[Uri]::EscapeDataString([string]$clients[0].id)+'/default-client-scopes'
    $assigned = Invoke-RestMethod -Uri $clientPath -Headers $headers -TimeoutSec 10
    if (@($assigned | Where-Object { $_.id -eq $basic[0].id }).Count -eq 0) {
        $null = Invoke-RestMethod -Method Put -Uri ($clientPath+'/'+[Uri]::EscapeDataString([string]$basic[0].id)) -Headers $headers -TimeoutSec 10
        Write-Host 'Scope basic asignado a eats-hub-cli.'
    } else { Write-Host 'Scope basic ya estaba asignado; no se modifico el cliente.' }
    $verified = Invoke-RestMethod -Uri $clientPath -Headers $headers -TimeoutSec 10
    if (@($verified | Where-Object { $_.id -eq $basic[0].id }).Count -ne 1) {
        throw 'No se pudo confirmar la asociacion de basic.'
    }
    Write-Host 'Configuracion verificada. Renueva los tres tokens: los anteriores no cambian.'
} catch {
    # Evitar que una respuesta administrativa muestre credenciales o tokens.
    throw 'No se completo la reparacion de identidad. Verifica Keycloak en 8180, las credenciales administrativas locales y la existencia del cliente y scope basic. No se borraron datos; puedes reintentar.'
} finally {
    $headers = $null
    $adminToken = $null
    $credentials = $null
}
