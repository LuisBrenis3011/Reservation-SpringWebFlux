[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LocalIdentity.Common.ps1')
# Se invoca solo manualmente. No arranca Docker ni vuelve a importar el realm.
$credentials=Read-IdentityCredentials
$names=@('cliente-a','cliente-b','cliente-dual')
foreach($name in $names){
    if($null -eq $credentials.accounts.PSObject.Properties[$name]){
        $bytes=New-Object byte[] 24
        $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
        $password=[Convert]::ToBase64String($bytes)
        $credentials.accounts | Add-Member -NotePropertyName $name -NotePropertyValue $password
    }
}
# Conservar las contrasenas incluso si una llamada posterior falla.
Write-PrivateText (Join-Path $script:IdentityPrivate 'credentials.json') ($credentials|ConvertTo-Json -Depth 20)
Sync-LocalIdentityImport
$headers=$null
try{
    $token=Invoke-RestMethod -Method Post -Uri 'http://localhost:8180/realms/master/protocol/openid-connect/token' -Body @{
        client_id='admin-cli';grant_type='password';username=$credentials.adminUser;password=$credentials.adminPassword
    } -TimeoutSec 10
    $headers=@{Authorization=('Bearer '+$token.access_token)}
    $base='http://localhost:8180/admin/realms/eats-hub-local'
    $clients=@(Invoke-RestMethod -Uri ($base+'/clients?clientId=eats-hub-cli') -Headers $headers -TimeoutSec 10)
    $clients=@($clients|Where-Object {$_.clientId -ceq 'eats-hub-cli'})
    if($clients.Count -ne 1 -or !$clients[0].publicClient -or !$clients[0].enabled -or
        $clients[0].protocol -cne 'openid-connect' -or $clients[0].attributes.'access.token.signed.response.alg' -cne 'RS256'){
        throw 'Cliente local incompatible; no se reemplaza.'
    }
    $scopes=@(Invoke-RestMethod -Uri ($base+'/clients/'+$clients[0].id+'/default-client-scopes') -Headers $headers -TimeoutSec 10)
    if(@($scopes|Where-Object {$_.name -ceq 'basic'}).Count -ne 1){throw 'Falta basic; ejecutar la reparacion existente primero.'}
    $template=Get-Content -LiteralPath (Join-Path $script:IdentityRoot 'src/main/resources/identity/eats-hub-local-realm.template.json') -Raw|ConvertFrom-Json
    foreach($expected in $template.clients[0].protocolMappers){
        $actual=@($clients[0].protocolMappers|Where-Object {$_.name -ceq $expected.name})
        if($actual.Count -ne 1 -or $actual[0].protocolMapper -cne $expected.protocolMapper){throw 'Mapper ajeno; no se reemplaza.'}
        foreach($field in $expected.config.PSObject.Properties){
            if($null -eq $actual[0].config.PSObject.Properties[$field.Name] -or $actual[0].config.PSObject.Properties[$field.Name].Value -cne $field.Value){throw 'Configuracion de claims ajena; no se reemplaza.'}
        }
    }
    $roles=@(Invoke-RestMethod -Uri ($base+'/roles') -Headers $headers -TimeoutSec 10)
    $role=@($roles|Where-Object {$_.name -ceq 'CUSTOMER'})
    if($role.Count -eq 0){
        $null=Invoke-RestMethod -Method Post -Uri ($base+'/roles') -Headers $headers -ContentType 'application/json' -Body '{"name":"CUSTOMER","description":"Cliente de reservas propias de Eats Hub"}' -TimeoutSec 10
        $role=@(Invoke-RestMethod -Uri ($base+'/roles/CUSTOMER') -Headers $headers -TimeoutSec 10)
    }
    if($role.Count -ne 1 -or $role[0].description -cne 'Cliente de reservas propias de Eats Hub' -or $role[0].composite){throw 'Rol CUSTOMER ajeno; conservar y revisar.'}
    $manager=Invoke-RestMethod -Uri ($base+'/roles/RESTAURANT_MANAGER') -Headers $headers -TimeoutSec 10
    $groups=@(Invoke-RestMethod -Uri ($base+'/groups') -Headers $headers -TimeoutSec 10)
    foreach($name in $names){
        $expectedRoles=@($role[0]);if($name -eq 'cliente-dual'){$expectedRoles+=,$manager}
        $users=@(Invoke-RestMethod -Uri ($base+'/users?exact=true&username='+[Uri]::EscapeDataString($name)) -Headers $headers -TimeoutSec 10)
        $users=@($users|Where-Object {$_.username -ceq $name})
        if($users.Count -gt 1){throw 'Usuario ambiguo.'}
        if($users.Count -eq 0){
            $body=@{username=$name;enabled=$true;emailVerified=$true;firstName='Demo';lastName=$name;email=($name+'@example.test');requiredActions=@();
                attributes=@{eats_hub_fixture=@('reservations-v1')};credentials=@(@{type='password';temporary=$false;value=$credentials.accounts.PSObject.Properties[$name].Value})}|ConvertTo-Json -Depth 10
            $null=Invoke-RestMethod -Method Post -Uri ($base+'/users') -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 10
            $users=@(Invoke-RestMethod -Uri ($base+'/users?exact=true&username='+$name) -Headers $headers -TimeoutSec 10)
        }
        if($users.Count -ne 1 -or !$users[0].enabled -or $null -eq $users[0].PSObject.Properties['attributes'] -or
            $null -eq $users[0].attributes.PSObject.Properties['eats_hub_fixture'] -or @($users[0].attributes.eats_hub_fixture) -notcontains 'reservations-v1'){
            throw 'Colision de usuario: no se modifican cuentas ajenas.'
        }
        $userPath=$base+'/users/'+[Uri]::EscapeDataString([string]$users[0].id)
        $assigned=@(Invoke-RestMethod -Uri ($userPath+'/role-mappings/realm') -Headers $headers -TimeoutSec 10)
        if(@($assigned|Where-Object {$_.name -in @('CUSTOMER','RESTAURANT_MANAGER') -and $_.name -notin @($expectedRoles|ForEach-Object {$_.name})}).Count){throw 'Roles existentes incompatibles; no se eliminan.'}
        $missing=@($expectedRoles|Where-Object {$_.id -notin @($assigned|ForEach-Object {$_.id})})
        if($missing.Count){$null=Invoke-RestMethod -Method Post -Uri ($userPath+'/role-mappings/realm') -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -InputObject $missing -Depth 10) -TimeoutSec 10}
        $assignedGroups=@(Invoke-RestMethod -Uri ($userPath+'/groups') -Headers $headers -TimeoutSec 10)
        if($name -eq 'cliente-dual'){
            $group=@($groups|Where-Object {$_.name -ceq $script:RestaurantA})
            if($group.Count -ne 1 -or @($assignedGroups|Where-Object {$_.id -ne $group[0].id}).Count){throw 'Grupos ajenos; no se reemplazan.'}
            if($assignedGroups.Count -eq 0){$null=Invoke-RestMethod -Method Put -Uri ($userPath+'/groups/'+$group[0].id) -Headers $headers -TimeoutSec 10}
        }elseif($assignedGroups.Count){throw 'Cliente con grupos ajenos; revisar sin sobrescribir.'}
    }
    Write-Host 'Clientes locales preparados; usuarios anteriores y contrasenas conservados. Solicita tokens nuevos manualmente.'
}catch{throw 'No se completo la preparacion de clientes. Se conservaron las credenciales y las cuentas existentes; revisar Keycloak y reintentar.'}
finally{$headers=$null;$token=$null;$credentials=$null}
