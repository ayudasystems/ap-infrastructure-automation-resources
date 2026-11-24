BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    . (Join-Path $PSScriptRoot '..\Invoke-ApimKeyRotation.ps1')
}

Describe 'Approval helpers' {
    BeforeEach {
        # Fail-safe: answers come only from mocks; nothing can read the console or reach Azure.
        $script:shown = [System.Collections.Generic.List[string]]::new()
        $script:answers = [System.Collections.Generic.Queue[string]]::new()
        Mock Invoke-AzRestMethod { throw 'SAFETY' }
        Mock Connect-AzAccount { throw 'SAFETY' }
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'tester@example.com' } } }
        Mock Add-RotationLogRow { }
        Mock Write-Host { $script:shown.Add(($Object -join ' ')) }
        Mock Read-Host { $script:shown.Add([string]$Prompt); $script:answers.Dequeue() }
    }

    It 'Given the user answers yes When the service rotation is asked Then it is approved' {
        $script:answers.Enqueue('y')
        Confirm-ServiceRotation -Service (New-TestService) -RotateKey Primary | Should -BeTrue
    }

    It 'Given the user answers no When the service rotation is asked Then it is rejected' {
        $script:answers.Enqueue('n')
        Confirm-ServiceRotation -Service (New-TestService) -RotateKey Primary | Should -BeFalse
    }

    It 'Given an unrecognised or empty answer When the service rotation is asked Then it is treated as a rejection' {
        $script:answers.Enqueue('maybe')
        Confirm-ServiceRotation -Service (New-TestService) -RotateKey All | Should -BeFalse
    }

    It 'Given the user answers yes When the master rotation is asked Then the prompt shows the Microsoft all-access warning verbatim' {
        $script:answers.Enqueue('y')
        Confirm-MasterRotation -Service (New-TestService) -RotateKey All | Out-Null
        ($script:shown -join "`n") | Should -BeLike "*$($script:MasterWarning)*"
    }

    It 'Given a service already approved When the master rotation is asked Then a separate answer is requested and a no keeps master untouched' {
        $script:answers.Enqueue('y')
        $script:answers.Enqueue('n')
        Confirm-ServiceRotation -Service (New-TestService) -RotateKey All | Should -BeTrue
        Confirm-MasterRotation -Service (New-TestService) -RotateKey All | Should -BeFalse
        Should -Invoke Read-Host -Times 2 -Exactly
    }

    It 'Given WhatIf and Confirm none preferences When approval is asked Then the user is still asked' {
        $script:answers.Enqueue('y')
        $ConfirmPreference = 'None'
        $WhatIfPreference = $true
        Confirm-ServiceRotation -Service (New-TestService) -RotateKey Primary | Out-Null
        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'Given an approval When the answer is given Then a decision row is logged at once with who, scope and decision' {
        $script:answers.Enqueue('y')
        Confirm-ServiceRotation -Service (New-TestService) -RotateKey Secondary | Out-Null
        Should -Invoke Add-RotationLogRow -Times 1 -Exactly -ParameterFilter {
            $Row.EventType -eq 'decision' -and $Row.Decision -eq 'approved' -and $Row.Scope -eq 'Secondary' -and
            $Row.SignedInIdentity -eq 'tester@example.com' -and $Row.Service -eq 'apim-one' -and $Row.Timestamp }
    }

    It 'Given a rejection When the answer is given Then a decision row is logged with outcome not executed' {
        $script:answers.Enqueue('n')
        Confirm-ServiceRotation -Service (New-TestService) -RotateKey All | Out-Null
        Should -Invoke Add-RotationLogRow -Times 1 -Exactly -ParameterFilter {
            $Row.EventType -eq 'decision' -and $Row.Decision -eq 'rejected' -and $Row.Outcome -eq 'not executed (rejected)' }
    }

    It 'Given a master approval and a master rejection When answered Then each is logged as its own decision with scope Master' {
        $script:answers.Enqueue('y')
        $script:answers.Enqueue('n')
        Confirm-MasterRotation -Service (New-TestService) -RotateKey All | Out-Null
        Confirm-MasterRotation -Service (New-TestService) -RotateKey All | Out-Null
        Should -Invoke Add-RotationLogRow -Times 1 -Exactly -ParameterFilter { $Row.Scope -eq 'Master' -and $Row.Decision -eq 'approved' }
        Should -Invoke Add-RotationLogRow -Times 1 -Exactly -ParameterFilter { $Row.Scope -eq 'Master' -and $Row.Decision -eq 'rejected' }
    }

    It 'Given the approval helpers When they run Then no real Azure command is invoked' {
        $script:answers.Enqueue('y')
        Confirm-ServiceRotation -Service (New-TestService) -RotateKey Primary | Out-Null
        Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly
        Should -Invoke Connect-AzAccount -Times 0 -Exactly
    }
}
