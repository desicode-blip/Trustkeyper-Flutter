param([Parameter(Mandatory = $true)][ValidateSet('trustkeyper')][string]$Project,
    [Parameter(Mandatory = $true)][int]$Build)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$firebase = 'C:/Users/ajayb/AppData/Roaming/npm/firebase.ps1'
$names = @('readTenantSetup', 'recordTenantSetup', 'listTenantSetupRequests', 'resolveTenantSetupRequest')
$previousTimeout = $env:FUNCTIONS_DISCOVERY_TIMEOUT
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
try {
    $targets = ($names | ForEach-Object { "functions:authentication:$_" }) -join ','
    & $firebase deploy --project $Project --account ajay@trustkeyper.com --only $targets --non-interactive `
        *> (Join-Path $root "output/ui-audit/build$Build-tenant-setup-deploy.log")
    if ($LASTEXITCODE -ne 0) { throw 'Tenant setup deployment failed. Read the saved diagnostic log.' }
    Write-Output 'The four tenant setup callables deployed successfully.'
} finally { $env:FUNCTIONS_DISCOVERY_TIMEOUT = $previousTimeout }
