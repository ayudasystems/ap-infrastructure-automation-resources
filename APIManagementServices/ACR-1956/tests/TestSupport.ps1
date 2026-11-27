# Shared, dot-sourced by every *.Tests.ps1 inside BeforeAll.
# SAFETY (hard rule): no test may ever reach Azure, authenticate or rotate a key.
# Every command that could reach Azure is shadowed here by a stub that THROWS.
# Functions take precedence over cmdlets/modules, so even with Az installed and a
# signed-in context a forgotten mock fails safe. Tests then Mock these stubs.

$script:SafetyMessage = 'SAFETY: real Azure/network command reached from a test - it must be mocked'

function Invoke-AzRestMethod {
    [CmdletBinding()]
    param($Method, $Path, $Payload, $ApiVersion, $SubscriptionId, $ResourceGroupName,
          $ResourceProviderName, $ResourceType, $Name, $Uri, $Headers, [switch]$AsJob)
    throw $script:SafetyMessage
}
function Connect-AzAccount { [CmdletBinding(SupportsShouldProcess = $true)] param([string]$Subscription, [Parameter(ValueFromRemainingArguments)]$Rest) throw $script:SafetyMessage }
function Get-AzContext { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) throw $script:SafetyMessage }
function Set-AzContext { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) throw $script:SafetyMessage }
function Get-AzSubscription { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) throw $script:SafetyMessage }
function Disconnect-AzAccount { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) throw $script:SafetyMessage }
function Get-AzAccessToken { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) throw $script:SafetyMessage }
function Invoke-RestMethod { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) throw $script:SafetyMessage }
function Invoke-WebRequest { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) throw $script:SafetyMessage }
function Read-Host { [CmdletBinding()] param($Prompt, [switch]$AsSecureString) throw 'SAFETY: unmocked Read-Host would block or answer for the user' }

# Canary values: must NEVER appear in any output, log, report or error text.
$script:KeyCanary  = 'KEYCANARY-9f3a1c7d-DO-NOT-LEAK'
$script:NoteCanary = 'NOTECANARY-4b8e2a-DO-NOT-LEAK'
$script:MasterWarning = 'All-access subscription enables access to every API in this API Management instance and should only be used by authorized users. Never use it for routine API access or embed the all-access key in client apps.'
$script:ApiVersion = 'api-version=2024-05-01'

function New-FakeResponse {
    param([int]$StatusCode = 200, $Body = $null, [hashtable]$Headers = @{})
    $content = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 10 -Compress } else { '' }
    [pscustomobject]@{ StatusCode = $StatusCode; Content = $content; Headers = $Headers }
}

function New-TestService {
    param([string]$Name = 'apim-one', [string]$AzSub = '11111111-1111-1111-1111-111111111111')
    [pscustomobject]@{
        Name = $Name; AzureSubscriptionId = $AzSub; AzureSubscriptionName = 'Az Sub One'
        ResourceGroup = 'rg-one'; Tier = 'Developer'
        Id = "/subscriptions/$AzSub/resourceGroups/rg-one/providers/Microsoft.ApiManagement/service/$Name"
    }
}

function New-ApimSubscription {
    param([string]$Sid, [string]$Display = $Sid, [string]$State = 'active', [string]$Owner = 'n/a')
    [pscustomobject]@{
        name = $Sid
        properties = [pscustomobject]@{
            displayName = $Display; state = $State; scope = '/apis'; ownerId = $Owner
            primaryKey = $script:KeyCanary; secondaryKey = $script:KeyCanary
        }
    }
}

function Test-NoLeak {
    # $Text: any captured output/file content. Returns $true when no canary is present.
    param([string]$Text)
    return (-not $Text.Contains($script:KeyCanary)) -and (-not $Text.Contains($script:NoteCanary))
}

function Get-AllFilesText {
    param([string]$Folder)
    if (-not (Test-Path $Folder)) { return '' }
    (Get-ChildItem -Path $Folder -Recurse -File | ForEach-Object { Get-Content -Raw -Path $_.FullName }) -join "`n"
}
