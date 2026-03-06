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
    [string[]]$ExcludedSamAccountNames = @(
        'Administrator',
        'Guest',
        'krbtgt',
        'svc_sql',
        'svc_backup'
    )
)

Import-Module ActiveDirectory -ErrorAction Stop

$DisableDate = Get-Date
$CutoffDate  = $DisableDate.AddDays(-$DaysInactive)
$DisableComment = "User has been disabled by 90 day script on $($DisableDate.ToString('yyyy-MM-dd HH:mm:ss'))"

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
