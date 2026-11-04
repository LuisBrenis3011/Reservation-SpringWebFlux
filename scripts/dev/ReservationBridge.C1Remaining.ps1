# Ejecutores de etapas C1. Solo las fronteras de transporte/proceso se sustituyen.
function Assert-BridgeC1ConfirmationExpectation([string]$Encoded,$View){
 try{
  $value=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Encoded))|ConvertFrom-Json -ErrorAction Stop
  foreach($id in @($value.restaurantId,$value.reservationId,$value.body.shiftId)){
   $parsed=[guid]::Empty
   if($id -isnot [string] -or -not [guid]::TryParseExact($id,'D',[ref]$parsed)){throw 'UUID invalido'}
  }
  if($value.restaurantId -cne $View.restaurantId -or $value.reservationId -cne $View.id -or $value.body.shiftId -cne $View.shiftId -or
     $value.issuer -cne $View.owner.issuer -or $value.subject -cne $View.owner.subject -or $value.key -cne 'c1-key' -or $value.match -cne '' -or
     $value.body.partySize -isnot [int] -or $value.body.partySize -lt 1 -or $value.body.partySize -gt 20 -or
     $value.body.partySize -ne $View.partySize -or $value.body.notes -isnot [string] -or $value.body.notes -cne $View.notes){throw 'Expectativas discordantes'}
 }catch{throw ('Expectativas C1 invalidas: '+$_.Exception.Message)}
}
function Invoke-BridgeC1ManagedCases([string]$FixtureRoot) {
    $entry=Join-Path $PSScriptRoot 'Test-LocalManagedReservationRollback.ps1'
    $results=@{}
    foreach($target in @('Prepare','StartPrevious','Previous','Current')) {
        foreach($policyState in @('CUT','NOCUT','READFAIL')) {
            if($null -ne (Get-Variable BridgeC1StageProbe -Scope Global -ErrorAction SilentlyContinue)){throw 'Ejecutor C1 ya activo.'}
            $module=$null
            $oldExit=Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
            $hadExit=$null -ne $oldExit;$savedExit=$null;if($hadExit){$savedExit=$oldExit.Value}
            $tokenName='EATS_C1_SYNTHETIC_TOKEN';$oldToken=[Environment]::GetEnvironmentVariable($tokenName,'Process')
            try {
                $module=New-Module -ArgumentList $entry,$FixtureRoot,${function:Assert-BridgeC1ConfirmationExpectation} -ScriptBlock {
                    param($entryPath,$fixturePath,$expectationValidator)
                    . $entryPath -Stage Prepare
                    Set-Item -Path Function:Assert-C1Expected -Value $expectationValidator
                    $script:ManagedBridgeCatalog=Join-Path $fixturePath 'catalog.md'
                    $script:ManagedBridgeScripts=Join-Path $fixturePath 'current-scripts'
                    $script:IdentityRoot=Join-Path $fixturePath ('managed-stage-'+[guid]::NewGuid().ToString('N'))
                    $script:IdentityPrivate=Join-Path $script:IdentityRoot 'secrets/local-identity'
                    [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
                    $script:BridgeEvidence=Join-Path $fixturePath 'bridge-evidence.json'
                    $script:BridgeCommit='';$script:WritersStopped=$true
                    $script:BackupDirectory=Join-Path $script:IdentityRoot 'backups/availability/synthetic'
                    [IO.Directory]::CreateDirectory($script:BackupDirectory)|Out-Null
                    function Save-C1Json([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($false))}
                    function Get-C1Tree([string]$Root){return @((Get-ChildItem -LiteralPath $Root -File -Recurse|Sort-Object FullName)|ForEach-Object{$_.FullName.Substring($Root.Length)+'='+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}) -join "`n"}
                    [IO.File]::WriteAllText((Join-Path $script:IdentityRoot '.env'),"MONGODB_HOST=localhost`nMONGODB_PORT=27018`nMONGODB_DATABASE=c1_synthetic`n")
                    $bridge=Assert-ManagedBridge $script:BridgeEvidence
                    $view=[pscustomobject]@{kind='MANAGED';id='55555555-5555-4555-8555-555555555555';restaurantId=$script:RestaurantA;shiftId='44444444-4444-4444-8444-444444444444';partySize=2;version=2;status='CONFIRMED';notes='synthetic';owner=@{issuer='c1-synthetic';subject='c1-user'};tableIds=@('66666666-6666-4666-8666-666666666666');zoneId='UTC';startInstant='2035-01-01T12:00:00Z';endInstant='2035-01-01T13:00:00Z'}
                    $proof=[pscustomobject]@{retired=$true}
                    $manifest=[pscustomobject]@{database='c1_synthetic';collections=@([pscustomobject]@{name='reservation_policy';documents=@($proof);indexes=@('_id_')})}
                    $global:BridgeC1StageProbe=[pscustomobject]@{state='CUT';phase='Prepare';commit=$bridge.commit;manifest=$manifest;view=$view;policyReads=0;manifestReads=0;git=0;java=0;http=0;forbidden=0;sessionPath=(Join-Path $script:IdentityPrivate 'managed-reservations-rollback-session.json')}
                    $claims=@{iss='c1-synthetic';sub='c1-user';exp=([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+3600)}
                    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($claims|ConvertTo-Json -Compress))).TrimEnd('=').Replace('+','-').Replace('/','_')
                    [Environment]::SetEnvironmentVariable('EATS_C1_SYNTHETIC_TOKEN',('synthetic.'+$encoded+'.synthetic'),'Process')
                    $checkpoint=Join-Path $script:IdentityPrivate 'reservation-confirmation-http-checkpoint.json'
                    $intent=@{shiftId=$view.shiftId;partySize=$view.partySize;notes=$view.notes}|ConvertTo-Json -Compress
                    Save-C1Json $checkpoint @{spec='SPEC-005';final=@{synthetic=$true};pendingName='';steps=@(@{expected=201;response=@{body=@{id=$view.id}};actor='EATS_C1_SYNTHETIC_TOKEN';identity=@{issuer=$claims.iss;subject=$claims.sub};body=$intent;key='c1-key'})}
                    $before=[pscustomobject]@{database=$manifest.database;collections=$manifest.collections;managedProof=$proof}
                    foreach($name in @('source-before.json','source-after.json','restored.json')){Save-C1Json (Join-Path $script:BackupDirectory $name) $before}
                    $archive=Join-Path $script:BackupDirectory 'database.archive.gz';[IO.File]::WriteAllText($archive,'synthetic archive: hash-only fixture')
                    $checkpointHashes=[ordered]@{};$checkpointHashes[$checkpoint]=(Get-FileHash -LiteralPath $checkpoint -Algorithm SHA256).Hash
                    Save-C1Json (Join-Path $script:BackupDirectory 'managed-validation.json') @{spec='SPEC-005';validation=@{restoreVerified=$true;sourceUnchanged=$true;writersStoppedDeclared=$true;database='c1_synthetic';archiveSha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash};proof=$proof;checkpointHashes=$checkpointHashes}
                    function docker {
                        $global:LASTEXITCODE=0
                        $arguments=$args -join ' '
                        if($arguments -match 'EATS_MANAGED_PROOF='){
                            $global:BridgeC1StageProbe.policyReads++
                            if($global:BridgeC1StageProbe.state -ceq 'READFAIL'){throw 'C1_LECTOR_GESTIONADO_FALLIDO'}
                            return (@{verified=$true;retired=($global:BridgeC1StageProbe.state -ceq 'CUT')}|ConvertTo-Json -Compress)
                        }
                        $global:BridgeC1StageProbe.manifestReads++
                        if($arguments -match 'EATS_CANCELLATION_EXPECTATIONS_BASE64='){
                            $refs=@($args|Where-Object {([string]$_).StartsWith('EATS_CANCELLATION_EXPECTATIONS_BASE64=')})
                            if($refs.Count -ne 1){throw 'Canal de expectativas duplicado o ausente'}
                            $payload=([string]$refs[0]).Substring('EATS_CANCELLATION_EXPECTATIONS_BASE64='.Length)
                            Assert-C1Expected $payload $global:BridgeC1StageProbe.view
                            return (@{reservationView=$global:BridgeC1StageProbe.view}|ConvertTo-Json -Depth 30 -Compress)
                        }
                        if($arguments -match 'EATS_BACKUP_SOURCE=true'){return ($global:BridgeC1StageProbe.manifest|ConvertTo-Json -Depth 30 -Compress)}
                        $global:BridgeC1StageProbe.forbidden++;throw 'C1_TRANSPORTE_NO_PREVISTO'
                    }
                    function git {
                        $global:BridgeC1StageProbe.git++;$global:LASTEXITCODE=0
                        switch([string]$args[0]){
                            'rev-parse'{return $global:BridgeC1StageProbe.commit}
                            'diff'{return}
                            'ls-files'{return}
                            'cat-file'{return}
                            default{$global:BridgeC1StageProbe.forbidden++;throw 'C1_GIT_NO_PREVISTO'}
                        }
                    }
                    function java { $global:BridgeC1StageProbe.java++;$global:LASTEXITCODE=0 }
                    function Get-NetTCPConnection {
                        if($global:BridgeC1StageProbe.phase -cin @('Previous','Current')){return [pscustomobject]@{OwningProcess=42}}
                    }
                    function Get-CimInstance {
                        $s=Get-Content -LiteralPath $global:BridgeC1StageProbe.sessionPath -Raw|ConvertFrom-Json
                        $command=if($global:BridgeC1StageProbe.phase -ceq 'Previous'){'java -jar '+$s.jar}else{'java -jar current.jar'}
                        return [pscustomobject]@{CommandLine=$command}
                    }
                    function Invoke-LocalHttp([string]$Uri,[hashtable]$Headers=@{}) {
                        $global:BridgeC1StageProbe.http++
                        if($Uri.EndsWith('/restaurants')){return [pscustomobject]@{Status=200;Headers=@{};Content='[]'}}
                        if($Uri.EndsWith('/reservations')){
                            $status=if($global:BridgeC1StageProbe.phase -ceq 'Previous'){404}else{401}
                            return [pscustomobject]@{Status=$status;Headers=@{};Content='{}'}
                        }
                        if($Uri.EndsWith('/'+$global:BridgeC1StageProbe.view.id)){
                            if(-not $Headers.ContainsKey('Authorization') -or $Headers.Authorization -notlike 'Bearer *'){throw 'GET sintetico sin identidad'}
                            return [pscustomobject]@{Status=200;Headers=@{ETag='"2"'};Content=($global:BridgeC1StageProbe.view|ConvertTo-Json -Compress)}
                        }
                        $global:BridgeC1StageProbe.forbidden++;throw 'C1_HTTP_NO_PREVISTO'
                    }
                    function Invoke-WebRequest { $global:BridgeC1StageProbe.forbidden++;throw 'C1_HTTP_REAL_PROHIBIDO' }
                    function Invoke-RestMethod { $global:BridgeC1StageProbe.forbidden++;throw 'C1_HTTP_REAL_PROHIBIDO' }
                    function Start-Process { $global:BridgeC1StageProbe.forbidden++;throw 'C1_PROCESO_REAL_PROHIBIDO' }
                    function Invoke-C1ManagedTrial([string]$Target,[string]$State){
                        $sequence=@('Prepare','StartPrevious','Previous','Current')
                        foreach($step in $sequence){
                            if($step -ceq $Target){break}
                            $script:Stage=$step;$global:BridgeC1StageProbe.phase=$step
                            Invoke-ManagedRollback
                        }
                        $treeBefore=Get-C1Tree $script:IdentityRoot
                        foreach($field in @('policyReads','manifestReads','git','java','http','forbidden')){$global:BridgeC1StageProbe.$field=0}
                        $global:BridgeC1StageProbe.state=$State;$global:BridgeC1StageProbe.phase=$Target;$script:Stage=$Target
                        $failure='';try{Invoke-ManagedRollback}catch{$failure=$_.Exception.Message}
                        $p=$global:BridgeC1StageProbe
                        $untouched=$treeBefore -ceq (Get-C1Tree $script:IdentityRoot)
                        $session=$null;if(Test-Path -LiteralPath $p.sessionPath){$session=Get-Content -LiteralPath $p.sessionPath -Raw|ConvertFrom-Json}
                        if($State -ceq 'CUT'){
                            $valid=$failure -ceq '' -and $null -ne $session -and $session.schemaVersion -eq 2 -and (Get-BridgeHash $session.jar) -ieq $session.jarSha256
                            switch($Target){
                                'Prepare'{$valid=$valid -and -not $session.previousStarted -and $p.java -eq 0 -and $p.http -eq 0}
                                'StartPrevious'{$valid=$valid -and $session.previousStarted -and $p.java -eq 1}
                                'Previous'{$valid=$valid -and $session.previousVerified -and $p.http -eq 2}
                                'Current'{$valid=$valid -and $session.currentVerified -and $p.http -eq 3}
                            }
                        }else{
                            $expected=if($State -ceq 'NOCUT'){'Reversion v2 exige corte persistente activo verificado'}else{'C1_LECTOR_GESTIONADO_FALLIDO'}
                            $valid=$failure -like ('*'+$expected+'*') -and $untouched -and $p.java -eq 0 -and $p.http -eq 0 -and $p.git -eq 0 -and $p.manifestReads -eq 0
                        }
                        $valid=$valid -and $p.policyReads -gt 0 -and $p.forbidden -eq 0
                        return [pscustomobject]@{passed=[bool]$valid;failure=$failure;policyReads=$p.policyReads;java=$p.java;http=$p.http;git=$p.git;manifestReads=$p.manifestReads;forbidden=$p.forbidden;unchanged=$untouched;root=$script:IdentityRoot}
                    }
                    Export-ModuleMember -Function Invoke-C1ManagedTrial
                }
                $result=& $module {param($t,$s) Invoke-C1ManagedTrial $t $s} $target $policyState
                $results[('C1-MANAGED-'+$target.ToUpperInvariant()+'-'+$policyState)]=$result
            } catch {
                # Fallo de preparacion: no se anuncio que la etapa se hubiera ejecutado.
                $results[('C1-MANAGED-'+$target.ToUpperInvariant()+'-'+$policyState)]=[pscustomobject]@{passed=$false;pending=$true;failure=$_.Exception.Message}
            } finally {
                if($null -ne $module){Remove-Module $module -Force -ErrorAction SilentlyContinue}
                Remove-Variable BridgeC1StageProbe -Scope Global -ErrorAction SilentlyContinue
                [Environment]::SetEnvironmentVariable($tokenName,$oldToken,'Process')
                if($hadExit){$global:LASTEXITCODE=$savedExit}else{Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue}
            }
        }
    }
    # Cada negativo necesita un control positivo de la misma etapa, ademas de la siembra real.
    foreach($target in @('PREPARE','STARTPREVIOUS','PREVIOUS','CURRENT')){
        $positive=$results[('C1-MANAGED-'+$target+'-CUT')]
        foreach($state in @('NOCUT','READFAIL')){
            $negative=$results[('C1-MANAGED-'+$target+'-'+$state)]
            if(-not $positive.passed){$negative.passed=$false;$negative|Add-Member -NotePropertyName pending -NotePropertyValue $true -Force}
        }
    }
    return $results
}

