<#
.SYNOPSIS
A watchdog that supervises the rport service and restarts it when needed.
The watchdog script is intended to be run every five minutes as a scheduled task.

This script is licensed under the MIT open-source license.
.PARAMETER Threshold
Use seconds
.PARAMETER Register
Register the script as a scheduled task. Requires -Threshold
.PARAMETER Unregister
Remove the scheduled task
.PARAMETER State
Print the state of the scheduled task
.OUTPUTS
System.String. Information about the state of rport and wether it has been restarted or not
.EXAMPLE
PS> watchdog.ps1 -Threshold 90
09/15/2022 17:10:13: RPort is running fine. Last activity 3.52854990959167 seconds ago (< 90).
.LINK
https://github.com/cloudradar-monitoring/rport-win-watchdog
https://oss.rport.io/advanced/watchdog-integration/
#>
Param(
    [switch]$Register,
    [switch]$Unregister,
    [switch]$State,
    [int]$Threshold = 0
)
$ErrorActionPreference = "Stop"

Set-Variable dir -Option Constant -Value 'C:\Program Files\rport'
Set-Variable stateFile -Option Constant -Value ($dir + '\data\state.json')
Set-Variable logFile -Option Constant -Value ($dir + '\watchdog.log')
Set-Variable taskName -Option Constant -Value "RPort-Watchdog"
Set-Variable IntervallMin -Option Constant -Value 5

function Write-Message($msg) {
    <#
    .SYNOPSIS
    Write messages to a logfile
    #>
    Write-Output "$(Get-Date): $($msg)" | Out-File $logFile -Append
}

function Test-RportState {
    <#
    .SYNOPSIS
    Test if rport is connected by reading the state.json file. If the last activity is older than the threshold, restart the service.
    .OUTPUTS
    System.ValueType Boolean
    #>
    try { $now = [DateTimeOffset]::Now.ToUnixTimeSeconds() }
    catch { $now = [Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s")) }

    $lastUpdate = (Get-Content $stateFile -Raw | ConvertFrom-Json).last_update_ts
    $diff = $now - $lastUpdate
    if ($diff -gt $Threshold) {
        Write-Message "RPort hangs. No activity deteced for $($diff) seconds (> $($Threshold)). Will restart rport service..."
        return $false
    }
    else {
        Write-Message "RPort is running fine. Last activity $($diff) seconds ago (< $($Threshold))."
        return $true
    }
}

function Restart-Rport {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    <#
    .SYNOPSIS
    Restart rport but only if the service could not be started during boot or if it claims to be running.
    This function does not restart rport if the service has been shut down properly.
    #>
    if ((Get-Service rport).Status -eq "Running") {
        Restart-Service rport
        Write-Message "RPort Service was running. RPort service restarted"
        return
    }
    if (Test-LastStartupError) {
        Restart-Service rport
        Write-Message "RPort service has failed to start during last boot. RPort service restarted"
        return
    }
    Write-Message "Not restarting RPort because it was intentionally stopped."
}

function Register-Task {
    <#
    .SYNOPSIS
    Register this script as a sheduled task so it continuoly runs in the background
    #>
    Write-Output "Registering scheduled task ..."
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Output "Existing scheduled task $($taskName) unregistered first."
    }
    $taskFile = '"C:\Program Files\rport\watchdog.ps1"'
    $description = 'A watchdog task that supervises the rport client by evaluating its state.json file'
    $action = New-ScheduledTaskAction `
        -Execute "powershell" `
        -Argument "-ExecutionPolicy bypass -file $( $taskFile ) -Threshold $Threshold" `
        -WorkingDirectory $dir
    $startTime = (get-date)
    $Params2012 = @{
     "Once" = $true
     "At" = $startTime
     "RepetitionInterval" = (New-TimeSpan -Minutes $IntervallMin)
     "RepetitionDuration" = (New-TimeSpan -Start (Get-Date) -End ((Get-Date).AddDays(9999)))
    }
    $Params2016 = @{
     "Once" = $true
     "At" = $startTime
     "RepetitionInterval" = (New-TimeSpan -Minutes $IntervallMin)
    }
    if([environment]::OSVersion.Version.Major -ge 10){$Params = $Params2016}
    if([environment]::OSVersion.Version.Major -le 6){$Params = $Params2012}
    $trigger = New-ScheduledTaskTrigger @Params
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
    $task = New-ScheduledTask `
        -Action $action `
        -Principal $principal `
        -Trigger $trigger `
        -Settings $settings `
        -Description $description
    Register-ScheduledTask $taskName -InputObject $task | Out-Null
    Write-Output "Task `"$( $taskName )`" [$( $taskFile )] scheduled every $($IntervallMin) minutes."
}

function Get-TaskState {
    <#
    .SYNOPSIS
    Print the state of the scheduled task
    #>
    $state = (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    if ($state) {
        Write-Output "Task $($taskName) is registered with state: $($state.state)"
        $taskInfo = (Get-ScheduledTaskInfo -TaskName $taskName)
        if ($taskInfo.LastTaskResult -eq 267011) {
            Write-Output "Task has not yet run."
        }
        elif($taskInfo.LastTaskResult -ne 0) {
            Write-Output "**CAUTION! The last execution of the task has failed.**"
        }
        $taskInfo
    }
    else {
        Write-Output "Task $($taskName) is not registered as a sheduled task."
    }
}

function Get-LastBoot {
    <#
    .SYNOPSIS
    Return the time of the last system boot
    .OUTPUTS
    System.Object time of the last boot
    #>
    #Get-WmiObject win32_operatingsystem | Select-Object @{LABEL = 'Time'; EXPRESSION = { $_.ConverttoDateTime($_.lastbootuptime) } }
    Get-CimInstance -ClassName win32_operatingsystem | Select-Object lastbootuptime
}
function Test-LastStartupError {
    <#
    .SYNOPSIS
    Return true if the last startup of rport during the boot process failed due to a timeout
    .OUTPUTS
    System.ValueType Boolean
    #>
    $rportStartupErrors = Get-WinEvent -FilterHashtable @{
        logname   = 'System'
        StartTime = (Get-LastBoot).lastbootuptime
        Level     = "2"
    } | Where-Object { $_.Message -like '*rport*' }
    $rportStartupErrors.Message | Select-String -Pattern "A time" -Quiet
}

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Error -Message "You are not an admin, please elevate and run the script again"
    exit 1
}

if (-not(Get-Service rport -ErrorAction SilentlyContinue)) {
    Write-Error "Service not found! This script requires rport to be registerd as a windows service."
    exit 1
}

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Output "Task unregistered"
    exit 0
}

if ($State) {
    Get-TaskState
    exit 0
}

if ($Threshold -eq 0) {
    Write-Error "Threshold missing. Use -Threshold N (seconds)"
    exit 1
}

if ($Register) {
    if ($PWD.Path -ne $dir) {
        Write-Output "Copy script to $($dir) first and execute again from there."
        exit 1
    }
    if (-not (Test-Path $stateFile -PathType Leaf)) {
        Write-Error "State File Not Found! The file $($stateFile) does not exist. Enable the watchdog integration first."
    }
    Register-Task
    exit 0
}

# Wipe the logfile before each run
Clear-Content $logFile -ErrorAction SilentlyContinue

# Execute the check, if state file exists.
if (-not (Test-Path $stateFile -PathType Leaf)) {
    Write-Message "ERROR: Statefile $($stateFile) not found. Not checking."
}
elseif (-not (Test-RportState)) {
    Restart-Rport
}

if (-not (($env:USERPROFILE).Endswith("systemprofile"))) {
    # Print the logfile to the console
    Get-Content $logFile
}