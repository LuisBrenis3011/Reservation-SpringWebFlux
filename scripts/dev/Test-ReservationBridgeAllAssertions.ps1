# Unica entrada de comprobaciones sinteticas. Sin servicios, Docker, Git ni builds.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('bridge-all-synthetic-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$jobs=@(
 @{name='contract';file='Test-ReservationBridgeAssertions.ps1';marker='OK: comprobaciones sinteticas'},
 @{name='preparation';file='Test-ReservationBridgePreparationAssertions.ps1';marker='OK: prerrequisitos'},
 @{name='isolation';file='Test-ReservationBridgeIsolationAssertions.ps1';marker='OK: inspeccion sintetica del observador'},
 @{name='observation';file='Test-ReservationBridgeObservationAssertions.ps1';marker='OK: barrera de arranque y cobertura'},
 @{name='audit';file='Test-ReservationBridgeAuditAssertions.ps1';marker='OK: rutas, expectativas'},
 @{name='review';file='Test-ReservationBridgeReviewAssertions.ps1';marker='OK: productor Review sintetico'},
 @{name='catalog';file='Test-ReservationBridgeCatalogAssertions.ps1';marker='OK: 54 casos C1'},
 @{name='execution';file='Test-ReservationBridgeExecutionAssertions.ps1';marker='OK: orquestacion sintetica completa'},
 @{name='recovery';file='Test-ManagedReservationRecoveryAssertions.ps1';marker='OK: opciones, JSON/Base64'},
 @{name='rollback';file='Test-ReservationBridgeRollbackAssertions.ps1';marker='OK: cadena, sesiones y JAR sinteticos'},
 @{name='cutover';file='Test-ReservationBridgeCutoverAssertions.ps1';marker='OK: evidencia v2 sintetica antes de origen'}
)
$results=@()
foreach($job in $jobs){
    $log=Join-Path $root ($job.name+'.log');$exit=1;$output=''
    try{
        $ErrorActionPreference='Continue'
        $output=(& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot $job.file) 2>&1|ForEach-Object {"$_"}) -join "`n"
        $exit=$LASTEXITCODE
    }catch{$output+="`n"+$_.Exception.Message}finally{$ErrorActionPreference='Stop'}
    [IO.File]::WriteAllText($log,$output,[Text.UTF8Encoding]::new($false))
    $status=if($exit -eq 0 -and $output.Contains($job.marker)){'Passed'}else{'Failed'}
    $results+=[pscustomobject]@{name=$job.name;status=$status;exitCode=$exit;log=$log;level='SYNTHETIC'}
    Write-Host ($job.name+': '+$status+' (sintetico)')
}
$python=Get-Command python -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
$pythonArgs=@('-B',(Join-Path $PSScriptRoot 'bridge/test_bridge_trace.py'))
if($null -eq $python){$python=Get-Command py -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1;$pythonArgs=@('-3')+$pythonArgs}
$output='Python 3 no disponible; no se acredita el parser de strace.';$status='Pending';$exit=1
if($null -ne $python){
    try{$ErrorActionPreference='Continue';$output=(& $python.Source @pythonArgs 2>&1|ForEach-Object {"$_"}) -join "`n";$exit=$LASTEXITCODE;$status=if($exit -eq 0 -and $output -match '(?m)^OK\s*$'){'Passed'}else{'Failed'}}catch{$output=$_.Exception.Message;$status='Failed'}finally{$ErrorActionPreference='Stop'}
}
$log=Join-Path $root 'trace-parser.log';[IO.File]::WriteAllText($log,$output,[Text.UTF8Encoding]::new($false))
$results+=[pscustomobject]@{name='trace-parser';status=$status;exitCode=$exit;log=$log;level='SYNTHETIC'}
Write-Host ('trace-parser: '+$status+' (sintetico)')
$node=Get-Command node -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
$status='Pending';$output='Node no disponible para comprobacion sintactica.';$exit=1
if($null -ne $node){
    $status='Passed';$output='';$exit=0
    foreach($relative in @('read-managed-reservation-policy.js','mongo-backup-manifest.js','mongo-cancellation-confirmation-manifest.js','bridge/environment_seed.js')){
        try{
            $ErrorActionPreference='Continue'
            $text=(& $node.Source --check (Join-Path $PSScriptRoot $relative) 2>&1|ForEach-Object {"$_"}) -join "`n"
            $code=$LASTEXITCODE;$output+=$relative+': '+$code+"`n"+$text+"`n"
            if($code -ne 0){$status='Failed';$exit=$code}
        }catch{$status='Failed';$exit=1;$output+=$_.Exception.Message}finally{$ErrorActionPreference='Stop'}
    }
}
$log=Join-Path $root 'javascript-syntax.log';[IO.File]::WriteAllText($log,$output,[Text.UTF8Encoding]::new($false))
$results+=[pscustomobject]@{name='javascript-syntax';status=$status;exitCode=$exit;log=$log;level='SYNTAX_ONLY'}
Write-Host ('javascript-syntax: '+$status+' (solo sintaxis)')
[IO.File]::WriteAllText((Join-Path $root 'summary.json'),($results|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
Write-Host "Resultados y logs conservados: $root"
if(@($results|Where-Object {$_.status -cne 'Passed'}).Count){throw 'Validacion sintetica incompleta o fallida; revisar summary.json y logs. No se acredita evidencia real.'}
Write-Host 'OK: validacion sintetica integrada completa. No acredita aislamiento, HTTP/JAR, corte, reversion real ni aprobacion de SPEC-005.'
