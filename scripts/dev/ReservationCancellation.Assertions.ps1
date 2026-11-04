# Funciones puras; reutiliza el canonizador estructural existente. Sin I/O ni reloj global.
. (Join-Path $PSScriptRoot 'ReservationReplacement.Assertions.ps1')
function ConvertTo-CancellationInstant([string]$value){
 if($value -notmatch '^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,9}))?(Z|[+-]\d\d:\d\d)$'){throw 'Instante no verificable.'}
 $seconds=$Matches[1];$fraction=[string]$Matches[2];$offset=$Matches[3]
 $utc=[DateTimeOffset]::Parse(($seconds+$offset),[Globalization.CultureInfo]::InvariantCulture).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss')
 return ($utc+'.'+$fraction.PadRight(9,'0')+'Z')
}
function ConvertTo-CancellationValue($value,[string]$field=''){
 if($null -eq $value){return $null}
 if($field -in @('startInstant','endInstant','createdAt','updatedAt','cancelledAt')){
  return ConvertTo-CancellationInstant ([string]$value)
 }
 if($value -is [string] -or $value -is [ValueType]){return $value}
 if($value -is [Collections.IDictionary]){
  $copy=[ordered]@{};foreach($key in $value.Keys){$copy[$key]=ConvertTo-CancellationValue $value[$key] $key};return $copy
 }
 if($value -is [Collections.IEnumerable]){
  $items=@();foreach($item in $value){$items+=,(ConvertTo-CancellationValue $item)};return ,$items
 }
 $copy=[ordered]@{};foreach($property in $value.PSObject.Properties){$copy[$property.Name]=ConvertTo-CancellationValue $property.Value $property.Name};return $copy
}
function Equal-Cancel($a,$b,[string]$name){
 Assert-ReplacementEqual (ConvertTo-CancellationValue $a) (ConvertTo-CancellationValue $b) $name
}
function Assert-CancellationStored($accepted,$actual){
 # POST de confirmación y GET tienen distinto estado/Location por contrato.
 if($actual.status -ne 200 -or $actual.location){throw 'GET debe ser 200 sin Location.'}
 Equal-Cancel $accepted.body $actual.body 'Cuerpo persistido'
 Equal-Cancel $accepted.etag $actual.etag 'ETag persistido'
}
function Assert-CancellationDelta($before,$after,$response,[string]$effect){
 Equal-Cancel $before.protectedCollections $after.protectedCollections 'Documentos ajenos/indices/opciones'
 Equal-Cancel $before.reservationInvariantSha256 $after.reservationInvariantSha256 'Historia/asignacion'
 Equal-Cancel $before.operationInvariantSha256 $after.operationInvariantSha256 'Metadata'
 $increment=0;if($effect -eq 'transition'){$increment=1}elseif($effect -ne 'noop'){throw 'Efecto desconocido.'}
 if($before.receiptCount -ne 0 -or $after.receiptCount -ne 1 -or $after.version -ne $before.version+$increment -or
    $after.revision -ne $before.revision+$increment -or !$after.receiptFingerprintMatches -or $after.receiptStatus -ne 200 -or
    $null -ne $after.receiptLocation -or $after.receiptVersion -ne $after.version -or $after.receiptRevision -ne $after.revision){throw 'Delta de cancelacion no esperado.'}
 Equal-Cancel $after.reservationView $response.body 'Respuesta/Mongo'
 Equal-Cancel $after.receiptView $response.body 'Respuesta/recibo'
 if($response.status -ne 200 -or $response.body.status -cne 'CANCELLED' -or $response.etag -cne ('"'+$response.body.version+'"') -or $response.location){throw 'Respuesta de cancelacion incorrecta.'}
 if($effect -eq 'noop'){Equal-Cancel $before.reservationView $after.reservationView 'Noop inmutable';Equal-Cancel $before.reservationSha256 $after.reservationSha256 'Documento BSON noop'}
}
function Assert-CancellationWindow($entry,$delta,[DateTimeOffset]$now){
 if($entry.effect -ne 'transition' -or $delta.receiptCount -eq 1){return} # recuperar intención aceptada
 $start=[DateTimeOffset]::Parse($entry.original.body.startInstant)
 $limit=$now;if($entry.actor -ceq 'EATS_HUB_TOKEN_CUSTOMER_A'){$limit=$now.AddHours(2)}
 if($start -lt $limit -or ($entry.actor -cne 'EATS_HUB_TOKEN_CUSTOMER_A' -and $start -le $now)){throw 'Plazo de operacion pendiente vencido; conservar fixture, clave y checkpoint.'}
}
function Assert-CancellationContinuity($checkpoint,$manifest,[string]$pending=''){
 if($checkpoint.pendingName){
  if($checkpoint.pendingName -cne $pending){throw 'Primero recuperar la intencion pendiente, sin otras escrituras.'}
 }else{Equal-Cancel $checkpoint.lastManifest $manifest 'Continuidad del ensayo'}
}
function Assert-CancellationCheckpoint($cp){
 foreach($name in @('schemaVersion','spec','q4Only','runId','id','nearId','q4Id','initial','steps','newIntent','newResponse','final','manifest','restart','pendingName','lastManifest','expected','temporal','q4')){
  if($null -eq $cp.PSObject.Properties[$name]){throw ('Checkpoint incompleto: '+$name)}
 }
 if($cp.schemaVersion -ne 2 -or $cp.spec -cne 'SPEC-008' -or $cp.runId -cnotmatch '^[0-9a-f]{32}$' -or $null -eq $cp.lastManifest){throw 'Checkpoint anterior/desconocido; conservar intacto, requiere revision explicita.'}
 foreach($field in @('id','nearId','q4Id')){$parsed=[guid]::Empty;if(![guid]::TryParse($cp.$field,[ref]$parsed)){throw 'UUID de checkpoint invalido.'}}
 $names=@();foreach($entry in @($cp.steps)){
  foreach($field in @('name','id','actor','identity','match','key','expected','effect','body','before','response','original','afterManifest')){if($null -eq $entry.PSObject.Properties[$field]){throw 'Etapa incompleta.'}}
  if($entry.name -cin $names -or $entry.key -cne ($cp.runId+'-'+$entry.name) -or $entry.effect -notin @('none','transition','noop')){throw 'Intencion alterada/duplicada.'}
  if($entry.id -cnotin @($cp.id,$cp.nearId,$cp.q4Id) -or $entry.id -ceq ([guid]::Empty).ToString()){throw 'Reserva fuera del ensayo.'}
  if($entry.actor -and $entry.actor -cnotin @('EATS_HUB_TOKEN_CUSTOMER_A','EATS_HUB_TOKEN_CUSTOMER_B','EATS_HUB_TOKEN_A','EATS_HUB_TOKEN_B','EATS_HUB_TOKEN_NO_ROLE')){throw 'Actor de etapa desconocido.'}
  $names+=@($entry.name)
  if($entry.actor -and ($null -eq $entry.identity -or !$entry.identity.issuer -or !$entry.identity.subject)){throw 'Identidad congelada ausente.'}
  if($null -ne $entry.response -and $null -eq $entry.afterManifest){throw 'Etapa sin evidencia posterior.'}
 }
 if($cp.pendingName -and $cp.pendingName -cne 'new-confirmation' -and $cp.pendingName -cnotin $names){throw 'Intencion pendiente desconocida.'}
 if($cp.pendingName -ceq 'new-confirmation' -and $null -eq $cp.newIntent){throw 'Intencion nueva ausente.'}
 if($null -ne $cp.newIntent){
  foreach($field in @('key','identity','body','before','afterManifest')){if($null -eq $cp.newIntent.PSObject.Properties[$field]){throw 'Nueva confirmacion incompleta.'}}
  $body=$cp.newIntent.body|ConvertFrom-Json
  if($body.shiftId -cne $cp.initial.body.shiftId -or $body.partySize -ne $cp.initial.body.partySize -or $body.notes -cne ('SPEC-008 '+$cp.runId)){throw 'Contenido de nueva intencion alterado.'}
  Equal-Cancel $cp.initial.body.owner $cp.newIntent.identity 'Titular de intencion congelada'
  if($cp.newIntent.key -cne ($cp.runId+'-new')){throw 'Clave nueva alterada.'}
 }
}
function Assert-CancellationConfirmation($before,$after,$response,$intent,[string]$restaurant){
 Equal-Cancel $before.protectedCollections $after.protectedCollections 'Conservacion durante nueva confirmacion'
 Equal-Cancel $before.operationInvariantSha256 $after.operationInvariantSha256 'Metadata confirmacion'
 if($before.receiptCount -ne 0 -or $null -ne $before.reservationView -or $after.receiptCount -ne 1 -or $after.revision -ne $before.revision+1 -or
    !$after.receiptFingerprintMatches -or $after.receiptStatus -ne 201 -or $after.receiptRevision -ne $after.revision -or $after.receiptVersion -ne 1){throw 'Delta de nueva confirmacion incorrecto.'}
 $row=$response.body;$wanted=$intent.body|ConvertFrom-Json
 if($response.status -ne 201 -or $response.etag -cne '"1"' -or $response.location -cne ('/catalog/restaurants/'+$restaurant+'/reservations/'+$row.id) -or
    $after.receiptLocation -cne $response.location -or $row.kind -cne 'MANAGED' -or $row.status -cne 'CONFIRMED' -or $row.version -ne 1 -or
    $row.restaurantId -cne $restaurant -or $row.owner.issuer -cne $intent.identity.issuer -or $row.owner.subject -cne $intent.identity.subject -or
    $row.shiftId -cne $wanted.shiftId -or $row.partySize -ne $wanted.partySize -or $row.notes -cne $wanted.notes -or $null -ne $row.cancelledAt){throw 'Nueva reserva no corresponde a intencion.'}
 Equal-Cancel ([pscustomobject]@{createdAt=$row.createdAt}) ([pscustomobject]@{createdAt=$row.updatedAt}) 'Fechas de nueva confirmacion'
 Equal-Cancel $after.reservationView $row 'Reserva nueva/Mongo'
 Equal-Cancel $after.receiptView $row 'Recibo nuevo/Mongo'
 if(!$after.assignmentValid -or !$after.snapshotValid -or !$after.noOverlap){throw 'Asignacion/snapshot nuevos no verificables.'}
}
