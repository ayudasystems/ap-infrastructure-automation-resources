BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    . (Join-Path $PSScriptRoot '..\Invoke-ApimKeyRotation.ps1')
    $script:Columns = 'Service', 'Subscription', 'KeyRotated', 'Owner', 'Timestamp', 'SignedInIdentity', 'Result',
                      'AzureSubscription', 'EventType', 'Decision', 'Scope', 'Outcome'
    function script:New-Row {
        param([hashtable]$Override = @{})
        $r = @{ Service = 'apim-one'; Subscription = 'Client One (s1)'; KeyRotated = 'Primary'; Owner = 'owner@example.com'
                Timestamp = '2026-11-24T10:00:00Z'; SignedInIdentity = 'tester@example.com'; Result = 'rotated'
                AzureSubscription = 'Az Sub One (aaaa)'; EventType = 'action'; Decision = 'n/a'; Scope = 'Primary'; Outcome = 'rotated' }
        foreach ($k in $Override.Keys) { $r[$k] = $Override[$k] }
        $r
    }
}

Describe 'Audit log and service report' {
    BeforeEach {
        # Fail-safe: reporting is pure file output; any Azure call is a bug and throws.
        Mock Invoke-AzRestMethod { throw 'SAFETY' }
        Mock Connect-AzAccount { throw 'SAFETY' }
        Mock Get-AzContext { throw 'SAFETY' }
        $script:shown = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:shown.Add(($Object -join ' ')) }
        $testRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        $script:log = Join-Path $testRoot 'rotation-log.csv'
        $script:outDir = Join-Path $testRoot 'run'
        New-Item -ItemType Directory -Path $script:outDir -Force | Out-Null
        $script:results = @(
            [pscustomobject]@{ Service = 'apim-one'; Subscription = 'Client One (s1)'; KeyRotated = 'Primary'; Owner = 'owner@example.com'; Result = 'rotated' },
            [pscustomobject]@{ Service = 'apim-one'; Subscription = 'Client Two (s2)'; KeyRotated = 'Primary'; Owner = 'n/a'; Result = 'failed' },
            [pscustomobject]@{ Service = 'apim-one'; Subscription = 'Built-in all-access subscription (master)'; KeyRotated = 'Primary'; Owner = 'n/a'; Result = 'simulated' },
            [pscustomobject]@{ Service = 'apim-one'; Subscription = 'Old (s3)'; KeyRotated = 'n/a'; Owner = 'n/a'; Result = 'skipped (not active)' })
        $script:inv = [pscustomobject]@{ Subscriptions = @(); NamedValues = @(); Backends = @(); Loggers = @() }
    }

    It 'Given a log row When it is added Then the CSV is created with the 12 columns in the fixed order' {
        Add-RotationLogRow -Row (script:New-Row) -LogPath $script:log
        $csv = Import-Csv $script:log
        $csv[0].PSObject.Properties.Name | Should -Be $script:Columns
    }

    It 'Given two rows added one after the other When the file is read Then both are present at once without a final flush' {
        Add-RotationLogRow -Row (script:New-Row) -LogPath $script:log
        @(Import-Csv $script:log).Count | Should -Be 1
        Add-RotationLogRow -Row (script:New-Row @{ Subscription = 'Client Two (s2)' }) -LogPath $script:log
        @(Import-Csv $script:log).Count | Should -Be 2
    }

    It 'Given a value starting with an equals sign When the row is added Then it is prefixed against CSV injection' {
        Add-RotationLogRow -Row (script:New-Row @{ Owner = '=HYPERLINK("http://x")' }) -LogPath $script:log
        (Import-Csv $script:log)[0].Owner | Should -BeLike "'=*"
    }

    It 'Given a decision row When it is added Then decision, scope, outcome and the deciding identity are stored' {
        Add-RotationLogRow -Row (script:New-Row @{ EventType = 'decision'; Decision = 'rejected'; Scope = 'Master'; Outcome = 'not executed (rejected)' }) -LogPath $script:log
        $r = (Import-Csv $script:log)[0]
        $r.EventType | Should -Be 'decision'
        $r.Decision | Should -Be 'rejected'
        $r.Scope | Should -Be 'Master'
        $r.Outcome | Should -Be 'not executed (rejected)'
        $r.SignedInIdentity | Should -Be 'tester@example.com'
    }

    It 'Given a row that wrongly carries a key value When it is added Then the key value is not written to the file' {
        Add-RotationLogRow -Row (script:New-Row @{ Result = $script:KeyCanary }) -LogPath $script:log
        Test-NoLeak (Get-Content -Raw $script:log) | Should -BeTrue
    }

    It 'Given a processed service When the report is written Then a file named after the service exists in the run folder' {
        Write-ServiceReport -Service (New-TestService) -Inventory $script:inv -Results $script:results -OutputFolder $script:outDir
        Test-Path (Join-Path $script:outDir 'apim-one.md') | Should -BeTrue
    }

    It 'Given a processed service When the report is written Then it has a Decisions and outcomes section and the portal reminder' {
        Write-ServiceReport -Service (New-TestService) -Inventory $script:inv -Results $script:results -OutputFolder $script:outDir
        $md = Get-Content -Raw (Join-Path $script:outDir 'apim-one.md')
        $md | Should -Match 'Decisions and outcomes'
        $md | Should -Match 'Developer Portal'
    }

    It 'Given rotated, failed, simulated and skipped results When the report is written Then each subscription, key and result is stated' {
        Write-ServiceReport -Service (New-TestService) -Inventory $script:inv -Results $script:results -OutputFolder $script:outDir
        $md = Get-Content -Raw (Join-Path $script:outDir 'apim-one.md')
        foreach ($t in 'Client One', 'Primary', 'rotated', 'failed', 'simulated', 'skipped') { $md | Should -Match $t }
    }

    It 'Given an inventory and results that carry key and Note canaries When the report is written Then no canary is in any file' {
        $dirty = [pscustomobject]@{ Subscriptions = @([pscustomobject]@{ primaryKey = $script:KeyCanary }); Notes = $script:NoteCanary }
        $res = $script:results + [pscustomobject]@{ Service = 'apim-one'; Subscription = 'x'; KeyRotated = 'Primary'; Owner = 'n/a'; Result = "failed $($script:KeyCanary)" }
        Write-ServiceReport -Service (New-TestService) -Inventory $dirty -Results $res -OutputFolder $script:outDir
        Test-NoLeak (Get-AllFilesText $script:outDir) | Should -BeTrue
    }

    It 'Given results with rotated, failed and simulated items When the summary is printed Then the counts are shown' {
        Write-RotationSummary -Results $script:results
        $text = $script:shown -join "`n"
        $text | Should -Match '(?i)rotated\D*1'
        $text | Should -Match '(?i)failed\D*1'
        $text | Should -Match '(?i)simulated\D*1'
        $text | Should -Match '(?i)skipped\D*1'
    }

    It 'Given results that carry a key canary When the summary is printed Then the canary is not printed' {
        $res = @([pscustomobject]@{ Service = 's'; Subscription = 'a'; KeyRotated = 'Primary'; Owner = 'n/a'; Result = "failed $($script:KeyCanary)" })
        Write-RotationSummary -Results $res
        Test-NoLeak ($script:shown -join "`n") | Should -BeTrue
    }

    It 'Given the reporting functions When they run Then no real Azure command is invoked' {
        Add-RotationLogRow -Row (script:New-Row) -LogPath $script:log
        Should -Invoke Invoke-AzRestMethod -Times 0 -Exactly
        Should -Invoke Connect-AzAccount -Times 0 -Exactly
    }
}