function Invoke-BridgeC1HistoryCases([string]$Directory){
    $entry=Join-Path $PSScriptRoot 'Test-LocalVersionRollback.ps1'
    $results=@{};$history=@()
    foreach($mode in @('DEFAULT','COMBINATIONS','SHIFTS')){
        if($null -ne (Get-Variable BridgeC1HistoryProbe -Scope Global -ErrorAction SilentlyContinue)){throw 'Ejecutor historico C1 ya activo.'}
        $module=$null;$oldExit=Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        $hadExit=$null -ne $oldExit;$savedExit=$null;if($hadExit){$savedExit=$oldExit.Value}
        try{
            $root=Join-Path $Directory ('c1-history-'+[guid]::NewGuid().ToString('N'))
            $module=New-Module -ArgumentList $entry,$root,$mode -ScriptBlock {
                param($entryPath,$rootPath,$modeValue)
                . $entryPath -Stage Prepare
                $script:IdentityRoot=$rootPath;$script:IdentityPrivate=Join-Path $rootPath 'secrets/local-identity'
                [IO.Directory]::CreateDirectory($script:IdentityPrivate)|Out-Null
                $script:IncludeManagedReservations=$false;$script:IncludeCombinations=$modeValue -ceq 'COMBINATIONS';$script:IncludeShifts=$modeValue -ceq 'SHIFTS'
                $script:BridgeEvidence='';$script:BridgeCommit='';$script:WritersStopped=$true;$script:BackupDirectory=''
                function Save-C1Json([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 50),[Text.UTF8Encoding]::new($false))}
                function Get-C1Tree([string]$Root){return @((Get-ChildItem -LiteralPath $Root -File -Recurse|Sort-Object FullName)|ForEach-Object{$_.FullName.Substring($Root.Length)+'='+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}) -join "`n"}
                [IO.File]::WriteAllText((Join-Path $rootPath '.env'),"MONGODB_HOST=localhost`nMONGODB_PORT=27018`nMONGODB_DATABASE=c1_synthetic`n")
                $manifest=[pscustomobject]@{database='c1_synthetic';collections=@([pscustomobject]@{name='synthetic';documents=@();indexes=@('_id_')})}
                $global:BridgeC1HistoryProbe=[pscustomobject]@{state='NOCUT';manifest=$manifest;policyReads=0;manifestReads=0;git=0;java=0;build=0;forbidden=0}
                if($modeValue -ceq 'DEFAULT'){
                    $checks=@(1..6|ForEach-Object{@{passed=$true}})
                    foreach($name in @('legacy-disabled-validation.json','legacy-enabled-validation.json')){Save-C1Json (Join-Path $script:IdentityPrivate $name) @{createdFixtureRemoved=$true;restaurantAUnchanged=$true;initialRevision=1;finalRevision=4;checks=$checks}}
                }else{
                    $script:BackupDirectory=Join-Path $rootPath 'backups/availability/synthetic'
                    [IO.Directory]::CreateDirectory($script:BackupDirectory)|Out-Null
                    $prefix=if($modeValue -ceq 'COMBINATIONS'){'combinations'}else{'shifts'}
                    $number=if($modeValue -ceq 'COMBINATIONS'){'002'}else{'003'}
                    $proof=[ordered]@{acceptedReceipts=7;revision=1}
                    if($modeValue -ceq 'COMBINATIONS'){$proof.uniqueIndex='restaurant_combination_members_unique'}else{$proof.shifts=2;$proof.zoneIndex='_id_';$proof.shiftIndex='restaurant_shift_interval'}
                    $httpPath=Join-Path $script:IdentityPrivate ($prefix+'-http-checkpoint.json')
                    $gatePath=Join-Path $script:IdentityPrivate ($prefix+'-gate-checkpoint.json')
                    Save-C1Json $httpPath @{runId='c1';final=@{revision=1}}
                    Save-C1Json $gatePath @{synthetic=$true}
                    $archive=Join-Path $script:BackupDirectory 'database.archive.gz';[IO.File]::WriteAllText($archive,'synthetic archive')
                    $before=[ordered]@{database=$manifest.database;collections=$manifest.collections}
                    $before[($prefix+'Proof')]=$proof
                    foreach($name in @('source-before.json','source-after.json','restored.json')){Save-C1Json (Join-Path $script:BackupDirectory $name) $before}
                    Save-C1Json (Join-Path $script:BackupDirectory ('spec-'+$number+'-validation.json')) @{spec=('SPEC-'+$number);database='c1_synthetic';restoreVerified=$true;sourceUnchanged=$true;writersStoppedDeclared=$true;runId='c1';proof=$proof;archiveSha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash;httpCheckpointSha256=(Get-FileHash -LiteralPath $httpPath -Algorithm SHA256).Hash;gateCheckpointSha256=(Get-FileHash -LiteralPath $gatePath -Algorithm SHA256).Hash}
                }
                function docker {
                    $global:LASTEXITCODE=0
                    if(($args -join ' ') -match 'EATS_MANAGED_PROOF='){
                        $global:BridgeC1HistoryProbe.policyReads++
                        return (@{verified=$true;retired=($global:BridgeC1HistoryProbe.state -ceq 'CUT')}|ConvertTo-Json -Compress)
                    }
                    if(($args -join ' ') -match 'EATS_BACKUP_SOURCE=true'){$global:BridgeC1HistoryProbe.manifestReads++;return ($global:BridgeC1HistoryProbe.manifest|ConvertTo-Json -Depth 30 -Compress)}
                    $global:BridgeC1HistoryProbe.forbidden++;throw 'C1_TRANSPORTE_HISTORICO_NO_PREVISTO'
                }
                function git {
                    $global:BridgeC1HistoryProbe.git++;$global:LASTEXITCODE=0
                    switch([string]$args[0]){
                        'rev-parse'{if($args -contains '--verify'){return ([string]$args[-1]).Replace('^{commit}','')};return ('a'*40)}
                        'diff'{return}
                        'ls-files'{return}
                        'archive'{
                            $output=@($args|Where-Object {([string]$_).StartsWith('--output=')})
                            if($output.Count -ne 1){throw 'Archive sintetico sin destino'}
                            [IO.File]::WriteAllText(([string]$output[0]).Substring(9),'synthetic archive');return
                        }
                        default{$global:BridgeC1HistoryProbe.forbidden++;throw 'C1_GIT_HISTORICO_NO_PREVISTO'}
                    }
                }
                function Expand-Archive([string]$LiteralPath,[string]$DestinationPath){
                    if(-not (Test-Path -LiteralPath $LiteralPath)){throw 'Archive doble ausente'}
                    $libs=Join-Path $DestinationPath 'build/libs';[IO.Directory]::CreateDirectory($libs)|Out-Null
                    [IO.File]::WriteAllText((Join-Path $libs 'previous.jar'),'synthetic JAR')
                }
                function Invoke-LocalRollbackBuild { $global:BridgeC1HistoryProbe.build++;$global:LASTEXITCODE=0 }
                function java { $global:BridgeC1HistoryProbe.java++;$global:LASTEXITCODE=0 }
                function Get-NetTCPConnection { return @() }
                function Invoke-WebRequest { $global:BridgeC1HistoryProbe.forbidden++;throw 'C1_HTTP_HISTORICO_PROHIBIDO' }
                function Invoke-RestMethod { $global:BridgeC1HistoryProbe.forbidden++;throw 'C1_HTTP_HISTORICO_PROHIBIDO' }
                function Get-CimInstance { $global:BridgeC1HistoryProbe.forbidden++;throw 'C1_PROCESO_HISTORICO_PROHIBIDO' }
                function Start-Process { $global:BridgeC1HistoryProbe.forbidden++;throw 'C1_PROCESO_HISTORICO_PROHIBIDO' }
                function Invoke-C1HistoryTrial {
                    $script:Stage='Prepare';Invoke-HistoricalRollback
                    $name=if($script:IncludeCombinations){'combinations-rollback-session.json'}elseif($script:IncludeShifts){'shifts-rollback-session.json'}else{'rollback-session.json'}
                    $sessionPath=Join-Path $script:IdentityPrivate $name
                    $original=[IO.File]::ReadAllBytes($sessionPath)
                    $session=Get-Content -LiteralPath $sessionPath -Raw|ConvertFrom-Json
                    $prepared=$global:BridgeC1HistoryProbe.build -eq 1 -and (Get-FileHash -LiteralPath $session.jar -Algorithm SHA256).Hash -ceq $session.jarSha256
                    $script:Stage='StartPrevious';Invoke-HistoricalRollback
                    $positive=$global:BridgeC1HistoryProbe.java -eq 1
                    # Nueva rama de la misma sesion preparada: se conserva el resultado positivo.
                    [IO.File]::WriteAllBytes(($sessionPath+'.positive'),[IO.File]::ReadAllBytes($sessionPath))
                    [IO.File]::WriteAllBytes($sessionPath,$original)
                    $before=Get-C1Tree $script:IdentityRoot
                    foreach($field in @('policyReads','manifestReads','git','java','build','forbidden')){$global:BridgeC1HistoryProbe.$field=0}
                    $global:BridgeC1HistoryProbe.state='CUT'
                    $failure='';try{Invoke-HistoricalRollback}catch{$failure=$_.Exception.Message}
                    $p=$global:BridgeC1HistoryProbe
                    $unchanged=$before -ceq (Get-C1Tree $script:IdentityRoot)
                    $passed=$prepared -and $positive -and $failure -like '*Corte persistente activo*' -and $p.policyReads -eq 1 -and $p.java -eq 0 -and $p.build -eq 0 -and $p.git -eq 0 -and $p.manifestReads -eq 0 -and $p.forbidden -eq 0 -and $unchanged
                    return [pscustomobject]@{passed=[bool]$passed;prepared=$prepared;positiveStart=$positive;failure=$failure;policyReads=$p.policyReads;java=$p.java;build=$p.build;git=$p.git;forbidden=$p.forbidden;sessionPreserved=$unchanged;root=$script:IdentityRoot}
                }
                Export-ModuleMember -Function Invoke-C1HistoryTrial
            }
            $result=& $module {Invoke-C1HistoryTrial}
            $results[('C1-RACE-'+$mode)]=$result;$history+=@($result)
        }catch{
            $result=[pscustomobject]@{passed=$false;pending=$true;failure=$_.Exception.Message}
            $results[('C1-RACE-'+$mode)]=$result;$history+=@($result)
        }finally{
            if($null -ne $module){Remove-Module $module -Force -ErrorAction SilentlyContinue}
            Remove-Variable BridgeC1HistoryProbe -Scope Global -ErrorAction SilentlyContinue
            if($hadExit){$global:LASTEXITCODE=$savedExit}else{Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue}
        }
    }
    $historyPassed=$history.Count -eq 3 -and @($history|Where-Object {-not $_.passed}).Count -eq 0
    $results['C1-SESSION-HISTORY']=[pscustomobject]@{passed=$historyPassed;pending=(-not $historyPassed);modes=$history}
    return $results
}
