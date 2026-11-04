# Comparadores locales de BridgeEvidence v2. No producen evidencia ni ejecutan servicios.
Set-StrictMode -Version Latest

function Get-BridgeField($Object, [string]$Name) {
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { throw "Campo ausente: $Name" }
    # Evitar que PowerShell desenvuelva arreglos vacios o de un elemento.
    return ,($Object.PSObject.Properties[$Name].Value)
}

function Assert-BridgeText($Value, [string]$Name) {
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw "Texto invalido: $Name" }
}

function Assert-BridgeTrue($Value, [string]$Name) {
    if ($Value -isnot [bool] -or $Value -ne $true) { throw "Booleano verdadero requerido: $Name" }
}

function Assert-BridgeUtc($Value, [string]$Name) {
    Assert-BridgeText $Value $Name
    $parsed = [DateTimeOffset]::MinValue
    if ($Value -notmatch '(Z|[+]00:00)$' -or -not [DateTimeOffset]::TryParse($Value, [ref]$parsed)) {
        throw "Fecha UTC invalida: $Name"
    }
}

function Assert-BridgeHash($Value, [string]$Name) {
    if ($Value -isnot [string] -or $Value -cnotmatch '^[0-9a-fA-F]{64}$') { throw "SHA256 invalido: $Name" }
}

function Get-BridgeSafeFile([string]$Root, [string]$RelativePath) {
    Assert-BridgeText $Root 'root'
    Assert-BridgeText $RelativePath 'path'
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.?([\\/]|$)' -or $RelativePath.Contains(':')) {
        throw 'Ruta no permitida.'
    }
    $rootItem = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer) { throw 'Raiz invalida.' }
    $rootFull = [IO.Path]::GetFullPath($rootItem.FullName).TrimEnd([char[]]'\/')
    $rootCursor = $rootItem
    while ($null -ne $rootCursor) {
        if (($rootCursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Raiz contiene enlace.' }
        $rootCursor = $rootCursor.Parent
    }
    $full = [IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))
    if (-not $full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta fuera de raiz.' }
    $cursor = $rootItem
    foreach ($segment in ($RelativePath -split '[\\/]+')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { throw 'Segmento vacio.' }
        $cursor = Get-Item -LiteralPath (Join-Path $cursor.FullName $segment) -Force -ErrorAction Stop
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Enlace no permitido.' }
    }
    if ($cursor.PSIsContainer) { throw 'Se esperaba un archivo.' }
    return $cursor.FullName
}

function Assert-BridgeFile([string]$Root, [string]$Path, $Sha256) {
    Assert-BridgeHash $Sha256 'archivo'
    $full = Get-BridgeSafeFile $Root $Path
    if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ine $Sha256) { throw 'Hash de archivo no coincide.' }
    return $full
}

function Get-BridgeCases([string]$Group) {
    $cases = [ordered]@{}
    switch -CaseSensitive ($Group) {
        'legacyReadsAuthorized' {
            1..5 | ForEach-Object { $cases[('LEG-{0:00}' -f $_)] = $(if ($_ -eq 5) {'HTTP_JAR_MANIFEST'} else {'HTTP_JAR'}) }
        }
        'v2ReadsVerified' {
            1..6 | ForEach-Object { $cases[('V2-{0:00}' -f $_)] = $(if ($_ -eq 6) {'HTTP_JAR_MANIFEST'} else {'HTTP_JAR'}) }
        }
        'legacyBarrierVerified' {
            foreach ($method in @('POST','PUT','DELETE')) { foreach ($gate in @('OFF','ON')) { $cases["BARRIER-HTTP-$method-$gate"]='HTTP_JAR_MANIFEST' } }
            foreach ($action in @('CREATE','UPDATE','DELETE')) { $cases["BARRIER-INTERNAL-$action"]='SOURCE_EXPORTED' }
            $cases['BARRIER-READ-FAIL']='SOURCE_EXPORTED'
        }
        'rollbackControlsVerified' {
            foreach ($mode in @('DEFAULT','COMBINATIONS','SHIFTS','MANAGED')) {
                foreach ($stage in @('PREPARE','STARTPREVIOUS','PREVIOUS','CURRENT')) {
                    foreach ($state in @('NOCUT','CUT','READFAIL')) { $cases["C1-$mode-$stage-$state"]='SYNTHETIC' }
                }
            }
            foreach ($mode in @('DEFAULT','COMBINATIONS','SHIFTS')) { $cases["C1-RACE-$mode"]='SYNTHETIC' }
            foreach ($id in @('C1-SESSION-HISTORY','C1-JAR-ALTERED','C1-EVIDENCE-ALTERED')) { $cases[$id]='SYNTHETIC' }
        }
        'isolation' {
            1..6 | ForEach-Object { $cases[('ISO-{0:00}' -f $_)] = $(if ($_ -le 4) {'ISOLATION_CONFIG'} else {'ISOLATION_OBSERVED'}) }
            1..3 | ForEach-Object { $cases[('ISO-NEG-{0:00}' -f $_)]='ISOLATION_NEGATIVE' }
        }
        default { throw 'Grupo desconocido.' }
    }
    return $cases
}

