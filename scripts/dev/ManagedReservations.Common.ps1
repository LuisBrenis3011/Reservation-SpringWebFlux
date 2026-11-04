# Funciones puras de C1 y transporte de solo lectura. Dot-source no ejecuta Docker.
function Assert-ManagedOptions([bool]$Managed,[bool]$Combinations,[bool]$Shifts){
 if(([int]$Managed+[int]$Combinations+[int]$Shifts) -gt 1){throw 'Selecciona un unico modo.'}
}
function Assert-ManagedPolicy($Policy,[bool]$Managed){
 if($null -eq $Policy -or $Policy.verified -ne $true -or $Policy.retired -isnot [bool]){throw 'No se pudo verificar politica; se rechaza la operacion.'}
 if($Policy.retired -and !$Managed){throw 'Corte persistente activo: rechazar modos y sesiones historicas.'}
}
function ConvertTo-ManagedBase64($Value){return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 50 -Compress)))}
function Read-ManagedPolicy([string]$Container='eats-availability-mongodb-replica-1',[int]$Port=27018,[bool]$IsSource=$true,[bool]$Proof=$false){
 $old=$OutputEncoding
 try{
  $OutputEncoding=[Text.UTF8Encoding]::new($false)
  $flag=if($IsSource){'true'}else{'false'};$proofFlag=if($Proof){'true'}else{'false'}
  $result=Get-Content (Join-Path $PSScriptRoot 'read-managed-reservation-policy.js') -Raw |
   & docker exec -i -e ('EATS_BACKUP_DATABASE='+$script:ManagedDatabase) -e ('EATS_BACKUP_SOURCE='+$flag) -e ('EATS_MANAGED_PROOF='+$proofFlag) $Container mongosh --quiet --port $Port --file /dev/stdin
  Assert-DockerSuccess 'verificar politica C1'
  return (($result -join "`n")|ConvertFrom-Json)
 }finally{$OutputEncoding=$old}
}
function Assert-LiveManagedMode {
 $policy=Read-ManagedPolicy
 Assert-ManagedPolicy $policy ([bool]$script:ManagedMode)
 if($null -ne $script:ManagedExpectedRetired -and $policy.retired -ne $script:ManagedExpectedRetired){throw "Politica cambio entre etapas; detener y revisar."}
 return $policy
}
function Initialize-ManagedMode([bool]$Managed,[bool]$Combinations,[bool]$Shifts){
 Assert-ManagedOptions $Managed $Combinations $Shifts
 $values=Read-LocalEnv (Join-Path $script:IdentityRoot '.env')
 if($values['MONGODB_HOST'] -notin @('localhost','127.0.0.1') -or $values['MONGODB_PORT'] -ne '27018' -or $values.ContainsKey('MONGODB_URI') -and $values['MONGODB_URI']){throw 'Solo Mongo local por campos.'}
 $script:ManagedDatabase=$values['MONGODB_DATABASE'];$script:ManagedMode=$Managed
 if($script:ManagedDatabase -notmatch '^[A-Za-z0-9_-]{1,63}$' -or $script:ManagedDatabase -in @('admin','local','config')){throw 'Base no permitida.'}
 $script:ManagedExpectedRetired=$null
 $initial=Assert-LiveManagedMode
 $script:ManagedExpectedRetired=$initial.retired
}
function Get-ManagedCheckpointHashes([string[]]$Paths){
 $result=[ordered]@{}
 foreach($item in @($Paths)){
  $full=[IO.Path]::GetFullPath($item);$allowed=[IO.Path]::GetFullPath($script:IdentityPrivate)+[IO.Path]::DirectorySeparatorChar
  if(!$full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Checkpoint fuera de secrets/local-identity.'}
  $null=Get-Content -LiteralPath $full -Raw|ConvertFrom-Json
  $result[$full]=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
 }
 return $result
}
