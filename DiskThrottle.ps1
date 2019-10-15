#-------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------
# Replace variables below from your Azure subscription


# Replace with your Log Analytics Workspace ID
$WorkspaceId = "xxxxxxx" 

# Replace with your Primary Key from the Log Analytics Workspace pane
$SharedKey = "xxxxxxx"

# Specify the name of the Azure Custom Log
$LogType = "DiskThrottleConfig"

# Input values to retrieve VM SKUs\capabilities from AZURE REST API 
# Use Instructions at https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal
# Create an Azure AD App, assign the app a Log Analytics Contributor role, and create a new application secret. Then collect the values below.
$TenantId = "xxxxxxx"
$SubscriptionId = "xxxxxxx"
$ClientId = "xxxxxxx"
$ClientSecret = "xxxxxxx"


#-------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------


# You can use an optional field to specify the timestamp from the data. If the time field is not specified, Azure Monitor assumes the time is the message ingestion time
$TimeStampField = Get-date
$TimeStampField = $TimeStampField.toUniversalTime()
$TimeStampField = $TimeStampField.ToString("yyyy-MM-ddTHH:mm:ss.ffffZ")

$VerboseString = $null


# Create the function to create the authorization signature
Function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}

# Create the function to create and post the requestd
Function Post-VMDiskDataToLogAnalytics($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    $VerboseString = "Post-VMDiskDataToLogAnalytics response: " + $response
    Write-Host $VerboseString

    return $response.StatusCode

}

# Get Azure resources capabilities from REST API
Function Get-AzureSKUData($TenantId, $SubscriptionId, $ClientId, $ClientSecret)
{
    $SKUDefinitions = $null
    
    $Resource = "https://management.core.windows.net/"
    $RequestAccessTokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    $body = "grant_type=client_credentials&client_id=$ClientId&client_secret=$ClientSecret&resource=$Resource"

    Write-Host "Authenticating to AZURE REST API - Needed for retrieving Azure SKUs"
    $Token = Invoke-RestMethod -Method Post -Uri $RequestAccessTokenUri -Body $body -ContentType 'application/x-www-form-urlencoded'
    Write-Host "Authenticated to AZURE REST API - Needed for retrieving Azure SKUs"

    # Get Azure Microsoft.Compute SKUs
    $ApiUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Compute/skus?api-version=2017-09-01"
    $Headers = @{}
    $Headers.Add("Authorization","$($Token.token_type) "+ " " + "$($Token.access_token)")

    Write-Host "Get VM Sizes and IOPS limits from Azure REST API"
    $SKUDefinitions = Invoke-RestMethod -Method Get -Uri $ApiUri -Headers $Headers
    Write-Host "Retrieved VM Sizes and IOPS limits from Azure REST API"

    $VerboseString = "Get-AzureSKUData Count: " + $SKUDefinitions.value.Count
    Write-Host $VerboseString

    return $SKUDefinitions

}

# Get VM and disk configuration
Function Get-DiskConfigurations($SKUDefinitions, $VMs, $Disks)
{
    $VMskuCache = [System.Collections.ArrayList]@()
    $DiskConfigurations = [System.Collections.ArrayList]@()
    $diskObj = $null

    $SKUDefinitions = $SKUDefinitions.value | Where { $_.resourceType -eq "virtualMachines" }

    foreach($vm in $VMs)
    {


        #TODO - Add limits for VM
        $VMsku = $VMSKUCache | Where { $_.resourceType -eq "virtualMachines" -and $_.locations -eq $vm.Location -and $_.name -eq $vm.HardwareProfile.VmSize}
        if ($VMsku -eq $null)
        {
            $VMsku = $SKUDefinitions | Where { $_.resourceType -eq "virtualMachines" -and $_.locations -eq $vm.Location -and $_.name -eq $vm.HardwareProfile.VmSize}
            $VMSKUCache += $VMsku
        }

        $VMIops = $VMsku.capabilities.Where({$_.name -eq "UncachedDiskIOPS" })
        $temp = [int]$VMIOPs[0].value

        $VMDiskBytes = $VMsku.capabilities.Where({$_.name -eq "UncachedDiskBytesPerSecond" })
        $temp = [int]$VMDiskBytes[0].value


        $osDisk = $Disks | Where {$_.Id -eq $vm.StorageProfile.OsDisk.ManagedDisk.Id}

        $diskObj = [PSCustomObject]@{
                    VMName = $vm.Name.ToLower()
                    VMResourceId = $vm.Id.ToLower()
                    VMType = $vm.HardwareProfile.VmSize
                    VMLocation = $vm.Location
                    DiskType = "OS"
                    DiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id.ToLower()
                    DiskLun = "0"
                    DiskIOPSLimit = $osDisk[0].DiskIOPSReadWrite
                    DiskBytesLimit = (([int]$osDisk[0].DiskMBpsReadWrite) * 1024 * 1024)
                    VMIOPSLimit = [int]$VMIOPs[0].value
                    VMBytesLimit = [int]$VMDiskBytes[0].value
                }
    
        $DiskConfigurations += $diskObj

        foreach($storageDisk in $vm.StorageProfile.DataDisks)
        {
            $dataDisk = $Disks | Where {$_.Id -eq $storageDisk.ManagedDisk.Id}

            $diskObj = [PSCustomObject]@{
                VMName = $vm.Name.ToLower()
                VMResourceId = $vm.Id.ToLower()
                VMType = $vm.HardwareProfile.VmSize
                VMLocation = $vm.Location
                DiskType = "Data"
                DiskId = $storageDisk.ManagedDisk.Id.ToLower()
                DiskLun = [int]$storageDisk.Lun + 2
                DiskIOPSLimit = $dataDisk[0].DiskIOPSReadWrite
                DiskBytesLimit = (([int]$dataDisk[0].DiskMBpsReadWrite) * 1024 * 1024)
                VMIOPSLimit = [int]$VMIOPs[0].value
                VMBytesLimit = [int]$VMDiskBytes[0].value
            }

            $DiskConfigurations += $diskObj

        }

    }
    
    $VerboseString = "`$DiskConfigurations Count : " + $DiskConfigurations.Count
    Write-Host $VerboseString

    return $DiskConfigurations

}


