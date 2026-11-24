BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    $script:RunnerPath = Join-Path $PSScriptRoot 'Invoke-Tests.ps1'
}

Describe 'Preflight' {
    It 'Given the installed Pester When the suite runs Then its version is at least 5' {
        (Get-Module Pester).Version | Should -BeGreaterOrEqual ([version]'5.0')
    }

    It 'Given a required Pester version that is not installed When the runner pre-check runs Then it exits non-zero with a clear message' {
        $out = & pwsh -NoProfile -File $script:RunnerPath -MinimumPesterVersion 99.0 -CheckOnly 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $out | Should -Match 'Pester >= 99\.0 is required'
    }

    It 'Given the skeleton script When it is dot-sourced Then it loads and exposes the planned functions' {
        . (Join-Path $PSScriptRoot '..\Invoke-ApimKeyRotation.ps1')
        foreach ($f in 'Invoke-ApimRequest', 'Get-ApimServices', 'Get-ApimInventory', 'Test-UserNotes',
                       'Invoke-KeyRotation', 'Confirm-ServiceRotation', 'Confirm-MasterRotation',
                       'Write-ServiceReport', 'Add-RotationLogRow') {
            Get-Command $f -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because $f
        }
    }

    It 'Given an Azure command that is not mocked When a test calls it Then the safety stub throws instead of reaching Azure' {
        { Invoke-AzRestMethod -Method POST -Path '/x' } | Should -Throw '*SAFETY*'
        { Connect-AzAccount } | Should -Throw '*SAFETY*'
        { Get-AzContext } | Should -Throw '*SAFETY*'
    }
}
