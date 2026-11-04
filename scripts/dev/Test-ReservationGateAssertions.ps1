# Solo comprobaciones puras con datos sinteticos, sin HTTP, Docker ni checkpoints reales.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReservationGate.Assertions.ps1')
. (Join-Path $PSScriptRoot 'ManagedReservations.Common.ps1')
function Reject-GateTest([scriptblock]$action,[string]$expected=''){
 $failed=$false;try{& $action}catch{if($expected -and $_.Exception.Message -cne $expected){throw ('Error inesperado: '+$_.Exception.Message)};$failed=$true}
 if(!$failed){throw 'Falta rechazo esperado.'}
}
$cp=[pscustomobject]@{schemaVersion=1;spec='SPEC-005-GATE';runId=('a'*32);baseline=$null;disabled=$null;enabled=$null}
Assert-ReservationGateStage $cp 'Baseline'
Reject-GateTest {Assert-ReservationGateStage $cp 'Disabled'}
$cp.baseline=[pscustomobject]@{snapshot=1};Assert-ReservationGateStage $cp 'Disabled'
Reject-GateTest {Assert-ReservationGateStage $cp 'Baseline'}
Reject-GateTest {Assert-ReservationGateStage $cp 'Enabled'}
$cp.disabled=[pscustomobject]@{passed=$true};Assert-ReservationGateStage $cp 'Enabled'
$cp.enabled=[pscustomobject]@{passed=$true};Reject-GateTest {Assert-ReservationGateStage $cp 'Enabled'}
$bad=$cp|ConvertTo-Json -Depth 20|ConvertFrom-Json;$bad.spec='SPEC-008';Reject-GateTest {Assert-ReservationGateStage $bad 'Enabled'}
Assert-ReservationGatePolicy ([pscustomobject]@{verified=$true;retired=$true})
Reject-GateTest {Assert-ReservationGatePolicy $null}
Reject-GateTest {Assert-ReservationGatePolicy ([pscustomobject]@{verified=$true;retired=$false})}
Reject-GateTest {Assert-ReservationGatePolicy ([pscustomobject]@{verified=$false;retired=$true})}
$snapshot=[pscustomobject]@{status=200;etag='"2"';body=[pscustomobject]@{id='a';version=2;updatedAt='2030-01-01T10:00:00Z'}}
$equivalent=[pscustomobject]@{body=[pscustomobject]@{updatedAt='2030-01-01T05:00:00.000-05:00';version=2;id='a'};etag='"2"';status=200}
Assert-ReservationGateSnapshot $snapshot $equivalent
$changed=$equivalent|ConvertTo-Json -Depth 10|ConvertFrom-Json;$changed.etag='"3"'
Reject-GateTest {Assert-ReservationGateSnapshot $snapshot $changed}
$changed=$equivalent|ConvertTo-Json -Depth 10|ConvertFrom-Json;$changed.body.version=3
Reject-GateTest {Assert-ReservationGateSnapshot $snapshot $changed}
Assert-ReservationGateHashes @{one='ABC';two='DEF'} @{two='DEF';one='ABC'}
Reject-GateTest {Assert-ReservationGateHashes @{one='ABC'} @{one='OTHER'}}
$payload=[ordered]@{database='catalog';id='11111111-1111-4111-8111-111111111111'}
$b64=ConvertTo-ManagedBase64 $payload;$decoded=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))|ConvertFrom-Json
if($decoded.id -cne $payload.id -or $decoded.database -cne $payload.database){throw 'Base64 alterado.'}
# Simula preflight antes de cualquier accion, con corte que cambia o lectura fallida.
$script:GateTestActions=0
function Invoke-GateTest($policy,[bool]$absent){
 Assert-ReservationGatePolicy $policy
 if(!$absent){throw 'UUID ocupado.'}
 $script:GateTestActions++
}
Reject-GateTest {Invoke-GateTest ([pscustomobject]@{verified=$true;retired=$false}) $true} 'Corte persistente no verificable; sin solicitudes de escritura.'
Reject-GateTest {Invoke-GateTest $null $true} 'Corte persistente no verificable; sin solicitudes de escritura.'
Reject-GateTest {Invoke-GateTest ([pscustomobject]@{verified=$true;retired=$true}) $false} 'UUID ocupado.'
if($script:GateTestActions -ne 0){throw 'Hubo una accion pese al rechazo.'}
Write-Host 'OK: etapas, politica, snapshots, hashes y preflight sinteticos. No acredita HTTP ni Mongo.'
