Param(
    [switch]$Register,
    [switch]$Unregister,
    [int]$Threshold = 0
)
$ErrorActionPreference = "Stop"
if ((-not $Unregister) -and ($Threshold -eq 0)) {
    Write-Error "Threshold missing"
}

$dir = 'C:\Program Files\rport\'
$stateFile = $dir + 'data\state.json'
$logFile = $dir + 'watchdog.log'
$taskName = "RPort-Watchdog"
$IntervallMin = 5

function Write-Log($msg) {
    if (($env:USERPROFILE).Endswith("systemprofile")) {
        Write-Output "$(Get-Date): $($msg)" | Out-File $logFile
    }
    else {
        Write-Output $($msg)
    }
}

function checkRport() {
    if (-not (Test-Path $stateFile -PathType Leaf)){
        Write-Log "ERROR: Statefile $($stateFile) not found. Not cheching."
        return
    }
    $now = ((Get-Date -UFormat %s) - [int](Get-Date -UFormat %Z) * 3600)
    $lastUpdate = (Get-Content $stateFile | ConvertFrom-Json).last_update_ts
    $diff = $now - $lastUpdate
    if ($diff -gt $Threshold) {
        Write-Log "RPort hangs. No activity deteced for $($diff) seconds (> $($Threshold)). Will restart service rport ..."
        Restart-Service rport
    }
    else {
        Write-Log "RPort is running fine. Last activity $($diff) seconds ago (< $($Threshold))."
    }
}

function registerTask() {
    if ($null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)){
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Output "Existing scheduled task $($taskName) unregistered."
    }
    $taskFile = '"C:\Program Files\rport\watchdog.ps1"'
    $description = 'A watchdog task that supervises the rport client by evaluating its state.json file'
    $action = New-ScheduledTaskAction `
        -Execute "powershell" `
        -Argument "-ExecutionPolicy bypass -file $( $taskFile ) -Threshold $Threshold" `
        -WorkingDirectory $dir
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervallMin)
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
    $task = New-ScheduledTask `
        -Action $action `
        -Principal $principal `
        -Trigger $trigger `
        -Settings $settings `
        -Description $description
    Register-ScheduledTask $taskName -InputObject $task|Out-Null
    Write-Output "Task `"$( $taskName )`" [$( $taskFile )] scheduled every $($IntervallMin) minutes."
}

if ($Register) {
    registerTask
}
elseif ($Unregister) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Output "Task unregistered"
}
else {
    checkRport
}

