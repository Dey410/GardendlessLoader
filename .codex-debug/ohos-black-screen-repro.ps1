param(
  [string]$HdcPath = 'D:\Code\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe',
  [int]$LauncherWaitSeconds = 4,
  [int]$GameWaitSeconds = 30
)

$ErrorActionPreference = 'Stop'
$bundleName = 'io.github.dey410.gardendlessloader'
$abilityName = 'EntryAbility'
$deviceLauncherPath = '/data/local/tmp/gardendless-repro-launcher.png'
$deviceGamePath = '/data/local/tmp/gardendless-repro-game.png'
$localLauncherPath = Join-Path $PSScriptRoot 'ohos-repro-launcher.png'
$localGamePath = Join-Path $PSScriptRoot 'ohos-repro-game.png'

function Invoke-Hdc {
  & $HdcPath @args
  if ($LASTEXITCODE -ne 0) {
    throw "hdc failed with exit code ${LASTEXITCODE}: $($args -join ' ')"
  }
}

function Get-DarkPixelRatio {
  param([string]$Path)

  Add-Type -AssemblyName System.Drawing
  $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
  try {
    $darkPixels = 0
    $sampledPixels = 0
    for ($y = 0; $y -lt $bitmap.Height; $y += 12) {
      for ($x = 0; $x -lt $bitmap.Width; $x += 12) {
        $color = $bitmap.GetPixel($x, $y)
        if ($color.R -le 16 -and $color.G -le 16 -and $color.B -le 16) {
          $darkPixels++
        }
        $sampledPixels++
      }
    }
    return $darkPixels / $sampledPixels
  } finally {
    $bitmap.Dispose()
  }
}

if (-not (Test-Path -LiteralPath $HdcPath)) {
  throw "hdc not found: $HdcPath"
}

$targets = (& $HdcPath list targets) -join "`n"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($targets) -or $targets -match 'Unauthorized') {
  throw "No authorized HarmonyOS device: $targets"
}

Invoke-Hdc shell aa force-stop $bundleName
$startOutput = ((& $HdcPath shell aa start -a $abilityName -b $bundleName) -join "`n")
if ($LASTEXITCODE -ne 0 -or $startOutput -match 'failed to start ability|Error Code:') {
  throw "INVALID REPRO: application launch failed: $startOutput"
}
Start-Sleep -Seconds $LauncherWaitSeconds
Invoke-Hdc shell uitest screenCap -p $deviceLauncherPath
Invoke-Hdc file recv $deviceLauncherPath $localLauncherPath

Add-Type -AssemblyName System.Drawing
$launcherBitmap = [System.Drawing.Bitmap]::FromFile($localLauncherPath)
try {
  $tapX = [int]($launcherBitmap.Width * 0.892)
  $tapY = [int]($launcherBitmap.Height * 0.885)
  $launcherBitmapHeight = $launcherBitmap.Height
} finally {
  $launcherBitmap.Dispose()
}

Invoke-Hdc shell hilog -r
Invoke-Hdc shell uitest uiInput click $tapX $tapY
$elapsed = 0
while ($elapsed -lt $GameWaitSeconds) {
  $interval = [Math]::Min(3, $GameWaitSeconds - $elapsed)
  Start-Sleep -Seconds $interval
  $elapsed += $interval
  Invoke-Hdc shell uitest uiInput click 10 ([int]($launcherBitmapHeight / 2))
}
Invoke-Hdc shell uitest screenCap -p $deviceGamePath
Invoke-Hdc file recv $deviceGamePath $localGamePath

$launcherDarkRatio = Get-DarkPixelRatio -Path $localLauncherPath
$gameDarkRatio = Get-DarkPixelRatio -Path $localGamePath
$pidText = ((& $HdcPath shell pidof $bundleName) -join ' ').Trim()
$debugLogs = ((& $HdcPath shell hilog -x -T GardendlessDebug -v time -v msec) -join "`n")
$metadataInitializationFailed =
  $debugLogs -match "Cannot read properties of undefined \(reading 'metadata'\)"
$localLogsPath = Join-Path $PSScriptRoot (
  'repro-logs-' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
)
Invoke-Hdc file recv -b $bundleName /data/storage/el2/base/haps/entry/files/logs $localLogsPath
$markerPath = Join-Path $localLogsPath 'active-session.json'
if (-not (Test-Path -LiteralPath $markerPath)) {
  throw 'INVALID REPRO: current structured log session marker is unavailable'
}
$currentSessionId = (Get-Content -Raw -LiteralPath $markerPath | ConvertFrom-Json).appSessionId
$currentLogText = ((
  Get-ChildItem -LiteralPath $localLogsPath -Filter "app-$currentSessionId-*.jsonl" |
    Sort-Object Name |
    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
) -join "`n")
$metadataInitializationFailed = $metadataInitializationFailed -or
  $currentLogText -match "Cannot read properties of undefined \(reading 'metadata'\)"
$imageDecodeFailed = $currentLogText -match 'Error 4930'

Write-Output ('launcherDarkRatio={0:P2}' -f $launcherDarkRatio)
Write-Output ('gameDarkRatio={0:P2}' -f $gameDarkRatio)
Write-Output "appPid=$pidText"
Write-Output "metadataInitializationFailed=$metadataInitializationFailed"
Write-Output "imageDecodeFailed=$imageDecodeFailed"

if ([string]::IsNullOrWhiteSpace($pidText)) {
  throw 'INVALID REPRO: application process is not running'
}

if ($launcherDarkRatio -ge 0.90) {
  throw 'INVALID REPRO: launcher was already black before tapping Start Game'
}

if ($gameDarkRatio -ge 0.95 -and -not [string]::IsNullOrWhiteSpace($pidText)) {
  Write-Error '[RED] Reproduced: game process is alive but at least 95% of the screen is black'
  exit 1
}

if ($metadataInitializationFailed) {
  Write-Error "[RED] Reproduced: GP-Next stopped because Tauri metadata was not initialized"
  exit 1
}

if ($imageDecodeFailed) {
  Write-Error '[RED] Reproduced: Cocos failed to decode a game image (Error 4930)'
  exit 1
}

Write-Output '[GREEN] Black-screen symptom was not reproduced'
exit 0
