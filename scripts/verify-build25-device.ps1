param(
    [string]$Serial = '3C15CL00CMU00000',
    [string]$Adb = 'C:\Users\ajayb\AppData\Local\Android\Sdk\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$evidence = Join-Path $root 'output/ui-audit'
$artifactPath = Join-Path $evidence 'build25-artifacts.json'
$artifacts = Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json

function Read-TestNodes([string]$Label) {
    [xml]$document = Get-Content -LiteralPath (Join-Path $evidence "$Label.xml") -Raw
    $nodes = @($document.SelectNodes('//node') | Where-Object { $_.package -eq 'com.trustkeyper.mobile.uitest' })
    if ($nodes.Count -eq 0) { throw "Evidence does not belong to the separate UI Test app: $Label" }
    return $nodes
}

function Assert-TestText([string]$Label, [string]$Expected) {
    $nodes = Read-TestNodes $Label
    if (!($nodes | Where-Object { $_.text -eq $Expected -or $_.'content-desc' -eq $Expected })) {
        throw "Expected device evidence is missing: $Label"
    }
}

$uiTestPackage = (& $Adb -s $Serial shell dumpsys package com.trustkeyper.mobile.uitest) -join "`n"
if ($LASTEXITCODE -ne 0 -or $uiTestPackage -notmatch 'versionCode=25\b') {
    throw 'Build 25 of the separate UI Test app is not installed.'
}
$originalPackage = (& $Adb -s $Serial shell dumpsys package com.trustkeyper.mobile) -join "`n"
if ($LASTEXITCODE -ne 0 -or $originalPackage -notmatch 'versionCode=18\b' -or
    $originalPackage -notmatch 'lastUpdateTime=2026-10-08 23:45:12') {
    throw 'The original app no longer matches its recorded unchanged identity.'
}
$installedPath = (& $Adb -s $Serial shell pm path com.trustkeyper.mobile.uitest) -join ''
if ($LASTEXITCODE -ne 0 -or $installedPath -notmatch '^package:(/data/app/[^\r\n]+/com\.trustkeyper\.mobile\.uitest-[^\r\n]+/base\.apk)$') {
    throw 'The installed UI Test APK path could not be verified.'
}
$baseApk = $Matches[1]
$installedCopy = Join-Path $evidence 'build25-installed-ui-test.apk'
& $Adb -s $Serial pull $baseApk $installedCopy 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'The installed UI Test APK could not be inspected.' }
$installedHash = (Get-FileHash -LiteralPath $installedCopy -Algorithm SHA256).Hash
if ($installedHash -ne $artifacts.uiTestApk.sha256) {
    throw 'The installed app is not the final archived UI Test APK.'
}

Assert-TestText 'build25-phone-renew-saved' 'Private draft saved'
Assert-TestText 'build25-phone-key-challenge' '3 keys'
Assert-TestText 'build25-phone-wrong-code' 'That TEST code is not correct.'
Assert-TestText 'build25-phone-key-completed' 'Moved in!'
Assert-TestText 'build25-phone-meter-missing-evidence' 'Add meter photos and readings before saving.'
Assert-TestText 'build25-phone-meter-saved' "Meter readings`nElectricity, water, gas`nDone"
Assert-TestText 'build25-phone-meter-reopened' '12345'
Assert-TestText 'build25-phone-meter-reopened' '678'
$beforeConfirmation = Read-TestNodes 'build25-phone-tenant-confirm-count'
$codeButton = @($beforeConfirmation | Where-Object { $_.'content-desc' -eq 'Get my confirmation code' })
if ($codeButton.Count -ne 1 -or $codeButton[0].enabled -ne 'false') {
    throw 'Tenant count confirmation was not required before requesting the code.'
}
Assert-TestText 'build25-phone-tenant-code-issued' '654321'

$result = [ordered]@{
    build = 25
    deviceModel = ((& $Adb -s $Serial shell getprop ro.product.model) -join '').Trim()
    uiTestPackage = 'com.trustkeyper.mobile.uitest'
    installedApkSha256 = $installedHash
    matchesArchivedApk = $true
    originalApp = @{ package = 'com.trustkeyper.mobile'; build = 18; lastUpdateTime = '2026-10-08 23:45:12'; unchanged = $true }
    checks = @(
        'Saved-source renewal creates and saves a separate private offline draft'
        'Broker key steppers retain two main-door keys and one bedroom key'
        'Wrong fixture code is rejected; correct code completes only the synthetic tenancy'
        'Missing meter evidence is rejected'
        'Reviewed synthetic meter photos and edited readings save and survive reopening'
        'Tenant code request is disabled until exact key count confirmation'
        'Confirmed tenant receives the private synthetic code'
    )
    scope = 'Selected offline journeys on the actual phone, not full-product or pixel-perfect acceptance'
    normalFirebaseAuthentication = 'Verified separately with normal Firebase SDK; not performed by the offline phone app'
    realMoneyOrMessagesSent = $false
    wholeProductAccepted = $false
}
$result | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $evidence 'build25-device-evidence.json') -Encoding utf8
$artifacts.physicalDeviceAcceptance = 'Selected offline journeys passed on phone; see build25-device-evidence.json. Whole-product acceptance remains open.'
$artifacts | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $artifactPath -Encoding utf8
$result | ConvertTo-Json -Depth 5
