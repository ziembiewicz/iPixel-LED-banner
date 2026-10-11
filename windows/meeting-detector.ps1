<#
.SYNOPSIS
  Tells Home Assistant whether a meeting app holds the microphone or the webcam on this PC.

.DESCRIPTION
  Windows keeps a per-app record of camera and microphone access (the same data behind
  the microphone icon in the taskbar) under
  HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore.
  An app that holds the device has LastUsedTimeStart set and LastUsedTimeStop = 0.
  Browsers, and so Teams on the web, are listed under the NonPackaged subkey, one key per
  executable path with '\' written as '#'.

  The record is a log, not live state: an app that is killed or crashes while holding the
  device never gets its LastUsedTimeStop written. So an entry counts only when
    - its executable is on the allowlist (config "apps", default msedge.exe and chrome.exe),
    - and a process with that exact path is running right now.

  The script polls every PollSeconds and posts {"in_use": true|false} to a Home Assistant
  webhook on every change, and again every HeartbeatSeconds. The heartbeat lets Home
  Assistant tell a silent PC (sleep, shutdown) from a finished meeting.
  Only booleans leave the PC: no app names, no window titles.

.NOTES
  Config file next to this script (not in the repository), config.json:
    { "webhook_url": "http://192.0.2.10:8123/api/webhook/MEETING_WEBHOOK_ID",
      "apps": ["msedge.exe", "chrome.exe"] }
  Log: meeting-detector.log next to this script (state changes and errors, rotated at 512 KB).
  Install: see windows/README.md.
#>
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [int]$PollSeconds = 10,
    [int]$HeartbeatSeconds = 60
)

$ErrorActionPreference = 'Stop'
$consentStore = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
$logPath = Join-Path $PSScriptRoot 'meeting-detector.log'
$logMaxBytes = 512KB

function Write-Log {
    param([string]$Message)
    try {
        if ((Test-Path $logPath) -and (Get-Item $logPath).Length -ge $logMaxBytes) {
            Move-Item -Force -Path $logPath -Destination "$logPath.1"
        }
        Add-Content -Path $logPath -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message)
    }
    catch {
        # Logging must never stop the detector.
    }
}

function Test-DeviceInUse {
    param([string]$Capability, [string[]]$Apps)
    $base = "$consentStore\$Capability\NonPackaged"
    if (-not (Test-Path $base)) { return $false }
    foreach ($key in Get-ChildItem -Path $base -ErrorAction SilentlyContinue) {
        $exeName = ($key.PSChildName -split '#')[-1]
        if ($Apps -notcontains $exeName) { continue }
        $p = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $p -or $null -eq $p.LastUsedTimeStop -or
            $p.LastUsedTimeStart -le 0 -or $p.LastUsedTimeStop -ne 0) { continue }
        # A killed or crashed app leaves its entry "in use" forever: trust it only while it runs.
        $exePath = $key.PSChildName -replace '#', '\'
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($exeName)
        if (Get-Process -Name $baseName -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath }) {
            return $true
        }
    }
    return $false
}

try {
    $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    $url = $config.webhook_url
    if (-not $url) { throw "webhook_url missing in $ConfigPath" }
    $apps = @($config.apps | Where-Object { $_ })
    if ($apps.Count -eq 0) { $apps = @('msedge.exe', 'chrome.exe') }
}
catch {
    Write-Log "ERROR config: $($_.Exception.Message)"
    exit 1
}
Write-Log "start: apps=$($apps -join ',') poll=${PollSeconds}s heartbeat=${HeartbeatSeconds}s"

$lastSentState = $null
$lastSentAt = [datetime]::MinValue
$lastError = $null

while ($true) {
    try {
        $mic = Test-DeviceInUse 'microphone' $apps
        $cam = Test-DeviceInUse 'webcam' $apps
        $inUse = $mic -or $cam
        $now = Get-Date

        if ($inUse -ne $lastSentState -or ($now - $lastSentAt).TotalSeconds -ge $HeartbeatSeconds) {
            $body = @{ in_use = $inUse; microphone = $mic; webcam = $cam } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 5 | Out-Null
            if ($inUse -ne $lastSentState) { Write-Log "in_use=$inUse (microphone=$mic webcam=$cam)" }
            $lastSentState = $inUse
            $lastSentAt = $now
            $lastError = $null
        }
    }
    catch {
        # Home Assistant unreachable or a transient read error: keep polling, the next round retries.
        # Log each distinct error once, not every round.
        if ($_.Exception.Message -ne $lastError) {
            $lastError = $_.Exception.Message
            Write-Log "ERROR: $lastError"
        }
    }
    Start-Sleep -Seconds $PollSeconds
}
