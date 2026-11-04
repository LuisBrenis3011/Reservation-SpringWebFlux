[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BackupDirectory,
      [Parameter(Mandatory=$true)][string]$BridgeEvidence,[switch]$WritersStopped,[switch]$Apply)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Common.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Review.ps1')
function Get-BridgeHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
$script:BridgeCutoverCatalogPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../specs/005-confirmar-reserva/contracts/bridge-catalog.md'))
$script:BridgeCutoverScriptRoot=$PSScriptRoot
function Assert-CutoverBridgeEvidence([string]$EvidencePath,[string]$ExpectedHash='',[string]$ExpectedCatalogHash='') {
    Assert-BridgeText $EvidencePath 'BridgeEvidence'
    $file=Get-Item -LiteralPath $EvidencePath -Force -ErrorAction Stop
    if($file.PSIsContainer -or $file.Name -cne 'bridge-evidence.json'){throw 'Se requiere bridge-evidence.json v2 revisado.'}
    $root=$file.Directory.FullName
    $hash=Get-BridgeHash (Get-BridgeSafeFile $root 'bridge-evidence.json')
    if($ExpectedHash -and $hash -ine $ExpectedHash){throw 'BridgeEvidence cambio entre preflight y Apply.'}
    $catalogHash=Get-BridgeHash $script:BridgeCutoverCatalogPath
    if($ExpectedCatalogHash -and $catalogHash -ine $ExpectedCatalogHash){throw 'Catalogo cambio entre preflight y Apply.'}
    $evidence=Read-BridgeJson $root 'bridge-evidence.json' $hash
    Assert-BridgeReviewChain $evidence $root $script:BridgeCutoverCatalogPath $catalogHash $script:BridgeCutoverScriptRoot
    return [pscustomobject]@{path=$file.FullName;sha256=$hash;catalogSha256=$catalogHash}
}
function Invoke-CutoverApplyGate($InitialEvidence,[scriptblock]$Action) {
    $null=Assert-CutoverBridgeEvidence $InitialEvidence.path $InitialEvidence.sha256 $InitialEvidence.catalogSha256
    $root=[IO.Path]::GetDirectoryName($InitialEvidence.path)
    $evidence=Read-BridgeJson $root 'bridge-evidence.json' $InitialEvidence.sha256
    $locks=[Collections.Generic.List[IO.FileStream]]::new()
    try {
        foreach($file in @(Get-BridgeReviewLockFiles $evidence $root $script:BridgeCutoverCatalogPath $script:BridgeCutoverScriptRoot)){
            $locks.Add([IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
        }
        $locks.Add([IO.File]::Open($InitialEvidence.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
        $null=Assert-CutoverBridgeEvidence $InitialEvidence.path $InitialEvidence.sha256 $InitialEvidence.catalogSha256
        & $Action
    } finally { foreach($stream in $locks){$stream.Dispose()} }
}
function Invoke-ReservationCutover([string]$BackupDirectory,[string]$BridgeEvidence,[bool]$WritersStopped,[bool]$Apply) {
# La cadena se comprueba antes de inspeccionar/redes, leer .env o contactar origen.
$initialBridge=Assert-CutoverBridgeEvidence $BridgeEvidence
if(!$WritersStopped){throw 'Deten todos los escritores y declara -WritersStopped.'}
if(Get-NetTCPConnection -LocalPort 8082 -State Listen -ErrorAction SilentlyContinue){throw 'Eats Hub sigue escuchando en 8082; detenlo manualmente.'}
$values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env')
if($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018'){throw 'Solo se admite Mongo local 27018.'}
$database=$values['MONGODB_DATABASE']
if($database -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $database -in @('admin','local','config')){throw 'Base no permitida.'}
if($values['RESERVATIONS_ENABLED'] -eq 'true'){throw 'El gate nuevo debe continuar apagado durante el corte.'}
$backup=[IO.Path]::GetFullPath((Join-Path $script:IdentityRoot $BackupDirectory))
$validation=Get-Content -LiteralPath (Join-Path $backup 'validation.json') -Raw|ConvertFrom-Json
$archive=Join-Path $backup 'database.archive.gz'
if(!$validation.restoreVerified -or !$validation.sourceUnchanged -or !$validation.writersStoppedDeclared -or
    $validation.database -cne $database -or $validation.source -cne 'eats-availability-mongodb-replica-1' -or
    (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $validation.archiveSha256){throw 'Respaldo/restauracion no acreditado o archive alterado.'}
$before=Get-Content -LiteralPath (Join-Path $backup 'source-before.json') -Raw|ConvertFrom-Json
$restored=Get-Content -LiteralPath (Join-Path $backup 'restored.json') -Raw|ConvertFrom-Json
$after=Get-Content -LiteralPath (Join-Path $backup 'source-after.json') -Raw|ConvertFrom-Json
function ManifestKey($value){return ($value.collections|ConvertTo-Json -Depth 30 -Compress)}
if((ManifestKey $before) -cne (ManifestKey $restored) -or (ManifestKey $before) -cne (ManifestKey $after)){throw 'Los manifiestos no coinciden.'}
# El JWT se valida criptograficamente con las claves del emisor local, sin imprimirlo.
function Decode-Bytes([string]$value){$value=$value.Replace('-','+').Replace('_','/');return [Convert]::FromBase64String($value.PadRight([int]([Math]::Ceiling($value.Length/4.0)*4),'='))}
function Assert-CutoverToken([string]$name,[string]$role){
    $jwt=[Environment]::GetEnvironmentVariable($name,'Process')
    if([string]::IsNullOrWhiteSpace($jwt)){throw ('Falta '+$name+' en esta terminal.')}
    $parts=$jwt.Split('.');if($parts.Length -ne 3){throw 'JWT invalido.'}
    $header=[Text.Encoding]::UTF8.GetString((Decode-Bytes $parts[0]))|ConvertFrom-Json
    $claims=ConvertFrom-JwtPayload $jwt
    if($header.alg -cne 'RS256' -or $claims.iss -cne $script:IdentityIssuer -or
        @($claims.aud) -notcontains 'eats-hub-catalog' -or [string]::IsNullOrWhiteSpace($claims.sub) -or
        [long]$claims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+30 -or @($claims.roles) -notcontains $role){throw 'JWT no cumple identidad/permisos/plazo.'}
    $notBefore=$claims.PSObject.Properties['nbf']
    if($null -ne $notBefore -and [long]$notBefore.Value -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+60){throw 'JWT todavia no es valido.'}
    $jwks=Invoke-RestMethod -Uri ($script:IdentityIssuer+'/protocol/openid-connect/certs') -TimeoutSec 10
    $key=@($jwks.keys|Where-Object {$_.kid -ceq $header.kid -and $_.kty -ceq 'RSA'})
    if($key.Count -ne 1){throw 'Clave publica no identificable.'}
    $parameters=New-Object Security.Cryptography.RSAParameters
    $parameters.Modulus=Decode-Bytes $key[0].n;$parameters.Exponent=Decode-Bytes $key[0].e
    $rsa=New-Object Security.Cryptography.RSACryptoServiceProvider
    try{$rsa.ImportParameters($parameters);if(!$rsa.VerifyData([Text.Encoding]::ASCII.GetBytes($parts[0]+'.'+$parts[1]),
        [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'),(Decode-Bytes $parts[2]))){throw 'Firma JWT invalida.'}}
    finally{$rsa.Dispose()}
    if($role -eq 'RESTAURANT_MANAGER' -and @($claims.restaurant_ids) -notcontains $script:RestaurantA){throw 'Encargado sin restaurante A.'}
}
Assert-CutoverToken 'EATS_HUB_TOKEN_CUSTOMER_A' 'CUSTOMER'
Assert-CutoverToken 'EATS_HUB_TOKEN_A' 'RESTAURANT_MANAGER'
$source='eats-availability-mongodb-replica-1'
$oldEncoding=$OutputEncoding
try{
    $OutputEncoding=[Text.UTF8Encoding]::new($false)
    $raw=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mongo-backup-manifest.js') -Raw |
        & docker exec -i -e ('EATS_BACKUP_DATABASE='+$database) -e EATS_BACKUP_SOURCE=true $source mongosh --quiet --port 27018 --file /dev/stdin
    Assert-DockerSuccess 'leer origen antes del corte'
    $current=($raw -join "`n")|ConvertFrom-Json
    if((ManifestKey $before) -cne (ManifestKey $current)){
        # Repetir el primer corte puede haber agregado exclusivamente su politica.
        $priorOther=@($before.collections|Where-Object {$_.name -ne 'reservation_policy'})|ConvertTo-Json -Depth 30 -Compress
        $currentOther=@($current.collections|Where-Object {$_.name -ne 'reservation_policy'})|ConvertTo-Json -Depth 30 -Compress
        if($priorOther -cne $currentOther){throw 'El origen cambio desde el respaldo; preparar otro respaldo verificado.'}
        $policyCollection=@($current.collections|Where-Object {$_.name -eq 'reservation_policy'})
        if($policyCollection.Count -ne 1 -or $policyCollection[0].count -ne 1){throw 'Cambio de politica no identificable.'}
    }
    $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{database=$database;apply=[bool]$Apply}|ConvertTo-Json -Compress)))
    $cutoverCommand={
        Get-Content -LiteralPath (Join-Path $PSScriptRoot 'set-local-reservation-cutover.js') -Raw |
            & docker exec -i -e ('EATS_CUTOVER_BASE64='+$payload) $source mongosh --quiet --port 27018 --file /dev/stdin
        Assert-DockerSuccess 'comprobar o registrar corte'
    }
    if($Apply){Invoke-CutoverApplyGate $initialBridge $cutoverCommand}else{& $cutoverCommand}
}finally{$OutputEncoding=$oldEncoding}
Write-Host 'Precondiciones comprobadas. No se cambia el gate ni se inicia la aplicacion. La activacion espera todo el lote.'
}
if($MyInvocation.InvocationName -ne '.') {
    Invoke-ReservationCutover $BackupDirectory $BridgeEvidence ([bool]$WritersStopped) ([bool]$Apply)
}
