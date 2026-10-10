# Dot-source this file to drive the emulator through its current accessibility tree.
$DemoDevice = 'emulator-5554'
function Get-DemoNodes {
    & adb -s $DemoDevice shell uiautomator dump /sdcard/foodpos-demo-ui.xml | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect emulator UI.' }
    [xml]$document = (& adb -s $DemoDevice shell cat /sdcard/foodpos-demo-ui.xml) -join "`n"
    $document.SelectNodes('//node')
}
function Show-DemoUi {
    Get-DemoNodes | Where-Object { $_.'content-desc' -or $_.text -or $_.hint } |
        ForEach-Object { "$($_.'content-desc') $($_.text) $($_.hint) $($_.bounds)" }
}
function Tap-DemoText([string]$Pattern) {
    $match = Get-DemoNodes | Where-Object {
        $_.enabled -eq 'true' -and (($_.'content-desc' -match $Pattern) -or ($_.text -match $Pattern))
    } | Select-Object -First 1
    if (!$match) { throw "Visible control not found: $Pattern" }
    if ($match.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Invalid control bounds.' }
    $tapX = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
    $tapY = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    & adb -s $DemoDevice shell input tap $tapX $tapY
    if ($LASTEXITCODE -ne 0) { throw 'Tap failed.' }
    Start-Sleep -Milliseconds 500
}
function Set-DemoField([string]$Hint, [string]$Value) {
    $field = Get-DemoNodes | Where-Object { $_.class -eq 'android.widget.EditText' -and $_.hint -match $Hint } | Select-Object -First 1
    if (!$field) { throw "Visible field not found: $Hint" }
    if ($field.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw 'Invalid field bounds.' }
    & adb -s $DemoDevice shell input tap ([int](([int]$Matches[1]+[int]$Matches[3])/2)) ([int](([int]$Matches[2]+[int]$Matches[4])/2))
    & adb -s $DemoDevice shell input keyevent 123
    & adb -s $DemoDevice shell input keyevent --longpress 67
    & adb -s $DemoDevice shell input text ($Value -replace ' ', '%s')
    & adb -s $DemoDevice shell input keyevent 4
}
function Back-Demo {
    & adb -s $DemoDevice shell input keyevent 4
    Start-Sleep -Milliseconds 500
}
function Scroll-Demo {
    & adb -s $DemoDevice shell input swipe 540 1850 540 700 500
    Start-Sleep -Milliseconds 500
}
