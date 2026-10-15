param([Parameter(Mandatory = $true)][ValidateSet('trustkeyper')][string]$Project,
    [Parameter(Mandatory = $true)][int]$Build)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$firebase = 'C:/Users/ajayb/AppData/Roaming/npm/firebase.ps1'
$names = @('createDocumentRequest', 'readDocumentRequest', 'recordDocumentRequest', 'beginDocumentUpload', 'completeDocumentUpload')
$previousTimeout = $env:FUNCTIONS_DISCOVERY_TIMEOUT
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
try {
    foreach ($name in $names) {
        Write-Output "Deploying $name"
        $log = Join-Path $root "output/ui-audit/build$Build-deploy-$name.log"
        & $firebase deploy --project $Project --account ajay@trustkeyper.com --only "functions:authentication:$name" --non-interactive *> $log
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $log -Tail 12
            throw 'The affected callable failed to deploy. Remaining functions were not changed.'
        }
    }
} finally { $env:FUNCTIONS_DISCOVERY_TIMEOUT = $previousTimeout }