function Assert-BridgeCases($Cases, [string]$Group) {
    if ($Cases -isnot [array]) { throw 'Cases debe ser arreglo.' }
    $expected = Get-BridgeCases $Group
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($case in $Cases) {
        $id = Get-BridgeField $case 'id'
        Assert-BridgeText $id 'id'
        if (-not $seen.Add($id) -or -not (@($expected.Keys) -ccontains $id)) { throw 'Caso duplicado o desconocido.' }
        if ((Get-BridgeField $case 'level') -cne $expected[$id]) { throw 'Nivel incorrecto.' }
        $expectedValue = Get-BridgeField $case 'expected'
        $actualValue = Get-BridgeField $case 'actual'
        if ($null -eq $expectedValue -or $null -eq $actualValue) { throw 'Resultado de caso ausente.' }
        if (($expectedValue | ConvertTo-Json -Depth 30 -Compress) -cne ($actualValue | ConvertTo-Json -Depth 30 -Compress)) { throw 'Resultado de caso distinto.' }
        Assert-BridgeTrue (Get-BridgeField $case 'passed') 'case.passed'
    }
    if ($seen.Count -ne $expected.Count) { throw 'Faltan casos.' }
}

function Read-BridgeJson([string]$Root, [string]$Path, $Sha256) {
    $full = Assert-BridgeFile $Root $Path $Sha256
    return Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
}

function Assert-BridgeCandidate($Candidate, [string]$Root) {
    if (((Get-BridgeField $Candidate 'schemaVersion') -isnot [int] -and (Get-BridgeField $Candidate 'schemaVersion') -isnot [long]) -or (Get-BridgeField $Candidate 'schemaVersion') -ne 2 -or
        (Get-BridgeField $Candidate 'kind') -cne 'reservation-bridge-candidate' -or
        (Get-BridgeField $Candidate 'state') -cne 'Prepared') { throw 'Candidato invalido.' }
    foreach ($name in @('runId','preparedBy','sourceTree','provenanceEntry')) { Assert-BridgeText (Get-BridgeField $Candidate $name) $name }
    Assert-BridgeUtc (Get-BridgeField $Candidate 'preparedAtUtc') 'preparedAtUtc'
    if ((Get-BridgeField $Candidate 'commit') -cnotmatch '^[0-9a-fA-F]{40}$') { throw 'Commit invalido.' }
    foreach ($prefix in @('sourceArchive','sourceFilesManifest','buildRecipe','jar')) {
        $null = Assert-BridgeFile $Root (Get-BridgeField $Candidate ($prefix+'Path')) (Get-BridgeField $Candidate ($prefix+'Sha256'))
    }
    Assert-BridgeJarProvenance $Candidate $Root
    $toolchain = Get-BridgeField $Candidate 'toolchain'
    if ((Get-BridgeField $toolchain 'jdk') -cne '21') { throw 'JDK invalido.' }
    Assert-BridgeText (Get-BridgeField $toolchain 'gradle') 'gradle'
}

