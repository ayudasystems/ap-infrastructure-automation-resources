# Get all subscriptions
$subscriptions = Get-AzSubscription

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id

    $resources = Get-AzResource

    $taggedResources = $resources | Where-Object { $_.Tags } | ForEach-Object {
        foreach ($tag in $_.Tags.GetEnumerator()) {
            [PSCustomObject]@{
                SubscriptionName = $sub.Name
                SubscriptionId   = $sub.Id
                TagKey           = $tag.Key
                TagValue         = $tag.Value
                ResourceName     = $_.Name
                ResourceId       = $_.ResourceId
                ResourceType     = $_.ResourceType
                ResourceGroup    = $_.ResourceGroupName
                Location         = $_.Location
            }
        }
    }

    $csvFile = "Azure_Resources_ByTags_$($sub.Name).csv"
    $taggedResources | Export-Csv -Path $csvFile -NoTypeInformation
    Write-Host "Exported: $csvFile"
}

Write-Host "✅ Export Complete! One file per subscription has been saved to your Cloud Shell home directory."
