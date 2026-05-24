<#
.SYNOPSIS
Looks for archived log files within C:\Windows\System32\winevt\Logs and moves them to a
specified archive directory.

.DESCRIPTION
Looks for archived log files within C:\Windows\System32\winevt\Logs and moves them to a
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
    $dcSession = New-PSSession -CopmuterName $env:LOGONSERVER -ErrorAction SilentlyContinue
    if ($dcSession -ne $null) {
        Import-Module ActiveDirectory -PSSession $dcSession -ErrorAction Stop
        $hosts = Get-ADComputer -Filter 'OperatingSystem -like "*Windows*" AND Enabled -eq $true' -Properties Name | Select-Object -ExpandProperty Name
        
        Return $hosts
    }
    else {
        Write-Host "Unable to connect to domain controller: $($env:LOGONSERVER). Running in non-domain environment." -ForegroundColor Yellow
        exit 1
    }
}

# Function to find archived logs based on a defined filter in passed remote host directory.
Function Get-ArchiveLogs {
    param([string]$remoteHostLogDirectory)

    $filterResults = [System.Collections.ArrayList]::new()
    $archiveLogFilter = @("Archive-Security*.evtx", "Archive-Application*.evtx", "Archive-System*.evtx")
    foreach ($filter in $archiveLogFilter) {
        write-host "Looking for logs matching filter: $filter" -ForegroundColor Yellow
        $logFiles = Get-ChildItem -Path $remoteHostLogDirectory -Filter $filter -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        foreach ($path in $logFiles) {
            if ($path -ne $null) {
                Write-Host "Path Found: $path" -ForegroundColor Green
                $filterResults.Add($path) | Out-Null
            }
        }
    }
    Return $filterResults  
}

# Function to move logs using robocopy. We rename the original archive file to prevent confliction in the destination directory.
Function Move-ArchiveLogs {
    param(
        [System.Collections.ArrayList]$pathCollection,
        [string]$logRetentionDir,
        [string]$roboCopyLogLoc
    )
    foreach ($file in $pathCollection) {
        try {
            if ($file -ne $null) {
                write-host $file
                $origFileName   = Split-Path -Path $file -Leaf
                # Rename file to prevent confliction
                $renamedFile    = rename-item -Path $file -NewName "$($env:COMPUTERNAME)_$origFileName" -ErrorAction Stop -PassThru
                # Breakout file path and name for robocopy
                $filePath       = Split-Path -Path $renamedFile -Parent
                $fileName       = Split-Path -Path $renamedFile -Leaf

                write-host $file
                robocopy $filePath $logRetentionDir $fileName /MOV /MT /R:3 /W:5 /LOG+:$roboCopyLogLoc  /TEE
            }
        } catch {
            Write-Host "Error moving file: $file. Error Message: $_" -ForegroundColor Red
        }
    }
}

# Function to compress logs retained with compact.exe
Function Compress-ArchivedLogs {
    param([String] $logRetentionDir)

    Get-ChildItem -Path $logRetentionDir -Filter "*.evtx" | ForEach-Object {
        compact /c $_.FullName
    }
}

########################################################## Main Script Body ##########################################################

# Main Body Variable Definitions
#[string]$logRetentionDir                                       = # Use this to define your remote log collection area
[string]$logRetentionDir                                        = "\\localhost\D$\code_projects\test_env\remote_log_loc\$($dte_year)\$($dte_month)\$($dte_day)\" # Test Dir
#[string]$remoteHostLogDirectory                                = '\\localhost\C$\Windows\System32\winevt\Logs\' # Standard Log Location on Windows Machines
[string]$remoteHostLogDirectory                                 = '\\localhost\D$\code_projects\test_env\logs_to_archive\' # Test Dir
[string]$sciptLogLoc                                            = "$($PsScriptRoot)\var\log\Get-ArchiveLogs.log"
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
        $returnedResults = Get-ArchiveLogs -remoteHostLogDirectory $remoteHostLogDirectory
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
    $returnedResults = Get-ArchiveLogs -remoteHostLogDirectory $remoteHostLogDirectory
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
    Move-ArchiveLogs -pathCollection $masterPathCollection -logRetentionDir $logRetentionDir -roboCopyLogLoc $roboCopyLogLoc
}
else{
    Write-Host "No archived logs to move..." -ForegroundColor Red
    Write-Host "Exiting... "
    exit 0
}

Compress-ArchivedLogs -logRetentionDir $logRetentionDir

stop-transcript