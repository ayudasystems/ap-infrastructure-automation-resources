#Requires -Version 7.0
<#
.SYNOPSIS
    Inventories Azure API Management services and rotates subscription keys after explicit approval.
.DESCRIPTION
    Signs in interactively with Az.Accounts, lists the account's Azure subscriptions and lets you pick one
    (then asks whether to pick another or finish). For each APIM service (one at a time), inventories metadata, checks user Notes (empty or
    not only), asks for approval and regenerates the primary and/or secondary subscription keys through
    the Regenerate Primary/Secondary Key REST APIs (api-version 2024-05-01, Invoke-AzRestMethod only).
    Named values, identity-provider, OpenID Connect and Auth0 secrets are never modified. No key value and
    no Note content is ever logged, reported or kept. Every approval and rejection is audited in
    rotation-log.csv. There is no unattended mode.
    Dot-source safe: the main flow runs only when the script is invoked, not when dot-sourced.
.PARAMETER RotateKey
    Primary, Secondary or All. Required for a run.
.PARAMETER OutputRoot
    Folder that receives a timestamped report folder (default: reports next to this script).
.PARAMETER WhatIf
    Simulates key regeneration without changing keys. Authentication, inventory, approval prompts and reports still run.
.EXAMPLE
    .\Invoke-ApimKeyRotation.ps1 -RotateKey Primary -WhatIf
.EXAMPLE
    .\Invoke-ApimKeyRotation.ps1 -RotateKey All -OutputRoot C:\Reports
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Primary', 'Secondary', 'All')]
    [string]$RotateKey,

    [string]$OutputRoot = (Join-Path $PSScriptRoot 'reports')
)

$script:ApimApiVersion = '2024-05-01'
$script:ArmApiVersion = '2022-12-01'
$script:ArmBase = 'https://management.azure.com'
$script:MaxAttempts = 5
$script:RotationLogPath = $null
$script:LogColumns = @('Service', 'Subscription', 'KeyRotated', 'Owner', 'Timestamp', 'SignedInIdentity', 'Result',
    'AzureSubscription', 'EventType', 'Decision', 'Scope', 'Outcome')
$script:AllAccessWarning = 'All-access subscription enables access to every API in this API Management instance and should only be used by authorized users. Never use it for routine API access or embed the all-access key in client apps.'

# ---------------------------------------------------------------- helpers

