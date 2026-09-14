BeforeDiscovery {
    if (-not (Get-Module -Name 'PS.GHOps')) {
        $manifest = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) -ChildPath 'PS.GHOps.psd1'
        Import-Module -Name $manifest -Force -ErrorAction Stop
    }
}

Describe -Name 'Test-GHRepoBaseline' -Fixture {
    BeforeAll {
        $script:baseline = @{
            schema_version = 1
            repo_settings  = @{
                allow_squash_merge     = $true
                allow_merge_commit     = $false
                delete_branch_on_merge = $true
            }
            security       = @{
                dependabot_alerts = $true
                secret_scanning   = $true
            }
            ruleset        = @{
                bypass_actors = @(
                    @{ actor_type = 'RepositoryRole'; actor_id = 5; bypass_mode = 'always' }
                )
                rules         = @{
                    deletion           = $true
                    required_signatures = $true
                    pull_request       = @{ required_approving_review_count = 0 }
                }
            }
            status_checks  = @{ 'acme/good' = @('build') }
        }
        # 'acme/good' MATCHES THE BASELINE; 'acme/drift' DIVERGES ON EVERY CATEGORY
        Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith {
            $good = $Path -match 'acme/good'
            switch -Regex ($Path) {
                'vulnerability-alerts$' {
                    if ($good) { return }
                    Write-Error -Message 'gh api failed: 404 Not Found' -ErrorAction Stop
                }
                'rulesets/1$' {
                    return [PSCustomObject] @{
                        id            = 1
                        target        = 'branch'
                        enforcement   = if ($good) { 'active' } else { 'disabled' }
                        bypass_actors = @([PSCustomObject] @{ actor_type = 'RepositoryRole'; actor_id = 5; bypass_mode = 'always' })
                        rules         = @(
                            [PSCustomObject] @{ type = 'deletion' }
                            [PSCustomObject] @{ type = 'required_signatures' }
                            [PSCustomObject] @{ type = 'pull_request'; parameters = [PSCustomObject] @{ required_approving_review_count = 0 } }
                            [PSCustomObject] @{ type = 'required_status_checks'; parameters = [PSCustomObject] @{ required_status_checks = @([PSCustomObject] @{ context = 'build' }) } }
                        )
                    }
                }
                'rulesets$' { return @([PSCustomObject] @{ id = 1 }) }
                default {
                    return [PSCustomObject] @{
                        allow_squash_merge     = $true
                        allow_merge_commit     = -not $good
                        delete_branch_on_merge = $true
                        security_and_analysis  = [PSCustomObject] @{
                            secret_scanning = [PSCustomObject] @{ status = if ($good) { 'enabled' } else { 'disabled' } }
                        }
                    }
                }
            }
        }
    }
    Context -Name 'compliant repository' -Fixture {
        It -Name 'reports every checked setting as compliant' -Test {
            $result = Test-GHRepoBaseline -Repository 'acme/good' -Baseline $script:baseline
            @($result).Where({ -not $_.Compliant }) | Should -BeNullOrEmpty
        }
        It -Name 'emits rows for all three categories' -Test {
            $result = Test-GHRepoBaseline -Repository 'acme/good' -Baseline $script:baseline
            ($result.Category | Sort-Object -Unique) | Should -Be @('RepoSettings', 'Ruleset', 'Security')
        }
        It -Name 'compares a parameterized rule by its parameters' -Test {
            $row = Test-GHRepoBaseline -Repository 'acme/good' -Baseline $script:baseline |
                Where-Object -Property Setting -EQ 'pull_request.required_approving_review_count'
            $row.Compliant | Should -BeTrue
        }
        It -Name 'matches required status-check contexts' -Test {
            $row = Test-GHRepoBaseline -Repository 'acme/good' -Baseline $script:baseline |
                Where-Object -Property Setting -EQ 'required_status_checks.contexts'
            $row.Actual | Should -Be 'build'
            $row.Compliant | Should -BeTrue
        }
        It -Name 'normalizes multi-value settings regardless of order or collection type' -Test {
            $reordered = $script:baseline.Clone()
            $reordered['status_checks'] = @{ 'acme/good' = @('zulu', 'alpha') }
            Mock -CommandName Invoke-GHApi -ModuleName 'PS.GHOps' -MockWith {
                switch -Regex ($Path) {
                    'rulesets/1$' {
                        return [PSCustomObject] @{
                            id          = 1
                            target      = 'branch'
                            enforcement = 'active'
                            rules       = @(
                                [PSCustomObject] @{ type = 'required_status_checks'; parameters = [PSCustomObject] @{ required_status_checks = @([PSCustomObject] @{ context = 'alpha' }, [PSCustomObject] @{ context = 'zulu' }) } }
                            )
                        }
                    }
                    'rulesets$' { return @([PSCustomObject] @{ id = 1 }) }
                    'vulnerability-alerts$' { return }
                    default { return [PSCustomObject] @{ } }
                }
            }
            $row = Test-GHRepoBaseline -Repository 'acme/good' -Baseline $reordered |
                Where-Object -Property Setting -EQ 'required_status_checks.contexts'
            $row.Expected | Should -Be 'alpha, zulu'
            $row.Actual | Should -Be 'alpha, zulu'
            $row.Compliant | Should -BeTrue
        }
    }
    Context -Name 'drifting repository' -Fixture {
        It -Name 'flags a mismatched repo setting' -Test {
            $row = Test-GHRepoBaseline -Repository 'acme/drift' -Baseline $script:baseline |
                Where-Object -Property Setting -EQ 'allow_merge_commit'
            $row.Compliant | Should -BeFalse
            $row.Expected | Should -Be 'False'
            $row.Actual | Should -Be 'True'
        }
        It -Name 'treats a 404 from vulnerability-alerts as disabled rather than an error' -Test {
            $row = Test-GHRepoBaseline -Repository 'acme/drift' -Baseline $script:baseline |
                Where-Object -Property Setting -EQ 'dependabot_alerts'
            $row.Actual | Should -Be 'False'
            $row.Compliant | Should -BeFalse
        }
        It -Name 'flags disabled secret scanning' -Test {
            $row = Test-GHRepoBaseline -Repository 'acme/drift' -Baseline $script:baseline |
                Where-Object -Property Setting -EQ 'secret_scanning'
            $row.Compliant | Should -BeFalse
        }
        It -Name 'ignores a ruleset that is not active' -Test {
            $row = Test-GHRepoBaseline -Repository 'acme/drift' -Baseline $script:baseline |
                Where-Object -Property Setting -EQ 'rule:deletion'
            $row.Actual | Should -Be 'False'
            $row.Compliant | Should -BeFalse
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects a repository not in owner/name form' -Test {
            { Test-GHRepoBaseline -Repository 'not-valid' -Baseline $script:baseline } | Should -Throw
        }
        It -Name 'rejects an unsupported schema version' -Test {
            { Test-GHRepoBaseline -Repository 'acme/good' -Baseline @{ schema_version = 99 } } | Should -Throw
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'accepts repositories from the pipeline' -Test {
            $result = 'acme/good', 'acme/drift' | Test-GHRepoBaseline -Baseline $script:baseline
            ($result.Repository | Sort-Object -Unique) | Should -Be @('acme/drift', 'acme/good')
        }
    }
}
