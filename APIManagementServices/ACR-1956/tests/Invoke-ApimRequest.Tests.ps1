BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSupport.ps1')
    . (Join-Path $PSScriptRoot '..\Invoke-ApimKeyRotation.ps1')
}

Describe 'Invoke-ApimRequest' {
    BeforeEach {
        # Fail-safe: every Azure/network/sleep command is mocked in every test.
        $script:calls = [System.Collections.Generic.List[object]]::new()
        $script:queue = [System.Collections.Generic.Queue[object]]::new()
        Mock Invoke-AzRestMethod {
            $script:calls.Add(@{ Method = $Method; Path = $Path; Payload = $Payload })
            $next = $script:queue.Dequeue()
            if ($next -is [scriptblock]) { & $next } else { $next }
        }
        Mock Start-Sleep { $script:sleeps += @($Seconds) }
        $script:sleeps = @()
    }

    It 'Given a path without api-version When a GET is sent Then the pinned api-version 2024-05-01 is used' {
        $script:queue.Enqueue((New-FakeResponse 200 @{ value = @() }))
        Invoke-ApimRequest -Method GET -Path '/subscriptions/s/resourceGroups/rg/providers/Microsoft.ApiManagement/service/a/subscriptions' | Out-Null
        $script:calls[0].Path | Should -Match 'api-version=2024-05-01'
    }

    It 'Given a 429 followed by a 200 When a GET is sent Then it is retried and succeeds' {
        $script:queue.Enqueue((New-FakeResponse 429 $null @{ 'Retry-After' = '7' }))
        $script:queue.Enqueue((New-FakeResponse 200 @{ value = @(@{ name = 'a' }) }))
        $r = Invoke-ApimRequest -Method GET -Path '/x/subscriptions'
        $script:calls.Count | Should -Be 2
        @($r).Count | Should -Be 1
    }

    It 'Given a 429 with Retry-After 7 When the request is retried Then it waits the 7 seconds asked for' {
        $script:queue.Enqueue((New-FakeResponse 429 $null @{ 'Retry-After' = '7' }))
        $script:queue.Enqueue((New-FakeResponse 200 @{ value = @() }))
        Invoke-ApimRequest -Method GET -Path '/x/subscriptions' | Out-Null
        Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Seconds -ge 7 }
    }

    It 'Given persistent 503 responses When a GET is sent Then it stops after 5 attempts and throws' {
        1..6 | ForEach-Object { $script:queue.Enqueue((New-FakeResponse 503)) }
        { Invoke-ApimRequest -Method GET -Path '/x/subscriptions' } | Should -Throw
        $script:calls.Count | Should -Be 5
    }

    It 'Given a 404 response When a GET is sent Then it is not retried' {
        $script:queue.Enqueue((New-FakeResponse 404))
        { Invoke-ApimRequest -Method GET -Path '/x/subscriptions' } | Should -Throw
        $script:calls.Count | Should -Be 1
    }

    It 'Given a regenerate POST answered with 503 then 204 When it is sent Then the 5xx is retried' {
        $script:queue.Enqueue((New-FakeResponse 503))
        $script:queue.Enqueue((New-FakeResponse 204))
        Invoke-ApimRequest -Method POST -Path '/x/subscriptions/s1/regeneratePrimaryKey' | Out-Null
        $script:calls.Count | Should -Be 2
    }

    It 'Given a regenerate POST that ends with no response When it is sent Then it is not retried and the outcome is reported unknown' {
        $script:queue.Enqueue({ throw 'The operation has timed out' })
        $script:queue.Enqueue((New-FakeResponse 204))
        { Invoke-ApimRequest -Method POST -Path '/x/subscriptions/s1/regeneratePrimaryKey' } | Should -Throw '*outcome unknown*'
        $script:calls.Count | Should -Be 1
    }

    It 'Given a list answered with a nextLink When a GET is sent Then every page is followed and all items returned' {
        $script:queue.Enqueue((New-FakeResponse 200 @{ value = @(@{ name = 'a' }); nextLink = 'https://management.azure.com/x/subscriptions?$skip=1&api-version=2024-05-01' }))
        $script:queue.Enqueue((New-FakeResponse 200 @{ value = @(@{ name = 'b' }) }))
        $r = @(Invoke-ApimRequest -Method GET -Path '/x/subscriptions')
        $r.Count | Should -Be 2
        $script:calls.Count | Should -Be 2
    }

    It 'Given a path that asks for secrets When a request is made Then it throws and no Azure call is made' -ForEach @(
        @{ P = '/x/namedValues/n1/listValue' }
        @{ P = '/x/identityProviders/aad/listSecrets' }
        @{ P = '/x/users/u1/subscriptions/s1/listSecrets' }
        @{ P = '/x/users/u1/token' }
    ) {
        { Invoke-ApimRequest -Method POST -Path $P } | Should -Throw -ExpectedMessage '*forbidden*'
        $script:calls.Count | Should -Be 0
    }

    It 'Given an error response echoing a key value When the request fails Then the error text contains no key value' {
        $script:queue.Enqueue((New-FakeResponse 400 @{ error = @{ code = 'Bad'; message = "echo $($script:KeyCanary)" } }))
        $msg = try { Invoke-ApimRequest -Method GET -Path '/x/subscriptions'; '' } catch { $_.Exception.Message + ($_ | Out-String) }
        $msg | Should -Match '400'
        Test-NoLeak $msg | Should -BeTrue
    }

    It 'Given a failure When the error is reported Then it carries the HTTP status and the request path' {
        $script:queue.Enqueue((New-FakeResponse 403))
        $msg = try { Invoke-ApimRequest -Method GET -Path '/x/subscriptions'; '' } catch { $_.Exception.Message }
        $msg | Should -Match '403'
        $msg | Should -Match '/x/subscriptions'
    }
}