function Get-UtcTimestamp {
    [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-SignedInIdentity {
    try {
        $id = (Get-AzContext).Account.Id
        if ($id) { return [string]$id }
    }
    catch { $null = $_ }
    return 'unknown'
}

function ConvertTo-SafeResult {
    # Results and outcomes are free text that could echo a secret: keep only a known vocabulary.
    param([string]$Text)
    $vocabulary = '^(failed \(outcome unknown\)|failed \(HTTP \d{3}\)|failed|rotated|simulated|' +
        'skipped \(not active\)|skipped \(declined\)|skipped \(service rejected\)|skipped|' +
        'not rotated \(master not confirmed\)|not rotated|rejected|approved|' +
        'not executed \(rejected\)|pending \(execution follows\)|n/a)'
    if ($Text -match $vocabulary) { return $Matches[1] }
    return 'redacted'
}

function Get-ApimPath {
    param([object]$Service, [string]$Resource)
    "$($Service.Id)/${Resource}?api-version=$($script:ApimApiVersion)"
}

# ---------------------------------------------------------------- REST wrapper

function Get-RetryDelaySeconds {
    param([object]$Response, [int]$Attempt)
    $backoff = [Math]::Min([Math]::Pow(2, $Attempt), 30)
    $value = $null
    try {
        $headers = $Response.Headers
        if ($headers) {
            $value = $headers['Retry-After']
            if ($null -eq $value -and $headers.RetryAfter) { $value = $headers.RetryAfter.Delta.TotalSeconds }
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { $value = @($value)[0] }
        }
    }
    catch { $value = $null }
    $seconds = 0.0
    if ($null -ne $value -and [double]::TryParse([string]$value, [ref]$seconds) -and $seconds -gt 0) {
        return [Math]::Max($seconds, 1)
    }
    return $backoff
}

function Send-ApimRequest {
    # One logical request with retry on 429 / 5xx. A request that ends with no response is
    # never retried when it is not a GET (the change may have been applied).
    param([string]$Method, [string]$Path, [string]$Payload)
    for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
        $response = $null
        $failed = $false
        try {
            if ($Payload) { $response = Invoke-AzRestMethod -Method $Method -Path $Path -Payload $Payload }
            else { $response = Invoke-AzRestMethod -Method $Method -Path $Path }
        }
        catch { $failed = $true }

        if ($failed -or $null -eq $response) {
            if ($Method -ne 'GET') {
                throw "$Method $Path ended with no response: outcome unknown, not retried; verify the state manually."
            }
            if ($attempt -lt $script:MaxAttempts) {
                Start-Sleep -Seconds ([Math]::Min([Math]::Pow(2, $attempt), 30))
                continue
            }
            throw "GET $Path failed: no response after $($script:MaxAttempts) attempts."
        }

        $code = [int]$response.StatusCode
        if ($code -ge 200 -and $code -lt 300) { return $response }
        if ($code -eq 429 -or $code -ge 500) {
            if ($attempt -lt $script:MaxAttempts) {
                Start-Sleep -Seconds (Get-RetryDelaySeconds -Response $response -Attempt $attempt)
                continue
            }
            throw "HTTP $code $Method $Path after $($script:MaxAttempts) attempts."
        }
        # Body deliberately not echoed: error bodies could carry secrets.
        throw "HTTP $code $Method $Path"
    }
}

function Invoke-ApimRequest {
    [CmdletBinding()]
    param(
        [string]$Method = 'GET',
        [string]$Path,
        [object]$Body
    )
    $Method = $Method.ToUpperInvariant()
    if ($Path -match '(?i)/(listSecrets|listValue|token)(\?|/|$)') {
        throw "Request forbidden by policy (secret-returning action): $Method $Path"
    }
    if ($Path -notmatch 'api-version=') {
        $sep = if ($Path.Contains('?')) { '&' } else { '?' }
        $Path = "$Path${sep}api-version=$($script:ApimApiVersion)"
    }
    $payload = $null
    if ($null -ne $Body) { $payload = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress } }

    $next = $Path
    while ($next) {
        $response = Send-ApimRequest -Method $Method -Path $next -Payload $payload
        $next = $null
        if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { continue }
        $parsed = $response.Content | ConvertFrom-Json -Depth 20
        if ($null -ne $parsed -and $parsed.PSObject.Properties['value']) {
            foreach ($item in @($parsed.value)) { $item }
            $link = $parsed.PSObject.Properties['nextLink']
            if ($link -and $link.Value) {
                $next = ([string]$link.Value) -replace '^https://management\.azure\.com', ''
            }
        }
        else {
            $parsed
        }
    }
}

# ---------------------------------------------------------------- discovery and inventory

function Get-AzureSubscriptionList {
    [CmdletBinding()]
    param()
    @(Invoke-ApimRequest -Method GET -Path "/subscriptions?api-version=$($script:ArmApiVersion)") |
        Where-Object { $_.subscriptionId }
}

function Select-AzureSubscription {
    [CmdletBinding()]
    param([object[]]$Subscriptions)
    Write-Host ''
    Write-Host 'Available Azure subscriptions:'
    for ($n = 0; $n -lt $Subscriptions.Count; $n++) {
        $s = $Subscriptions[$n]
        Write-Host ("  [{0}] {1} ({2}) - {3}" -f ($n + 1), $s.displayName, $s.subscriptionId, $s.state)
    }
    while ($true) {
        $answer = ([string](Read-Host -Prompt "Select a subscription (1-$($Subscriptions.Count)) or Q to finish")).Trim()
        if ($answer -match '^(q|quit)$') { return $null }
        $index = 0
        if ([int]::TryParse($answer, [ref]$index) -and $index -ge 1 -and $index -le $Subscriptions.Count) {
            return $Subscriptions[$index - 1]
        }
        Write-Host 'Invalid selection.'
    }
}

