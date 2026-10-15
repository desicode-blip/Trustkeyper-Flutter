param(
    [ValidateSet('Inspect', 'Tap', 'Text', 'Back', 'Swipe', 'Capture')]
    [string]$Action = 'Inspect',
    [string]$Description,
    [string]$NearDescription,
    [string]$Text,
    [ValidatePattern('^[a-zA-Z0-9-]+$')]
    [string]$Label = 'phone-check',
    [string]$Adb = 'C:\Users\ajayb\AppData\Local\Android\Sdk\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$output = Join-Path $root 'output/ui-audit'
$xmlPath = Join-Path $output "$Label.xml"

function Read-TestUi {
    $dump = & $Adb shell uiautomator dump /data/local/tmp/trustkeyper-ui.xml 2>&1
    if ($LASTEXITCODE -ne 0 -or ($dump -join "`n") -match 'ERROR|Exception|null root' -or
        ($dump -join "`n") -notmatch 'dumped to: /data/local/tmp/trustkeyper-ui.xml') {
        throw 'A fresh phone UI dump was not produced. No cached state will be used.'
    }
    & $Adb pull /data/local/tmp/trustkeyper-ui.xml $xmlPath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The phone UI dump could not be read.' }
    [xml]$document = Get-Content -LiteralPath $xmlPath -Raw
    $nodes = @($document.SelectNodes('//node'))
    if (!($nodes | Where-Object { $_.package -eq 'com.trustkeyper.mobile.uitest' })) {
        throw 'The separate UI Test app is not visible. No further action will be taken.'
    }
    return $nodes
}

$nodes = Read-TestUi
switch ($Action) {
    'Tap' {
        if ([string]::IsNullOrWhiteSpace($Description)) { throw 'Choose an observed label.' }
        $matches = @($nodes | Where-Object {
            $_.package -eq 'com.trustkeyper.mobile.uitest' -and
            ($_.'content-desc' -eq $Description -or $_.text -eq $Description -or $_.hint -eq $Description)
        })
        if ($NearDescription) {
            $anchors = @($nodes | Where-Object {
                $_.package -eq 'com.trustkeyper.mobile.uitest' -and
                ($_.'content-desc' -eq $NearDescription -or $_.text -eq $NearDescription -or $_.hint -eq $NearDescription)
            })
            if ($anchors.Count -ne 1) { throw 'The observed row label is missing or ambiguous.' }
            $anchorBounds = @([regex]::Matches($anchors[0].bounds, '\d+') | ForEach-Object { [int]$_.Value })
            $anchorCenter = ($anchorBounds[1] + $anchorBounds[3]) / 2
            $nearby = @($matches | ForEach-Object {
                $bounds = @([regex]::Matches($_.bounds, '\d+') | ForEach-Object { [int]$_.Value })
                [pscustomobject]@{
                    node = $_
                    distance = [math]::Abs((($bounds[1] + $bounds[3]) / 2) - $anchorCenter)
                    width = $bounds[2] - $bounds[0]
                    height = $bounds[3] - $bounds[1]
                }
            } | Sort-Object distance, @{ Expression = 'width'; Descending = $true })
            if ($nearby.Count -eq 0 -or $nearby[0].distance -gt [math]::Max($nearby[0].height, $anchorBounds[3] - $anchorBounds[1])) {
                throw 'The action is not visible beside the observed row label.'
            }
            $matches = @($nearby[0].node)
        }
        if ($matches.Count -ne 1) { throw 'The requested label is missing or ambiguous.' }
        $coordinates = @([regex]::Matches($matches[0].bounds, '\d+') | ForEach-Object { [int]$_.Value })
        if ($coordinates.Count -ne 4) { throw 'The target bounds are unavailable.' }
        & $Adb shell input tap ([int](($coordinates[0] + $coordinates[2]) / 2)) ([int](($coordinates[1] + $coordinates[3]) / 2))
    }
    'Text' {
        if ($Text -notmatch '^[a-zA-Z0-9 -]{1,100}$') { throw 'Use non-sensitive ASCII TEST input only.' }
        if (!($nodes | Where-Object { $_.package -eq 'com.trustkeyper.mobile.uitest' -and $_.focused -eq 'true' -and $_.class -eq 'android.widget.EditText' })) {
            throw 'An editable UI Test field must be focused first.'
        }
        & $Adb shell input text ($Text.Replace(' ', '%s'))
    }
    'Back' { & $Adb shell input keyevent 4 }
    'Swipe' {
        $coordinates = @([regex]::Matches($nodes[0].bounds, '\d+') | ForEach-Object { [int]$_.Value })
        $center = [int](($coordinates[0] + $coordinates[2]) / 2)
        & $Adb shell input swipe $center ([int]($coordinates[3] * 0.75)) $center ([int]($coordinates[3] * 0.3)) 400
    }
    'Capture' {
        & $Adb shell screencap -p /data/local/tmp/trustkeyper-screen.png
        & $Adb pull /data/local/tmp/trustkeyper-screen.png (Join-Path $output "$Label.png") 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'The UI Test screenshot was not copied.' }
    }
}
if ($Action -notin @('Inspect', 'Capture')) { $nodes = Read-TestUi }
$nodes | Where-Object { $_.package -eq 'com.trustkeyper.mobile.uitest' -and ($_.'content-desc' -or $_.text -or $_.hint) } |
    ForEach-Object { @{ description = $_.'content-desc'; text = $_.text; hint = $_.hint; bounds = $_.bounds; enabled = $_.enabled } } |
    ConvertTo-Json -Compress
