BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    . (Join-Path $PSScriptRoot '..\Invoke-ApimKeyRotation.ps1')
}

Describe 'Discovery, inventory and Note check' {
    BeforeEach {
        # Fail-safe: nothing below can reach Azure; REST goes through the mocked wrapper,
        # and the underlying Azure commands are throwing stubs (see TestSupport.ps1).
        $script:requests = [System.Collections.Generic.List[object]]::new()
        Mock Invoke-AzRestMethod { throw 'SAFETY: inventory tests must go through the mocked Invoke-ApimRequest' }
        Mock Connect-AzAccount { throw 'SAFETY' }
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'tester@example.com' } } }
        Mock Invoke-ApimRequest {
            $script:requests.Add(@{ Method = $Method; Path = $Path })
            # Azure subscription listing: anchored regex ('?' in a wildcard would also match '/').
            if ($Path -match '^/subscriptions\?') {
                return @([pscustomobject]@{ subscriptionId = 'aaaa'; displayName = 'Sub With Apim' },
                         [pscustomobject]@{ subscriptionId = 'bbbb'; displayName = 'Sub Without Apim' })
            }
            switch -Wildcard ($Path) {
                '/subscriptions/aaaa/providers/Microsoft.ApiManagement/service*' {
                    @([pscustomobject]@{ name = 'apim-one'; id = '/subscriptions/aaaa/resourceGroups/rg-one/providers/Microsoft.ApiManagement/service/apim-one'; sku = [pscustomobject]@{ name = 'Developer' } }); break }
                '/subscriptions/bbbb/providers/Microsoft.ApiManagement/service*' { @(); break }
                '*/subscriptions[?]*' {
                    @((New-ApimSubscription 'master' 'Built-in all-access subscription'), (New-ApimSubscription 's1' 'Client One' 'active' '/users/u1')); break }
                '*/identityProviders[?]*' { @([pscustomobject]@{ name = 'aad'; type = 'microsoft'; id = 'idp1'; properties = [pscustomobject]@{ clientId = 'cid'; clientSecret = $script:KeyCanary } }); break }
                '*/openidConnectProviders[?]*' { @([pscustomobject]@{ name = 'oidc'; id = 'o1'; properties = [pscustomobject]@{ clientSecret = $script:KeyCanary } }); break }
                '*/authorizationServers[?]*' { @([pscustomobject]@{ name = 'as'; id = 'a1'; properties = [pscustomobject]@{ clientSecret = $script:KeyCanary } }); break }
                '*/users/*/groups[?]*' { @([pscustomobject]@{ name = 'Developers' }); break }
                '*/users[?]*' {
                    @([pscustomobject]@{ name = 'u1'; id = 'u1'; properties = [pscustomobject]@{ firstName = 'Ann'; lastName = 'Lee'; email = 'ann@example.com'; state = 'active'; identities = @([pscustomobject]@{ provider = 'Basic'; id = 'ann@example.com' }); note = $script:NoteCanary } },
                      [pscustomobject]@{ name = 'u2'; id = 'u2'; properties = [pscustomobject]@{ firstName = 'Bob'; lastName = 'Roe'; email = 'bob@example.com'; state = 'active'; identities = @(); note = '' } }); break }
                default { @() }
            }
        }
    }

    It 'Given an Azure subscription without APIM When services are discovered Then it is skipped and only the APIM service is returned' {
        $svc = @(Get-ApimServices)
        $svc.Count | Should -Be 1
        $svc[0].Name | Should -Be 'apim-one'
        $svc[0].AzureSubscriptionId | Should -Be 'aaaa'
    }

    It 'Given several Azure subscriptions When services are discovered Then every one of them is enumerated and queried' {
        Get-ApimServices | Out-Null
        Should -Invoke Invoke-ApimRequest -ParameterFilter { $Path -like '/subscriptions/aaaa/providers/Microsoft.ApiManagement/service*' }
        Should -Invoke Invoke-ApimRequest -ParameterFilter { $Path -like '/subscriptions/bbbb/providers/Microsoft.ApiManagement/service*' }
    }

    It 'Given an APIM service When the inventory is taken Then every design resource family is requested' {
        Get-ApimInventory -Service (New-TestService) | Out-Null
        $paths = $script:requests.Path -join "`n"
        foreach ($frag in '/subscriptions?', '/namedValues', '/backends', '/authorizationServers', '/openidConnectProviders',
                          '/identityProviders', '/portalsettings/signin', '/authorizationProviders', '/loggers', '/products', '/users') {
            $paths | Should -Match ([regex]::Escape($frag)) -Because $frag
        }
    }

    It 'Given an APIM service When the inventory is taken Then only GET requests are made' {
        Get-ApimInventory -Service (New-TestService) | Out-Null
        ($script:requests | Where-Object { $_.Method -and $_.Method -ne 'GET' }).Count | Should -Be 0
    }

    It 'Given providers that carry client secrets When the inventory is taken Then the result holds no secret value or secret field' {
        $inv = Get-ApimInventory -Service (New-TestService)
        $json = $inv | ConvertTo-Json -Depth 10
        Test-NoLeak $json | Should -BeTrue
        $json | Should -Not -Match 'clientSecret'
    }

    It 'Given subscriptions that carry keys When the inventory is taken Then only allow-listed metadata remains' {
        $inv = Get-ApimInventory -Service (New-TestService)
        $json = $inv | ConvertTo-Json -Depth 10
        $json | Should -Not -Match 'primaryKey|secondaryKey'
        $json | Should -Match 'Client One'
    }

    It 'Given a service whose inventory is taken When secrets could be requested Then no listSecrets, listValue or token call is made' {
        Get-ApimInventory -Service (New-TestService) | Out-Null
        Test-UserNotes -Service (New-TestService) | Out-Null
        ($script:requests.Path -join "`n") | Should -Not -Match 'listSecrets|listValue|/token'
    }

    It 'Given one user with a Note and one without When the Note check runs Then only the user with a Note is reported' {
        $r = Test-UserNotes -Service (New-TestService)
        @($r.NonEmptyNoteUsers).Count | Should -Be 1
        $r.NonEmptyNoteUsers[0].Email | Should -Be 'ann@example.com'
    }

    It 'Given a user with a non-empty Note When it is reported Then Full Name, Email, State, Identity and Groups are present' {
        $u = (Test-UserNotes -Service (New-TestService)).NonEmptyNoteUsers[0]
        $u.FullName | Should -Be 'Ann Lee'
        $u.Email | Should -Be 'ann@example.com'
        $u.State | Should -Be 'active'
        $u.Identity | Should -Match 'ann@example.com'
        @($u.Groups) | Should -Contain 'Developers'
    }

    It 'Given a user with a Note When the check runs Then the Note content appears in no result, output or error stream' {
        $all = Test-UserNotes -Service (New-TestService) *>&1 | Out-String
        $json = Test-UserNotes -Service (New-TestService) | ConvertTo-Json -Depth 10
        Test-NoLeak ($all + $json) | Should -BeTrue
    }

    It 'Given a user with a Note When the check runs Then the result exposes no Note property' {
        $r = Test-UserNotes -Service (New-TestService)
        ($r | ConvertTo-Json -Depth 10) | Should -Not -Match '"note"'
        $r.NonEmptyNoteUsers[0].PSObject.Properties.Name | Should -Not -Contain 'Note'
    }

    It 'Given the discovery and inventory When they run Then no real Azure command is invoked' {
        Get-ApimServices | Out-Null
        Get-ApimInventory -Service (New-TestService) | Out-Null
        Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly
        Should -Invoke Connect-AzAccount -Times 0 -Exactly
    }
}
