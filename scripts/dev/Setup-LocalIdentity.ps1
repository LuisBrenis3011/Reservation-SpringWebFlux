[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')

function New-IdentityPassword {
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

Push-Location $script:IdentityRoot
try {
    $null = & docker info --format '{{.OSType}}'
    Assert-DockerSuccess 'consultar Docker; iniciar Docker Desktop si no responde'
    $envPath = Join-Path $script:IdentityRoot '.env'
    $applicationEnv = Read-LocalEnv $envPath
    if ($applicationEnv['MONGODB_PORT'] -ne '27018' -or $applicationEnv['MONGODB_HOST'] -notin @('localhost','127.0.0.1')) {
        throw 'Este script solo prepara datos en Mongo local 27018. Revisar MONGODB_HOST/PORT.'
    }
    if ($applicationEnv.ContainsKey('MONGODB_URI') -and ![string]::IsNullOrWhiteSpace($applicationEnv['MONGODB_URI'])) {
        $uri = [Uri]$applicationEnv['MONGODB_URI']
        if ($uri.Host -notin @('localhost','127.0.0.1') -or $uri.Port -ne 27018) {
            throw 'MONGODB_URI apunta fuera del entorno local 27018. No se modifico la conexion.'
        }
    }
    $database = $applicationEnv['MONGODB_DATABASE']
    if ($database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')) {
        throw 'MONGODB_DATABASE no es una base de fixtures permitida.'
    }

    $credentialPath = Join-Path $script:IdentityPrivate 'credentials.json'
    $importPath = Join-Path $script:IdentityPrivate 'import/eats-hub-local-realm.json'
    $volumes = @(& docker volume ls --format '{{.Name}}')
    Assert-DockerSuccess 'consultar volumenes'
    if (!(Test-Path $credentialPath)) {
        if ((Test-Path $importPath) -or $volumes -contains 'eats-identity_keycloak-data') {
            throw 'Existe identidad previa sin archivo de credenciales. Conservar y revisar; no se reemplaza.'
        }
        $accounts = [ordered]@{}
        foreach ($name in @('encargado-a','encargado-b','sin-rol')) { $accounts[$name] = New-IdentityPassword }
        $credentials = [ordered]@{ schemaVersion=1; realm='eats-hub-local'; adminUser='local-admin';
            adminPassword=(New-IdentityPassword); accounts=$accounts }
        Write-PrivateText $credentialPath ($credentials | ConvertTo-Json -Depth 10)
    }
    $credentials = Read-IdentityCredentials
    if ($credentials.schemaVersion -ne 1 -or $credentials.realm -ne 'eats-hub-local') {
        throw 'El archivo de credenciales no pertenece a esta configuracion.'
    }
    Sync-LocalIdentityImport
    $composeEnv = "EATS_IDENTITY_ADMIN_USER=" + $credentials.adminUser + [Environment]::NewLine +
                  "EATS_IDENTITY_ADMIN_PASSWORD=" + $credentials.adminPassword + [Environment]::NewLine
    $composeEnvPath = Join-Path $script:IdentityPrivate 'compose.env'
    if (Test-Path $composeEnvPath) {
        if ([IO.File]::ReadAllText($composeEnvPath) -ne $composeEnv) { throw 'El entorno privado de Keycloak difiere; revisar sin sobrescribir.' }
    } else { Write-PrivateText $composeEnvPath $composeEnv }

    $portOwners = @(& docker ps --filter 'publish=8180' --format '{{.Names}}')
    Assert-DockerSuccess 'consultar puerto 8180'
    if (@($portOwners | Where-Object { $_ -ne 'eats-identity-keycloak-1' }).Count -gt 0) {
        throw '8180 lo utiliza otro contenedor. No se detuvo ni modifico.'
    }
    $compose = @(Get-IdentityComposeArgs)
    & docker @compose config --quiet
    Assert-DockerSuccess 'validar Compose sin mostrar secretos'
    & docker @compose up -d
    Assert-DockerSuccess 'arrancar Keycloak local'

    Write-Host 'Esperando discovery y claves publicas de Keycloak...'
    $ready = $false
    for ($attempt=0; $attempt -lt 90; $attempt++) {
        try {
            $discovery = Invoke-RestMethod -Uri ($script:IdentityIssuer+'/.well-known/openid-configuration') -TimeoutSec 3
            if ($discovery.issuer -eq $script:IdentityIssuer) {
                $keys = Invoke-RestMethod -Uri $discovery.jwks_uri -TimeoutSec 3
                if (@($keys.keys | Where-Object { $_.kty -eq 'RSA' -and $_.use -eq 'sig' }).Count -gt 0) {
                    $ready=$true; break
                }
            }
        } catch { }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'Keycloak no termino de preparar el realm. Revisar logs locales; las rutas no se habilitaron.' }

    & (Join-Path $PSScriptRoot 'Repair-LocalIdentity.ps1')

    Write-Host 'Keycloak listo. Verificando fixtures en el Mongo de 27018...'
    $mongoCompose = @('compose','--env-file',$envPath,'-p','eats-availability','-f',
        (Join-Path $script:IdentityRoot 'src/main/resources/docker-compose.replica.yml'))
    $oldEncoding = $OutputEncoding
    try {
        $OutputEncoding = [Text.UTF8Encoding]::new($false)
        Get-Content -LiteralPath (Join-Path $PSScriptRoot 'seed-local-identity-restaurants.js') -Raw |
            & docker @mongoCompose exec -T -e ("EATS_HUB_SEED_DATABASE="+$database) mongodb-replica mongosh --quiet --port 27018 --file /dev/stdin
        Assert-DockerSuccess 'preparar restaurantes sin sobrescribir datos'
    } finally { $OutputEncoding=$oldEncoding }

    $backupPath=Join-Path $script:IdentityPrivate 'application.env.before-identity'
    if (!(Test-Path $backupPath)) { Copy-Item -LiteralPath $envPath -Destination $backupPath }
    Set-LocalEnvValues $envPath @{
        AVAILABILITY_ISSUER_URI=$script:IdentityIssuer
        AVAILABILITY_JWK_SET_URI=($script:IdentityIssuer+'/protocol/openid-connect/certs')
        AVAILABILITY_AUDIENCE='eats-hub-catalog'
        AVAILABILITY_ENABLED='true'
    }
    Write-Host 'Preparacion terminada. Se conservaron los secretos y los datos anteriores.'
    Write-Host 'Reinicia SpringWebFluxApplication en IntelliJ, manteniendo SERVER_PORT=8082.'
    Write-Host 'Las contrasenas solo estan en secrets/local-identity/credentials.json; no pegarlas en el chat.'
} finally { Pop-Location }
