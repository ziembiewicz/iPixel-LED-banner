# Meeting detector (Windows)

`meeting-detector.ps1` tells Home Assistant whether the microphone or the webcam is in use,
so the door sign switches to ON AIR during a call. It works with any app, including
Teams in a browser, because it reads the same per-app access record Windows uses for
the microphone icon in the taskbar. No third-party agent, no MQTT broker, no Home Assistant token.

## How it fits

```
PC: meeting-detector.ps1 ──POST webhook (LAN only)──> HA: automation spotkanie_pc
    └─ input_boolean.pc_spotkanie ──> automation spotkanie_status ──> input_select.status_tomka
```

- A post arrives on every change and every 60 s as a heartbeat.
- No post for 3 minutes (sleep, shutdown) means the meeting is over.
- A status set by hand (kiosk tile) always wins over the automation.

## Install

1. Copy `meeting-detector.ps1` to `%LOCALAPPDATA%\meeting-detector\`.
2. Create `%APPDATA%\meeting-detector\config.json` with your Home Assistant address and the
   webhook ID from automation `spotkanie_pc` (keep this file out of any repository):

   ```json
   { "webhook_url": "http://192.0.2.10:8123/api/webhook/MEETING_WEBHOOK_ID" }
   ```

3. Register a logon task for the current user (PowerShell, no admin rights needed):

   ```powershell
   $dir = Join-Path $env:LOCALAPPDATA 'meeting-detector'
   $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
     -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dir\meeting-detector.ps1`""
   $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
   $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
     -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
     -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
   Register-ScheduledTask -TaskName 'meeting-detector' -Action $action -Trigger $trigger `
     -Settings $settings -Description 'Reports microphone/webcam use to Home Assistant'
   Start-ScheduledTask -TaskName 'meeting-detector'
   ```

   The task must run as the logged-on user: the access record lives in that user's registry hive.
   A console window may flash once at logon.

## Check

- Webhook reachable from the PC:
  `Invoke-RestMethod -Method Post -ContentType 'application/json' -Body '{"in_use":false}' -Uri <webhook_url>`
- Task running: `Get-ScheduledTask meeting-detector | Select-Object State`
- In Home Assistant, `input_boolean.pc_spotkanie` turns on within ~10 s of joining a call.

## Known limits

- Any app that holds the microphone or the webcam (a voice recorder, a game chat) counts as a meeting.
- The webhook is `local_only`: it does not work from outside the home network, for example over a full-tunnel VPN.

## Remove

```powershell
Unregister-ScheduledTask -TaskName 'meeting-detector' -Confirm:$false
```
