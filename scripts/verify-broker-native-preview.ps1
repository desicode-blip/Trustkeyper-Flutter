param([int]$Build = 33)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$output = Join-Path $root 'output/ui-audit'
$adb = 'C:\Users\ajayb\AppData\Local\Android\Sdk\platform-tools\adb.exe'

function Read-Nodes([string]$State) {
    [xml]$document = Get-Content -LiteralPath (Join-Path $output "build$Build-phone-$State.xml") -Raw
    return @($document.SelectNodes('//node') | Where-Object { $_.package -eq 'com.trustkeyper.mobile.uitest' })
}

function Require-Label($Nodes, [string]$Label) {
    $found = @($Nodes | Where-Object { $_.'content-desc' -eq $Label -or $_.text -eq $Label })
    if ($found.Count -ne 1) { throw "Native preview label missing or ambiguous: $Label" }
    return $found[0]
}

$drafts = Read-Nodes 'drafts'
$positions = @('All', 'In progress', 'Signed', 'Drafts') | ForEach-Object {
    $node = Require-Label $drafts $_
    [int]([regex]::Matches($node.bounds, '\d+')[1].Value)
}
if (@($positions | Select-Object -Unique).Count -ne 1) { throw 'Agreement filters wrap on the phone.' }
Require-Label $drafts "OFFLINE TEST · Phoenix Towers 402`nStopped at Tenant documents`nDraft" | Out-Null
Require-Label (Read-Nodes 'tenant-resume') 'Step 3 of 5 · Tenant' | Out-Null
Require-Label (Read-Nodes 'tenant-resume') 'TEST Priya' | Out-Null
Require-Label (Read-Nodes 'owner-update') 'Step 2 of 5 · Owner' | Out-Null
Require-Label (Read-Nodes 'owner-update') 'TEST Rajesh' | Out-Null
$share = Read-Nodes 'share-dialog'
foreach ($label in @('Send Aadhaar link?', "WhatsApp`nBest – most people use it", "SMS`nNormal text message", 'Add email', 'Cancel')) {
    Require-Label $share $label | Out-Null
}
$add = Read-Nodes 'add-dialog'
foreach ($label in @('Add Aadhaar card', "Click photo`nUse camera", "Upload`nFrom phone", 'Cancel')) {
    Require-Label $add $label | Out-Null
}
$artifacts = Get-Content -LiteralPath (Join-Path $output "build$Build-artifacts.json") -Raw | ConvertFrom-Json
$path = (& $adb shell pm path com.trustkeyper.mobile.uitest | Select-Object -First 1).Trim().Replace('package:', '')
if ($path -notmatch '^/data/app/[^\s]*com\.trustkeyper\.mobile\.uitest[^\s]*/base\.apk$') { throw 'Unexpected preview APK path.' }
$installed = (& $adb shell sha256sum $path) -split '\s+' | Select-Object -First 1
if ($installed.ToUpperInvariant() -ne $artifacts.uiTestApk.sha256) { throw 'Phone preview does not match the final archived APK.' }
$original = (& $adb shell dumpsys package com.trustkeyper.mobile) -join "`n"
if ($original -notmatch 'versionCode=32\s' -or $original -notmatch 'lastUpdateTime=2026-10-11 18:53:00') {
    throw 'Original-app baseline changed; do not certify it untouched.'
}
$result = @{
    build = $Build
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    installedPreviewMatchesFinalArchive = $true
    installedPreviewSha256 = $installed.ToUpperInvariant()
    originalAppUnchanged = $true
    originalAppBuild = 32
    checks = @('single-row agreement filters', 'saved draft reopens tenant documents',
        'upload update opens matching owner documents', 'approved sharing controls',
        'interactive Aadhaar add controls')
    limitation = 'Offline UI preview checks only; not authenticated app, physical FCM delivery or whole-product pixel acceptance.'
}
$result | ConvertTo-Json -Depth 4 | Out-File -LiteralPath (Join-Path $output "build$Build-native-checks.json") -Encoding utf8
$result | ConvertTo-Json -Depth 4 -Compress
