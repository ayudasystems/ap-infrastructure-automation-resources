BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    . (Join-Path $PSScriptRoot '..\Invoke-ApimKeyRotation.ps1')
}

# Contract assumed for the main flow: Invoke-ApimKeyRotationMain returns the process exit code (0 / 1);
# the "continue with the next service?" question is asked through Read-Host.
Describe 'Main flow (fully mocked end to end)' {
    BeforeEach {
        # Fail-safe: no path leads to Azure. Azure commands throw; REST goes through the mocked wrapper;
        # every POST (regeneration) is only recorded, never sent.
        $script:order = [System.Collections.Generic.List[string]]::new()
        $script:posts = [System.Collections.Generic.List[string]]::new()
        $script:answers = [System.Collections.Generic.Queue[string]]::new()
        $script:serviceAnswers = @{ 'apim-a' = $true; 'apim-b' = $true }
        $script:rotateFails = @()
        $script:out = Join-Path $TestDrive ('out-' + [guid]::NewGuid().ToString('N'))
        Mock Invoke-AzRestMethod { throw 'SAFETY: main flow must never reach Azure' }
        Mock Connect-AzAccount { throw 'SAFETY: no login from tests' }
        Mock Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'tester@example.com' } } }
        Mock Start-Sleep { }
        Mock Write-Host { $script:hostText += ($Object -join ' ') + "`n" }
        $script:hostText = ''
        Mock Get-ApimServices { @((New-TestService 'apim-a'), (New-TestService 'apim-b')) }
        Mock Read-Host { $script:order.Add('continue?'); if ($script:answers.Count) { $script:answers.Dequeue() } else { 'y' } }
        Mock Confirm-ServiceRotation { $script:order.Add("approve:$($Service.Name)"); [bool]$script:serviceAnswers[$Service.Name] }
        Mock Confirm-MasterRotation { $script:order.Add("master:$($Service.Name)"); $false }
        Mock Invoke-ApimRequest {
            switch -Wildcard ($Path) {
                '*/regenerate*' { $script:posts.Add($Path); if ($script:rotateFails -and ($script:rotateFails | Where-Object { $Path -like "*$_*" })) { throw 'HTTP 500 failed' }; $null; break }
                '*/subscriptions?*' { @((New-ApimSubscription 's1' 'Client One'), (New-ApimSubscription 'master' 'Built-in all-access subscription')); break }
                '*/users/*/groups?*' { @([pscustomobject]@{ name = 'Developers' }); break }
                '*/users?*' { @([pscustomobject]@{ name = 'u1'; id = 'u1'; properties = [pscustomobject]@{ firstName = 'A'; lastName = 'B'; email = 'a@example.com'; state = 'active'; identities = @(); note = $script:NoteCanary } }); break }
                default { @() }
            }
        }
    }

    It 'Given two services both approved When the flow runs Then each is rotated in turn, one service at a time' {
        Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Out-Null
        $seq = ($script:order | Where-Object { $_ -like 'approve:*' }) -join ','
        $seq | Should -Be 'approve:apim-a,approve:apim-b'
        $script:order.IndexOf('approve:apim-b') | Should -BeGreaterThan $script:order.IndexOf('continue?')
        @($script:posts | Where-Object { $_ -match '/service/apim-a/' }).Count | Should -BeGreaterThan 0
        @($script:posts | Where-Object { $_ -match '/service/apim-b/' }).Count | Should -BeGreaterThan 0
    }

    It 'Given the first service rejected When the flow runs Then nothing is regenerated for it and the next service is still processed' {
        $script:serviceAnswers['apim-a'] = $false
        Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Out-Null
        @($script:posts | Where-Object { $_ -match '/service/apim-a/' }).Count | Should -Be 0
        @($script:posts | Where-Object { $_ -match '/service/apim-b/' }).Count | Should -BeGreaterThan 0
    }

    It 'Given a rejected service When the flow runs Then the master confirmation is not asked for it' {
        $script:serviceAnswers['apim-a'] = $false
        Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Out-Null
        $script:order | Should -Not -Contain 'master:apim-a'
    }

    It 'Given every service rejected When the flow ends Then the exit code is 0 because rejections are not failures' {
        $script:serviceAnswers['apim-a'] = $false
        $script:serviceAnswers['apim-b'] = $false
        Invoke-ApimKeyRotationMain -RotateKey All -OutputRoot $script:out -Confirm:$false | Select-Object -Last 1 | Should -Be 0
    }

    It 'Given a regeneration that fails on the first service When the flow runs Then the second service is still processed and the exit code is 1' {
        $script:rotateFails = @('/service/apim-a/')
        $code = Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Select-Object -Last 1
        $code | Should -Be 1
        @($script:posts | Where-Object { $_ -match '/service/apim-b/' }).Count | Should -BeGreaterThan 0
    }

    It 'Given an unexpected error in one service When the flow runs Then the run continues with the next service and the exit code is 1' {
        Mock Get-ApimInventory { if ($Service.Name -eq 'apim-a') { throw 'boom' } else { [pscustomobject]@{} } }
        $code = Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Select-Object -Last 1
        $code | Should -Be 1
        $script:order | Should -Contain 'approve:apim-b'
    }

    It 'Given all rotations succeed When the flow ends Then the exit code is 0' {
        Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Select-Object -Last 1 | Should -Be 0
    }

    It 'Given the user answers no to continue When the first service is done Then the second service is not processed' {
        $script:answers.Enqueue('n')
        Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Out-Null
        $script:order | Should -Not -Contain 'approve:apim-b'
    }

    It 'Given WhatIf When the flow runs Then no regenerate call is made' {
        Invoke-ApimKeyRotationMain -RotateKey All -OutputRoot $script:out -WhatIf | Out-Null
        $script:posts.Count | Should -Be 0
    }

    It 'Given no service approval When the flow runs Then no regenerate call is made for any service' {
        $script:serviceAnswers['apim-a'] = $false
        $script:serviceAnswers['apim-b'] = $false
        Invoke-ApimKeyRotationMain -RotateKey All -OutputRoot $script:out -Confirm:$false | Out-Null
        $script:posts.Count | Should -Be 0
    }

    It 'Given a run When it starts Then a timestamped folder with the audit CSV and one report per processed service is created' {
        Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Out-Null
        $run = Get-ChildItem $script:out -Directory | Select-Object -First 1
        $run.Name | Should -Match '^\d{8}-\d{6}$'
        Test-Path (Join-Path $run.FullName 'rotation-log.csv') | Should -BeTrue
        Test-Path (Join-Path $run.FullName 'apim-a.md') | Should -BeTrue
        Test-Path (Join-Path $run.FullName 'apim-b.md') | Should -BeTrue
    }

    It 'Given a rejection When the flow runs Then the decision is recorded in the audit CSV' {
        Mock Confirm-ServiceRotation { $Service.Name -ne 'apim-a' }
        Invoke-ApimKeyRotationMain -RotateKey Primary -OutputRoot $script:out -Confirm:$false | Out-Null
        $csv = Get-ChildItem $script:out -Recurse -Filter rotation-log.csv | Select-Object -First 1
        (Import-Csv $csv.FullName | Where-Object { $_.Service -eq 'apim-a' -and $_.Decision -eq 'rejected' }) | Should -Not -BeNullOrEmpty
    }

    It 'Given subscriptions with keys and users with Notes When the flow runs Then no key value or Note content appears in console, errors or files' {
        $console = Invoke-ApimKeyRotationMain -RotateKey All -OutputRoot $script:out -Confirm:$false *>&1 | Out-String
        $files = Get-AllFilesText $script:out
        Test-NoLeak ($console + $script:hostText + $files) | Should -BeTrue
    }

    It 'Given the whole flow When it runs Then no real Azure command is invoked' {
        Invoke-ApimKeyRotationMain -RotateKey All -OutputRoot $script:out -Confirm:$false | Out-Null
        Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly
        Should -Invoke Connect-AzAccount -Times 0 -Exactly
    }
}
