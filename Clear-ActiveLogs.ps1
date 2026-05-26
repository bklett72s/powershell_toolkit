<#
.SYNOPSIS
Clear and saves log files within C:\Windows\System32\winevt\Logs and moves them to a
specified archive directory.

.DESCRIPTION
Clears and saves log files within C:\Windows\System32\winevt\Logs and moves them to a
specified archive directory.

.NOTES
- Requires appropriate permissions to access and move log files.
- Run with service account that has privileges to access and move log files.
- Ensure the archive directory exists and has sufficient storage space.
#>

[CmdletBinding()]
param(
    [string]$dte_year  = (Get-Date -Format "yyyy"),
    [string]$dte_month = "$(Get-Date -Format "MM")-$(Get-Date -Format "MMM")",
    [string]$dte_day   = (Get-Date -Format "dd")
)

# Function user ActiveDirectory module to get a list of enabled windows hosts in the domain.
Function Get-Hosts {
    $dc = $env:LOGONSERVER -replace '^\\\\',''
    $dcSession = New-PSSession -ComputerName $dc -ErrorAction SilentlyContinue
    if ($dcSession -ne $null) {
        Import-Module ActiveDirectory -PSSession $dcSession -ErrorAction Stop
        $hosts = Get-ADComputer -Filter 'OperatingSystem -like "*Windows*" -and Enabled -eq $true' -Properties Name | Select-Object -ExpandProperty Name
        
        Return $hosts
    }
    else {
        Write-Host "Unable to connect to domain controller: $($env:LOGONSERVER). Running in non-domain environment." -ForegroundColor Yellow
        exit 1
    }
}

Function Get-Logs {
    param( 
        [string]$remoteHostLogDirectory
    )

    $filterResults  = [System.Collections.ArrayList]::new()
    $logFilter      = @("Security", "Application", "System")
    $stamp        = (Get-Date -Format "HHmmss")

    foreach ($log in $logFilter) {
        $clearedFile= "$($remoteHostLogDirectory)\$($env:COMPUTERNAME)-Cleared-$log-$($dte_year)-$($dte_month)-$($dte_day)-$($stamp).evtx"
        Write-Host "Attempting to clear $log within $($remoteHostLogDirectory)" -ForegroundColor Yellow
        if ($targetHost -ieq $env:COMPUTERNAME) {
           wevtutil cl $log /bu:$clearedFile | Out-Null
        }
        else {
           wevtutil cl $log /bu:$clearedFile /r:$targetHost | Out-Null
        }

        if ($LASTEXITCODE -eq 0) {
           $filterResults.Add($clearedFile) | Out-Null
        }
        else {
           Write-Host "wevtutil failed for $log on $targetHost" -ForegroundColor Red
        }
        $filterResults.Add($clearedFile) | Out-Null
    }
    return $filterResults
}

# Function to move logs using robocopy. We rename the original archive file to prevent confliction in the destination directory.
Function Move-Logs {
    param(
        [System.Collections.ArrayList]$pathCollection,
        [string]$logRetentionDir,
        [string]$roboCopyLogLoc
    )
    foreach ($file in $pathCollection) {
        try {
            if ($file -ne $null) {
                write-host $file

                $filePath       = Split-Path -Path $file -Parent
                $fileName       = Split-Path -Path $file -Leaf
                robocopy $filePath $logRetentionDir $fileName /MOV /MT /XC /R:3 /W:5 /LOG+:$roboCopyLogLoc  /TEE
            }
        } catch {
            Write-Host "Error moving file: $file. Error Message: $_" -ForegroundColor Red
        }
    }
}

# Function to compress logs retained with compact.exe
Function Compress-ClearedLogs {
    param([String] $logRetentionDir)

    New-Item -ItemType File -Path "$logRetentionDir\README_BEFORE_OPENING_LOGS.txt" -Value `
        "These logs have been compressed using compact.exe. To open these logs, you will need to decompress them using the following command: compact /u <filename.evtx>" `
        -ErrorAction SilentlyContinue

    Get-ChildItem -Path $logRetentionDir -Filter "*.evtx" | ForEach-Object {
        compact /c $_.FullName
    }
}

########################################################## Main Script Body ##########################################################

# Main Body Variable Definitions
#[string]$logRetentionDir                                       = # Use this to define your remote log collection area
[string]$logRetentionDir                                        = "\\localhost\D$\code_projects\test_env\remote_log_loc\$($dte_year)\$($dte_month)\$($dte_day)\cleared\" # Test Dir
[string]$remoteHostLogDirectory                                 = '\\localhost\C$\Windows\System32\winevt\Logs\' # Standard Log Location on Windows Machines
#[string]$remoteHostLogDirectory                                 = '\\localhost\D$\code_projects\test_env\logs_to_archive\' # Test Dir
[string]$sciptLogLoc                                            = "$($PsScriptRoot)\var\log\Clear-ActiveLogs.log"
[string]$roboCopyLogLoc                                         = "$($PsScriptRoot)\var\log\robocopy_archivelogs.log"
$masterPathCollection                                           = [System.Collections.ArrayList]::new()

# Ensure log retention directory exists
if (-not (Test-Path -Path $sciptLogLoc)) {
    New-Item -ItemType File -Path $sciptLogLoc | Out-Null
}
start-transcript -Path $sciptLogLoc -Force -Append

# Ensure log retention directory exists
if (-not (Test-Path -Path $logRetentionDir)) {
    New-Item -ItemType Directory -Path $logRetentionDir | Out-Null
}

# Domain Check - If we're part of a domain, we'll loop through hosts and look for logs, if not we'll just check locally and move any logs we find
if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
    $hosts = Get-Hosts
    foreach ($hostname in $hosts) {
        Write-Host "Domain Detected... Looking for Hosts...." -ForegroundColor Green
        Write-Host "Checking $hostname for archived Logs..." -ForegroundColor Blue
        $remoteHostLogDirectory = $remoteHostLogDirectory.Replace("localhost", $hostname)
        $returnedResults = Get-Logs -remoteHostLogDirectory $remoteHostLogDirectory
        if ($returnedResults.Count -gt 1) {
           $masterPathCollection.AddRange($returnedResults) | Out-Null
        }
        elseif ($returnedResults.Count -eq 1) {
           $masterPathCollection.Add($returnedResults) | Out-Null
        }
        else {
            Write-Host "No archived logs found in $remoteHostLogDirectory" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "No Domain Detected... Remaining Local...." -ForegroundColor Green
    Write-Host "Looking for logs in $remoteHostLogDirectory" -ForegroundColor Blue
    $returnedResults = Get-Logs -remoteHostLogDirectory $remoteHostLogDirectory
    write-host $returnedResults.Count
    if ($returnedResults.Count -gt 1) {
       $masterPathCollection.AddRange($returnedResults) | Out-Null
    }
    elseif ($returnedResults.Count -eq 1) {
       $masterPathCollection.Add($returnedResults) | Out-Null
    }
    else {
        Write-Host "No archived logs found in $remoteHostLogDirectory" -ForegroundColor Yellow
        Write-Host "Exiting... "
        exit 0
    }
}

# Move logs if we have any paths collected in our master collection
if ($masterPathCollection.Count -ne 0) {
    Move-Logs -pathCollection $masterPathCollection -logRetentionDir $logRetentionDir -roboCopyLogLoc $roboCopyLogLoc
    Compress-ClearedLogs -logRetentionDir $logRetentionDir
}
else{
    Write-Host "No archived logs to move..." -ForegroundColor Red
    Write-Host "Exiting... "
    exit 0
}
