<#
.SYNOPSIS
  Tells Home Assistant whether the microphone or the webcam is in use on this PC.

.DESCRIPTION
  Windows keeps a per-app record of camera and microphone access (the same data behind
  the microphone icon in the taskbar) under
  HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore.
  An app that holds the device right now has LastUsedTimeStart set and LastUsedTimeStop = 0.
  Browsers, and so Teams on the web, are listed under the NonPackaged subkey.

  The script polls every PollSeconds and posts {"in_use": true|false} to a Home Assistant
  webhook on every change, and again every HeartbeatSeconds. The heartbeat lets Home
  Assistant tell a silent PC (sleep, shutdown) from a finished meeting.
  Only booleans leave the PC: no app names, no window titles.

.NOTES
  Config file (not in the repository), default %APPDATA%\meeting-detector\config.json:
    { "webhook_url": "http://192.0.2.10:8123/api/webhook/MEETING_WEBHOOK_ID" }
  Install: see windows/README.md.
#>
param(
    [string]$ConfigPath = (Join-Path $env:APPDATA 'meeting-detector\config.json'),
    [int]$PollSeconds = 10,
    [int]$HeartbeatSeconds = 60
)

$ErrorActionPreference = 'Stop'
$consentStore = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'

function Test-DeviceInUse {
    param([string]$Capability)
    $base = "$consentStore\$Capability"
    if (-not (Test-Path $base)) { return $false }
    foreach ($key in Get-ChildItem -Path $base -Recurse -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.LastUsedTimeStop -and
            $p.LastUsedTimeStart -gt 0 -and $p.LastUsedTimeStop -eq 0) {
            return $true
        }
    }
    return $false
}

$url = (Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json).webhook_url
if (-not $url) { throw "webhook_url missing in $ConfigPath" }

$lastSentState = $null
$lastSentAt = [datetime]::MinValue

while ($true) {
    $mic = Test-DeviceInUse 'microphone'
    $cam = Test-DeviceInUse 'webcam'
    $inUse = $mic -or $cam
    $now = Get-Date

    if ($inUse -ne $lastSentState -or ($now - $lastSentAt).TotalSeconds -ge $HeartbeatSeconds) {
        $body = @{ in_use = $inUse; microphone = $mic; webcam = $cam } | ConvertTo-Json -Compress
        try {
            Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 5 | Out-Null
            $lastSentState = $inUse
            $lastSentAt = $now
        }
        catch {
            # Home Assistant unreachable: keep polling, the next round retries.
        }
    }
    Start-Sleep -Seconds $PollSeconds
}
