BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    . (Join-Path $PSScriptRoot '..\Invoke-ApimKeyRotation.ps1')
}

Describe 'Invoke-KeyRotation' {
    BeforeEach {
        # Fail-safe: no real key can be regenerated - POSTs only reach the mocked wrapper.
        $script:posts = [System.Collections.Generic.List[string]]::new()
        $script:failPath = $null
        Mock Invoke-AzRestMethod { throw 'SAFETY: rotation tests must never reach Azure' }
        Mock Connect-AzAccount { throw 'SAFETY' }
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'tester@example.com' } } }
        Mock Start-Sleep { }
        Mock Add-RotationLogRow { }
        Mock Confirm-MasterRotation { $true }
        Mock Invoke-ApimRequest {
            if ($Method -eq 'POST') {
                $script:posts.Add($Path)
                if ($script:failPath -and $Path -like "*$($script:failPath)*") { throw 'HTTP 500 /regenerate failed' }
                return $null
            }
            @((New-ApimSubscription 'master' 'Built-in all-access subscription'),
              (New-ApimSubscription 's1' 'Client One'),
              (New-ApimSubscription 's2' 'Client Two'),
              (New-ApimSubscription 's3' 'Suspended Client' 'suspended'),
              (New-ApimSubscription 's4' 'Cancelled Client' 'cancelled'))
        }
        function script:PostsFor($sid, $op) { @($script:posts | Where-Object { $_ -match "/subscriptions/$sid/$op" }) }
    }

    It 'Given RotateKey Primary When keys are rotated Then only the regeneratePrimaryKey endpoint is called for active subscriptions' {
        Invoke-KeyRotation -Service (New-TestService) -RotateKey Primary -Confirm:$false | Out-Null
        (script:PostsFor 's1' 'regeneratePrimaryKey').Count | Should -Be 1
        (script:PostsFor 's2' 'regeneratePrimaryKey').Count | Should -Be 1
        ($script:posts | Where-Object { $_ -match 'regenerateSecondaryKey' }).Count | Should -Be 0
    }

    It 'Given RotateKey Secondary When keys are rotated Then only the regenerateSecondaryKey endpoint is called' {
        Invoke-KeyRotation -Service (New-TestService) -RotateKey Secondary -Confirm:$false | Out-Null
        (script:PostsFor 's1' 'regenerateSecondaryKey').Count | Should -Be 1
        ($script:posts | Where-Object { $_ -match 'regeneratePrimaryKey' }).Count | Should -Be 0
    }

    It 'Given RotateKey All When keys are rotated Then both regenerate endpoints are called for each active subscription' {
        Invoke-KeyRotation -Service (New-TestService) -RotateKey All -Confirm:$false | Out-Null
        foreach ($sid in 's1', 's2') {
            (script:PostsFor $sid 'regeneratePrimaryKey').Count | Should -Be 1
            (script:PostsFor $sid 'regenerateSecondaryKey').Count | Should -Be 1
        }
    }

    It 'Given suspended and cancelled subscriptions When keys are rotated Then they are never rotated' {
        Invoke-KeyRotation -Service (New-TestService) -RotateKey All -Confirm:$false | Out-Null
        ($script:posts | Where-Object { $_ -match '/subscriptions/(s3|s4)/' }).Count | Should -Be 0
    }

    It 'Given the master subscription not confirmed When keys are rotated Then master is left untouched and others are still rotated' {
        Mock Confirm-MasterRotation { $false }
        $res = Invoke-KeyRotation -Service (New-TestService) -RotateKey All -Confirm:$false
        ($script:posts | Where-Object { $_ -match '/subscriptions/master/' }).Count | Should -Be 0
        (script:PostsFor 's1' 'regeneratePrimaryKey').Count | Should -Be 1
        ($res | Where-Object { $_.Subscription -match 'master' } | Select-Object -First 1).Result | Should -Match 'not rotated|skipped|rejected'
    }

    It 'Given the master subscription confirmed When keys are rotated Then the master regenerate endpoint is called' {
        Invoke-KeyRotation -Service (New-TestService) -RotateKey Primary -Confirm:$false | Out-Null
        (script:PostsFor 'master' 'regeneratePrimaryKey').Count | Should -Be 1
    }

    It 'Given automatic confirmation requested with Confirm false When keys are rotated Then the separate master confirmation is still asked' {
        Invoke-KeyRotation -Service (New-TestService) -RotateKey Primary -Confirm:$false | Out-Null
        Should -Invoke Confirm-MasterRotation -Times 1 -Exactly
    }

    It 'Given WhatIf When keys are rotated Then no regenerate call is made and results are marked simulated' {
        $res = Invoke-KeyRotation -Service (New-TestService) -RotateKey All -WhatIf
        $script:posts.Count | Should -Be 0
        @($res | Where-Object { $_.Result -eq 'simulated' }).Count | Should -BeGreaterThan 0
    }

    It 'Given one regeneration that fails When keys are rotated Then the failure is recorded and the other subscriptions are still rotated' {
        $script:failPath = '/subscriptions/s1/'
        $res = Invoke-KeyRotation -Service (New-TestService) -RotateKey Primary -Confirm:$false
        ($res | Where-Object { $_.Subscription -match 's1|Client One' }).Result | Should -Match 'failed'
        (script:PostsFor 's2' 'regeneratePrimaryKey').Count | Should -Be 1
    }

    It 'Given subscriptions that carry key values When keys are rotated Then no key value appears in results or output' {
        $out = Invoke-KeyRotation -Service (New-TestService) -RotateKey All -Confirm:$false *>&1 | Out-String
        Test-NoLeak ($out + ($out | ConvertTo-Json)) | Should -BeTrue
    }

    It 'Given every regeneration When it is performed Then an action row with the result is logged for it' {
        Invoke-KeyRotation -Service (New-TestService) -RotateKey Primary -Confirm:$false | Out-Null
        Should -Invoke Add-RotationLogRow -ParameterFilter { $Row.EventType -eq 'action' -and $Row.KeyRotated -eq 'Primary' } -Times 3
    }
}
