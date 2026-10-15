param([string]$Downloads = 'C:\Users\ajayb\Downloads')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$app = Join-Path $root 'apps/flutter_app'
$evidence = Join-Path $root 'output/ui-audit'
$bundle = Join-Path $app 'build/app/outputs/bundle/release/app-release.aab'
$apk = Join-Path $app 'build/app/outputs/flutter-apk/app-debug.apk'
$java = Join-Path $root 'output/local-tooling/java21/jdk-21.0.12.1+1-jre/bin/java.exe'
$bundletool = Join-Path $root 'output/local-tooling/bundletool-all.jar'
$aapt = 'C:\Users\ajayb\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt.exe'
$keytool = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\bin\keytool.exe'
$fingerprint = '94:E2:48:81:D0:EC:4D:EF:34:52:1A:C0:62:82:1C:91:42:89:69:C7'
$latestSource = Get-ChildItem -LiteralPath (Join-Path $app 'lib') -File -Recurse |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
foreach ($artifact in @($bundle, $apk, (Join-Path $app 'build/web/main.dart.js'))) {
    if ((Get-Item -LiteralPath $artifact).LastWriteTime -lt $latestSource.LastWriteTime) {
        throw 'An interrupted build left a stale artifact. Rebuild before archiving.'
    }
}

$badging = & $aapt dump badging $apk
if ($LASTEXITCODE -ne 0 -or !($badging -match "package: name='com.trustkeyper.mobile.uitest' versionCode='27'")) {
    throw 'The separate UI Test APK identity/build did not match.'
}
$permissions = & $aapt dump permissions $apk
if ($LASTEXITCODE -ne 0 -or $permissions -match 'android.permission.INTERNET') {
    throw 'The offline UI Test APK unexpectedly has Internet permission.'
}
& $java -jar $bundletool validate "--bundle=$bundle" *> (Join-Path $evidence 'build27-bundle-validation.log')
if ($LASTEXITCODE -ne 0) { throw 'Android bundle validation failed.' }
$manifest = & $java -jar $bundletool dump manifest "--bundle=$bundle" --module=base
if ($LASTEXITCODE -ne 0) { throw 'Android bundle manifest could not be read.' }
$manifestText = $manifest -join "`n"
if ($manifestText -notmatch 'package="com.trustkeyper.mobile"' -or
    $manifestText -notmatch 'android:versionCode="27"' -or
    $manifestText -notmatch 'android:versionName="2.0.0"' -or
    $manifestText -notmatch 'android.permission.INTERNET') {
    throw 'Normal Firebase bundle identity, version or Internet permission did not match.'
}
$certificate = & $keytool -printcert -jarfile $bundle 2>&1
if ($LASTEXITCODE -ne 0 -or !($certificate -match [regex]::Escape($fingerprint))) {
    throw 'Android bundle does not match the Google Play upload certificate.'
}
$aabArchive = Join-Path $Downloads 'TrustKeyper-v2.0.0-build27-manager-callbacks.aab'
$apkArchive = Join-Path $Downloads 'TrustKeyper-UI-Test-build27.apk'
Copy-Item -LiteralPath $bundle -Destination $aabArchive
Copy-Item -LiteralPath $apk -Destination $apkArchive
$mapping = Join-Path $app 'build/app/outputs/mapping/release/mapping.txt'
if (Test-Path -LiteralPath $mapping) {
    Copy-Item -LiteralPath $mapping -Destination (Join-Path $evidence 'build27-release-mapping.txt')
}
$result = [ordered]@{
    build = 27
    version = '2.0.0'
    aab = @{ path = $aabArchive; package = 'com.trustkeyper.mobile'; sha256 = (Get-FileHash -LiteralPath $aabArchive -Algorithm SHA256).Hash; uploadCertificateSha1 = $fingerprint }
    uiTestApk = @{ path = $apkArchive; package = 'com.trustkeyper.mobile.uitest'; sha256 = (Get-FileHash -LiteralPath $apkArchive -Algorithm SHA256).Hash; internetPermission = $false; firebaseData = $false }
    webMainSha256 = (Get-FileHash -LiteralPath (Join-Path $app 'build/web/main.dart.js') -Algorithm SHA256).Hash
    crashlyticsSymbolUpload = 'deferred'
    physicalDeviceAcceptance = 'pending; see separate device evidence'
}
$result | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $evidence 'build27-artifacts.json') -Encoding utf8
$result | ConvertTo-Json -Depth 5


