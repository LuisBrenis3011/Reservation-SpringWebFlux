[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Disabled','Enabled')][string]$Stage)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
$baselinePath=Join-Path $script:IdentityPrivate 'combinations-http-checkpoint.json'
$evidencePath=Join-Path $script:IdentityPrivate 'combinations-gate-checkpoint.json'
if(!(Test-Path -LiteralPath $baselinePath)){throw 'Falta el checkpoint HTTP de SPEC-002. No se crearan fixtures.'}
$baselineHash=(Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash
$baseline=Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$root='http://localhost:8082/catalog'
$collection=$root+'/restaurants/'+$script:RestaurantA+'/table-combinations'
$tables=$root+'/restaurants/'+$script:RestaurantA+'/tables'
if($baseline.schemaVersion -ne 1 -or $baseline.spec -cne 'SPEC-002' -or
    $baseline.baseUrl -cne $collection -or !$baseline.httpCompleted -or
    $null -eq $baseline.restart -or !$baseline.restart.operatorDeclaredRestart -or
    !$baseline.restart.dataAndRevisionPreserved){throw 'Completa HTTP y reinicio con el checkpoint propio de SPEC-002.'}
$id=([guid]$baseline.final.combinationId).ToString()
$resource=$collection+'/'+$id
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
function Gate-Snapshot($Response,[string]$Kind) {
    $body=$Response.Content | ConvertFrom-Json
    return @($body.items | Sort-Object id | ForEach-Object {
        if($Kind -eq 'tables'){
            [pscustomobject]@{id=$_.id;restaurantId=$_.restaurantId;label=$_.label;capacity=$_.capacity}
        }else{
            [pscustomobject]@{id=$_.id;restaurantId=$_.restaurantId;tableIds=@($_.tableIds | Sort-Object);capacity=$_.capacity}
        }
    })
}
$lock=$null
try {
    try{$lock=[IO.File]::Open(($evidencePath+'.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
    catch{throw 'Otro proceso esta usando la evidencia del gate de combinaciones.'}
    if(Test-Path -LiteralPath $evidencePath){
        $journal=Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        if($journal.schemaVersion -ne 1 -or $journal.spec -cne 'SPEC-002' -or
            $journal.runId -cne $baseline.runId -or $journal.baselineSha256 -cne $baselineHash){
            throw 'La evidencia del gate corresponde a otro checkpoint o este cambio. Se conserva sin sobrescribir.'
        }
    }else{
        $journal=[pscustomobject]@{schemaVersion=1;spec='SPEC-002';runId=$baseline.runId;
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
        Check-Gate (Invoke-LocalHttp -Uri $collection) 404 'Coleccion de combinaciones oculta' 'NOT_FOUND'
        Check-Gate (Invoke-LocalHttp -Uri $resource) 404 'Combinacion oculta' 'NOT_FOUND'
    }else{
        Check-Gate (Invoke-LocalHttp -Uri $collection) 401 'Coleccion requiere autenticacion al reactivar' 'UNAUTHENTICATED'
        Check-Gate (Invoke-LocalHttp -Uri $resource) 401 'Recurso requiere autenticacion al reactivar' 'UNAUTHENTICATED'
        $current=Invoke-LocalHttp -Uri $resource -Headers $headers
        Check-Gate $current 200 'Combinacion recuperada al reactivar'
        Equal-Gate ($baseline.final.resource.content | ConvertFrom-Json) ($current.Content | ConvertFrom-Json) 'Identidad, propietario, integrantes y capacidad'
        Gate-Revision $current
        Equal-Gate $baseline.final.resource.etag (Gate-Etag $current) 'ETag original'
        $list=Invoke-LocalHttp -Uri $collection -Headers $headers
        Check-Gate $list 200 'Coleccion autorizada al reactivar'
        Gate-Revision $list
        Equal-Gate @($baseline.final.combinations) @(Gate-Snapshot $list 'combinations') 'Todas las combinaciones conservadas'
        $tableList=Invoke-LocalHttp -Uri $tables -Headers $headers
        Check-Gate $tableList 200 'Mesas conservadas al reactivar'
        Gate-Revision $tableList
        Equal-Gate @($baseline.final.tables) @(Gate-Snapshot $tableList 'tables') 'Todas las mesas conservadas'
        Write-Host 'OK: mismos datos, integrantes, capacidad, revision y ETag; sin escrituras HTTP.'
    }
    if((Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash -cne $baselineHash){throw 'Cambio el checkpoint HTTP durante la comprobacion. No se registra aprobacion.'}
    $disabledAttempt=$null
    if($null -ne $disabled){$disabledAttempt=$disabled.attemptId}
    $result=[pscustomobject]@{attemptId=[guid]::NewGuid().ToString('N');timestampUtc=[DateTime]::UtcNow.ToString('o');
        stage=$Stage;disabledAttemptId=$disabledAttempt;combinationId=$id;revision=$baseline.final.revision;
        checks=$checks.ToArray();dataPreservedAfterReactivation=($Stage -eq 'Enabled');
        note='Solo GET; configuracion y reinicios manuales. No acredita recibos/indices en Mongo, respaldo/restauracion ni reversion de version.'}
    $journal.attempts=@($journal.attempts)+@($result)
    $temp=$evidencePath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    Write-PrivateText $temp ($journal | ConvertTo-Json -Depth 30)
    if(Test-Path -LiteralPath $evidencePath){[IO.File]::Replace($temp,$evidencePath,[System.Management.Automation.Language.NullString]::Value)}
    else{[IO.File]::Move($temp,$evidencePath)}
    Write-Host 'Etapa registrada en combinations-gate-checkpoint.json; checkpoint HTTP original intacto.'
    Write-Host 'El cambio de gate y reinicio son manuales. Respaldo/restauracion, reversion y cierre siguen pendientes.'
}finally{if($null -ne $lock){$lock.Dispose()}}
