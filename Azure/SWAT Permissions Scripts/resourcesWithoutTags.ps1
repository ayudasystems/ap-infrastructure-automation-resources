$TagName = 'OwnedByTeam'

$subscriptions = Get-AzSubscription

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id

    # -----------------------------------------------
    ## 1. Get Resources (Excluding Resource Groups)
    # -----------------------------------------------
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
    $ResourcesFileName = "Azure_Resources_Missing_OwnedByTeam_$($sub.Name).csv"
    $ResourceResults | Export-Csv -Path $ResourcesFileName -NoTypeInformation

    # -----------------------------------------------
    ## 2. Get Resource Groups
    # -----------------------------------------------
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
    $ResourceGroupsFileName = "Azure_RGs_Missing_OwnedByTeam_$($sub.Name).csv"
    $ResourceGroupResults | Export-Csv -Path $ResourceGroupsFileName -NoTypeInformation

    Write-Host "Exported: $ResourcesFileName"
    Write-Host "Exported: $ResourceGroupsFileName"
}

Write-Host "✅ Export Complete! Two files per subscription have been saved to your Cloud Shell home directory."
