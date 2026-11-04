# Configuracion explicita del JAR. No lee .env ni crea procesos al cargarse.
function New-BridgeApplicationArguments($Endpoints, [bool]$Gate) {
    $expected=@{MONGO=27017;REDIS=6379;JWKS=8081}
    $values=@{}
    $addresses=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($role in @('MONGO','REDIS','JWKS')) {
        $endpoint=Get-BridgeField $Endpoints $role
        $address=Get-BridgeField $endpoint 'address'
        $port=Get-BridgeField $endpoint 'port'
        $parsed=[Net.IPAddress]::None
        if ($address -isnot [string] -or -not [Net.IPAddress]::TryParse($address,[ref]$parsed) -or
            $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
            [Net.IPAddress]::IsLoopback($parsed) -or $parsed.ToString() -cne $address -or
            $address -eq '0.0.0.0' -or $address -eq '255.255.255.255') { throw 'Endpoint aislado invalido.' }
        if (($port -isnot [int] -and $port -isnot [long]) -or $port -ne $expected[$role]) { throw 'Puerto aislado invalido.' }
        if (-not $addresses.Add($address)) { throw 'Direcciones de servicios duplicadas.' }
        $values[$role]=$address
    }
    $uri='mongodb://'+$values.MONGO+':27017/bridge?replicaSet=bridgeRs'
    $jwks='http://'+$values.JWKS+':8081'
    $gateText=if($Gate){'true'}else{'false'}
    return @(
        '-Djava.net.preferIPv4Stack=true',
        '-jar','/opt/bridge.jar',
        '--spring.config.location=classpath:/application.properties',
        '--spring.config.import=',
        '--spring.profiles.active=',
        '--server.address=0.0.0.0','--server.port=8080',
        ('--mongodb.uri='+$uri),'--mongodb.database=bridge',
        ('--mongodb.host='+$values.MONGO),'--mongodb.port=27017',
        '--mongodb.username=bridge','--mongodb.password=',
        '--mongodb.authentication-database=admin',
        ('--spring.mongodb.uri='+$uri),
        ('--spring.data.mongodb.uri='+$uri),
        ('--REDIS_HOST='+$values.REDIS),'--REDIS_PORT=6379',
        '--REDIS_DATABASE=0','--REDIS_PASSWORD=',
        '--availability.enabled=true',
        ('--availability.issuer-uri='+$jwks),
        ('--availability.jwk-set-uri='+$jwks+'/jwks'),
        '--availability.audience=eats-hub-catalog',
        ('--reservations.enabled='+$gateText)
    )
}

function Assert-BridgeApplicationHolder($Inspection) {
    $config=Get-BridgeField $Inspection 'Config'
    $entry=Get-BridgeField $config 'Entrypoint'
    $command=Get-BridgeField $config 'Cmd'
    if ($entry -isnot [array] -or $entry.Count -ne 1 -or $entry[0] -cne '/bin/sh' -or
        $command -isnot [array] -or $command.Count -ne 2 -or $command[0] -cne '-c' -or
        $command[1] -cne 'while :; do sleep 3600; done') { throw 'La aplicacion no tiene el proceso de espera esperado.' }
    # Este proceso mantiene el espacio de red. No debe arrancar Java por defecto.
}
