param([string]$Serial = '3C15CL00CMU00000')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$adb = 'C:\Users\ajayb\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence = Join-Path $root 'output/ui-audit'
$artifactsPath = Join-Path $evidence 'build26-artifacts.json'
$artifacts = Get-Content -LiteralPath $artifactsPath -Raw | ConvertFrom-Json
$original = (& $adb -s $Serial shell dumpsys package com.trustkeyper.mobile) -join "`n"
if ($original -notmatch 'versionCode=18\b' -or $original -notmatch 'lastUpdateTime=2026-10-08 23:45:12') { throw 'Original app identity changed.' }
$test = (& $adb -s $Serial shell dumpsys package com.trustkeyper.mobile.uitest) -join "`n"
if ($test -notmatch 'versionCode=26\b') { throw 'The selected UI Test build is not installed.' }
$installed = (& $adb -s $Serial shell pm path com.trustkeyper.mobile.uitest) -join ''
if ($installed -notmatch '^package:(/data/app/[^\r\n]+/com\.trustkeyper\.mobile\.uitest-[^\r\n]+/base\.apk)$') { throw 'UI Test APK path did not match.' }
$copy = Join-Path $evidence 'build26-installed-ui-test.apk'
& $adb -s $Serial pull $Matches[1] $copy 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Installed app could not be read.' }
$hash = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
if ($hash -ne $artifacts.uiTestApk.sha256) { throw 'Installed APK differs from the archived APK.' }
foreach ($check in @(
    @{ label = 'build26-phone-deductions'; expected = 'Send to owner and tenants' },
    @{ label = 'build26-phone-publish'; expected = "From ₹44,000 deposit" },
    @{ label = 'build26-phone-key-code'; expected = '654321' },
    @{ label = 'build26-phone-owner'; expected = 'Add a missed item' }
)) {
    [xml]$document = Get-Content -LiteralPath (Join-Path $evidence "$($check.label).xml") -Raw
    if (!($document.SelectNodes('//node') | Where-Object {
        $_.package -eq 'com.trustkeyper.mobile.uitest' -and ($_.'content-desc' -eq $check.expected -or $_.text -eq $check.expected)
    })) { throw "Device evidence is missing: $($check.label)" }
}
$result = @{
    build = 26; installedApkSha256 = $hash; matchesArchivedApk = $true
    deviceModel = 'CPH2707'; uiTestPackage = 'com.trustkeyper.mobile.uitest'
    originalApp = @{ build = 18; unchanged = $true; lastUpdateTime = '2026-10-08 23:45:12' }
    checks = @('Broker offline checklist/deductions render and report publication opens participant shares',
      'Tenant returned-key attestation exposes the private synthetic code', 'Owner report and missed-item entry render')
    scope = 'Selected offline layouts/actions; not every artboard, native Firebase or real financial acceptance'
    wholeProductAccepted = $false; realMoneyOrMessagesSent = $false
}
$result | ConvertTo-Json -Depth 5 | Out-File (Join-Path $evidence 'build26-device-evidence.json') -Encoding utf8
$artifacts.physicalDeviceAcceptance = 'Selected offline move-out checks passed; see build26-device-evidence.json. Whole-product acceptance remains open.'
$artifacts | ConvertTo-Json -Depth 5 | Out-File $artifactsPath -Encoding utf8
$result | ConvertTo-Json -Depth 5
