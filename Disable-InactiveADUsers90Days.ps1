<#
.SYNOPSIS
Disable AD users inactive for 90+ days and stamp Description with disable date.

.DESCRIPTION
Finds enabled AD user accounts whose LastLogonDate is older than the inactivity
threshold, disables them, and writes the Description field as:
"User has been disabled by 90 day script on <timestamp>"

.NOTES
- Requires RSAT ActiveDirectory module.
- Run with privileges to disable users and edit user attributes.
- Uses LastLogonDate (derived from lastLogonTimestamp, replicated).
#>

[CmdletBinding()]
param(
    [int]$DaysInactive = 90,
    [string]$SearchBase = $null,
    [string]$LogDirectory = 'C:\Logs\AD',
    [string[]]$ExcludedSamAccountNames = @(
        'Administrator',
        'Guest',
        'krbtgt',
        'svc_sql',
        'svc_backup'
    )
)

$DisableDate = Get-Date
$CutoffDate  = $DisableDate.AddDays(-$DaysInactive)
$DisableComment = "User has been disabled by 90 day script on $($DisableDate.ToString('yyyy-MM-dd HH:mm:ss'))"
$TranscriptPath = Join-Path -Path $LogDirectory -ChildPath ("Disable-InactiveADUsers90Days_{0}.log" -f $DisableDate.ToString('yyyyMMdd_HHmmss'))
$TranscriptStarted = $false

# Ensure log directory exists
if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}

# Validate we can create a file in the log directory
$LogWriteTestFile = Join-Path -Path $LogDirectory -ChildPath (".write-test-{0}.tmp" -f [guid]::NewGuid().ToString())
try {
    New-Item -ItemType File -Path $LogWriteTestFile -Force -ErrorAction Stop | Out-Null
    Remove-Item -Path $LogWriteTestFile -Force -ErrorAction Stop
}
catch {
    throw "Unable to create logs in '$LogDirectory'. Check path and permissions. Error: $($_.Exception.Message)"
}

try {
    Start-Transcript -Path $TranscriptPath -Force -ErrorAction Stop
    $TranscriptStarted = $true

    Import-Module ActiveDirectory -ErrorAction Stop

    Write-Host "Transcript logging to: $TranscriptPath" -ForegroundColor Cyan
    Write-Host "Searching for enabled users inactive since before $($CutoffDate.ToString('yyyy-MM-dd HH:mm:ss')) ..." -ForegroundColor Cyan

    $params = @{
        Filter     = { Enabled -eq $true -and LastLogonDate -lt $CutoffDate }
        Properties = @('ObjectGUID','LastLogonDate','SamAccountName','DistinguishedName','Description','Name')
    }
    if ($SearchBase) { $params.SearchBase = $SearchBase }

    $staleUsers = Get-ADUser @params |
        Where-Object {
            $_.SamAccountName -notin $ExcludedSamAccountNames -and
            $_.DistinguishedName -notmatch 'OU=Domain Controllers'
        }

    if (-not $staleUsers) {
        Write-Host 'No eligible inactive users found.' -ForegroundColor Green
        return
    }

    Write-Host "Users to disable: $($staleUsers.Count)" -ForegroundColor Yellow
    $staleUsers |
        Select-Object Name,SamAccountName,LastLogonDate,DistinguishedName |
        Sort-Object LastLogonDate |
        Format-Table -AutoSize

    foreach ($user in $staleUsers) {
        try {
            Disable-ADAccount -Identity $user.ObjectGUID -ErrorAction Stop
            Set-ADUser -Identity $user.ObjectGUID -Description $DisableComment -ErrorAction Stop
            Write-Host "Disabled + commented: $($user.SamAccountName)" -ForegroundColor Magenta
        }
        catch {
            Write-Warning "Failed for $($user.SamAccountName): $($_.Exception.Message)"
        }
    }

    Write-Host "`nCompleted." -ForegroundColor Green
}
finally {
    if ($TranscriptStarted) {
        Stop-Transcript | Out-Null
    }

    if (Test-Path -Path $TranscriptPath) {
        Write-Host "Log created successfully: $TranscriptPath" -ForegroundColor Green
    }
    else {
        Write-Warning "Transcript log was not created: $TranscriptPath"
    }
}
