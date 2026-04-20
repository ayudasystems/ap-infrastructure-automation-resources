$TagName = 'OwnedByTeam'
$subscriptions = Get-AzSubscription

$AllResourceResults = @()
$AllResourceGroupResults = @()

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id

    # Resources (excluding resource groups)
    $AllResources = Get-AzResource | Where-Object {
        $_.ResourceType -ne 'Microsoft.Resources/resourceGroups'
    }
    $ResourcesWithoutTag = $AllResources | Where-Object {
        $_.Tags -eq $null -or $_.Tags.Keys -notcontains $TagName
    }
    $ResourceResults = $ResourcesWithoutTag | Select-Object @{
        Name = 'SubscriptionName'
        Expression = { $sub.Name }
    }, @{
        Name = 'SubscriptionId'
        Expression = { $sub.Id }
    }, @{
        Name = 'Name'
        Expression = { $_.Name }
    }, @{
        Name = 'ResourceType'
        Expression = { $_.ResourceType }
    }, @{
        Name = 'ResourceGroupName'
        Expression = { $_.ResourceGroupName }
    }, @{
        Name = 'Location'
        Expression = { $_.Location }
    }
    $AllResourceResults += $ResourceResults

    # Resource Groups
    $ResourceGroupsWithoutTag = Get-AzResourceGroup | Where-Object {
        $_.Tags -eq $null -or $_.Tags.Keys -notcontains $TagName
    }
    $ResourceGroupResults = $ResourceGroupsWithoutTag | Select-Object @{
        Name = 'SubscriptionName'
        Expression = { $sub.Name }
    }, @{
        Name = 'SubscriptionId'
        Expression = { $sub.Id }
    }, @{
        Name = 'Name'
        Expression = { $_.ResourceGroupName }
    }, @{
        Name = 'ResourceType'
        Expression = "Microsoft.Resources/resourceGroups"
    }, @{
        Name = 'ResourceGroupName'
        Expression = { $_.ResourceGroupName }
    }, @{
        Name = 'Location'
        Expression = { $_.Location }
    }
    $AllResourceGroupResults += $ResourceGroupResults
}

$ResourcesFileName = "Azure_Resources_Missing_OwnedByTeam_AllSubscriptions.csv"
$ResourceGroupsFileName = "Azure_RGs_Missing_OwnedByTeam_AllSubscriptions.csv"

$AllResourceResults | Export-Csv -Path $ResourcesFileName -NoTypeInformation
$AllResourceGroupResults | Export-Csv -Path $ResourceGroupsFileName -NoTypeInformation

Write-Host "✅ Export Complete! Two files have been saved to your Cloud Shell home directory."
