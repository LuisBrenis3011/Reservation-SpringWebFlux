Set-StrictMode -Version Latest

$script:IdentityRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$script:IdentityPrivate = Join-Path $script:IdentityRoot 'secrets/local-identity'
$script:IdentityIssuer = 'http://localhost:8180/realms/eats-hub-local'
$script:RestaurantA = '11111111-1111-4111-8111-111111111111'
$script:RestaurantB = '22222222-2222-4222-8222-222222222222'

function Read-LocalEnv([string]$Path) {
    $values = @{}
    if (!(Test-Path -LiteralPath $Path)) { throw "Falta el archivo local: $Path" }
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_.-]*)\s*=(.*)$') {
            $value = $Matches[2].Trim()
            if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$Matches[1]] = $value
        }
    }
    return $values
}

function Write-PrivateText([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Set-LocalEnvValues([string]$Path, [hashtable]$Values) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadAllLines($Path)) { $lines.Add($line) }
    foreach ($key in $Values.Keys) {
        $indices = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ('^\s*' + [regex]::Escape($key) + '\s*=')) { $indices += $i }
        }
        if ($indices.Count -gt 1) { throw "Clave duplicada en .env: $key. Resolver antes de continuar." }
        if ($indices.Count -eq 1) { $lines[$indices[0]] = $key + '=' + $Values[$key] }
        else { $lines.Add($key + '=' + $Values[$key]) }
    }
    Write-PrivateText $Path (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
}

function Get-IdentityComposeArgs {
    return @('compose', '--env-file', (Join-Path $script:IdentityPrivate 'compose.env'),
        '-p', 'eats-identity', '-f', (Join-Path $script:IdentityRoot 'src/main/resources/docker-compose.identity.yml'))
}

function Assert-DockerSuccess([string]$Action) {
    if ($LASTEXITCODE -ne 0) { throw "Docker no pudo completar: $Action. No se habilitaron las rutas." }
}

function Read-IdentityCredentials {
    $path = Join-Path $script:IdentityPrivate 'credentials.json'
    if (!(Test-Path -LiteralPath $path)) { throw 'Primero ejecutar Setup-LocalIdentity.ps1.' }
    return ([IO.File]::ReadAllText($path) | ConvertFrom-Json)
}

function Sync-LocalIdentityImport {
    $credentials = Read-IdentityCredentials
    if ($credentials.schemaVersion -ne 1 -or $credentials.realm -ne 'eats-hub-local') {
        throw 'El archivo de credenciales no pertenece a esta configuracion.'
    }
    $templatePath = Join-Path $script:IdentityRoot 'src/main/resources/identity/eats-hub-local-realm.template.json'
    $realm = [IO.File]::ReadAllText($templatePath) | ConvertFrom-Json
    foreach ($user in $realm.users) {
        $property = $credentials.accounts.PSObject.Properties[$user.username]
        if ($null -eq $property -or [string]::IsNullOrWhiteSpace($property.Value)) {
            throw 'Faltan credenciales locales; no se reemplazan.'
        }
        $user.credentials = @([pscustomobject]@{type='password'; value=$property.Value; temporary=$false})
    }
    $importPath = Join-Path $script:IdentityPrivate 'import/eats-hub-local-realm.json'
    $expected = $realm | ConvertTo-Json -Depth 50 -Compress
    if (Test-Path -LiteralPath $importPath) {
        $original = [IO.File]::ReadAllText($importPath)
        $existing = $original | ConvertFrom-Json | ConvertTo-Json -Depth 50 -Compress
        if ($existing -ceq $expected) { return }
        # Solo se admite la plantilla anterior exacta, sin basic. Cualquier otra
        # diferencia, incluidas credenciales, se conserva y detiene la operacion.
        $legacy = $expected | ConvertFrom-Json
        $legacy.roles.realm = @($legacy.roles.realm | Where-Object { $_.name -cne 'CUSTOMER' })
        $client = @($legacy.clients | Where-Object { $_.clientId -eq 'eats-hub-cli' })
        if ($client.Count -ne 1) { throw 'La plantilla no identifica un unico cliente local.' }
        $previousWithBasic = $legacy | ConvertTo-Json -Depth 50 -Compress
        $client[0].defaultClientScopes = @($client[0].defaultClientScopes | Where-Object { $_ -ne 'basic' })
        if ($existing -cne $previousWithBasic -and $existing -cne ($legacy | ConvertTo-Json -Depth 50 -Compress)) {
            throw 'La importacion privada tiene diferencias ajenas a basic/CUSTOMER. No se sobrescribio.'
        }
        $backup = Join-Path $script:IdentityPrivate 'import/eats-hub-local-realm.before-basic.json'
        if (!(Test-Path -LiteralPath $backup)) { Write-PrivateText $backup $original }
    }
    Write-PrivateText $importPath ($realm | ConvertTo-Json -Depth 50)
}

function ConvertFrom-JwtPayload([string]$Token) {
    $parts = $Token.Split('.')
    if ($parts.Length -ne 3) { throw 'El proveedor no devolvio un JWT.' }
    $value = $parts[1].Replace('-', '+').Replace('_', '/')
    $value = $value.PadRight([int]([math]::Ceiling($value.Length / 4.0) * 4), '=')
    return ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value)) | ConvertFrom-Json)
}

function Invoke-LocalHttp([string]$Uri, [string]$Method = 'Get', [hashtable]$Headers = @{}, [string]$Body) {
    $request = @{ Uri=$Uri; Method=$Method; Headers=$Headers; UseBasicParsing=$true; TimeoutSec=20; ErrorAction='Stop' }
    if ($PSBoundParameters.ContainsKey('Body')) { $request.Body=$Body; $request.ContentType='application/json' }
    try {
        $response = Invoke-WebRequest @request
        return [pscustomobject]@{ Status=[int]$response.StatusCode; Headers=$response.Headers; Content=$response.Content }
    } catch {
        $failure = $_
        $property = $failure.Exception.PSObject.Properties['Response']
        if ($null -eq $property -or $null -eq $property.Value) { throw "No hay conexion HTTP con $Uri" }
        $response = $property.Value
        $content = ''
        if ($failure.ErrorDetails -and $failure.ErrorDetails.Message) { $content=$failure.ErrorDetails.Message }
        if ([string]::IsNullOrWhiteSpace($content)) {
            try {
                if ($response -is [Net.HttpWebResponse]) {
                    $reader = [IO.StreamReader]::new($response.GetResponseStream())
                    try { $content=$reader.ReadToEnd() } finally { $reader.Dispose() }
                } elseif ($null -ne $response.PSObject.Properties['Content']) {
                    $content=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                }
            } catch { }
        }
        return [pscustomobject]@{ Status=[int]$response.StatusCode; Headers=$response.Headers; Content=$content }
    }
}