function Assert-BridgeReport($Report, $Candidate, [string]$CandidateSha256, [string]$CatalogSha256, [string]$Root) {
    if (((Get-BridgeField $Report 'schemaVersion') -isnot [int] -and (Get-BridgeField $Report 'schemaVersion') -isnot [long]) -or (Get-BridgeField $Report 'schemaVersion') -ne 2 -or (Get-BridgeField $Report 'kind') -cne 'reservation-bridge-verification' -or
        (Get-BridgeField $Report 'catalogVersion') -cne '1.4.0' -or (Get-BridgeField $Report 'status') -cne 'Passed') { throw 'Reporte invalido.' }
    foreach ($field in @('runId','commit','jarSha256')) {
        if ((Get-BridgeField $Report $field) -cne (Get-BridgeField $Candidate $field)) { throw "Referencia distinta: $field" }
    }
    if ((Get-BridgeField $Report 'candidateSha256') -ine $CandidateSha256 -or
        (Get-BridgeField $Report 'catalogSha256') -ine $CatalogSha256) { throw 'Hash de referencia distinto.' }
    Assert-BridgeText (Get-BridgeField $Report 'executedBy') 'executedBy'
    Assert-BridgeUtc (Get-BridgeField $Report 'startedAtUtc') 'startedAtUtc'
    Assert-BridgeUtc (Get-BridgeField $Report 'finishedAtUtc') 'finishedAtUtc'
    if ([DateTimeOffset](Get-BridgeField $Report 'startedAtUtc') -gt [DateTimeOffset](Get-BridgeField $Report 'finishedAtUtc')) { throw 'Fechas invertidas.' }
    $group = Get-BridgeField $Report 'groupId'
    Assert-BridgeCases (Get-BridgeField $Report 'cases') $group
    foreach ($name in @('scriptHashes','attachments')) {
        $items = Get-BridgeField $Report $name
        if ($items -isnot [array] -or $items.Count -eq 0) { throw "Referencias ausentes: $name" }
        foreach ($item in $items) { $null = Assert-BridgeFile $Root (Get-BridgeField $item 'path') (Get-BridgeField $item 'sha256') }
    }
    $null = Get-BridgeField $Report 'isolation'
}



