# Regresiones H1/C1/R1/A1. No transportes, procesos ni servicios reales.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Test-LocalManagedReservationRollback.ps1') -Stage Prepare
. (Join-Path $PSScriptRoot 'ReservationBridge.C1Remaining.ps1')
. (Join-Path $PSScriptRoot 'ReservationBridge.Observation.ps1')
function Expect-AuditRejection([scriptblock]$Action,[string]$Reason){
    $failure='';try{& $Action}catch{$failure=$_.Exception.Message}
    if($failure -notmatch $Reason){throw ('Rechazo de auditoria no acreditado: '+$failure+'; esperado: '+$Reason)}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('bridge-audit-synthetic-'+[guid]::NewGuid().ToString('N'))
$inside=Join-Path $root 'allowed';$outside=Join-Path $root 'outside'
[IO.Directory]::CreateDirectory($inside)|Out-Null
[IO.Directory]::CreateDirectory($outside)|Out-Null
$file=Join-Path $inside 'normal.json';[IO.File]::WriteAllText($file,'{}')
$null=Assert-BridgeManagedPath $inside $file
$null=Assert-BridgeManagedPath $inside (Join-Path $inside 'new/file.json') $true
Expect-AuditRejection {$null=Assert-BridgeManagedPath $inside (Join-Path $outside 'foreign.json') $true} 'fuera de raiz'
Expect-AuditRejection {$null=Assert-BridgeManagedPath $inside (Join-Path $inside 'missing.json')} 'ausente'
# La fixture no crea enlaces NTFS: el doble solo sustituye los metadatos de
# un directorio propio. No requiere elevacion ni acredita una junction real.
$link=Join-Path $inside 'junction'
[IO.Directory]::CreateDirectory($link)|Out-Null
[IO.File]::WriteAllText((Join-Path $link 'existing.json'),'{}')
[IO.File]::WriteAllText((Join-Path $outside 'existing.json'),'{}')
$before=(Get-FileHash -LiteralPath (Join-Path $outside 'existing.json')).Hash
$script:AuditActions=0
$null=Assert-BridgeManagedPath $inside (Join-Path $link 'existing.json')
& {
    function Get-Item {
        [CmdletBinding()]
        param([string]$LiteralPath,[switch]$Force)
        if([IO.Path]::GetFullPath($LiteralPath) -ieq [IO.Path]::GetFullPath($link)){
            return [pscustomobject]@{PSIsContainer=$true;FullName=$link;Attributes=([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)}
        }
        Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath -Force:$Force -ErrorAction Stop
    }
    Expect-AuditRejection {$null=Assert-BridgeManagedPath $inside (Join-Path $link 'existing.json');$script:AuditActions++} 'enlace o junction'
    Expect-AuditRejection {$null=Assert-BridgeManagedPath $inside (Join-Path $link 'new/session.json') $true;$script:AuditActions++} 'enlace o junction'
    Expect-AuditRejection {$null=Assert-BridgeManagedPath $link (Join-Path $link 'existing.json');$script:AuditActions++} 'enlace o junction'
}
if($script:AuditActions -ne 0 -or (Get-FileHash -LiteralPath (Join-Path $outside 'existing.json')).Hash -cne $before){throw 'La ruta enlazada alcanzo accion o altero fixture externa.'}
$view=[pscustomobject]@{id='55555555-5555-4555-8555-555555555555';restaurantId='11111111-1111-4111-8111-111111111111';shiftId='44444444-4444-4444-8444-444444444444';owner=@{issuer='c1-synthetic';subject='c1-user'};partySize=2;notes='synthetic'}
$expected=[pscustomobject]@{reservationId=$view.id;restaurantId=$view.restaurantId;issuer=$view.owner.issuer;subject=$view.owner.subject;key='c1-key';match='';body=@{shiftId=$view.shiftId;partySize=2;notes='synthetic'}}
function Encode-AuditExpected($Value){return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 12 -Compress)))}
Assert-BridgeC1ConfirmationExpectation (Encode-AuditExpected $expected) $view
$saved=$expected|ConvertTo-Json -Depth 12
$expected.reservationId=$view.shiftId
Expect-AuditRejection {Assert-BridgeC1ConfirmationExpectation (Encode-AuditExpected $expected) $view} 'Expectativas C1 invalidas'
$expected=$saved|ConvertFrom-Json;$expected.body.PSObject.Properties.Remove('notes')
Expect-AuditRejection {Assert-BridgeC1ConfirmationExpectation (Encode-AuditExpected $expected) $view} 'Expectativas C1 invalidas'
$expected=$saved|ConvertFrom-Json;$expected.body.shiftId='c1-shift'
Expect-AuditRejection {Assert-BridgeC1ConfirmationExpectation (Encode-AuditExpected $expected) $view} 'Expectativas C1 invalidas'
Expect-AuditRejection {Assert-BridgeC1ConfirmationExpectation '!!!' $view} 'Expectativas C1 invalidas'
foreach($code in @(101,113,99)){
    # No-route admite el resto de la comprobacion; la cobertura SYSCALL se
    # valida obligatoriamente en Assert-BridgeIsolation, nunca se deriva del errno.
    Assert-BridgeDeniedProbeObservable ([pscustomobject]@{connected=$false;acknowledged=$false;errorCode=$code})
}
Expect-AuditRejection {Assert-BridgeDeniedProbeObservable ([pscustomobject]@{connected=$true;acknowledged=$true;errorCode=$null})} 'establecio conexion'
# Un timeout solo permite seguir comprobando captura y prueba independiente.
Assert-BridgeDeniedProbeObservable ([pscustomobject]@{connected=$false;acknowledged=$false;errorCode=110})
Write-Host 'OK: rutas, expectativas y admisibilidad de sondas sinteticos; no acredita aislamiento real.'
Write-Host "Fixtures conservadas: $root"