function Get-ApimServices {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SubscriptionId)
    $azSubscriptions = @(Get-AzureSubscriptionList)
    foreach ($azSub in $azSubscriptions) {
        if ($azSub.subscriptionId -ne $SubscriptionId) { continue }
        try {
            $found = @(Invoke-ApimRequest -Method GET -Path "/subscriptions/$($azSub.subscriptionId)/providers/Microsoft.ApiManagement/service?api-version=$($script:ApimApiVersion)")
        }
        catch {
            Write-Warning "Azure subscription $($azSub.subscriptionId): APIM discovery failed ($($_.Exception.Message)); skipped."
            continue
        }
        foreach ($svc in $found) {
            if (-not $svc.name -or -not $svc.id) { continue }
            $rg = if ($svc.id -match '/resourceGroups/([^/]+)/') { $Matches[1] } else { '' }
            [pscustomobject]@{
                Name                  = [string]$svc.name
                AzureSubscriptionId   = [string]$azSub.subscriptionId
                AzureSubscriptionName = [string]$azSub.displayName
                ResourceGroup         = $rg
                Tier                  = [string]$svc.sku.name
                Id                    = [string]$svc.id
            }
        }
    }
}

function Test-UserNotes {
    [CmdletBinding()]
    param([object]$Service)
    $users = @(Invoke-ApimRequest -Method GET -Path (Get-ApimPath $Service 'users'))
    $reported = [System.Collections.Generic.List[object]]::new()
    $checked = 0
    foreach ($user in $users) {
        $props = $user.properties
        if (-not $props) { continue }
        $checked++
        # Only the yes/no result is kept; the content is dropped immediately.
        $hasNote = -not [string]::IsNullOrWhiteSpace([string]$props.note)
        if ($props.PSObject.Properties['note']) { $props.note = $null }
        if (-not $hasNote) { continue }
        $groups = @()
        try {
            $groups = @(Invoke-ApimRequest -Method GET -Path (Get-ApimPath $Service "users/$($user.name)/groups") | ForEach-Object { [string]$_.name })
        }
        catch { Write-Warning "Groups of user $($user.name) could not be read." }
        $reported.Add([pscustomobject]@{
                FullName = (("$($props.firstName) $($props.lastName)").Trim())
                Email    = [string]$props.email
                State    = [string]$props.state
                Identity = (@($props.identities | ForEach-Object { "$($_.provider):$($_.id)" }) -join '; ')
                Groups   = $groups
            })
    }
    [pscustomobject]@{
        UsersChecked      = $checked
        NonEmptyNoteCount = $reported.Count
        NonEmptyNoteUsers = @($reported)
    }
}

function Get-ApimInventory {
    [CmdletBinding()]
    param([object]$Service)

    function Get-List([string]$Resource) { @(Invoke-ApimRequest -Method GET -Path (Get-ApimPath $Service $Resource)) }

    # Allow-list projection: only the listed fields are ever copied; secrets cannot pass through.
    $subscriptions = Get-List 'subscriptions' | ForEach-Object {
        [pscustomobject]@{ Sid = [string]$_.name; DisplayName = [string]$_.properties.displayName; State = [string]$_.properties.state
            Scope = [string]$_.properties.scope; OwnerId = [string]$_.properties.ownerId }
    }
    $namedValues = Get-List 'namedValues' | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.name; DisplayName = [string]$_.properties.displayName; IsSecret = [bool]$_.properties.secret }
    }
    $backends = Get-List 'backends' | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.name; Url = [string]$_.properties.url; Protocol = [string]$_.properties.protocol }
    }
    $authServers = Get-List 'authorizationServers' | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.name; ClientId = [string]$_.properties.clientId }
    }
    $oidc = Get-List 'openidConnectProviders' | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.name; ClientId = [string]$_.properties.clientId }
    }
    $idps = Get-List 'identityProviders' | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.name; Type = [string]$_.properties.type; ClientId = [string]$_.properties.clientId }
    }
    $signin = Get-List 'portalsettings/signin' | ForEach-Object {
        [pscustomobject]@{ Enabled = [string]$_.properties.enabled }
    }
    $authProviders = Get-List 'authorizationProviders' | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.name; IdentityProvider = [string]$_.properties.identityProvider }
    }
    $loggers = Get-List 'loggers' | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.name; LoggerType = [string]$_.properties.loggerType }
    }
    $products = Get-List 'products' | ForEach-Object {
        $policyCount = 0
        try { $policyCount = @(Invoke-ApimRequest -Method GET -Path (Get-ApimPath $Service "products/$($_.name)/policies")).Count }
        catch { $policyCount = -1 }
        [pscustomobject]@{ Name = [string]$_.name; DisplayName = [string]$_.properties.displayName; State = [string]$_.properties.state; PolicyCount = $policyCount }
    }
    $notes = Test-UserNotes -Service $Service

    [pscustomobject]@{
        Subscriptions          = @($subscriptions)
        NamedValues            = @($namedValues)
        Backends               = @($backends)
        AuthorizationServers   = @($authServers)
        OpenIdConnectProviders = @($oidc)
        IdentityProviders      = @($idps)
        PortalSignin           = @($signin)
        AuthorizationProviders = @($authProviders)
        Loggers                = @($loggers)
        Products               = @($products)
        Notes                  = $notes
    }
}