# Get VM and Disk data
$VMs = get-AzVM
$VerboseString = "VM Count : " + $VMs.Count
Write-Host $VerboseString

$Disks = Get-AzDisk
$VerboseString = "Disk Count : " + $Disks.Count
Write-Host $VerboseString

# Get Azure SKU data
$SKUDefinitions = Get-AzureSKUData -TenantId $TenantId -SubscriptionId $SubscriptionId -ClientId $ClientId -ClientSecret $ClientSecret


# Merge VM and disk data with IOPS and MBytes from Azure capabilities SKU
$DiskConfigurations = Get-DiskConfigurations -SKUDefinitions $SKUDefinitions -VMs $VMs -Disks $Disks
$json =  $DiskConfigurations | ConvertTo-Json


# Submit the data to the API endpoint
Post-VMDiskDataToLogAnalytics -customerId $WorkspaceId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($json)) -logType $logType  

# Make sure DiskData was uploaded to Log Analytics
$CheckForUploadResults = $null
while($CheckForUploadResults.Count -lt $DiskConfigurations.Count)
{
    Start-Sleep -Seconds 10
    
    $CheckForUploadQuery = @'
    DiskThrottleConfig_CL
    | where TimeGenerated >= todatetime('xxxx')
'@

    $CheckForUploadQuery = $CheckForUploadQuery.Replace("xxxx", $TimeStampField)

    $CheckForUploadResults = Invoke-AzOperationalInsightsQuery -workspaceId $workspaceId -Query $CheckForUploadQuery
    $CheckForUploadResults = $CheckForUploadResults.Results | measure

    $VerboseString = "Uploaded " + $DiskConfigurations.Count + " entries, Found " + $CheckForUploadResults.Count + " uploaded results" 
    Write-Host $VerboseString

}


Write-Host "-----------------------------------------"
Write-Host "Check for throttling events" 


# Run Disk and VM throttling queries
$DiskThrottleQuery = @'
DiskThrottleConfig_CL
| where TimeGenerated >= todatetime('xxxx')
| project VMResourceId_s , DiskId_s , DiskIOPSLimit_d , DiskBytesLimit_d, DiskLun=tostring(toint(DiskLun_d)), DiskType_s, VMIOPSLimit_d , VMBytesLimit_d 
| join kind= inner (
    Perf 
    | where ObjectName == "PhysicalDisk" and (CounterName == "Disk Transfers/sec" or CounterName == "Disk Bytes/sec") 
    | project TimeGenerated, Computer , _ResourceId , CounterName , InstanceName , CounterValue , Lun=iff(InstanceName == "_Total", "", strcat_array(split(InstanceName, " ", 0), ""))
) on $left.VMResourceId_s == $right._ResourceId and $left.DiskLun == $right.Lun
| where (CounterName == "Disk Transfers/sec" and CounterValue >=  DiskIOPSLimit_d) or (CounterName == "Disk Bytes/sec" and CounterValue >=  DiskBytesLimit_d)
| project TimeGenerated , VMResourceId_s, Computer, DiskId_s, CounterName, CounterValue, DiskIOPSLimit_d, DiskBytesLimit_d , DiskType_s, Lun
'@
$DiskThrottleQuery = $DiskThrottleQuery.Replace("xxxx", $TimeStampField)

$DiskThrottleResults = Invoke-AzOperationalInsightsQuery -workspaceId $workspaceId -Query $DiskThrottleQuery
$VerboseString = $DiskThrottleResults.Results | Measure | Select -Property Count
Write-Host "Found ", $VerboseString, " disk throttling events"


$VMThrottleQuery = @'
DiskThrottleConfig_CL
| where TimeGenerated >= todatetime('xxxx')
| project VMResourceId_s , VMIOPSLimit_d , VMBytesLimit_d 
| join kind= inner (
    Perf 
    | where ObjectName == "PhysicalDisk" and (CounterName == "Disk Transfers/sec" or CounterName == "Disk Bytes/sec") and InstanceName == "_Total" 
    | project TimeGenerated, Computer , _ResourceId , CounterName , InstanceName , CounterValue
) on $left.VMResourceId_s == $right._ResourceId
| where (CounterName == "Disk Transfers/sec" and CounterValue >=  VMIOPSLimit_d) or (CounterName == "Disk Bytes/sec" and CounterValue >=  VMBytesLimit_d)
| project TimeGenerated , VMResourceId_s, Computer, CounterName, CounterValue, VMIOPSLimit_d, VMBytesLimit_d
'@
$VMThrottleQuery = $VMThrottleQuery.Replace("xxxx", $TimeStampField)

$VMThrottleResults = Invoke-AzOperationalInsightsQuery -workspaceId $workspaceId -Query $VMThrottleQuery
$VerboseString = $VMThrottleResults.Results | Measure | Select -Property Count
Write-Host "Found ", $VerboseString, " VM throttling events"


Write-Host "-----------------------------------------"
Write-Host "-----------------------------------------"
Write-Host "-----------------------------------------"
Write-Host "To export results, run the following " 
Write-Host "Export-Csv -Path C:\temp\DiskThrottle.csv `$DiskThrottleResults"
Write-Host "OR"
Write-Host "Export-Csv -Path C:\temp\VMThrottle.csv `$VMThrottleResults"
