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

# Generate a new random password
$newPassword = Generate-RandomPassword

# Set the user password to the new random password
$securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force
try {
    Set-LocalUser -Name $env:USERNAME -Password $securePassword
} catch {
    Write-Error "Unable to update the password. The value provided for the new password does not meet the length, complexity, or history requirements of the domain."
    exit
}

# Schedule a task to reset the password to blank after 1 second
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `"Start-Sleep -Seconds 1; Reset-UserPassword`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)
$taskName = "ResetPassword"
try {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -User "SYSTEM"
} catch {
    Write-Error "Failed to create the scheduled task."
    exit
}

# Define the path to the startup folder
$userStartupFolder = [System.Environment]::GetFolderPath('Startup')
$commonStartupFolder = [System.Environment]::GetFolderPath('CommonStartup')

# Use the user startup folder if available, otherwise use the common startup folder
if ([string]::IsNullOrWhiteSpace($userStartupFolder)) {
    if ([string]::IsNullOrWhiteSpace($commonStartupFolder)) {
        Write-Error "Unable to retrieve the startup folder path."
        exit
    } else {
        $startupFolder = $commonStartupFolder
    }
} else {
    $startupFolder = $userStartupFolder
}

# Define the path to the script
$scriptPath = Join-Path $startupFolder "PasswordChangeScript.ps1"

# Check if the script is already present in the startup folder
if (-not (Test-Path $scriptPath)) {
    # Script content
    $scriptContent = @"
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
    for (\$i = 8; \$i -lt 16; \$i++) {
        \$password += \$chars | Get-Random -Count 1
    }
    return (\$password | Sort-Object {Get-Random}) -join ''
}

# Function to set the user password to blank
function Reset-UserPassword {
    \$username = \$env:USERNAME
    \$nullPassword = ConvertTo-SecureString """" -AsPlainText -Force
    Set-LocalUser -Name \$username -Password \$nullPassword
}

# Generate a new random password
\$newPassword = Generate-RandomPassword

# Set the user password to the new random password
\$securePassword = ConvertTo-SecureString -String \$newPassword -AsPlainText -Force
Set-LocalUser -Name \$env:USERNAME -Password \$securePassword

# Schedule a task to reset password to blank after 1 second
\$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command `"Start-Sleep -Seconds 1; Reset-UserPassword`""
\$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)
Register-ScheduledTask -TaskName "ResetPassword" -Action \$action -Trigger \$trigger -User "SYSTEM"
"@

    # Create the script file
    try {
        $scriptContent | Out-File -FilePath $scriptPath -Encoding utf8
    } catch {
        Write-Error "Access to the path '$scriptPath' is denied."
        exit
    }

    # Create a shortcut to the script in the startup folder
    $shortcutPath = Join-Path $startupFolder "PasswordChangeScript.lnk"
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`""
        $shortcut.Save()
        Write-Host "Script added to startup."
    } catch {
        Write-Error "Unable to save shortcut to '$shortcutPath'."
        exit
    }
} else {
    Write-Host "The script is already present in the startup folder."
}

# Register the script to run as administrator at startup
$regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
$regName = "PasswordChangeScript"
$regValue = "powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`""
try {
    New-ItemProperty -Path $regPath -Name $regName -Value $regValue -PropertyType String -Force
    Write-Host "Script registered to run at startup."
} catch {
    Write-Error "Unable to register the script to run at startup."
}
