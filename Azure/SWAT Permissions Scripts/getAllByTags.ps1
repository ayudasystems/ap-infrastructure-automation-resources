# TODO
# - Group by 'OwnedByTeam'
# - Get for all subscriptions


# Connect if not connected already
# Connect-AzAccount

# Get all resources in the subscription
$resources = Get-AzResource

# Group by tags
$grouped = $resources | Where-Object { $_.Tags } | ForEach-Object {
    foreach ($tag in $_.Tags.GetEnumerator()) {
        [PSCustomObject]@{
            TagKey   = $tag.Key
            TagValue = $tag.Value
            Resource = $_.ResourceId
        }
    }
} | Group-Object TagKey, TagValue

# Print grouped resources
foreach ($group in $grouped) {
    Write-Output "`nTag: $($group.Name)"
    $group.Group | ForEach-Object { Write-Output "  - $($_.Resource)" }
}


OWNED BY TEAM