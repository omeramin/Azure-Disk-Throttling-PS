# Azure-Disk-Throttling-PS

This PS script allows you to query Azure and Disk Throttling events for VMs in Azure. 
Complete the pre-reqs to setup data collection, and allow connectivity through REST APIs
Once the script finishes, you can export the results to CSV, or view in PS.

* $DiskThrottleResults
* $VMThrottleResults
* Export-Csv -Path C:\temp\DiskThrottle.csv $DiskThrottleResults
* Export-Csv -Path C:\temp\VMThrottle.csv $VMThrottleResults


```powershell

PS C:\Temp> DiskThrottle.ps1

VM Count : 2
Disk Count : 5
Authenticating to AZURE REST API - Needed for retrieving Azure SKUs
Authenticated to AZURE REST API - Needed for retrieving Azure SKUs
Get VM Sizes and IOPS limits from Azure REST API
Retrieved VM Sizes and IOPS limits from Azure REST API
Get-AzureSKUData Count: 8561
$DiskConfigurations Count : 5
Post-VMDiskDataToLogAnalytics response: 
200
Uploaded 5 entries, Found 5 uploaded results
-----------------------------------------
Check for throttling events
Found  @{Count=14}  disk throttling events
Found  @{Count=0}  VM throttling events
-----------------------------------------
-----------------------------------------
-----------------------------------------
To export results, run the following 
Export-Csv -Path C:\temp\DiskThrottle.csv $DiskThrottleResults
OR
Export-Csv -Path C:\temp\VMThrottle.csv $VMThrottleResults

PS C:\Temp> 

```


## Pre-Reqs
1. Create Log Analytics workspace and push VM counters to workspace. Please record the workspace Id, and security key. You can find this in the Advanced Settings | Connected Sources pane.
1. Connect VM to Log Analytics Workspace.
1. Go to Log Analytics workspace | Advanced Settings | Data | Windows Performance Counters. Add the following counters to be collected at 10s intervals. PhysicalDisk(*)\Disk Bytes/sec, PhysicalDisk(*)\Disk Transfers/sec. It can take 20-30 minutes for counter values to first appear in the workspace.
1. Create an Azure AD Applicaiton, Assign the application to a role, and then create a client secret (https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal). Record the following values.
   1. $TenantId
   1. $SubscriptionId 
   1. $ClientId
   1. $ClientSecret
1. Edit the script with the values collected above.


Note - The first run of the script can take 20-30 min. This is because we create a custom log in Log Analytics to store Disk\VM configurations and throttling limits. There can be a long delay between creating the custom log and data to show up. During this period, the script will check for data every 10 seconds. Once the data shows up, then it will move forward. Future runs of the script will be much faster since the custom log will not be created again.




## Script Logic
The script uses the following logic.

1. Get list of VMs and Disks
1. Get Azure Compute capabilities for each SKU using AZURE REST API
1. Match Disks to each corresponding VM, add in the VM IOPS,DiskBytes Limit.
1. Post Disk\VM data to Log Analytics. Doing this for performance reasons. It is faster to run the throttling queries in Log Analytics compared to doing it locally.
1. Run queries for Disk and VM throttling.
1. Output results
