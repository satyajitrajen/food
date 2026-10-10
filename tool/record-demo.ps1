param(
    [ValidatePattern('^emulator-\d+$')][string]$Device = 'emulator-5554',
    [ValidatePattern('^[a-z0-9-]+$')][string]$Scene = 'demo',
    [ValidateRange(1,180)][int]$Seconds = 60
)
$ErrorActionPreference = 'Stop'
$destination = Join-Path $PSScriptRoot '../demo/recordings'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$remote = "/sdcard/foodpos-$Scene.mp4"
& adb -s $Device get-state
if ($LASTEXITCODE -ne 0) { throw 'Emulator is unavailable.' }
Write-Host "Recording $Scene for $Seconds seconds. Perform the scene now."
& adb -s $Device shell screenrecord --bit-rate 8000000 --time-limit $Seconds $remote
if ($LASTEXITCODE -ne 0) { throw 'Screen recording failed.' }
$output = Join-Path $destination "$Scene.mp4"
& adb -s $Device pull $remote $output
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $output) -or (Get-Item -LiteralPath $output).Length -eq 0) {
    throw 'Recording was not saved.'
}
& adb -s $Device shell rm $remote
Write-Host "Saved $output"
