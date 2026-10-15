param(
    [Parameter(Mandatory = $true)][int]$Build,
    [string]$SigningCredentialsFile = $(if ($env:TRUSTKEYPER_SIGNING_CREDENTIALS_FILE) {
        $env:TRUSTKEYPER_SIGNING_CREDENTIALS_FILE
    } else { Join-Path $HOME '.trustkeyper/signing/android-upload.json' }),
    [string]$FlutterExecutable = 'flutter'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$app = Join-Path $root 'apps/flutter_app'
$evidence = Join-Path $root 'output/ui-audit'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$version = Select-String -LiteralPath (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*2\.0\.0\+(\d+)\s*$'
if (!$version -or [int]$version.Matches[0].Groups[1].Value -ne $Build) {
    throw 'The requested build must match pubspec.yaml.'
}

function Get-SourceSnapshot {
    $files = @(
        foreach ($directory in @('lib', 'test', 'assets', 'web', 'android/app/src')) {
            Get-ChildItem -LiteralPath (Join-Path $app $directory) -File -Recurse |
                Where-Object {
                    $_.Name -ne 'GeneratedPluginRegistrant.java' -and
                    $_.FullName.Replace('\', '/') -notlike '*/test/failures/*'
                }
        }
        foreach ($relative in @('pubspec.yaml', 'pubspec.lock', 'android/app/build.gradle.kts',
            'android/settings.gradle.kts', 'android/build.gradle.kts', 'android/gradle.properties',
            'android/app/google-services.json')) {
            $path = Join-Path $app $relative
            if (Test-Path -LiteralPath $path) { Get-Item -LiteralPath $path }
        }
    ) | Sort-Object FullName -Unique
    $entries = @($files | ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($app.Length + 1).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($entries | ConvertTo-Json -Depth 4 -Compress))
        $digest = [System.BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-', '')
    } finally { $algorithm.Dispose() }
    return @{ sha256 = $digest; files = $entries }
}

function Invoke-FlutterStage([string]$Name, [string[]]$Arguments) {
    Write-Output $Name
    Push-Location $app
    try {
        & $FlutterExecutable @Arguments *> (Join-Path $evidence "build$Build-$Name.log")
        if ($LASTEXITCODE -ne 0) { throw "$Name failed. See the saved build log." }
    } finally { Pop-Location }
}

Invoke-FlutterStage 'dependencies' @('pub', 'get')
& node (Join-Path $PSScriptRoot 'check-firebase-web-sdk.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Firebase browser SDK version does not match FlutterFire.' }
$before = Get-SourceSnapshot
Invoke-FlutterStage 'flutter-tests' @('test', '--reporter', 'expanded', '--concurrency=1')
Invoke-FlutterStage 'analyze' @('analyze')
Invoke-FlutterStage 'web-build' @('build', 'web', '--release', '--no-wasm-dry-run')
Write-Output 'aab-build'
& (Join-Path $PSScriptRoot 'build-flutter-aab.ps1') -SigningCredentialsFile $SigningCredentialsFile `
    -FlutterExecutable $FlutterExecutable -SkipCrashlyticsUpload *> (Join-Path $evidence "build$Build-aab-build.log")
if ($LASTEXITCODE -ne 0) { throw 'Signed AAB build failed.' }
Invoke-FlutterStage 'ui-test-build' @('build', 'apk', '--debug', '--target', 'lib/ui_test_main.dart',
    '--dart-define=TRUSTKEYPER_UI_TEST=true', '--dart-define=TRUSTKEYPER_EMAIL_OTP_ENABLED=false')
$after = Get-SourceSnapshot
if ($before.sha256 -ne $after.sha256) {
    throw 'Source changed during validation/builds. No testing artifacts are archived.'
}
[ordered]@{
    build = $Build
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    unchangedDuringBuild = $true
    source = $after
} | ConvertTo-Json -Depth 6 | Out-File -LiteralPath (Join-Path $evidence "build$Build-source-snapshot.json") -Encoding utf8
& (Join-Path $PSScriptRoot 'verify-testing-artifacts.ps1') -Build $Build *> (Join-Path $evidence "build$Build-artifact-verification.log")
$artifactPath = Join-Path $evidence "build$Build-artifacts.json"
$artifacts = Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json
$artifacts | Add-Member -NotePropertyName sourceSnapshotVerified -NotePropertyValue $true -Force
$artifacts | Add-Member -NotePropertyName sourceSnapshotSha256 -NotePropertyValue $after.sha256 -Force
$artifacts | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $artifactPath -Encoding utf8
Write-Output 'Verified and archived unchanged-source testing artifacts.'
