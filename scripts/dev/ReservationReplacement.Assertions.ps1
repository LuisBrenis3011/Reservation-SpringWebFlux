# Funciones puras: no HTTP, Docker, lectura/escritura de archivos ni acceso al reloj global.
function ConvertTo-ReplacementCanonicalJson($value){
    if($null -eq $value){return 'null'}
    if($value -is [string] -or $value -is [ValueType]){return (ConvertTo-Json -InputObject $value -Compress)}
    if($value -is [Collections.IDictionary]){
        $pairs=@();foreach($key in @($value.Keys|Sort-Object)){$pairs+=((ConvertTo-Json -InputObject ([string]$key) -Compress)+':'+(ConvertTo-ReplacementCanonicalJson $value[$key]))}
        return ('{'+($pairs -join ',')+'}')
    }
    if($value -is [Collections.IEnumerable]){
        $items=@();foreach($item in $value){$items+=,(ConvertTo-ReplacementCanonicalJson $item)};return ('['+($items -join ',')+']')
    }
    $pairs=@();foreach($property in @($value.PSObject.Properties|Sort-Object Name)){
        $pairs+=((ConvertTo-Json -InputObject $property.Name -Compress)+':'+(ConvertTo-ReplacementCanonicalJson $property.Value))
    }
    return ('{'+($pairs -join ',')+'}')
}
function Assert-ReplacementEqual($a,$b,[string]$name){
    if((ConvertTo-ReplacementCanonicalJson $a) -cne (ConvertTo-ReplacementCanonicalJson $b)){throw ($name+': diferencia no permitida.')}
}
function Assert-ReplacementTime($a,$b,[string]$field){
    if($field -in @('localStart','localEnd')){
        if([DateTime]::Parse($a,[Globalization.CultureInfo]::InvariantCulture).Ticks -ne [DateTime]::Parse($b,[Globalization.CultureInfo]::InvariantCulture).Ticks){throw ('Hora local distinta: '+$field)}
    }elseif([DateTimeOffset]::Parse($a) -ne [DateTimeOffset]::Parse($b)){throw ('Instante distinto: '+$field)}
}
function Assert-ReplacementStored($expected,$actual){
    $copies=@();foreach($response in @($expected,$actual)){
        $copy=$response|ConvertTo-Json -Depth 45|ConvertFrom-Json
        foreach($field in @('localStart','localEnd')){$copy.body.$field=[DateTime]::Parse($copy.body.$field,[Globalization.CultureInfo]::InvariantCulture).ToString('yyyy-MM-ddTHH:mm:ss.fffffff')}
        foreach($field in @('startInstant','endInstant','createdAt','updatedAt')){$copy.body.$field=[DateTimeOffset]::Parse($copy.body.$field).UtcDateTime.ToString('o')}
        $copies+=@($copy)
    }
    Assert-ReplacementEqual $copies[0] $copies[1] 'Estado guardado'
}
function Assert-ReplacementIdentity($expected,$claims,[long]$now){
    if([long]$claims.exp -le $now+30){throw 'Token expirado o por expirar; renovar manualmente con la misma identidad.'}
    if($expected.issuer -cne $claims.iss -or $expected.subject -cne $claims.sub){throw 'La identidad no coincide con la intencion guardada.'}
}
function New-ReplacementNearSnapshot($response,[string]$uri,[string]$notes,[DateTimeOffset]$now){
    $seconds=([DateTimeOffset]::Parse($response.body.startInstant)-$now).TotalSeconds
    if($response.body.status -cne 'CONFIRMED' -or $seconds -le 120 -or $seconds -ge 7200){throw 'Fixture cercana fuera del margen inicial.'}
    return [pscustomobject]@{uri=$uri;initial=$response;body=[pscustomobject]@{shiftId=$response.body.shiftId;partySize=$response.body.partySize;notes=$notes};match=$response.etag}
}
function Assert-ReplacementDelta($before,$after){
    Assert-ReplacementEqual $before.protectedCollections $after.protectedCollections 'Documentos ajenos, indices y opciones'
    Assert-ReplacementEqual $before.reservationInvariantSha256 $after.reservationInvariantSha256 'Identidad/historia/campos inmutables'
    Assert-ReplacementEqual $before.operationInvariantSha256 $after.operationInvariantSha256 'Metadatos de coordinacion'
    if([long]$after.version -ne [long]$before.version+1 -or [long]$after.revision -ne [long]$before.revision+1 -or
       $before.receiptCount -ne 0 -or $after.receiptCount -ne 1 -or $after.receiptStatus -ne 200 -or
       [long]$after.receiptRevision -ne [long]$after.revision -or [long]$after.receiptVersion -ne [long]$after.version -or $null -ne $after.receiptLocation){throw 'Delta de version/revision/recibo no esperado.'}
    if($after.receiptFingerprintMatches -ne $true){throw 'Recibo de otra intencion.'}
}
function Assert-ReplacementDatabase($manifest,$actual,$tables){
    foreach($view in @($manifest.reservationView,$manifest.receiptView)){
        $response=[pscustomobject]@{status=200;etag=('"'+$view.version+'"');location='';body=$view}
        Assert-ReplacementStored $response $actual
    }
    Assert-ReplacementEqual @($manifest.tableSnapshots.id|Sort-Object) @($actual.body.tableIds|Sort-Object) 'Snapshot BSON de mesas'
    foreach($snapshot in @($manifest.tableSnapshots)){
        $table=@($tables|Where-Object {$_.id -ceq $snapshot.id})
        if($table.Count -ne 1 -or [long]$table[0].capacity -ne [long]$snapshot.capacity){throw 'Capacidad historica BSON distinta de la mesa asignada.'}
    }
}
function Assert-ReplacementSuccess($prior,$actual,$intent,$shift,$tables,$combinations){
    $old=$prior.body;$row=$actual.body
    foreach($field in @('id','restaurantId','owner','createdAt')){Assert-ReplacementEqual $old.$field $row.$field ('Inmutable '+$field)}
    if($actual.status -ne 200 -or $actual.location -or $actual.etag -cne ('"'+$row.version+'"') -or
       [long]$row.version -ne [long]$old.version+1 -or $row.kind -cne 'MANAGED' -or $row.status -cne 'CONFIRMED' -or
       $null -ne $row.cancelledAt -or $row.shiftId -cne $intent.shiftId -or $row.partySize -ne $intent.partySize -or $row.notes -cne $intent.notes){throw 'PUT no coincide con intencion/estado/version/ETag.'}
    foreach($field in @('localStart','localEnd','startInstant','endInstant')){Assert-ReplacementTime $shift.$field $row.$field $field}
    Assert-ReplacementEqual $shift.zoneId $row.zoneId 'Zona destino'
    if([DateTimeOffset]::Parse($row.updatedAt) -lt [DateTimeOffset]::Parse($old.updatedAt)){throw 'updatedAt retrocedio.'}
    $ids=@($row.tableIds);if($ids.Count -eq 0 -or @($ids|Select-Object -Unique).Count -ne $ids.Count){throw 'Asignacion vacia o repetida.'}
    [long]$capacity=0
    foreach($id in $ids){$table=@($tables|Where-Object {$_.id -ceq $id});if($table.Count -ne 1 -or $table[0].capacity -le 0){throw 'Mesa no verificable.'};$capacity+=[long]$table[0].capacity}
    if($capacity -ne [long]$row.assignedCapacity -or $capacity -lt $intent.partySize){throw 'Capacidad insuficiente/incoherente.'}
    if($row.combinationId){$combination=@($combinations|Where-Object {$_.id -ceq $row.combinationId});if($combination.Count -ne 1){throw 'Combinacion ausente.'};Assert-ReplacementEqual @($combination[0].tableIds|Sort-Object) @($ids|Sort-Object) 'Integrantes'}
    elseif($ids.Count -ne 1){throw 'Varias mesas sin combinacion configurada.'}
    if($old.shiftId -ceq $intent.shiftId -and [long]$old.assignedCapacity -ge $intent.partySize){
        foreach($field in @('tableIds','combinationId','assignedCapacity','zoneId')){Assert-ReplacementEqual $old.$field $row.$field ('Q1/historia '+$field)}
        foreach($field in @('localStart','localEnd','startInstant','endInstant')){Assert-ReplacementTime $old.$field $row.$field $field}
    }
}
