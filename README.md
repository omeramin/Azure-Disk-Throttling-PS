# Azure-Disk-Throttling-PS

This PS script allows you to query Azure and Disk Throttling events for VMs in Azure. 
Complete the pre-reqs to setup data collection, and allow connectivity through REST APIs
Once the script finishes, you can export the results to CSV, or view in PS.

* $DiskThrottleResults
* $VMThrottleResults
* Export-Csv -Path C:\temp\DiskThrottle.csv $DiskThrottleResults
* Export-Csv -Path C:\temp\VMThrottle.csv $VMThrottleResults



## Pre-Reqs
1. Create Log Analytics workspace and push VM counters to workspace. Please record the workspace Id, and security key. You can find this in the Advanced Settings | Connected Sources pane.
1. Connect VM to Log Analytics Workspace.
1. Go to Log Analytics workspace | Advanced Settings | Data | Windows Performance Counters. Add the following counters to be collected at 10s intervals. PhysicalDisk(*)\Disk Bytes/sec, PhysicalDisk(*)\Disk Transfers/sec.
1. Create an Azure AD Applicaiton, Assign the application to a role, and then create a client secret. Record the following script. 
   1. $TenantId
   1. $SubscriptionId 
   1. $ClientId
   1. $ClientSecret
https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal
1. Edit the script with the values collected above.



## Script Logic
The script uses the following logic.

1. Get list of VMs and Disks
1. Get Azure Compute capabilities for each SKU using AZURE REST API
1. Match Disks to each corresponding VM, add in the VM IOPS,DiskBytes Limit.
1. Post Disk\VM data to Log Analytics. Doing this for performance reasons. It is faster to run the throttling queries in Log Analytics compared to doing it locally.
1. Run queries for Disk and VM throttling.
1. Output results