function Assert-BridgeJarProvenance($Candidate, [string]$Root) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $jar = Assert-BridgeFile $Root (Get-BridgeField $Candidate 'jarPath') (Get-BridgeField $Candidate 'jarSha256')
    $name = Get-BridgeField $Candidate 'provenanceEntry'
    Assert-BridgeText $name 'provenanceEntry'
    if ($name -match '(^|/)\.\.?(/|$)' -or $name.StartsWith('/') -or $name.Contains('\')) { throw 'Entrada de procedencia invalida.' }
    $expected = Get-BridgeField $Candidate 'provenanceSha256'
    Assert-BridgeHash $expected 'provenanceSha256'
    $zip = [IO.Compression.ZipFile]::OpenRead($jar)
    try {
        $entries = @($zip.Entries | Where-Object { $_.FullName -ceq $name })
        if ($entries.Count -ne 1 -or $entries[0].Length -gt 65536) { throw 'Procedencia ausente, duplicada o demasiado grande.' }
        $stream = $entries[0].Open()
        try {
            $memory = [IO.MemoryStream]::new()
            try {
                $stream.CopyTo($memory)
                $bytes = $memory.ToArray()
            } finally { $memory.Dispose() }
        } finally { $stream.Dispose() }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
        if ($actual -ine $expected) { throw 'Hash de procedencia distinto.' }
        $metadata = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
        foreach ($field in @('commit','sourceArchiveSha256','buildRecipeSha256')) {
            if ((Get-BridgeField $metadata $field) -ine (Get-BridgeField $Candidate $field)) { throw "Procedencia distinta: $field" }
        }
    } finally { $zip.Dispose() }
}

function Assert-BridgeIsolation($Isolation, [string]$Root) {
    if ((Get-BridgeField $Isolation 'kind') -cne 'reservation-bridge-isolation' -or
        (Get-BridgeField $Isolation 'status') -cne 'Passed') { throw 'Aislamiento no acreditado.' }
    Assert-BridgeCases (Get-BridgeField $Isolation 'cases') 'isolation'
    foreach ($field in @('observerContinuous','observerSawAllowed','observerSawDenied','sentinelBlocked','preflightComplete','runNoForeignDestinations')) {
        Assert-BridgeTrue (Get-BridgeField $Isolation $field) $field
    }
    foreach ($field in @('runId','observerVersion','sentinelCorrelationId')) { Assert-BridgeText (Get-BridgeField $Isolation $field) $field }
    foreach ($field in @('preflightStartedUtc','preflightFinishedUtc','runStartedUtc','runFinishedUtc')) { Assert-BridgeUtc (Get-BridgeField $Isolation $field) $field }
    if ([DateTimeOffset](Get-BridgeField $Isolation 'preflightStartedUtc') -gt [DateTimeOffset](Get-BridgeField $Isolation 'preflightFinishedUtc') -or
        [DateTimeOffset](Get-BridgeField $Isolation 'preflightFinishedUtc') -gt [DateTimeOffset](Get-BridgeField $Isolation 'runStartedUtc') -or
        [DateTimeOffset](Get-BridgeField $Isolation 'runStartedUtc') -gt [DateTimeOffset](Get-BridgeField $Isolation 'runFinishedUtc')) { throw 'Fases de aislamiento invalidas.' }
    $documents = @{}
    foreach ($field in @('allowlist','topology','observation','sentinelProof','syscallCoverage')) {
        $ref = Get-BridgeField $Isolation $field
        $document = Read-BridgeJson $Root (Get-BridgeField $ref 'path') (Get-BridgeField $ref 'sha256')
        if (((Get-BridgeField $document 'schemaVersion') -isnot [int] -and (Get-BridgeField $document 'schemaVersion') -isnot [long]) -or (Get-BridgeField $document 'schemaVersion') -ne 1 -or (Get-BridgeField $document 'kind') -cne ('reservation-bridge-isolation-' + $field) -or
            (Get-BridgeField $document 'runId') -cne (Get-BridgeField $Isolation 'runId')) {
            throw "Adjunto de aislamiento incompatible: $field"
        }
        $documents[$field] = $document
    }
    # No confiar en banderas generales sin comprobar la estructura de los adjuntos.
    foreach ($field in @('allowlist','topology','observation','sentinelProof','syscallCoverage')) {
        $records = Get-BridgeField $documents[$field] 'records'
        if ($records -isnot [array] -or $records.Count -eq 0) { throw "Adjunto sin registros: $field" }
    }
    foreach ($field in @('topology','observation','sentinelProof','syscallCoverage')) {
        if ((Get-BridgeField $documents[$field] 'records').Count -ne 1) { throw "Cantidad invalida: $field" }
    }
    $top = (Get-BridgeField $documents.topology 'records')[0]
    foreach ($field in @('networkId','appContainerId','observerContainerId')) { Assert-BridgeText (Get-BridgeField $top $field) $field }
    Assert-BridgeTrue (Get-BridgeField $top 'internal') 'internal'
    foreach ($field in @('hostNetwork','hostGateway','observerPrivileged','appExtraCapabilities','sourceMounts')) {
        $v=Get-BridgeField $top $field
        if ($v -isnot [bool] -or $v -ne $false) { throw "Topologia insegura: $field" }
    }
    $services=Get-BridgeField $top 'services'
    if ($services -isnot [array] -or $services.Count -eq 0) { throw 'Servicios ausentes.' }
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $addresses=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $roles=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $null=$ids.Add((Get-BridgeField $top 'appContainerId'))
    if (-not $ids.Add((Get-BridgeField $top 'observerContainerId'))) { throw 'IDs duplicados.' }
    $destinations=@{}
    foreach ($service in $services) {
        $id=Get-BridgeField $service 'id'; $address=Get-BridgeField $service 'address'; $role=Get-BridgeField $service 'role'
        Assert-BridgeText $id 'id'; Assert-BridgeText $address 'address'; Assert-BridgeText $role 'role'
        if (-not $ids.Add($id) -or -not $addresses.Add($address)) { throw 'Servicio duplicado.' }
        $null=$roles.Add($role); $destinations[$id]=$address
    }
    foreach ($role in @('MONGO','REDIS','JWKS','DNS')) { if (-not $roles.Contains($role)) { throw "Servicio ausente: $role" } }
    # El contrato admite como destino la aplicacion, ademas de los servicios.
    # La direccion se inventaria explicitamente; no se deriva de un evento.
    if ($null -ne $top.PSObject.Properties['appAddress']) {
        $appAddress=Get-BridgeField $top 'appAddress'
        Assert-BridgeText $appAddress 'appAddress'
        $parsedAddress=[Net.IPAddress]::None
        if (-not [Net.IPAddress]::TryParse($appAddress,[ref]$parsedAddress) -or
            $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
            $parsedAddress.ToString() -cne $appAddress -or -not $addresses.Add($appAddress)) { throw 'Direccion de aplicacion invalida.' }
        $destinations[(Get-BridgeField $top 'appContainerId')]=$appAddress
    }
    $allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in (Get-BridgeField $documents.allowlist 'records')) {
        $src=Get-BridgeField $entry 'sourceId'; $dst=Get-BridgeField $entry 'destinationId'
        $address=Get-BridgeField $entry 'address'; $protocol=Get-BridgeField $entry 'protocol'; $port=Get-BridgeField $entry 'port'
        if (-not $ids.Contains($src) -or -not $destinations.ContainsKey($dst) -or $destinations[$dst] -cne $address -or
            -not (@('TCP','UDP') -ccontains $protocol) -or
            ($port -isnot [int] -and $port -isnot [long]) -or $port -lt 1 -or $port -gt 65535) { throw 'Destino permitido invalido.' }
        if (-not $allowed.Add("$src|$dst|$address|$protocol|$port")) { throw 'Destino permitido duplicado.' }
    }
    $obs=(Get-BridgeField $documents.observation 'records')[0]
    $coverage=(Get-BridgeField $documents.syscallCoverage 'records')[0]
    if((Get-BridgeField $Isolation 'observerVersion') -cne 'AF_PACKET+STRACE-v1' -or (Get-BridgeField $coverage 'method') -cne 'AF_PACKET+STRACE-v1'){throw 'Metodo de observacion incompatible.'}
    Assert-BridgeText (Get-BridgeField $coverage 'traceVersion') 'traceVersion'
    $caps=Get-BridgeField $coverage 'capabilities'
    if($caps -isnot [array] -or $caps.Count -ne 2 -or -not ($caps -ccontains 'NET_RAW') -or -not ($caps -ccontains 'SYS_PTRACE') -or $coverage.pidMode -cne ('container:'+$top.appContainerId)){throw 'Permisos de traza incompatibles.'}
    $profileHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'bridge/observer-seccomp.json') -Algorithm SHA256).Hash
    if((Get-BridgeField $coverage 'seccompSha256') -ine $profileHash){throw 'Seccomp evaluado distinto del actual.'}
    $targets=Get-BridgeField $coverage 'targets';$traceIds=@{}
    if($targets -isnot [array] -or $targets.Count -lt 3){throw 'Cobertura de syscalls incompleta.'}
    foreach($target in $targets){
        Assert-BridgeText (Get-BridgeField $target 'id') 'trace.id'
        Assert-BridgeTrue (Get-BridgeField $target 'ready') 'trace.ready'
        if($traceIds.ContainsKey($target.id) -or $target.kind -cnotin @('java','probe') -or ($target.pid -isnot [int] -and $target.pid -isnot [long]) -or ($target.tracerPid -isnot [int] -and $target.tracerPid -isnot [long]) -or $target.pid -le 1 -or $target.tracerPid -le 1 -or $target.pid -eq $target.tracerPid -or ($target.exitCode -isnot [int] -and $target.exitCode -isnot [long]) -or $target.exitCode -ne 0){throw 'Objetivo de traza invalido.'}
        foreach($name in @('startedUtc','finishedUtc')){Assert-BridgeUtc (Get-BridgeField $target $name) ('trace.'+$name)}
        if([DateTimeOffset]$target.startedUtc -gt [DateTimeOffset]$target.finishedUtc -or [DateTimeOffset]$target.startedUtc -lt [DateTimeOffset]$Isolation.preflightStartedUtc -or [DateTimeOffset]$target.finishedUtc -gt [DateTimeOffset]$Isolation.runFinishedUtc){throw 'Ventana de traza incompleta.'}
        if($target.kind -ceq 'java' -and [DateTimeOffset]$target.startedUtc -lt [DateTimeOffset]$Isolation.runStartedUtc){throw 'Java observado antes de RECORRIDO.'}
        if($target.kind -ceq 'java'){
            $checks=Get-BridgeField $target 'threadChecks'
            if(($checks -isnot [int] -and $checks -isnot [long]) -or $checks -le 0){throw 'Threads Java sin comprobacion de cobertura.'}
            Assert-BridgeUtc (Get-BridgeField $target 'lastThreadCheckUtc') 'trace.lastThreadCheckUtc'
            if([DateTimeOffset]$target.lastThreadCheckUtc -lt [DateTimeOffset]$target.startedUtc -or [DateTimeOffset]$target.lastThreadCheckUtc -gt [DateTimeOffset]$target.finishedUtc){throw 'Comprobacion de threads fuera de cobertura.'}
        }
        $traceIds[$target.id]=$target
    }
    if(@($targets|Where-Object {$_.kind -ceq 'java'}).Count -eq 0 -or @($targets|Where-Object {$_.kind -ceq 'probe'}).Count -lt 2){throw 'Faltan controles de syscall o Java.'}
    if ((Get-BridgeField $obs 'observerContainerId') -cne (Get-BridgeField $top 'observerContainerId')) { throw 'Observador distinto.' }
    Assert-BridgeTrue (Get-BridgeField $obs 'continuous') 'continuous'
    $dropped=Get-BridgeField $obs 'droppedEvents'
    if (($dropped -isnot [int] -and $dropped -isnot [long]) -or $dropped -ne 0) { throw 'Eventos perdidos.' }
    foreach ($field in @('startedUtc','finishedUtc')) { Assert-BridgeUtc (Get-BridgeField $obs $field) $field }
    if ([DateTimeOffset](Get-BridgeField $obs 'startedUtc') -gt [DateTimeOffset](Get-BridgeField $Isolation 'preflightStartedUtc') -or
        [DateTimeOffset](Get-BridgeField $obs 'finishedUtc') -lt [DateTimeOffset](Get-BridgeField $Isolation 'runFinishedUtc')) { throw 'Cobertura incompleta.' }
    $events=Get-BridgeField $obs 'events'
    if ($events -isnot [array] -or $events.Count -eq 0) { throw 'Eventos ausentes.' }
    $sentinel=$null; $permitted=0;$packetAllowed=0;$syscallAllowed=0
    foreach ($event in $events) {
        $phase=Get-BridgeField $event 'phase'; $time=Get-BridgeField $event 'timestampUtc'; Assert-BridgeUtc $time 'timestampUtc'
        $src=Get-BridgeField $event 'sourceId'; $dst=Get-BridgeField $event 'destinationId'; $addr=Get-BridgeField $event 'address'
        $protocol=Get-BridgeField $event 'protocol'; $port=Get-BridgeField $event 'port'; $correlation=Get-BridgeField $event 'correlationId'; $outcome=Get-BridgeField $event 'outcome'
        foreach ($v in @($src,$dst,$addr,$correlation)) { Assert-BridgeText $v 'evento' }
        if (-not $ids.Contains($src) -or -not (@('TCP','UDP') -ccontains $protocol) -or ($port -isnot [int] -and $port -isnot [long]) -or $port -lt 1 -or $port -gt 65535 -or -not (@('ATTEMPT','BLOCKED') -ccontains $outcome)) { throw 'Evento invalido.' }
        if ($phase -ceq 'AUTOCOMPROBACION') { $start=Get-BridgeField $Isolation 'preflightStartedUtc'; $end=Get-BridgeField $Isolation 'preflightFinishedUtc' }
        elseif ($phase -ceq 'RECORRIDO') { $start=Get-BridgeField $Isolation 'runStartedUtc'; $end=Get-BridgeField $Isolation 'runFinishedUtc' }
        else { throw 'Fase invalida.' }
        if ([DateTimeOffset]$time -lt [DateTimeOffset]$start -or [DateTimeOffset]$time -gt [DateTimeOffset]$end) { throw 'Evento fuera de fase.' }
        $matched=$allowed.Contains("$src|$dst|$addr|$protocol|$port")
        if ($phase -ceq 'RECORRIDO' -and -not $matched) { throw 'Destino ajeno en recorrido.' }
        if ($phase -ceq 'AUTOCOMPROBACION') {
            if ($matched) { $permitted++ }
            else {
                if ($null -ne $sentinel -or $correlation -cne (Get-BridgeField $Isolation 'sentinelCorrelationId') -or $outcome -cne 'BLOCKED') { throw 'Centinela invalido.' }
                $sentinel=$event
            }
        }
        $channel=Get-BridgeField $event 'channel'
        if($channel -ceq 'SYSCALL'){
            $traceId=Get-BridgeField $event 'traceId'
            if(-not $traceIds.ContainsKey($traceId)){throw 'Evento sin objetivo de traza.'}
            $target=$traceIds[$traceId]
            if([DateTimeOffset]$time -lt [DateTimeOffset]$target.startedUtc -or [DateTimeOffset]$time -gt [DateTimeOffset]$target.finishedUtc){throw 'Evento fuera de cobertura de syscall.'}
            if($phase -ceq 'AUTOCOMPROBACION' -and $matched){$syscallAllowed++}
            if(-not $matched -and ($target.kind -cne 'probe' -or $event.pid -ne $target.pid)){throw 'Centinela sin syscall de sonda.'}
        }elseif($channel -ceq 'PACKET'){
            if(-not $matched){throw 'Paquete denegado sin syscall correlacionada.'}
            if($phase -ceq 'AUTOCOMPROBACION'){$packetAllowed++}
        }else{throw 'Canal de observacion desconocido.'}
    }
    if ($null -eq $sentinel -or $permitted -eq 0 -or $packetAllowed -eq 0 -or $syscallAllowed -eq 0) { throw 'Autocomprobacion incompleta.' }
    $proof=(Get-BridgeField $documents.sentinelProof 'records')[0]
    Assert-BridgeTrue (Get-BridgeField $proof 'blocked') 'blocked'
    foreach ($field in @('sourceId','destinationId','address','protocol','port','correlationId')) {
        if ((Get-BridgeField $proof $field) -cne (Get-BridgeField $sentinel $field)) { throw "Prueba de centinela distinta: $field" }
    }
    $proofRef=Get-BridgeField $proof 'proofRef'; $proofPath=Get-BridgeField $proofRef 'path'
    if ($proofPath -ieq (Get-BridgeField (Get-BridgeField $Isolation 'observation') 'path') -or $proofPath -ieq (Get-BridgeField (Get-BridgeField $Isolation 'sentinelProof') 'path')) { throw 'Prueba no independiente.' }
    $null=Assert-BridgeFile $Root $proofPath (Get-BridgeField $proofRef 'sha256')
}

