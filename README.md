## 🐶 A watchdog for the rport service on Windows

> ✋ **Use only if really needed!** The rport client is robust and always re-establishes the 
> connection to the rport server. The watchdog should only be used in rare cases when have experienced
> lost connections. Do not use as a generic preventive measure.

A watchdog that supervises the rport service and restarts it when needed.
The watchdog script is intended to be run every five minutes as a scheduled task.

If you have the rport [watchdog integration](https://oss.rport.io/advanced/watchdog-integration/) enabled,
this scripts checks the internal state of the rport client by reading the `state.json` file.

If the rport client has not actively confirmed its successful connection to the rport server,
the timestamp inside the json file will become obsolete. The scripts will compare this timestamp
with the current time and restart the rport service if the given threshold is exceeded.

### Installation & Usage

Install from a PowerShell with administrative rights.

```powershell
cd "C:\Program Files\rport"
iwr https://github.com/cloudradar-monitoring/rport-win-watchdog/releases/latest/download/watchdog.ps1 `
-OutFile watchgog.ps1
```

Test, if the state file can be read:

```powershell
PS> .\watchdog.ps1 -Threshold 90
09/15/2022 19:44:15: RPort is running fine. Last activity 27.7940099239349 seconds ago (< 90).
```

Before registering the scheduled task, read about [what's your best threshold](https://oss.rport.io/advanced/watchdog-integration/#implement-your-watchdog).

Register the script as a scheduled task:

```powershell
PS>  .\watchdog.ps1 -Threshold 300 -Register
Registering scheduled task ...
Task "RPort-Watchdog" ["C:\Program Files\rport\watchdog.ps1"] scheduled every 5 minutes.
```

### More options

Unregister aka stop the watchdog:

```powershell
.\watchdog.ps1 -Unregister
```

Check, if it's working:

```powerhsell
PS> .\watchdog.ps1 -State
Task RPort-Watchdog is registered with state: Ready


LastRunTime        : 9/15/2022 7:54:54 PM
LastTaskResult     : 0
NextRunTime        : 9/15/2022 7:59:59 PM
NumberOfMissedRuns : 0
TaskName           : RPort-Watchdog
TaskPath           :
PSComputerName     :
```

Get the full help message:

```powershell
Get-Help .\watchdog.ps1 -Full
```