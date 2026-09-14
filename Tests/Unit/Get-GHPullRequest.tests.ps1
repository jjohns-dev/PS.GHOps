BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'Get-GHPullRequest' -Fixture {
    BeforeAll {
        # RETURN A DISTINCT PR PER ROLE SO UNION/DEDUPE BEHAVIOR IS OBSERVABLE.
        # PR #1 (aws-lambda) IS RETURNED FOR BOTH --author AND --review-requested;
        # PR #2 (web-app) ONLY FOR --author.
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith {
            [PSCustomObject] @{ login = 'octo' }
        }
        Mock -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -MockWith {
            $pr1 = [PSCustomObject] @{
                number     = 1
                title      = 'first'
                state      = 'open'
                isDraft    = $false
                updatedAt  = '2026-07-01T12:00:00Z'
                repository = [PSCustomObject] @{ nameWithOwner = 'PS-MCS/aws-lambda'; name = 'aws-lambda' }
                author     = [PSCustomObject] @{ login = 'octo' }
                assignees  = @([PSCustomObject] @{ login = 'octo' }, [PSCustomObject] @{ login = 'hubot' })
                url        = 'https://github.com/PS-MCS/aws-lambda/pull/1'
            }
            $pr2 = [PSCustomObject] @{
                number     = 2
                title      = 'second'
                state      = 'open'
                isDraft    = $true
                updatedAt  = '2026-07-02T12:00:00Z'
                repository = [PSCustomObject] @{ nameWithOwner = 'PS-MCS/web-app'; name = 'web-app' }
                author     = [PSCustomObject] @{ login = 'octo' }
                assignees  = @()
                url        = 'https://github.com/PS-MCS/web-app/pull/2'
            }
            if ($Argument -contains '--review-requested') { $pr1 }
            else { $pr1; $pr2 }
        }
    }
    Context -Name 'default role' -Fixture {
        It -Name 'defaults to a single --author search' -Test {
            Get-GHPullRequest -Organization PS-MCS | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains 'prs' -and $Argument -contains '--author' -and $Argument -contains 'octo' }
        }
        It -Name 'returns one projected row per pull request' -Test {
            $result = Get-GHPullRequest -Organization PS-MCS
            $result | Should -HaveCount 2
        }
        It -Name 'projects the expected properties' -Test {
            $row = Get-GHPullRequest -Organization PS-MCS | Where-Object Number -EQ 1
            $row.Repository | Should -Be 'PS-MCS/aws-lambda'
            $row.Title | Should -Be 'first'
            $row.State | Should -Be 'open'
            $row.Draft | Should -BeFalse
            $row.Roles | Should -Be 'Author'
            $row.Author | Should -Be 'octo'
            $row.Assignees | Should -Be 'octo, hubot'
            $row.Updated | Should -BeOfType [System.DateTime]
        }
    }
    Context -Name 'user resolution' -Fixture {
        It -Name 'searches by the explicit user when supplied' -Test {
            Get-GHPullRequest -Organization PS-MCS -User btrampf | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains 'btrampf' -and $Argument -notcontains 'octo' }
        }
    }
    Context -Name 'multiple roles' -Fixture {
        It -Name 'runs one search per role' -Test {
            Get-GHPullRequest -Organization PS-MCS -Role Author, ReviewRequested | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 2 -Exactly
        }
        It -Name 'unions and deduplicates on owner/repo#number' -Test {
            $result = Get-GHPullRequest -Organization PS-MCS -Role Author, ReviewRequested
            $result | Should -HaveCount 2
        }
        It -Name 'records every matched relationship in Roles' -Test {
            $row = Get-GHPullRequest -Organization PS-MCS -Role Author, ReviewRequested | Where-Object Number -EQ 1
            $row.Roles | Should -Be 'Author, ReviewRequested'
        }
        It -Name 'maps each role to its search qualifier' -Test {
            Get-GHPullRequest -Organization PS-MCS -Role ReviewRequested | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains '--review-requested' }
        }
    }
    Context -Name 'prefix filtering' -Fixture {
        It -Name 'keeps only repos whose name matches the prefix' -Test {
            $result = Get-GHPullRequest -Organization PS-MCS -Prefix aws
            $result | Should -HaveCount 1
            $result.Repository | Should -Be 'PS-MCS/aws-lambda'
        }
    }
    Context -Name 'repository scope' -Fixture {
        It -Name 'searches with repeated --repo arguments' -Test {
            Get-GHPullRequest -Repository 'PS-MCS/web-app', 'PS-MCS/aws-lambda' | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains '--repo' -and $Argument -notcontains '--owner' }
        }
    }
    Context -Name 'state handling' -Fixture {
        It -Name 'omits --state when State is all' -Test {
            Get-GHPullRequest -Organization PS-MCS -State all | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -notcontains '--state' }
        }
        It -Name 'maps merged to the --merged flag without --state' -Test {
            Get-GHPullRequest -Organization PS-MCS -State merged | Out-Null
            Should -Invoke -CommandName Invoke-GHCli -ModuleName 'PS.GHOps' -Times 1 -Exactly `
                -ParameterFilter { $Argument -contains '--merged' -and $Argument -notcontains '--state' }
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects a repository not in owner/name form' -Test {
            { Get-GHPullRequest -Repository 'not-a-valid-repo' } | Should -Throw
        }
        It -Name 'rejects an unknown role' -Test {
            { Get-GHPullRequest -Organization PS-MCS -Role Bogus } | Should -Throw
        }
    }
}
