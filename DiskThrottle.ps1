function IsCounterThrottled{
    param ($VM, $Counter, $Disk, $DiskType)

    $returnThrottleObject = $null
    $debugString = $null 

    if ($Disk -ne $null) 
    {
        if($Counter.CounterName -eq "Disk Transfers/sec" -and [double]$Counter.max -ge $Disk.DiskIOPSReadWrite)
        {
            $returnThrottleObject = [PSCustomObject]@{
                VMName = $VM.Name
                Counter = $Counter.CounterName
                CounterValue = $Counter.max
                CounterSimpleName = "IOPS"
                CounterInstance = $Counter.InstanceName
                CounterTimeGenerated = $Counter.TimeGenerated
                Disk = $Disk.Name
                ResourceLimit = $Disk.DiskIOPSReadWrite
                ThrottleType = $DiskType

            }
            $debugString = "Disk Throttled" + "," + $VM.Name + "," + "Disk Transfer/sec" + "," + $Counter.TimeGenerated + "," + $Disk.Name + "," + $Disk.DiskIOPSReadWrite + "," + $Counter.max
            Write-Host $debugString

        }

        if($Counter.CounterName -eq "Disk Bytes/sec" -and (([double]$Counter.max)/1024/1024) -ge $Disk.DiskMBpsReadWrite)
        {
            $returnThrottleObject = [PSCustomObject]@{
                VMName = $VM.Name
                Counter = $Counter.CounterName
                CounterValue = $Counter.max
                CounterSimpleName = "Disk MB/sec"
                CounterInstance = $Counter.InstanceName
                CounterTimeGenerated = $Counter.TimeGenerated
                Disk = $Disk.Name
                ResourceLimit = $Disk.DiskMBpsReadWrite
                ThrottleType = $DiskType
                }
            $debugString = "Disk Throttled" + "," + $VM.Name + "," + "Disk MBytes/sec" + "," + $Counter.TimeGenerated + "," + $Disk.Name + "," + $disk.DiskMBpsReadWrite + "," + ([double]$Counter.max)/1024/1024
            Write-Host $debugString
        }        

    }
    else
    {
        #CounterInstance = _Total
        if($Counter.CounterName -eq "Disk Transfers/sec" -and [double]$Counter.max -ge $VM.VMIops)
        {

            $returnThrottleObject = [PSCustomObject]@{
                VMName = $VM.Name
                Counter = $Counter.CounterName
                CounterValue = $Counter.max
                CounterSimpleName = "IOPS"
                CounterInstance = $Counter.InstanceName
                CounterTimeGenerated = $Counter.TimeGenerated
                Disk = ""
                ResourceLimit = ""
                ThrottleType = "VM"
                }

            $debugString = "VM Throttled" + "," + $VM.Name + "," + "VM - Disk Transfer/sec" + "," + $Counter.TimeGenerated + "," + $Disk.Name + "," + $Disk.DiskIOPSReadWrite + "," + $Counter.max
            Write-Host $debugString
        }

        if($Counter.CounterName -eq "Disk Bytes/sec" -and [double]$Counter.max -ge $VM.VMDiskBytes)
        {
            $returnThrottleObject = [PSCustomObject]@{
                VMName = $VM.Name
                Counter = $Counter.CounterName
                CounterValue = $Counter.max
                CounterSimpleName = "Disk MB/sec"
                CounterInstance = $Counter.InstanceName
                CounterTimeGenerated = $Counter.TimeGenerated
                Disk = ""
                ResourceLimit = ""
                ThrottleType = "VM"
                }

            $debugString = "VM Throttled" + "," + $VM.Name + "," + "VM - Disk MBytes/sec" + "," + $Counter.TimeGenerated + "," + $Disk.Name + "," + ([double]$VM.VMDiskBytes)/1024/1024 + "," + ([double]$Counter.max)/1024/1024
            Write-Host $debugString
        }    
    }

    Return $returnThrottleObject

}


