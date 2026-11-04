[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Disabled','Enabled')][string]$Stage)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
$baselinePath=Join-Path $script:IdentityPrivate 'shifts-http-checkpoint.json'
$evidencePath=Join-Path $script:IdentityPrivate 'shifts-gate-checkpoint.json'
if(!(Test-Path -LiteralPath $baselinePath)){throw 'Falta el checkpoint HTTP de SPEC-003. No se crearan fixtures.'}
$baselineHash=(Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash
$baseline=Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$root='http://localhost:8082/catalog'
$collection=$root+'/restaurants/'+$script:RestaurantA+'/shifts'
$tables=$root+'/restaurants/'+$script:RestaurantA+'/tables'
if($baseline.schemaVersion -ne 1 -or $baseline.spec -cne 'SPEC-003' -or
    $baseline.baseUrl -cne $collection -or !$baseline.httpCompleted -or
    $null -eq $baseline.restart -or !$baseline.restart.operatorDeclaredRestart -or
    !$baseline.restart.dataAndRevisionPreserved){throw 'Completa HTTP y reinicio con el checkpoint propio de SPEC-003.'}
$zone=$root+'/restaurants/'+$script:RestaurantA+'/time-zone'
$combinations=$root+'/restaurants/'+$script:RestaurantA+'/table-combinations'
if(@($baseline.final.resources).Count -ne 2){throw 'El checkpoint no contiene los dos turnos esperados.'}
$targets=@(
    [pscustomobject]@{name='Zona';uri=$zone;expected=$baseline.final.zone},
    [pscustomobject]@{name='Coleccion de turnos';uri=$collection;expected=$baseline.final.list})
foreach($entry in $baseline.final.resources){
    $id=([guid]$entry.id).ToString()
    $targets+=([pscustomobject]@{name=('Turno '+$id);uri=($collection+'/'+$id);expected=$entry.response})
}
$checks=[Collections.Generic.List[object]]::new()
function Check-Gate($Response,[int]$Status,[string]$Name,[string]$Code='') {
    if($Response.Status -ne $Status){throw "$Name : se esperaba HTTP $Status y se recibio $($Response.Status). Revisa AVAILABILITY_ENABLED y reinicia manualmente IntelliJ."}
    if($Code -and (($Response.Content | ConvertFrom-Json).code -cne $Code)){throw "$Name : codigo de dominio inesperado."}
    $checks.Add([pscustomobject]@{name=$Name;status=$Response.Status;passed=$true})
    Write-Host "OK: $Name -> HTTP $Status"
}
function Equal-Gate($Expected,$Actual,[string]$Name) {
    if(($Expected | ConvertTo-Json -Depth 40 -Compress) -cne ($Actual | ConvertTo-Json -Depth 40 -Compress)){
        throw "$Name : datos distintos del checkpoint; no se acredita conservacion. Evita otras escrituras."
    }
}
function Gate-Etag($Response) {
    $value=$Response.Headers['ETag']
    if($null -eq $value){throw 'Falta ETag.'}
    return [string](@($value)[0])
}
function Gate-Revision($Response) {
    $body=$Response.Content | ConvertFrom-Json
    if([long]$body.revision -ne [long]$baseline.final.revision -or
        (Gate-Etag $Response) -cne ('"'+[string]$baseline.final.revision+'"')){throw 'Revision/ETag cambiaron durante el ciclo del gate.'}
}
$lock=$null
try {
    try{$lock=[IO.File]::Open(($evidencePath+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch{throw 'Otro proceso esta usando la evidencia del gate de turnos.'}
    if(Test-Path -LiteralPath $evidencePath){
        $journal=Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        if($journal.schemaVersion -ne 1 -or $journal.spec -cne 'SPEC-003' -or
            $journal.runId -cne $baseline.runId -or $journal.baselineSha256 -cne $baselineHash){
            throw 'La evidencia del gate corresponde a otro checkpoint o este cambio. Se conserva sin sobrescribir.'
        }
    }else{
        $journal=[pscustomobject]@{schemaVersion=1;spec='SPEC-003';runId=$baseline.runId;
            baselineSha256=$baselineHash;attempts=@()}
    }
    $disabled=$null
    $headers=@{}
    if($Stage -eq 'Enabled'){
        $previous=@($journal.attempts | Where-Object {$_.stage -eq 'Disabled'})
        if(!$previous.Count){throw 'Primero cambia el gate a false, reinicia y verifica -Stage Disabled.'}
        $disabled=$previous[-1]
        $token=$env:EATS_HUB_TOKEN_A
        if([string]::IsNullOrWhiteSpace($token)){throw 'Obten el token de encargado-a en esta misma PowerShell.'}
        $claims=ConvertFrom-JwtPayload $token
        if($null -eq $claims.PSObject.Properties['sub'] -or [string]::IsNullOrWhiteSpace([string]$claims.sub) -or
            [long]$claims.exp -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+30){throw 'Token incompleto, expirado o por expirar; renueva encargado-a.'}
        $headers.Authorization='Bearer '+$token
    }
    Check-Gate (Invoke-LocalHttp -Uri ($root+'/restaurants')) 200 'Catalogo antiguo accesible'
    if($Stage -eq 'Disabled'){
        foreach($target in $targets){
            Check-Gate (Invoke-LocalHttp -Uri $target.uri) 404 ($target.name+' oculta') 'NOT_FOUND'
        }
    }else{
        foreach($target in $targets){
            Check-Gate (Invoke-LocalHttp -Uri $target.uri) 401 ($target.name+' exige autenticacion') 'UNAUTHENTICATED'
            $current=Invoke-LocalHttp -Uri $target.uri -Headers $headers
            Check-Gate $current 200 ($target.name+' recuperada')
            Equal-Gate ($target.expected.content|ConvertFrom-Json) ($current.Content|ConvertFrom-Json) ($target.name+' datos conservados')
            Gate-Revision $current
            Equal-Gate $target.expected.etag (Gate-Etag $current) ($target.name+' ETag conservado')
        }
        foreach($target in @(
            [pscustomobject]@{name='Mesas';uri=$tables;expected=$baseline.final.tables},
            [pscustomobject]@{name='Combinaciones';uri=$combinations;expected=$baseline.final.combinations})){
            $current=Invoke-LocalHttp -Uri $target.uri -Headers $headers
            Check-Gate $current 200 ($target.name+' conservadas')
            Equal-Gate ($target.expected.content|ConvertFrom-Json) ($current.Content|ConvertFrom-Json) $target.name
            Gate-Revision $current
            Equal-Gate $target.expected.etag (Gate-Etag $current) ($target.name+' ETag')
        }
        Write-Host 'OK: zona, ambos turnos, ambos extremos, revision y ETag conservados; solo GET.'
    }
    if((Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash -cne $baselineHash){throw 'Cambio el checkpoint HTTP durante la comprobacion. No se registra aprobacion.'}
    $disabledAttempt=$null
    if($null -ne $disabled){$disabledAttempt=$disabled.attemptId}
    $result=[pscustomobject]@{attemptId=[guid]::NewGuid().ToString('N');timestampUtc=[DateTime]::UtcNow.ToString('o');
        stage=$Stage;disabledAttemptId=$disabledAttempt;shiftIds=@($baseline.final.resources|ForEach-Object{$_.id});revision=$baseline.final.revision;
        checks=$checks.ToArray();dataPreservedAfterReactivation=($Stage -eq 'Enabled');
        note='Solo GET; configuracion y reinicios manuales. No acredita recibos/indices en Mongo, respaldo/restauracion ni reversion de version.'}
    $journal.attempts=@($journal.attempts)+@($result)
    $temp=$evidencePath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    Write-PrivateText $temp ($journal | ConvertTo-Json -Depth 30)
    if(Test-Path -LiteralPath $evidencePath){[IO.File]::Replace($temp,$evidencePath,[System.Management.Automation.Language.NullString]::Value)}
    else{[IO.File]::Move($temp,$evidencePath)}
    Write-Host 'Etapa registrada en shifts-gate-checkpoint.json; checkpoint HTTP original intacto.'
    Write-Host 'El cambio de gate y reinicio son manuales. Respaldo/restauracion, reversion y cierre siguen pendientes.'
}finally{if($null -ne $lock){$lock.Dispose()}}
