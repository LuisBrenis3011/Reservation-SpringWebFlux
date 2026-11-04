# Dobles de la barrera de arranque/traza. Ningun comando Docker se ejecuta.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Prepare-LocalReservationBridge.ps1')
function Expect-ObservationRejection([scriptblock]$Action,[string]$Reason){$failure='';try{& $Action}catch{$failure=$_.Exception.Message};if($failure -notmatch $Reason){throw ('Rechazo inesperado: '+$failure)}}
$script:TraceRequests=0
function Set-BridgeObservationJson {param($Container,$Path,$Value);$script:TraceRequests++}
$target=[pscustomobject]@{id='java1';pid=10;kind='java';ready=$true;finishedUtc=$null}
$script:TraceState=[pscustomobject]@{status='RUNNING';phase='RECORRIDO';traceTargets=@($target);droppedEvents=0;heartbeatUtc=[DateTimeOffset]::UtcNow.ToString('o')}
function Update-BridgeObservationState {param($Observation);return $script:TraceState}
$ctx=[pscustomobject]@{containers=@{APP=('a'*64)};Plan=[pscustomobject]@{runId='synthetic'}}
$obs=[pscustomobject]@{observerId=('b'*64);runId='synthetic';Context=$ctx;activeTraceId='java1'}
Start-BridgeTraceTarget $obs 'java1' 10 'java'
if($script:TraceRequests -ne 1){throw 'Solicitud de traza no emitida.'}
Assert-BridgeObservationAlive $obs
function Get-BridgeObservationInspection {param($Id);return [pscustomobject]@{Config=[pscustomobject]@{Labels=@{'eats.bridge.run'='synthetic'}};State=[pscustomobject]@{Running=$false}}}
$target.finishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
Expect-ObservationRejection {Assert-BridgeObservationAlive $obs} 'Cobertura de syscalls Java interrumpida'
$script:TraceState.status='ERROR'
Expect-ObservationRejection {Start-BridgeTraceTarget $obs 'java2' 11 'java'} 'Observador no disponible'

$script:DockerCalls=@();$script:Hash=('a'*64)
function Invoke-BridgeIsolationDocker([string[]]$Arguments){
    $script:DockerCalls+=@([pscustomobject]@{arguments=@($Arguments)})
    if($Arguments -contains 'sha256sum'){return ($script:Hash+'  /opt/bridge.jar')}
    if($Arguments -contains 'cat'){return '10'}
    if($Arguments -contains '-d'){return}
    throw 'Docker doble recibio una operacion imprevista'
}
function Stop-BridgeEnvironmentApplication {param($Context)}
function Start-BridgeTraceTarget {param($Observation,$Id,$TargetPid,$Kind,$Correlation);throw 'TRACE_UNAVAILABLE'}
$endpoints=[pscustomobject]@{MONGO=[pscustomobject]@{address='172.29.0.2';port=27017};REDIS=[pscustomobject]@{address='172.29.0.3';port=6379};JWKS=[pscustomobject]@{address='172.29.0.4';port=8081}}
$resources=@(1..4|ForEach-Object {[pscustomobject]@{}})+@([pscustomobject]@{mounts=@([pscustomobject]@{sha256=$script:Hash})})
$ctx=[pscustomobject]@{observationReady=$false;containers=@{APP=('a'*64)};Plan=[pscustomobject]@{resources=$resources};runId='synthetic';endpoints=$endpoints;Observation=$obs;gate=$false}
Expect-ObservationRejection {Start-BridgeEnvironmentApplication $ctx $true} 'no iniciar JAR'
if($script:DockerCalls.Count -ne 0){throw 'Accion antes de autocomprobacion.'}
$ctx.observationReady=$true
Expect-ObservationRejection {Start-BridgeEnvironmentApplication $ctx $true} 'TRACE_UNAVAILABLE'
if($ctx.gate){throw 'Arranque acreditado sin traza.'}
$launch=@($script:DockerCalls|Where-Object {$_.arguments -contains '-d'})
if($launch.Count -ne 1 -or ($launch[0].arguments -join ' ') -notmatch 'kill -STOP \$\$; exec java'){throw 'Launcher no se detiene antes de Java.'}
Write-Host 'OK: barrera de arranque y cobertura de syscalls sinteticas; no acredita procesos ni aislamiento reales.'