# ---------------------------------------------------------------- audit log

function Initialize-RotationLog {
    param([string]$LogPath)
    $header = ($script:LogColumns | ForEach-Object { '"' + $_ + '"' }) -join ','
    Set-Content -LiteralPath $LogPath -Value $header -Encoding utf8 -WhatIf:$false -Confirm:$false
}

function Add-RotationLogRow {
    [CmdletBinding()]
    param([hashtable]$Row, [string]$LogPath)
    if (-not $LogPath) { return }
    $folder = Split-Path -Parent $LogPath
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force -WhatIf:$false -Confirm:$false | Out-Null
    }
    $ordered = [ordered]@{}
    foreach ($col in $script:LogColumns) {
        $text = if ($Row.ContainsKey($col) -and $null -ne $Row[$col]) { [string]$Row[$col] } else { '' }
        if ($col -in 'Result', 'Outcome') { $text = ConvertTo-SafeResult $text }
        if ($text -match '^[=+\-@\t\r]') { $text = "'" + $text }   # CSV formula injection guard
        $ordered[$col] = $text
    }
    $line = ([pscustomobject]$ordered | ConvertTo-Csv | Select-Object -Skip 1) -join "`n"
    if (-not (Test-Path -LiteralPath $LogPath) -or (Get-Item -LiteralPath $LogPath).Length -eq 0) {
        Initialize-RotationLog -LogPath $LogPath
    }
    Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8 -WhatIf:$false -Confirm:$false
}

# ---------------------------------------------------------------- approvals

function Register-Decision {
    param([object]$Service, [string]$Scope, [bool]$Approved)
    $row = @{
        Service           = $Service.Name
        Subscription      = 'n/a'
        KeyRotated        = 'n/a'
        Owner             = 'n/a'
        Timestamp         = Get-UtcTimestamp
        SignedInIdentity  = Get-SignedInIdentity
        Result            = if ($Approved) { 'approved' } else { 'rejected' }
        AzureSubscription = "$($Service.AzureSubscriptionName) ($($Service.AzureSubscriptionId))"
        EventType         = 'decision'
        Decision          = if ($Approved) { 'approved' } else { 'rejected' }
        Scope             = $Scope
        Outcome           = if ($Approved) { 'pending (execution follows)' } else { 'not executed (rejected)' }
    }
    Add-RotationLogRow -Row $row -LogPath $script:RotationLogPath
}

function Read-Approval {
    param([string]$Prompt)
    # Always asks, whatever -WhatIf / -Confirm preferences say (no unattended mode).
    $answer = Read-Host -Prompt $Prompt
    return ([string]$answer).Trim() -match '^(y|yes)$'
}

