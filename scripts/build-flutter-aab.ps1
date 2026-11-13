param(
    [string]$SigningCredentialsFile = $(if ($env:TRUSTKEYPER_SIGNING_CREDENTIALS_FILE) {
        $env:TRUSTKEYPER_SIGNING_CREDENTIALS_FILE
    } else { Join-Path $HOME '.trustkeyper/signing/android-upload.json' }),
    [string]$FlutterExecutable = 'flutter',
    [switch]$SkipCrashlyticsUpload,
    [switch]$VerifySigningOnly,
    [switch]$Tk2Staging
)

$ErrorActionPreference = 'Stop'
$expectedFingerprint = '94:E2:48:81:D0:EC:4D:EF:34:52:1A:C0:62:82:1C:91:42:89:69:C7'
$credentialsPath = (Resolve-Path -LiteralPath $SigningCredentialsFile).Path
$credentials = (Get-Content -LiteralPath $credentialsPath -Raw | ConvertFrom-Json).android.keystore
if (!$credentials) { throw 'Android keystore credentials are missing.' }
$storePath = [System.IO.Path]::GetFullPath((Join-Path (Split-Path $credentialsPath) $credentials.keystorePath))
if (!(Test-Path -LiteralPath $storePath)) { throw 'The upload keystore was not found.' }
$signingEnvironment = @{
    TRUSTKEYPER_UPLOAD_STORE_FILE = $storePath
    TRUSTKEYPER_UPLOAD_STORE_PASSWORD = $credentials.keystorePassword
    TRUSTKEYPER_UPLOAD_KEY_ALIAS = $credentials.keyAlias
    TRUSTKEYPER_UPLOAD_KEY_PASSWORD = $credentials.keyPassword
    TRUSTKEYPER_SKIP_CRASHLYTICS_UPLOAD = ([bool]($SkipCrashlyticsUpload -or $Tk2Staging)).ToString().ToLowerInvariant()
}
$previousEnvironment = @{}
$appDirectory = Join-Path (Split-Path $PSScriptRoot) 'apps/flutter_app'

try {
    foreach ($name in $signingEnvironment.Keys) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ([string]::IsNullOrWhiteSpace($signingEnvironment[$name])) {
            throw 'One or more upload signing settings are missing.'
        }
        [Environment]::SetEnvironmentVariable($name, $signingEnvironment[$name], 'Process')
    }
    $certificate = & keytool -list -v -keystore $storePath -alias $credentials.keyAlias -storepass:env TRUSTKEYPER_UPLOAD_STORE_PASSWORD 2>&1
    if ($LASTEXITCODE -ne 0 -or !($certificate -match [regex]::Escape($expectedFingerprint))) {
        throw 'The keystore does not match the Google Play upload certificate.'
    }
    if ($VerifySigningOnly) {
        Write-Output 'The private Android upload key matches the existing Google Play certificate.'
        return
    }
    Push-Location $appDirectory
    try {
        $buildArguments = @('build', 'appbundle', '--release')
        if ($Tk2Staging) {
            $expectedFlutter = (Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) '.flutter-version') -Raw).Trim()
            $sdkVersion = (& $FlutterExecutable --version --machine | ConvertFrom-Json).frameworkVersion
            if ($LASTEXITCODE -ne 0 -or $sdkVersion -ne $expectedFlutter) { throw "Use Flutter $expectedFlutter for TK2 staging builds." }
            $configPath = Join-Path $appDirectory 'tk2_cloud.json'
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            if ($config.TK2_FIREBASE_PROJECT_ID -ne 'trustkeyper-app-staging' -or
                $config.TK2_FIREBASE_STORAGE_BUCKET -ne 'trustkeyper-app-staging.firebasestorage.app' -or
                ([string]$config.TK2_WEB_URL).TrimEnd('/') -ne 'https://trustkeyper-tk2-staging.web.app' -or
                $config.TK2_FIREBASE_APP_ID_ANDROID -ne '1:882743913919:android:187b9e9baee7d355d4c50a' -or
                !$config.TK2_FIREBASE_API_KEY_ANDROID -or $config.TK2_EMULATOR_HOST) {
                throw 'Use the TrustKeyper Android Firebase settings for staging and the staging website.'
            }
            $buildArguments += @('--no-pub', '-t', 'lib/main_tk2.dart', '--dart-define=TK2_NATIVE=true', "--dart-define-from-file=$configPath")
            & $FlutterExecutable pub get --enforce-lockfile
            if ($LASTEXITCODE -ne 0) { throw 'The locked Flutter dependencies could not be restored.' }
        }
        & $FlutterExecutable @buildArguments
        if ($LASTEXITCODE -ne 0) { throw 'The Android release build failed.' }
        $bundlePath = Join-Path $appDirectory 'build/app/outputs/bundle/release/app-release.aab'
        $bundleCertificate = & keytool -printcert -jarfile $bundlePath 2>&1
        if ($LASTEXITCODE -ne 0 -or !($bundleCertificate -match [regex]::Escape($expectedFingerprint))) {
            throw 'The output bundle does not match the Google Play upload certificate.'
        }
        Write-Output "Verified Google Play upload signature: $bundlePath"
        if ($SkipCrashlyticsUpload -and !$Tk2Staging) { Write-Output 'Crashlytics build-time symbol upload deferred; archive the release mapping for later upload.' }
    } finally {
        Pop-Location
    }
} finally {
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
}
