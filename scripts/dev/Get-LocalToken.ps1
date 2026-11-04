[CmdletBinding()]
param(
    [ValidateSet('encargado-a','encargado-b','sin-rol','cliente-a','cliente-b','cliente-dual')][string]$User='encargado-a',
    [switch]$CopyPassword,
    [switch]$NoBrowser
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
$credentials=Read-IdentityCredentials
if($null -eq $credentials.accounts.PSObject.Properties[$User]){throw 'Falta preparar este usuario. Ejecuta Setup-LocalReservationIdentity.ps1 cuando corresponda; no se alteraron tokens anteriores.'}
if ($CopyPassword) {
    Set-Clipboard -Value $credentials.accounts.PSObject.Properties[$User].Value
    Write-Host 'Contrasena de este usuario copiada al portapapeles local; no se imprimio.'
}
$discovery=Invoke-RestMethod -Uri ($script:IdentityIssuer+'/.well-known/openid-configuration') -TimeoutSec 10
if ($discovery.issuer -ne $script:IdentityIssuer) { throw 'Emisor inesperado.' }
$device=Invoke-RestMethod -Method Post -Uri $discovery.device_authorization_endpoint -Body @{
    client_id='eats-hub-cli'; scope='openid profile'
} -TimeoutSec 10
Write-Host ("Inicia sesion como: "+$User)
Write-Host ("Abre esta direccion local: "+$device.verification_uri_complete)
if (!$NoBrowser) {
    $edgePaths=@(
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft/Edge/Application/msedge.exe'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Microsoft/Edge/Application/msedge.exe')
    )
    $edge=$edgePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($edge) {
        Write-Host 'Se abre Edge en privado. Cierra esa ventana al terminar para cambiar de usuario.'
        Start-Process -FilePath $edge -ArgumentList @('--inprivate','--new-window',$device.verification_uri_complete) | Out-Null
    } else {
        Write-Host 'Abre la direccion indicada en una ventana privada para evitar reutilizar otra cuenta.'
    }
}
$deadline=[DateTime]::UtcNow.AddSeconds([Math]::Min([int]$device.expires_in,600))
$interval=[Math]::Max(1,[int]$device.interval)
$token=$null
while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Seconds $interval
    try {
        $token=Invoke-RestMethod -Method Post -Uri $discovery.token_endpoint -Body @{
            client_id='eats-hub-cli'; grant_type='urn:ietf:params:oauth:grant-type:device_code'; device_code=$device.device_code
        } -TimeoutSec 10
        break
    } catch {
        $errorCode='unknown'
        try { $errorCode=($_.ErrorDetails.Message | ConvertFrom-Json).error } catch { }
        if ($errorCode -eq 'authorization_pending') { continue }
        if ($errorCode -eq 'slow_down') { $interval+=5; continue }
        throw ("No se obtuvo token. Estado del proveedor: "+$errorCode)
    }
}
if ($null -eq $token) { throw 'Expiro la autorizacion del dispositivo; vuelve a ejecutar el comando.' }
# Esta lectura sirve de comprobacion local; la firma la valida Eats Hub con JWK.
$claims=ConvertFrom-JwtPayload $token.access_token
$subjectProperty=$claims.PSObject.Properties['sub']
if ($null -eq $subjectProperty -or [string]::IsNullOrWhiteSpace([string]$subjectProperty.Value)) {
    throw 'El token no contiene sub (identificador del usuario). Ejecuta Repair-LocalIdentity.ps1 y solicita un token nuevo. No se guardo este token.'
}
$isCustomer=$User -in @('cliente-a','cliente-b','cliente-dual')
$expectedOwner=if($User -eq 'encargado-b') {$script:RestaurantB} else {$script:RestaurantA}
if ($claims.iss -ne $script:IdentityIssuer -or $claims.preferred_username -ne $User -or
    @($claims.aud) -notcontains 'eats-hub-catalog') {
    throw 'El token no corresponde al usuario o restaurante esperado. Cambia de cuenta en el navegador y repite.'
}
$roleProperty=$claims.PSObject.Properties['roles']
$roles=if($null -eq $roleProperty) {@()} else {@($roleProperty.Value)}
$isManager=$roles -contains 'RESTAURANT_MANAGER'
if (($isCustomer -and $roles -notcontains 'CUSTOMER') -or
    ($User -in @('sin-rol','cliente-a','cliente-b') -and $isManager) -or
    ($User -in @('encargado-a','encargado-b','cliente-dual') -and !$isManager)) {
    throw 'Los roles del token no coinciden con la configuracion local.'
}
if($isManager -or $User -eq 'sin-rol'){
    $ownerClaim=$claims.PSObject.Properties['restaurant_ids']
    if($null -eq $ownerClaim -or @($ownerClaim.Value) -notcontains $expectedOwner){throw 'Falta el restaurante esperado; no se guardo el token.'}
}
$variable=switch($User) {
    'encargado-a' {'EATS_HUB_TOKEN_A'}
    'encargado-b' {'EATS_HUB_TOKEN_B'}
    'sin-rol' {'EATS_HUB_TOKEN_NO_ROLE'}
    'cliente-a' {'EATS_HUB_TOKEN_CUSTOMER_A'}
    'cliente-b' {'EATS_HUB_TOKEN_CUSTOMER_B'}
    'cliente-dual' {'EATS_HUB_TOKEN_DUAL'}
}
[Environment]::SetEnvironmentVariable($variable,[string]$token.access_token,'Process')
if ($User -eq 'encargado-a') {
    $env:EATS_HUB_MANAGER_TOKEN=[string]$token.access_token
    $env:EATS_HUB_RESTAURANT_ID=$script:RestaurantA
}
Write-Host ("Token guardado solo en esta terminal: "+$variable+". No se imprimio ni escribio en disco.")
Write-Host 'Para cambiar de usuario, cierra la sesion de Keycloak o usa una ventana privada.'
