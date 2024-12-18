# Ensure the script runs with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "You need to run this script as an administrator."
    exit
}

# Function to generate a random password that meets complexity requirements
function Generate-RandomPassword {
    $upper = [char[]]('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
    $lower = [char[]]('abcdefghijklmnopqrstuvwxyz')
    $digit = [char[]]('0123456789')
    $special = [char[]]('!@#$%^&*()_+-=[]{}|;:,.<>?')
    $chars = $upper + $lower + $digit + $special
    $password = ''
    $password += $upper | Get-Random -Count 2
    $password += $lower | Get-Random -Count 2
    $password += $digit | Get-Random -Count 2
    $password += $special | Get-Random -Count 2
    for ($i = 8; $i -lt 16; $i++) {
        $password += $chars | Get-Random -Count 1
    }
    return ($password | Sort-Object {Get-Random}) -join ''
}

# Function to set the user password to blank
function Reset-UserPassword {
    $username = $env:USERNAME
    $nullPassword = ConvertTo-SecureString """" -AsPlainText -Force
    Set-LocalUser -Name $username -Password $nullPassword
}

# Function to set a new random password for the current user
function Set-NewRandomPassword {
    $newPassword = Generate-RandomPassword
    $securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force
    Set-LocalUser -Name $env:USERNAME -Password $securePassword
}

# Check if the password is blank and set a new random password if true
if ((Get-LocalUser -Name $env:USERNAME).Password -eq "") {
    Set-NewRandomPassword
}

# Schedule a task to reset password to blank on shutdown or restart
$actionShutdown = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `Reset-UserPassword`"
$triggerShutdown = New-ScheduledTaskTrigger -AtStartup
$triggerShutdown.EventTriggerId = 1074 # Trigger on shutdown/restart
$taskNameShutdown = "ResetPasswordOnShutdown"
try {
    if (Get-ScheduledTask -TaskName $taskNameShutdown -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskNameShutdown -Confirm:$false
    }
    Register-ScheduledTask -TaskName $taskNameShutdown -Action $actionShutdown -Trigger $triggerShutdown -User "SYSTEM"
} catch {
    Write-Error "Failed to create the scheduled task."
    exit
}

# Schedule a task to generate a random password every hour after user logs in
$actionRandomPassword = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `Set-NewRandomPassword`"
$triggerRandomPassword = New-ScheduledTaskTrigger -At (Get-Date).AddMinutes(1) # Start 1 minute after login
$triggerRandomPassword.RepetitionInterval = New-TimeSpan -Hours 1  # Repeat every hour
$triggerRandomPassword.RepetitionDuration = New-TimeSpan -Days 1   # Repeat for a full day
$taskNameRandomPassword = "GenerateRandomPasswordHourly"
try {
    if (Get-ScheduledTask -TaskName $taskNameRandomPassword -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskNameRandomPassword -Confirm:$false
    }
    Register-ScheduledTask -TaskName $taskNameRandomPassword -Action $actionRandomPassword -Trigger $triggerRandomPassword -User $env:USERNAME
} catch {
    Write-Error "Failed to create the scheduled task for hourly password generation."
    exit
}

Write-Host "Scheduled tasks created successfully."
