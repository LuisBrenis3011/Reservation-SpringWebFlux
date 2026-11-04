# Solo funciones puras y dobles. No Docker, HTTP, builds, procesos ni bases.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ManagedReservations.Common.ps1')
function Reject-ManagedTest([scriptblock]$Action){
 $failed=$false;try{& $Action}catch{$failed=$true};if(!$failed){throw 'Se esperaba rechazo.'}
}
foreach($managed in @($false,$true)){
 foreach($combination in @($false,$true)){
  foreach($shift in @($false,$true)){
   if(([int]$managed+[int]$combination+[int]$shift) -gt 1){Reject-ManagedTest {Assert-ManagedOptions $managed $combination $shift}}
   else{Assert-ManagedOptions $managed $combination $shift}
  }
 }
}
$absent=[pscustomobject]@{verified=$true;retired=$false}
$cut=[pscustomobject]@{verified=$true;retired=$true}
Assert-ManagedPolicy $absent $false
Assert-ManagedPolicy $cut $true
Reject-ManagedTest {Assert-ManagedPolicy $cut $false}
Reject-ManagedTest {Assert-ManagedPolicy $null $true}
Reject-ManagedTest {Assert-ManagedPolicy ([pscustomobject]@{verified=$false;retired=$false}) $false}
Reject-ManagedTest {Assert-ManagedPolicy ([pscustomobject]@{verified=$true;retired='false'}) $false}
Reject-ManagedTest {[Convert]::FromBase64String('!!!')|Out-Null}
Reject-ManagedTest {'{invalido'|ConvertFrom-Json|Out-Null}
$sample=[ordered]@{notes='Español: comillas " y apóstrofo''';ids=@('a','b');enabled=$false}
$encoded=ConvertTo-ManagedBase64 $sample
$decoded=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))|ConvertFrom-Json
if($decoded.notes -cne $sample.notes -or $decoded.enabled -ne $false -or @($decoded.ids).Count -ne 2){throw 'Canal JSON/Base64 alterado.'}
# Sustituir lector: probar transiciones sin ejecutar el transporte real.
function Read-ManagedPolicy {
 if($script:ManagedTestFailure){throw 'Lectura fallida sintetica'}
 return $script:ManagedTestPolicy
}
$script:ManagedMode=$false;$script:ManagedExpectedRetired=$null
$script:ManagedTestFailure=$false;$script:ManagedTestPolicy=$absent
$null=Assert-LiveManagedMode # Prepare historico sin corte
$script:ManagedExpectedRetired=$false
$script:ManagedTestPolicy=$cut
$script:ManagedTestActions=0
function Invoke-ManagedTestStage([scriptblock]$Action){$null=Assert-LiveManagedMode;& $Action}
Reject-ManagedTest {Invoke-ManagedTestStage {$script:ManagedTestActions++}}
if($script:ManagedTestActions -ne 0){throw 'Se ejecuto una accion tras corte.'}
Reject-ManagedTest {$null=Assert-LiveManagedMode} # StartPrevious tras corte: debe rechazar
foreach($stage in @('Prepare','StartPrevious','Previous','Current')){
 foreach($mode in @('Default','IncludeCombinations','IncludeShifts')){
  $script:ManagedMode=$false;$script:ManagedExpectedRetired=$null;$script:ManagedTestPolicy=$cut
  Reject-ManagedTest {$null=Assert-LiveManagedMode}
  $script:ManagedTestPolicy=$absent;$null=Assert-LiveManagedMode
  $script:ManagedTestFailure=$true
  Reject-ManagedTest {$null=Assert-LiveManagedMode}
  $script:ManagedTestFailure=$false
 }
}
$script:ManagedMode=$true;$script:ManagedExpectedRetired=$true;$script:ManagedTestPolicy=$cut
$null=Assert-LiveManagedMode
$script:ManagedTestPolicy=$absent;Reject-ManagedTest {$null=Assert-LiveManagedMode}
# Inspeccionar presencia del guard en ambos puntos de entrada y antes de acciones.
foreach($file in @('Test-LocalMongoRestore.ps1','Test-LocalVersionRollback.ps1','Test-LocalManagedReservationRollback.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$t,[ref]$e)
 if($e.Count){throw 'Sintaxis incorrecta.'}
 if(!$ast.Extent.Text.Contains('Initialize-ManagedMode') -or !$ast.Extent.Text.Contains('Assert-LiveManagedMode')){throw 'Falta control C1.'}
}
Write-Host 'OK: opciones, JSON/Base64, politica y transicion Prepare/StartPrevious sinteticas. No acredita Mongo ni version puente.'
