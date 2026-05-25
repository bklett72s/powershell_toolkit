# Powershell Toolkit  
## Repo Summary  
The powershell toolkit is a compilation of scripts developed to support certain functions that could be  
automated.  

## Disable-InactiveADUsers90Days.ps1 (Cant fully test due to lack of domain currently)  
### Script Summary  
Script to disable users and apply a comment to them that have been inactive for over 90 days.  

### Script Assumptions  
- The account running the script has...
  * Ability to login to the DC to import the ActiveDirectory Module OR have RSAT installed on machine
  * Permission to read AD Objects wihtin the domains forest
  * Permission to modify AD Objects
  * Is defined in "Logon as Service" and "Logon as Batch Job"
    + This should be done through Groups over the account itself
- The system/domain allows...
  * Allows for "Logon as Service"
  * Allows for "Logon as Batch Job"

## Get-ArchiveLogs.ps1 (Cant fully test due to lack of domain currently)  
### Script Summary  
Script to search local and remote hosts on or off a domain for archived archived security, application, and  
security logs. Once identified it takes a UNC of that log and stores it for movement once collection  
has completed. The script calls robocopy to move the items leveraging its confirmation of movment,  
deletion of original, multi-threading, retries, and logging to provide a robust solution for  
moving files that require a high level of maintenance in the assets integrity.  
Once complete, the script will compress the items in the final directory.  

### Script Assumptions 
- The account running the script has...
  * Permission to search remote host directories via UNC
  * Permission to read archived logs
  * Permission to copy archived logs
  * Permission to delete archived logs
  * Permission to place logs in collection/retention area
  * Permission to create log retention area if not made
  * Is defined in "Logon as Service" and "Logon as Batch Job"
    + This should be done through Groups over the account itself
- The system/domain allows...
  * Allows for "Logon as Service"
  * Allows for "Logon as Batch Job"
  * Allows for navigation via UNC


## Clear-ActiveLogs.ps1 (Cant fully test due to lack of domain currently)  
### Script Summary  
Script to clear and save security, application, and  
security logs on local and remote hosts on or off a domain for. The script searches the 
standard location for these logs and uses the native wevtutil to clear and buckup the logs. 
The script then calls robocopy to move the items leveraging its confirmation of movment,  
deletion of original, multi-threading, retries, and logging to provide a robust solution for  
moving files that require a high level of maintenance in the assets integrity.  
Once complete, the script will compress the items in the final directory.  

### Script Assumptions 
- The account running the script has...
  * Permission to search remote host directories via UNC
  * Permission to read archived logs
  * Permission to copy archived logs
  * Permission to delete archived logs
  * Permission to place logs in collection/retention area
  * Permission to create log retention area if not made
  * Is defined in "Logon as Service" and "Logon as Batch Job"
    + This should be done through Groups over the account itself
- The system/domain allows...
  * Allows for "Logon as Service"
  * Allows for "Logon as Batch Job"
  * Allows for navigation via UNC