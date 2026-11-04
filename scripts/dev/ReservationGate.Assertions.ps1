# Funciones puras; no HTTP ni acceso a Mongo.
. (Join-Path $PSScriptRoot 'ReservationCancellation.Assertions.ps1')
function Assert-ReservationGateStage($cp,[string]$stage){
 if($cp.schemaVersion -ne 1 -or $cp.spec -cne 'SPEC-005-GATE' -or $cp.runId -cnotmatch '^[0-9a-f]{32}$'){throw 'Checkpoint ajeno o incompleto.'}
 if($stage -ceq 'Baseline' -and $null -ne $cp.baseline){throw 'Baseline ya fijado.'}
 if($stage -ceq 'Disabled' -and ($null -eq $cp.baseline -or $null -ne $cp.disabled)){throw 'Disabled requiere baseline y no puede repetirse.'}
 if($stage -ceq 'Enabled' -and ($null -eq $cp.disabled -or $null -ne $cp.enabled)){throw 'Enabled requiere Disabled y no puede repetirse.'}
}
function Assert-ReservationGatePolicy($p){
 if($null -eq $p -or $p.verified -ne $true -or $p.retired -isnot [bool] -or !$p.retired){throw 'Corte persistente no verificable; sin solicitudes de escritura.'}
}
function Assert-ReservationGateSnapshot($prior,$current){Equal-Cancel $prior $current 'Snapshot/ETag del ensayo'}
function Assert-ReservationGateHashes($prior,$current){Equal-Cancel $prior $current 'Checkpoints de origen'}