#----------------------------------------------------------------
#----------------------------------------------------------------
#EDIT VARIABLES BELOW TO CHANGE QUERY PARAMETERS
#----------------------------------------------------------------
#----------------------------------------------------------------

#EDIT TO SET INTERVAL - The lower the interval, the longer the script will take to run.
#Example - 1d, 1h, 1m. The lowest is 10s. 
$timeIntervalWindow = "1d"
Write-Host "###timeIntervalWindow = ", $timeIntervalWindow


#EDIT TO SET HISTORY - Changes the query to pull records for the defined window relative to current time
#Example $historyWindow = "3d" - Query pull counters from (now() - 3 days) to now()
#$historyWindow = "-3d"
Write-Host "###historyWindow = ", $historyWindow


#EDIT TO TARGET PARTICULAR VM - If scanning all VMs in subscription, then do not set variable in line below
#Example - $targetVM = "VMname"
$targetVM = $null
Write-Host "###targetVM = ", $targetVM


#EDIT - Input values to retrieve VM SKUs\capabilities from AZURE REST API
$TenantId = "xxxxxxxxxxxxxxxxxx"
$ClientId = "xxxxxxxxxxxxxxxxxx"
$ClientSecret = "xxxxxxxxxxxxxxxxxx"
$SubscriptionId = "xxxxxxxxxxxxxxxxxx"

#EDIT - Log Analytics workspace id
$workspaceId = "5ccfd947-42f9-4b91-b698-519e7d9ca180"
#----------------------------------------------------------------
#----------------------------------------------------------------
#----------------------------------------------------------------



#Exit script if required variables not set.
if ([string]::IsNullOrEmpty($TenantId) -or [string]::IsNullOrEmpty($ClientId) -or [string]::IsNullOrEmpty($ClientSecret) -or [string]::IsNullOrEmpty($SubscriptionId) -or [string]::IsNullOrEmpty($timeIntervalWindow))
{
    Write-Host "Parameters empty or null. Check script variables at top of script."
    exit
}


# Variables
$VMSKUCache = [System.Collections.ArrayList]@()
$ThrottleResults = [System.Collections.ArrayList]@()



$Resource = "https://management.core.windows.net/"

$RequestAccessTokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/token"

$body = "grant_type=client_credentials&client_id=$ClientId&client_secret=$ClientSecret&resource=$Resource"

Write-Host "### Authenticating to AZURE REST API for retrieving Azure SKUs"
$Token = Invoke-RestMethod -Method Post -Uri $RequestAccessTokenUri -Body $body -ContentType 'application/x-www-form-urlencoded'
Write-Host "###   Authenticated to AZURE REST API for retrieving Azure SKUs"

# Get Azure Microsoft.Compute SKUs
$ApiUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Compute/skus?api-version=2017-09-01"
$Headers = @{}
$Headers.Add("Authorization","$($Token.token_type) "+ " " + "$($Token.access_token)")

Write-Host "### Get VM Sizes and IOPS limits from Azure REST API"
$SKUDefinitions = Invoke-RestMethod -Method Get -Uri $ApiUri -Headers $Headers
Write-Host "###   Retrieved VM Sizes and IOPS limits from Azure REST API"







$Query = @'
Perf | where ObjectName == "PhysicalDisk" and (CounterName == "Disk Transfers/sec" or CounterName == "Disk Bytes/sec" ) 
'@

