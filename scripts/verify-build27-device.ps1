param([string]$Serial = '3C15CL00CMU00000')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$adb = 'C:\Users\ajayb\AppData\Local\Android\Sdk\platform-tools\adb.exe'
$evidence = Join-Path $root 'output/ui-audit'
$artifactsPath = Join-Path $evidence 'build27-artifacts.json'
$artifacts = Get-Content -LiteralPath $artifactsPath -Raw | ConvertFrom-Json
$original = (& $adb -s $Serial shell dumpsys package com.trustkeyper.mobile) -join "`n"
if ($LASTEXITCODE -ne 0 -or $original -notmatch 'versionCode=18\b' -or
    $original -notmatch 'lastUpdateTime=2026-10-08 23:45:12') {
    throw 'Original app identity changed or could not be read.'
}
$test = (& $adb -s $Serial shell dumpsys package com.trustkeyper.mobile.uitest) -join "`n"
if ($LASTEXITCODE -ne 0 -or $test -notmatch 'versionCode=27\b') {
    throw 'The selected UI Test build is not installed.'
}
$installed = (& $adb -s $Serial shell pm path com.trustkeyper.mobile.uitest) -join ''
if ($LASTEXITCODE -ne 0 -or
    $installed -notmatch '^package:(/data/app/[^\r\n]+/com\.trustkeyper\.mobile\.uitest-[^\r\n]+/base\.apk)$') {
    throw 'UI Test APK path did not match.'
}
$installedPath = $Matches[1]
$copy = Join-Path $evidence 'build27-installed-ui-test.apk'
& $adb -s $Serial pull $installedPath $copy 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Installed app could not be read.' }
$hash = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
if ($hash -ne $artifacts.uiTestApk.sha256) {
    throw 'Installed APK differs from the archived APK.'
}
foreach ($check in @(
    @{ label = 'build27-phone-final-topic'; expected = 'Plan and fee' },
    @{ label = 'build27-phone-final-requested'; expected = 'Call requested' },
    @{ label = 'build27-phone-final-confirmed'; expected = 'TEST Anita will call you' },
    @{ label = 'build27-phone-final-missed'; expected = 'We could not reach you' },
    @{ label = 'build27-phone-final-rescheduled'; expected = 'Tomorrow evening on +919000000001' }
)) {
    [xml]$document = Get-Content -LiteralPath (Join-Path $evidence "$($check.label).xml") -Raw
    if (!($document.SelectNodes('//node') | Where-Object {
        $_.package -eq 'com.trustkeyper.mobile.uitest' -and
        ($_.'content-desc'.Contains($check.expected) -or $_.text.Contains($check.expected))
    })) {
        throw "Device evidence is missing: $($check.label)"
    }
}
$result = @{
    build = 27
    installedApkSha256 = $hash
    matchesArchivedApk = $true
    deviceModel = 'CPH2707'
    uiTestPackage = 'com.trustkeyper.mobile.uitest'
    originalApp = @{ build = 18; unchanged = $true; lastUpdateTime = '2026-10-08 23:45:12' }
    checks = @(
        'Owner callback topic selection and in-memory request saved',
        'Confirmed TEST manager and scheduled India-time fixture rendered',
        'Missed TEST call rendered and owner rescheduled to tomorrow evening'
    )
    scope = 'Selected offline layouts/actions; not all-artboard or normal Firebase/native-call acceptance'
    wholeProductAccepted = $false
    realMoneyOrMessagesSent = $false
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$result | ConvertTo-Json -Depth 5 | Out-File (Join-Path $evidence 'build27-device-evidence.json') -Encoding utf8
$artifacts.physicalDeviceAcceptance = 'Selected offline callbacks passed; see build27-device-evidence.json. Whole-product acceptance remains open.'
$artifacts | ConvertTo-Json -Depth 5 | Out-File $artifactsPath -Encoding utf8
$result | ConvertTo-Json -Depth 5
