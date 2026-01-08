# 1. Define the Mapping: "TagValue" = @("Group ID 1", "Group ID 2")
$teamMapping = @{
    "BookingGang"   = @("58cb2b85-f4b1-464e-bbcb-9d67d3f377f1")
    "Bizarres"   = @("084364c0-8dfb-406d-9a6c-850c846386ab")
    "Bizarres,BookingGang"   = @("084364c0-8dfb-406d-9a6c-850c846386ab", "58cb2b85-f4b1-464e-bbcb-9d67d3f377f1")
    "Finance-StaticOps"  = @("cb671f80-8b3b-4d64-b990-2d274eb1864a")
    "Inventory/Digital Ops Team"    = @("0d9ff9d8-2be3-4277-aeb8-7b3821b9aa7d")
}

$tagName = "OwnedByTeam"
$roleName = "Contributor"

foreach ($entry in $teamMapping.GetEnumerator()) {
    $tagValue = $entry.Key
    $groupIds = $entry.Value # This is now an array

    Write-Host "`n--- Processing Tag: $tagValue ---" -ForegroundColor Cyan

    # 2. Find all Resource Groups with the specific Tag Value
    $rgs = Get-AzResourceGroup | Where-Object { $_.Tags[$tagName] -eq $tagValue }

    if ($null -eq $rgs -or $rgs.Count -eq 0) {
        Write-Host "No Resource Groups found with tag '$tagValue'" -ForegroundColor Gray
        continue
    }

    # 3. Loop through each Group ID assigned to this Tag
    foreach ($groupId in $groupIds) {
        
        # 4. Apply the Role Assignment to each found Resource Group
        foreach ($rg in $rgs) {
            $existingAssignment = Get-AzRoleAssignment -ObjectId $groupId `
                                                       -RoleDefinitionName $roleName `
                                                       -ResourceGroupName $rg.ResourceGroupName `
                                                       -ErrorAction SilentlyContinue

            if ($null -eq $existingAssignment) {
                Write-Host "Action: Assigning $roleName to Group $groupId on $($rg.ResourceGroupName)" -ForegroundColor Green
                New-AzRoleAssignment -ObjectId $groupId `
                                     -RoleDefinitionName $roleName `
                                     -ResourceGroupName $rg.ResourceGroupName
            } else {
                Write-Host "Skip: Group $groupId already has access to $($rg.ResourceGroupName)" -ForegroundColor Gray
            }
        }
    }
}