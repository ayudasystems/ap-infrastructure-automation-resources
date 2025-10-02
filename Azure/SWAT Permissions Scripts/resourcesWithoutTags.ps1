# Set the filenames. They will be saved to your Cloud Shell's home directory.
$ResourcesFileName = 'Azure_Resources_Missing_OwnedByTeam.csv'
$ResourceGroupsFileName = 'Azure_RGs_Missing_OwnedByTeam.csv'

$TagName = 'OwnedByTeam'

# -----------------------------------------------
## 1. Get Resources (Excluding Resource Groups) 
# -----------------------------------------------

# Get all resources, then exclude Resource Groups from this set
$AllResources = Get-AzResource | Where-Object { 
    $_.ResourceType -ne 'Microsoft.Resources/resourceGroups' 
}

# Filter the resources for the missing tag
$ResourcesWithoutTag = $AllResources | Where-Object { 
    $_.Tags -eq $null -or $_.Tags.Keys -notcontains $TagName 
}

# Select properties for the first file
$ResourceResults = $ResourcesWithoutTag | Select-Object @{
    Name = 'Name'
    Expression = {$_.Name}
}, @{
    Name = 'ResourceType'
    Expression = {$_.ResourceType}
}, @{
    Name = 'ResourceGroupName'
    Expression = {$_.ResourceGroupName}
}, @{
    Name = 'Location'
    Expression = {$_.Location}
}

# Export to the first CSV file
$ResourceResults | Export-Csv -Path $ResourcesFileName -NoTypeInformation

# -----------------------------------------------
## 2. Get Resource Groups 
# -----------------------------------------------

$ResourceGroupsWithoutTag = Get-AzResourceGroup | Where-Object { 
    $_.Tags -eq $null -or $_.Tags.Keys -notcontains $TagName 
}

# Select properties for the second file (Note: ResourceGroupName is used for 'Name')
$ResourceGroupResults = $ResourceGroupsWithoutTag | Select-Object @{
    Name = 'Name'
    Expression = {$_.ResourceGroupName} # Use RG name for the 'Name' column
}, @{
    Name = 'ResourceType'
    Expression = "Microsoft.Resources/resourceGroups"
}, @{
    Name = 'ResourceGroupName'
    Expression = {$_.ResourceGroupName} # Use RG name again for consistency
}, @{
    Name = 'Location'
    Expression = {$_.Location}
}

# Export to the second CSV file
$ResourceGroupResults | Export-Csv -Path $ResourceGroupsFileName -NoTypeInformation

Write-Host "✅ Export Complete! Two files have been saved to your Cloud Shell home directory:"
Write-Host "1. $ResourcesFileName"
Write-Host "2. $ResourceGroupsFileName"