function Confirm-ServiceRotation {
    [CmdletBinding()]
    param([object]$Service, [string]$RotateKey)
    Write-Host ''
    Write-Host "APIM service '$($Service.Name)' (Azure subscription $($Service.AzureSubscriptionName), resource group $($Service.ResourceGroup))"
    Write-Host "Requested rotation scope: $RotateKey key of every active subscription (the all-access subscription is asked separately)."
    $approved = Read-Approval "Rotate $RotateKey key(s) on '$($Service.Name)'? (y/N)"
    Register-Decision -Service $Service -Scope $RotateKey -Approved $approved
    return $approved
}

function Confirm-MasterRotation {
    [CmdletBinding()]
    param([object]$Service, [string]$RotateKey)
    Write-Host ''
    Write-Host "WARNING - built-in all-access subscription (master) of '$($Service.Name)':"
    Write-Host $script:AllAccessWarning
    $approved = Read-Approval "Also rotate the $RotateKey key(s) of the built-in all-access subscription on '$($Service.Name)'? (y/N)"
    Register-Decision -Service $Service -Scope 'Master' -Approved $approved
    return $approved
}

# ---------------------------------------------------------------- rotation

function Invoke-KeyRotation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([object]$Service, [string]$RotateKey)

    $operations = switch ($RotateKey) {
        'Primary' { @('Primary') }
        'Secondary' { @('Secondary') }
        'All' { @('Primary', 'Secondary') }
        default { throw "Invalid RotateKey '$RotateKey'." }
    }
    $identity = Get-SignedInIdentity
    $azSub = "$($Service.AzureSubscriptionName) ($($Service.AzureSubscriptionId))"
    $masterAnswer = $null

    function Add-Action($Result) {
        $row = @{
            Service = $Service.Name; Subscription = $Result.Subscription; KeyRotated = $Result.KeyRotated
            Owner = $Result.Owner; Timestamp = Get-UtcTimestamp; SignedInIdentity = $identity; Result = $Result.Result
            AzureSubscription = $azSub; EventType = 'action'; Decision = 'n/a'
            Scope = if ($Result.KeyRotated -eq 'n/a') { $RotateKey } else { $Result.KeyRotated }; Outcome = $Result.Result
        }
        Add-RotationLogRow -Row $row -LogPath $script:RotationLogPath
    }

    $subscriptions = @(Invoke-ApimRequest -Method GET -Path (Get-ApimPath $Service 'subscriptions'))
    foreach ($sub in $subscriptions) {
        $sid = [string]$sub.name
        $label = "$($sub.properties.displayName) ($sid)"
        $owner = if ($sub.properties.ownerId) { [string]$sub.properties.ownerId } else { 'n/a' }
        $base = @{ Service = $Service.Name; Subscription = $label; Owner = $owner }

        if ([string]$sub.properties.state -ne 'active') {
            $r = [pscustomobject]($base + @{ KeyRotated = 'n/a'; Result = 'skipped (not active)' })
            Add-Action $r; $r; continue
        }
        if ($sid -eq 'master') {
            if ($null -eq $masterAnswer) { $masterAnswer = [bool](Confirm-MasterRotation -Service $Service -RotateKey $RotateKey) }
            if (-not $masterAnswer) {
                $r = [pscustomobject]($base + @{ KeyRotated = 'n/a'; Result = 'not rotated (master not confirmed)' })
                Add-Action $r; $r; continue
            }
        }
        foreach ($op in $operations) {
            $result = $null
            if ($PSCmdlet.ShouldProcess("$($Service.Name)/$sid", "Regenerate $op key")) {
                try {
                    Invoke-ApimRequest -Method POST -Path (Get-ApimPath $Service "subscriptions/$sid/regenerate$($op)Key") | Out-Null
                    $result = 'rotated'
                }
                catch {
                    $msg = $_.Exception.Message
                    $result = if ($msg -match 'outcome unknown') { 'failed (outcome unknown)' }
                    elseif ($msg -match 'HTTP (\d{3})') { "failed (HTTP $($Matches[1]))" }
                    else { 'failed' }
                    Write-Warning "Regenerating the $op key of '$label' on '$($Service.Name)': $result"
                }
            }
            else {
                $result = if ($WhatIfPreference) { 'simulated' } else { 'skipped (declined)' }
            }
            $r = [pscustomobject]($base + @{ KeyRotated = $op; Result = $result })
            Add-Action $r; $r
        }
    }
}

