param([Parameter(Mandatory = $true)][ValidateSet('trustkeyper')][string]$Project,
    [Parameter(Mandatory = $true)][int]$Build,
    [ValidateRange(1, 2)][int]$BatchSize = 2)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$firebase = 'C:/Users/ajayb/AppData/Roaming/npm/firebase.ps1'
$names = @('createDocumentRequest', 'readDocumentRequest', 'recordDocumentRequest',
    'beginDocumentUpload', 'completeDocumentUpload', 'saveOwnerPropertyStep',
    'requestAgreementReview', 'recordAgreementReview', 'prepareAgreementApproval',
    'readAgreementApproval', 'replyToAgreementApproval', 'beginAgreementCopyUpload',
    'completeAgreementCopyUpload', 'readAgreementCopy', 'createAgreementRenewal',
    'readTenancy', 'recordTenancyAction', 'issueKeyConfirmationCode',
    'readMoveOut', 'recordMoveOutAction', 'issueKeyReturnCode', 'quoteRentPayment',
    'beginRentPayment', 'confirmRentPayment', 'reconcileRentPayment', 'razorpayTestWebhook')
$previousTimeout = $env:FUNCTIONS_DISCOVERY_TIMEOUT
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
try {
    for ($offset = 0; $offset -lt $names.Count; $offset += $BatchSize) {
        $batch = @($names | Select-Object -Skip $offset -First $BatchSize)
        $filter = ($batch | ForEach-Object { 'functions:authentication:' + $_ }) -join ','
        $log = Join-Path $root "output/ui-audit/build$Build-backend-batch$offset.log"
        Write-Output "Deploying $($batch -join ', ')"
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            & $firebase deploy --project $Project --account ajay@trustkeyper.com --only $filter --non-interactive *> $log
            if ($LASTEXITCODE -eq 0) { break }
            $details = Get-Content -LiteralPath $log -Raw
            if ($attempt -eq 3 -or $details -notmatch 'Quota exceeded for total allowable CPU|Unable to parse JSON|429|UNAVAILABLE') {
                Get-Content -LiteralPath $log -Tail 12
                throw 'An affected function batch failed; remaining batches were not deployed.'
            }
            Write-Output 'Transient deployment capacity failure; waiting before this batch retry.'
            Start-Sleep -Seconds 60
        }
    }
    Write-Output 'All affected property-label callables deployed.'
} finally { $env:FUNCTIONS_DISCOVERY_TIMEOUT = $previousTimeout }