if ($targetVM)
{
   $Query += " and Computer == `"" + $targetVM + "`""
}

if ($historyWindow)
{
    $Query += " and TimeGenerated >= now(" + $historyWindow + ")"
}

$Query += @'
 | summarize ["min"] = min(CounterValue), 
    ["avg"] = avg(CounterValue), 
    ["percentile85"] = percentile(CounterValue, 85), 
    ["max"] = max(CounterValue) 
        by Computer, _ResourceId, CounterName, InstanceName, bin(TimeGenerated, XX)
| sort by InstanceName, Computer, _ResourceId, CounterName, TimeGenerated
'@

$Query = $Query.Replace("XX", $timeIntervalWindow)
Write-Debug $Query




Write-Host "### Getting data from Log Analytics"
$Counters = Invoke-AzOperationalInsightsQuery -workspaceId $workspaceId -Query $Query
$temp = $Counters.Results | measure
Write-Host "###   Retrieved data from Log Analytics, Counter Records = ", $temp.Count


Write-Host "### Getting list of VMs"
if ($targetVM)
{
    $VirtualMachines = Get-AzVM -Name $targetVM
}
else
{ 
    $VirtualMachines = Get-AzVM
}
Write-Host "###   Retrieved list of VMs, VM Count = ", $VirtualMachines.Count

Write-Host "### Getting list of Managed Disks"
$ManagedDisks = Get-AzDisk
if ($targetVM)
{
    $ManagedDisks = $ManagedDisks | Where {$_.ManagedBy -eq $VirtualMachines[0].Id}

}
Write-Host "###   Retrieved list of Managed Disks, Managed Disk Count = ", $ManagedDisks.Count


Write-Host "### Checking for throttling"
foreach($counter in $Counters.Results)
{


    $vm = $VirtualMachines | Where-Object Id -EQ $counter._ResourceId
    #VM level throttling
    #$vm[0].HardwareProfile.VmSize


    if($counter.InstanceName -eq "_Total")
    {
        #TODO - Compare counter to VM max IOPS

        $VMsku = $VMSKUCache.Where({ $_.resourceType -eq "virtualMachines" -and $_.locations -eq $vm.Location -and $_.name -eq $vm.HardwareProfile.VmSize} )
        if ($VMsku[0] -eq $null)
        {
            
            $VMsku = $SKUDefinitions.value | Where { $_.resourceType -eq "virtualMachines" -and $_.locations -eq $vm.Location -and $_.name -eq $vm.HardwareProfile.VmSize}
            $VMSKUCache += $VMsku
        }
         

        $VMIops = $VMsku.capabilities.Where({$_.name -eq "UncachedDiskIOPS" })
        $temp = [int]$VMIOPs[0].value
        $vm | Add-Member -NotePropertyName VMIops -NotePropertyValue $temp -Force

        $VMDiskBytes = $VMsku.capabilities.Where({$_.name -eq "UncachedDiskBytesPerSecond" })
        $temp = [int]$VMDiskBytes[0].value
        $vm | Add-Member -NotePropertyName VMDiskBytes -NotePropertyValue $temp -Force

        IsCounterThrottled -VM $vm -Counter $counter -Disk $null




    }
    else
    {
        $splitDiskLun = $counter.InstanceName.Split(' ')
        $diskLun = [int]$splitDiskLun[0]
        if($diskLun -eq 0)
        {
            #OS disk
            $disk = $ManagedDisks| Where-Object Name -eq $vm[0].StorageProfile.OsDisk.Name

            $object = IsCounterThrottled -VM $vm -Counter $counter -Disk $disk -DiskType "OS Disk"
            if ($object -ne $null)
            {
                $ThrottleResults += $object
            }
            
        }
        elseif ($diskLun -ge 2)
        {
            #DataDisks
            foreach ($dataDisk in $vm[0].StorageProfile.DataDisks)
            {

                #Lun 0 - OS disk -OS disk always is on Lun 0
                #Lun 1 - Temp disk
                #Lun 2 - First data disk  
                if ($dataDisk.Lun -eq ($diskLun - 2))
                {
                    $disk = $ManagedDisks| Where-Object Name -eq $dataDisk.Name
                    
                    IsCounterThrottled -VM $vm -Counter $counter -Disk $disk -DiskType "Data Disk"

                    break
                }

            }
        }
        
    }


    
}

if ($ThrottleResults.Count -eq 0)
{
    Write-Host "###No Throttling found in retrieved counters"
}

$timeIntervalWindow = $null
$historyWindow = $null
$targetVM = $null


Return $ThrottleResults

