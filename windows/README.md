# Meeting detector (Windows)

`meeting-detector.ps1` tells Home Assistant whether a meeting app holds the microphone or the
webcam, so the door sign switches to ON AIR during a call. By default only Microsoft Edge and
Google Chrome count, because Teams runs in the browser. It reads the same per-app access record
Windows uses for the microphone icon in the taskbar. No third-party agent, no MQTT broker,
no Home Assistant token.

## How it fits

```
PC: meeting-detector.ps1 ──POST webhook (LAN only)──> HA: automation spotkanie_pc
    └─ input_boolean.pc_spotkanie ──> automation spotkanie_status ──> input_select.status_tomka
```

- A post arrives on every change and every 60 s as a heartbeat.
- No post for 3 minutes (sleep, shutdown) means the meeting is over.
- A status set by hand (kiosk tile) always wins over the automation.

## Which apps count

Only executables listed in `apps` in `config.json` (default: `msedge.exe`, `chrome.exe`).
A game or Discord holding the microphone does not light ON AIR.

The access record is a log, not live state: an app that is killed or crashes while it holds the
microphone stays "in use" there forever. The script therefore also checks that a process with
the exact path from the record is running. Entries of closed apps are ignored.

## Install

Everything lives in one folder, `%LOCALAPPDATA%\meeting-detector\`:

1. Copy `meeting-detector.ps1` there.
2. Create `config.json` in the same folder with your Home Assistant address and the webhook ID
   from automation `spotkanie_pc` (keep this file out of any repository):

   ```json
   { "webhook_url": "http://192.0.2.10:8123/api/webhook/MEETING_WEBHOOK_ID",
     "apps": ["msedge.exe", "chrome.exe"] }
   ```

   `apps` is optional; leave it out to use the default list.

3. Register a logon task for the current user (PowerShell, no admin rights needed). The task
   starts the script through `conhost.exe --headless`, so no window appears even when Windows
   Terminal is the default console (it ignores `-WindowStyle Hidden`):

   ```powershell
   $dir = Join-Path $env:LOCALAPPDATA 'meeting-detector'
   $action = New-ScheduledTaskAction -Execute 'conhost.exe' `
     -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$dir\meeting-detector.ps1`""
   $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
   $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
     -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
     -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
   Register-ScheduledTask -TaskName 'meeting-detector' -Action $action -Trigger $trigger `
     -Settings $settings -Description 'Reports meeting microphone/webcam use to Home Assistant' -Force
   Start-ScheduledTask -TaskName 'meeting-detector'
   ```

   The task must run as the logged-on user: the access record lives in that user's registry hive.

### Upgrading from the first version

The first version read `config.json` from `%APPDATA%` (Roaming) and started a visible window.
Stop the old task, move the config next to the script, copy the new script and run step 3 again
(`-Force` replaces the task):

```powershell
Stop-ScheduledTask -TaskName 'meeting-detector'
Move-Item "$env:APPDATA\meeting-detector\config.json" "$env:LOCALAPPDATA\meeting-detector\"
```

## Check

- Task running: `Get-ScheduledTask meeting-detector | Select-Object State` shows `Running`.
- Log: `Get-Content "$env:LOCALAPPDATA\meeting-detector\meeting-detector.log" -Tail 20`.
  It records the start, every change of `in_use` and errors (a missing config, Home Assistant
  unreachable). The webhook address is never logged. The log rotates at 512 KB.
- Webhook reachable from the PC:
  `Invoke-RestMethod -Method Post -ContentType 'application/json' -Body '{"in_use":false}' -Uri <webhook_url>`
- Which apps Windows lists as holding the microphone right now (before the allowlist and the
  running-process check):

  ```powershell
  Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\NonPackaged' |
    Get-ItemProperty | Where-Object { $_.LastUsedTimeStart -gt 0 -and $_.LastUsedTimeStop -eq 0 } |
    Select-Object PSChildName
  ```

- In Home Assistant, `input_boolean.pc_spotkanie` turns on within ~10 s of joining a call.

## Known limits

- Any use of the microphone or the webcam in a listed browser counts as a meeting, not only Teams.
- If the browser crashes during a call while another browser window keeps running, its stale
  "in use" entry survives the running-process check. It clears the next time that browser uses
  the microphone; until then, set the status by hand on the kiosk.
- Apps from the Microsoft Store (packaged apps, for example the Teams desktop app) are not checked.
- The webhook is `local_only`: it does not work from outside the home network, for example over a full-tunnel VPN.

## Remove

```powershell
Unregister-ScheduledTask -TaskName 'meeting-detector' -Confirm:$false
```
