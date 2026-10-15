param([Parameter(Mandatory = $true)][ValidateSet('trustkeyper')][string]$Project,
    [Parameter(Mandatory = $true)][int]$Build)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$firebase = 'C:/Users/ajayb/AppData/Roaming/npm/firebase.ps1'
$names = @('readAccountProfile', 'saveAccountProfile', 'readAccountClosure', 'closeAccount',
    'listAccountClosures', 'finishAccountClosure', 'restoreClosedAccount')
$previousTimeout = $env:FUNCTIONS_DISCOVERY_TIMEOUT
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
try {
    $targets = ($names | ForEach-Object { "functions:authentication:$_" }) -join ','
    & $firebase deploy --project $Project --account ajay@trustkeyper.com --only $targets --non-interactive `
        *> (Join-Path $root "output/ui-audit/build$Build-account-deploy.log")
    if ($LASTEXITCODE -ne 0) {
        $log = Join-Path $root "output/ui-audit/build$Build-account-deploy.log"
        $failures = @(Select-String -LiteralPath $log -Pattern '^- Error ')
        $invokers = @(Select-String -LiteralPath $log -Pattern '^- Error Failed to set invoker function (\w+) in region asia-south1$')
        if (!$failures.Count -or $failures.Count -ne $invokers.Count -or
            @($invokers | Where-Object { $_.Matches[0].Groups[1].Value -notin $names }).Count) {
            throw 'Account deployment failed. Read the saved diagnostic log.'
        }
        Write-Output 'Only invoker IAM configuration failed. Verifying all seven active services before applying the existing callable transport configuration.'
    }
    & node (Join-Path $PSScriptRoot 'configure-callable-transport.cjs') "--project=$Project" --apply "--functions=$($names -join ',')" `
        *> (Join-Path $root "output/ui-audit/build$Build-account-transport.log")
    if ($LASTEXITCODE -ne 0) { throw 'Account callable transport verification failed.' }
    Write-Output 'The seven account callables deployed and their normal authenticated transport is configured.'
} finally { $env:FUNCTIONS_DISCOVERY_TIMEOUT = $previousTimeout }