function Assert-BridgeEvidence([string]$Root, [string]$EvidencePath, [string]$EvidenceSha256, [string]$CatalogPath, [string]$CatalogSha256) {
    # CatalogPath es la ruta confiable entregada por el llamador, no proviene del JSON.
    Assert-BridgeHash $CatalogSha256 'catalogSha256'
    if ((Get-FileHash -LiteralPath $CatalogPath -Algorithm SHA256 -ErrorAction Stop).Hash -ine $CatalogSha256) { throw 'Catalogo alterado.' }
    $evidence = Read-BridgeJson $Root $EvidencePath $EvidenceSha256
    Assert-BridgeEvidenceObject $evidence $Root $CatalogPath $CatalogSha256
}

function Assert-BridgeEvidenceObject($evidence,[string]$Root,[string]$CatalogPath,[string]$CatalogSha256) {
    Assert-BridgeHash $CatalogSha256 'catalogSha256'
    if ((Get-FileHash -LiteralPath $CatalogPath -Algorithm SHA256 -ErrorAction Stop).Hash -ine $CatalogSha256) { throw 'Catalogo alterado.' }
    if (((Get-BridgeField $evidence 'schemaVersion') -isnot [int] -and (Get-BridgeField $evidence 'schemaVersion') -isnot [long]) -or (Get-BridgeField $evidence 'schemaVersion') -ne 2 -or
        (Get-BridgeField $evidence 'kind') -cne 'reservation-bridge-review' -or
        (Get-BridgeField $evidence 'catalogVersion') -cne '1.4.0' -or
        (Get-BridgeField $evidence 'reviewScope') -cne 'local-isolated' -or
        (Get-BridgeField $evidence 'catalogSha256') -ine $CatalogSha256) { throw 'Evidencia invalida.' }
    Assert-BridgeText (Get-BridgeField $evidence 'author') 'author'
    Assert-BridgeUtc (Get-BridgeField $evidence 'reviewedAtUtc') 'reviewedAtUtc'
    $groups = @('legacyReadsAuthorized','v2ReadsVerified','legacyBarrierVerified','rollbackControlsVerified')
    foreach ($group in $groups) { Assert-BridgeTrue (Get-BridgeField $evidence $group) $group }
    $candidateRef = Get-BridgeField $evidence 'candidate'
    $candidateHash = Get-BridgeField $candidateRef 'sha256'
    $candidate = Read-BridgeJson $Root (Get-BridgeField $candidateRef 'path') $candidateHash
    Assert-BridgeCandidate $candidate $Root
    foreach ($field in @('runId','commit','jarPath','jarSha256')) {
        if ((Get-BridgeField $evidence $field) -cne (Get-BridgeField $candidate $field)) { throw "Candidato distinto: $field" }
    }
    $refs = Get-BridgeField $evidence 'reports'
    if ($refs -isnot [array] -or $refs.Count -ne 4) { throw 'Se requieren cuatro reportes.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $isoHash = $null
    foreach ($ref in $refs) {
        $group = Get-BridgeField $ref 'groupId'
        if (-not ($groups -ccontains $group) -or -not $seen.Add($group)) { throw 'Grupo repetido o desconocido.' }
        $report = Read-BridgeJson $Root (Get-BridgeField $ref 'path') (Get-BridgeField $ref 'sha256')
        if ((Get-BridgeField $report 'groupId') -cne $group) { throw 'Grupo de reporte distinto.' }
        Assert-BridgeReport $report $candidate $candidateHash $CatalogSha256 $Root
        if ([DateTimeOffset](Get-BridgeField $report 'finishedAtUtc') -gt [DateTimeOffset](Get-BridgeField $evidence 'reviewedAtUtc')) { throw 'Reporte posterior a revision.' }
        if ($group -cne 'rollbackControlsVerified') {
            $isoRef = Get-BridgeField $report 'isolation'
            $hash = Get-BridgeField $isoRef 'sha256'
            if ($null -ne $isoHash -and $hash -ine $isoHash) { throw 'Aislamiento no compartido.' }
            $isoHash = $hash
            $iso = Read-BridgeJson $Root (Get-BridgeField $isoRef 'path') $hash
            if ((Get-BridgeField $iso 'runId') -cne (Get-BridgeField $candidate 'runId')) { throw 'Run de aislamiento distinto.' }
            Assert-BridgeIsolation $iso $Root
        }
    }
    if ($seen.Count -ne 4) { throw 'Faltan grupos.' }
}
# Comparar una evidencia local no sustituye la observacion ni autoriza operaciones.