# ---------------------------------------------------------------- report and summary

function ConvertTo-MdCell {
    param($Value)
    ([string]$Value) -replace '\|', '\|' -replace '[\r\n]+', ' '
}

function Write-ServiceReport {
    [CmdletBinding()]
    param([object]$Service, [object]$Inventory, [object]$Results, [string]$OutputFolder)

    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# APIM service $($Service.Name)")
    $md.Add('')
    $md.Add("- Azure subscription: $($Service.AzureSubscriptionName) ($($Service.AzureSubscriptionId))")
    $md.Add("- Resource group: $($Service.ResourceGroup)")
    $md.Add("- Tier: $($Service.Tier)")
    $md.Add("- Report generated (UTC): $(Get-UtcTimestamp)")
    $md.Add('')
    $md.Add('Key values and Note content are never recorded in this report.')
    $md.Add('')
    $md.Add('## Inventory')
    $md.Add('')
    if ($Inventory) {
        foreach ($family in 'Subscriptions', 'NamedValues', 'Backends', 'AuthorizationServers', 'OpenIdConnectProviders',
            'IdentityProviders', 'PortalSignin', 'AuthorizationProviders', 'Loggers', 'Products') {
            $items = @($Inventory.$family | Where-Object { $null -ne $_ })
            $md.Add("- ${family}: $($items.Count)")
        }
        $md.Add('')
        $subs = @($Inventory.Subscriptions | Where-Object { $_.DisplayName })
        if ($subs.Count) {
            $md.Add('### Subscriptions (metadata only)')
            $md.Add('')
            $md.Add('| Name | Id | State | Scope | Owner |')
            $md.Add('|---|---|---|---|---|')
            foreach ($s in $subs) { $md.Add("| $(ConvertTo-MdCell $s.DisplayName) | $(ConvertTo-MdCell $s.Sid) | $(ConvertTo-MdCell $s.State) | $(ConvertTo-MdCell $s.Scope) | $(ConvertTo-MdCell $s.OwnerId) |") }
            $md.Add('')
        }
        $md.Add('### User Notes check')
        $md.Add('')
        $notes = $Inventory.Notes
        if ($notes -and $notes.PSObject.Properties['NonEmptyNoteUsers']) {
            $md.Add("Users with a non-empty Note: $(@($notes.NonEmptyNoteUsers).Count) (content not read into this report).")
            $md.Add('')
            if (@($notes.NonEmptyNoteUsers).Count) {
                $md.Add('| Full name | Email | State | Identity | Groups |')
                $md.Add('|---|---|---|---|---|')
                foreach ($u in $notes.NonEmptyNoteUsers) {
                    $md.Add("| $(ConvertTo-MdCell $u.FullName) | $(ConvertTo-MdCell $u.Email) | $(ConvertTo-MdCell $u.State) | $(ConvertTo-MdCell $u.Identity) | $(ConvertTo-MdCell (@($u.Groups) -join ', ')) |")
                }
                $md.Add('')
            }
        }
        else {
            $md.Add('Not available.')
            $md.Add('')
        }
    }
    else {
        $md.Add('Not available.')
        $md.Add('')
    }

    $md.Add('## Rotation results')
    $md.Add('')
    $md.Add('| Subscription | Key | Owner | Result |')
    $md.Add('|---|---|---|---|')
    foreach ($r in @($Results | Where-Object { $null -ne $_ })) {
        $md.Add("| $(ConvertTo-MdCell $r.Subscription) | $(ConvertTo-MdCell $r.KeyRotated) | $(ConvertTo-MdCell $r.Owner) | $(ConvertTo-MdCell (ConvertTo-SafeResult $r.Result)) |")
    }
    $md.Add('')

    $md.Add('## Decisions and outcomes')
    $md.Add('')
    $md.Add('| Timestamp (UTC) | Event | Decision | Scope | Decided by | Outcome |')
    $md.Add('|---|---|---|---|---|---|')
    if ($script:RotationLogPath -and (Test-Path -LiteralPath $script:RotationLogPath)) {
        try {
            $rows = Import-Csv -LiteralPath $script:RotationLogPath | Where-Object { $_.Service -eq $Service.Name -and $_.EventType -in 'decision', 'skip' }
            foreach ($row in $rows) {
                $md.Add("| $(ConvertTo-MdCell $row.Timestamp) | $(ConvertTo-MdCell $row.EventType) | $(ConvertTo-MdCell $row.Decision) | $(ConvertTo-MdCell $row.Scope) | $(ConvertTo-MdCell $row.SignedInIdentity) | $(ConvertTo-MdCell $row.Outcome) |")
            }
        }
        catch { Write-Warning 'The decision log could not be read for the report.' }
    }
    $md.Add('')
    $md.Add('## Follow-up')
    $md.Add('')
    $md.Add('- Re-enable Developer Portal Basic Authentication (Developer portal > Identities) so users can retrieve their new keys from the Developer Portal.')
    $md.Add('- Named values, identity-provider, OpenID Connect and Auth0 secrets were inventoried only; they are not rotated by this script.')

    $safeName = $Service.Name -replace '[^\w\.\-]', '_'
    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force -WhatIf:$false -Confirm:$false | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $OutputFolder "$safeName.md") -Value ($md -join "`n") -Encoding utf8 -WhatIf:$false -Confirm:$false
}

