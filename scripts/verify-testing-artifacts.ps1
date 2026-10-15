param(
    [Parameter(Mandatory = $true)][int]$Build,
    [string]$Downloads = 'C:\Users\ajayb\Downloads'
)

$ErrorActionPreference = 'Stop'
if ($Build -lt 28) { throw 'Use the historical verification scripts for earlier releases.' }
$root = Split-Path $PSScriptRoot
$app = Join-Path $root 'apps/flutter_app'
$evidence = Join-Path $root 'output/ui-audit'
$bundle = Join-Path $app 'build/app/outputs/bundle/release/app-release.aab'
$apk = Join-Path $app 'build/app/outputs/flutter-apk/app-debug.apk'
$web = Join-Path $app 'build/web/main.dart.js'
$java = Join-Path $root 'output/local-tooling/java21/jdk-21.0.12.1+1-jre/bin/java.exe'
$bundletool = Join-Path $root 'output/local-tooling/bundletool-all.jar'
$aapt = 'C:\Users\ajayb\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt.exe'
$keytool = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\bin\keytool.exe'
$jarsigner = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\bin\jarsigner.exe'
$fingerprint = '94:E2:48:81:D0:EC:4D:EF:34:52:1A:C0:62:82:1C:91:42:89:69:C7'
$sources = @(
    Get-ChildItem -LiteralPath (Join-Path $app 'lib') -File -Recurse
    Get-Item -LiteralPath (Join-Path $app 'pubspec.yaml')
)
$latestSource = $sources | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$latestProductionSource = $sources | Where-Object { $_.Name -ne 'ui_test_main.dart' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
foreach ($artifact in @($bundle, $apk, $web)) {
    $relevantSource = if ($artifact -eq $apk) { $latestSource } else { $latestProductionSource }
    if ((Get-Item -LiteralPath $artifact).LastWriteTime -lt $relevantSource.LastWriteTime) {
        throw 'A testing artifact is stale. Rebuild before archiving.'
    }
}
if (!(Get-Content -LiteralPath $web -Raw).Contains('flutter-fire-fn')) {
    throw 'The web build is missing Cloud Functions registration. Clean and rebuild without --no-pub.'
}
$badging = & $aapt dump badging $apk
if ($LASTEXITCODE -ne 0 -or !($badging -match "package: name='com.trustkeyper.mobile.uitest' versionCode='$Build' versionName='2.0.0'")) {
    throw 'Separate UI Test package identity or version did not match.'
}
$permissions = & $aapt dump permissions $apk
if ($LASTEXITCODE -ne 0 -or $permissions -match 'android.permission.INTERNET') {
    throw 'The offline UI Test APK must not have Internet permission.'
}
& $java -jar $bundletool validate "--bundle=$bundle" *> (Join-Path $evidence "build$Build-bundle-validation.log")
if ($LASTEXITCODE -ne 0) { throw 'Android bundle validation failed.' }
$manifest = & $java -jar $bundletool dump manifest "--bundle=$bundle" --module=base
if ($LASTEXITCODE -ne 0) { throw 'Bundle manifest could not be read.' }
$manifestText = $manifest -join "`n"
if ($manifestText -notmatch 'package="com.trustkeyper.mobile"' -or
    $manifestText -notmatch "android:versionCode=`"$Build`"" -or
    $manifestText -notmatch 'android:versionName="2.0.0"' -or
    $manifestText -notmatch 'android.permission.INTERNET') {
    throw 'Normal Firebase bundle identity, version or Internet permission did not match.'
}
$certificate = & $keytool -printcert -jarfile $bundle 2>&1
if ($LASTEXITCODE -ne 0 -or !($certificate -match [regex]::Escape($fingerprint))) {
    throw 'Bundle does not match the Google Play upload certificate.'
}
$signatureLog = Join-Path $evidence "build$Build-bundle-signature-verification.log"
& $jarsigner '-J-Duser.language=en' -verify $bundle *> $signatureLog
if ($LASTEXITCODE -ne 0 -or
    !(Select-String -LiteralPath $signatureLog -Pattern '^jar verified\.' -Quiet) -or
    (Select-String -LiteralPath $signatureLog -Pattern 'unsigned entries' -Quiet)) {
    throw 'Bundle cryptographic signature or signed-entry coverage did not verify.'
}
$aabArchive = Join-Path $Downloads "TrustKeyper-v2.0.0-build$Build-testing.aab"
$apkArchive = Join-Path $Downloads "TrustKeyper-UI-Test-build$Build.apk"
Copy-Item -LiteralPath $bundle -Destination $aabArchive
Copy-Item -LiteralPath $apk -Destination $apkArchive
$mapping = Join-Path $app 'build/app/outputs/mapping/release/mapping.txt'
if (Test-Path -LiteralPath $mapping) {
    Copy-Item -LiteralPath $mapping -Destination (Join-Path $evidence "build$Build-release-mapping.txt")
}
$result = [ordered]@{
    build = $Build
    version = '2.0.0'
    cryptographicSignatureVerified = $true
    verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
    aab = @{ path = $aabArchive; package = 'com.trustkeyper.mobile'; bytes = (Get-Item -LiteralPath $aabArchive).Length; sha256 = (Get-FileHash -LiteralPath $aabArchive -Algorithm SHA256).Hash; uploadCertificateSha1 = $fingerprint }
    uiTestApk = @{ path = $apkArchive; package = 'com.trustkeyper.mobile.uitest'; sha256 = (Get-FileHash -LiteralPath $apkArchive -Algorithm SHA256).Hash; internetPermission = $false; firebaseData = $false }
    webMainSha256 = (Get-FileHash -LiteralPath $web -Algorithm SHA256).Hash
    crashlyticsSymbolUpload = 'deferred; mapping archived'
    installedByThisScript = $false
    physicalDeviceAcceptance = 'pending; artifact verification does not establish physical-device acceptance'
    wholeProductAcceptance = 'not certified; see docs/product-requirements-coverage.md'
}
$result | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $evidence "build$Build-artifacts.json") -Encoding utf8
$result | ConvertTo-Json -Depth 5