function Write-RotationSummary {
    [CmdletBinding()]
    param([object]$Results)
    $all = @($Results | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-SafeResult $_.Result })
    $rotated = @($all | Where-Object { $_ -eq 'rotated' }).Count
    $failed = @($all | Where-Object { $_ -like 'failed*' }).Count
    $simulated = @($all | Where-Object { $_ -eq 'simulated' }).Count
    $skipped = @($all | Where-Object { $_ -like 'skipped*' -or $_ -like 'not rotated*' -or $_ -eq 'rejected' }).Count
    Write-Host ''
    Write-Host 'Summary'
    Write-Host "  Rotated: $rotated"
    Write-Host "  Failed: $failed"
    Write-Host "  Simulated: $simulated"
    Write-Host "  Skipped: $skipped"
}

# ---------------------------------------------------------------- main flow

function Invoke-ApimKeyRotationMain {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$RotateKey, [string]$OutputRoot)

    if ($RotateKey -notin 'Primary', 'Secondary', 'All') {
        throw 'Parameter -RotateKey (Primary, Secondary or All) is required.'
    }
    if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot 'reports' }
    if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
        throw 'The Az.Accounts module is required (Install-Module Az.Accounts).'
    }

    Write-Host 'Sign in to Azure in your browser.'
    Connect-AzAccount -WhatIf:$false -Confirm:$false -ErrorAction Stop | Out-Null
    Get-AzAccessToken -ErrorAction Stop | Out-Null
    Write-Host "Signed in as $(Get-SignedInIdentity)"

    $runFolder = Join-Path $OutputRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $runFolder -Force -WhatIf:$false -Confirm:$false | Out-Null
    $script:RotationLogPath = Join-Path $runFolder 'rotation-log.csv'
    Initialize-RotationLog -LogPath $script:RotationLogPath
    Write-Host "Reports: $runFolder"

    $allResults = [System.Collections.Generic.List[object]]::new()
    $failures = 0
    $azureSubscriptions = @(Get-AzureSubscriptionList)
    if ($azureSubscriptions.Count -eq 0) { Write-Host 'No Azure subscriptions are available for this account.' }

    while ($azureSubscriptions.Count -gt 0) {
    $selected = Select-AzureSubscription -Subscriptions $azureSubscriptions
    if (-not $selected) { break }
    Write-Host "Checking APIM services in $($selected.displayName) ($($selected.subscriptionId))..."
    $services = @(Get-ApimServices -SubscriptionId $selected.subscriptionId)
    if ($services.Count -eq 0) { Write-Host "No APIM services found in Azure subscription $($selected.subscriptionId)." }

    for ($i = 0; $i -lt $services.Count; $i++) {
        $service = $services[$i]
        Write-Host ''
        Write-Host "=== APIM service $($i + 1)/$($services.Count): $($service.Name) ==="
        try {
            $inventory = Get-ApimInventory -Service $service
            $nonEmpty = if ($inventory.Notes) { $inventory.Notes.NonEmptyNoteCount } else { 'n/a' }
            Write-Host "Inventory taken. Users with a non-empty Note: $nonEmpty"

            if (Confirm-ServiceRotation -Service $service -RotateKey $RotateKey) {
                $results = @(Invoke-KeyRotation -Service $service -RotateKey $RotateKey)
            }
            else {
                Add-RotationLogRow -LogPath $script:RotationLogPath -Row @{
                    Service = $service.Name; Subscription = 'n/a'; KeyRotated = 'n/a'; Owner = 'n/a'; Timestamp = Get-UtcTimestamp
                    SignedInIdentity = Get-SignedInIdentity; Result = 'skipped (service rejected)'
                    AzureSubscription = "$($service.AzureSubscriptionName) ($($service.AzureSubscriptionId))"
                    EventType = 'skip'; Decision = 'rejected'; Scope = $RotateKey; Outcome = 'not executed (rejected)'
                }
                $results = @([pscustomobject]@{ Service = $service.Name; Subscription = 'n/a'; KeyRotated = 'n/a'; Owner = 'n/a'; Result = 'skipped (service rejected)' })
            }
            foreach ($r in $results) { $allResults.Add($r) }
            $failures += @($results | Where-Object { (ConvertTo-SafeResult $_.Result) -like 'failed*' }).Count
            Write-ServiceReport -Service $service -Inventory $inventory -Results $results -OutputFolder $runFolder
        }
        catch {
            $failures++
            Write-Warning "Service '$($service.Name)' failed: $($_.Exception.Message)"
            $allResults.Add([pscustomobject]@{ Service = $service.Name; Subscription = 'n/a'; KeyRotated = 'n/a'; Owner = 'n/a'; Result = 'failed' })
            Add-RotationLogRow -LogPath $script:RotationLogPath -Row @{
                Service = $service.Name; Subscription = 'n/a'; KeyRotated = 'n/a'; Owner = 'n/a'; Timestamp = Get-UtcTimestamp
                SignedInIdentity = Get-SignedInIdentity; Result = 'failed'
                AzureSubscription = "$($service.AzureSubscriptionName) ($($service.AzureSubscriptionId))"
                EventType = 'action'; Decision = 'n/a'; Scope = $RotateKey; Outcome = 'failed'
            }
        }

        if ($i -lt $services.Count - 1) {
            $answer = Read-Host -Prompt 'Continue with the next APIM service? (Y/n)'
            if (([string]$answer).Trim() -match '^(n|no)$') {
                Write-Host 'Stopped by the user; remaining services were not analysed.'
                break
            }
        }
    }

    $another = Read-Host -Prompt 'Select another subscription? (Y/n)'
    if (([string]$another).Trim() -match '^(n|no)$') { break }
    }

    Write-RotationSummary -Results $allResults
    if ($failures -gt 0) { return 1 }
    return 0
}

# Run the main flow only when invoked as a script, never when dot-sourced.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RotateKey) {
        Write-Host @'
Usage:
  .\Invoke-ApimKeyRotation.ps1 -RotateKey <Primary|Secondary|All> [-OutputRoot <path>] [-WhatIf] [-Confirm]

  -RotateKey   Required. Select the primary key, secondary key, or both (All).
  -OutputRoot  Optional. Report folder; defaults to 'reports' next to the script.
  -WhatIf      Simulate key regeneration without changing keys. Authentication,
               inventory, approval prompts, and reports still run.
  -Confirm     Ask for confirmation of each key regeneration.

Examples:
  .\Invoke-ApimKeyRotation.ps1 -RotateKey Primary -WhatIf
  .\Invoke-ApimKeyRotation.ps1 -RotateKey All -OutputRoot C:\Reports
'@
        exit 1
    }
    $exitCode = Invoke-ApimKeyRotationMain -RotateKey $RotateKey -OutputRoot $OutputRoot
    exit ([int]($exitCode | Select-Object -Last 1))
}
