function Test-GHRepoBaseline {
    <#
    .SYNOPSIS
        Report how one or more repositories deviate from a settings baseline.
    .DESCRIPTION
        Compares each repository's live configuration against a supplied baseline
        and emits one row per checked setting, whether or not it complies. The
        function is READ-ONLY; it changes nothing.

        Three categories are compared:

            RepoSettings - merge methods and branch auto-deletion
            Security     - Dependabot alerts and security updates, secret
                           scanning, and secret-scanning push protection
            Ruleset      - branch-ruleset rules, bypass actors, and required
                           status-check contexts

        Ruleset comparison aggregates every ACTIVE ruleset whose target is
        'branch', because GitHub applies all matching rulesets cumulatively -- a
        rule is satisfied if any active branch ruleset provides it. Ruleset NAME
        is deliberately not compared; it carries no enforcement meaning and
        differs across existing repositories.

        The baseline is supplied by the caller, not read from disk, so this
        function has no dependency on any particular repository or file format.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Repository
        Repositories to check, in 'owner/name' form.
    .PARAMETER Baseline
        The baseline definition, as a dictionary. Must carry a 'schema_version'
        of 1. Recognized sections are 'repo_settings', 'security', 'ruleset',
        and 'status_checks'; any section that is absent is simply not compared.

        Any IDictionary is accepted -- a literal hashtable, an [ordered] one, or
        the output of ConvertFrom-Json -AsHashtable. The -AsHashtable switch is
        REQUIRED when reading JSON: plain ConvertFrom-Json yields PSCustomObject,
        which is not an IDictionary and will fail parameter binding.
    .INPUTS
        System.String. Repository names can be supplied from the pipeline.
    .OUTPUTS
        System.Management.Automation.PSCustomObject, one per checked setting, with:
            Repository - 'owner/name'
            Category   - RepoSettings, Security, or Ruleset
            Setting    - the setting's name
            Expected   - the baseline value, as text
            Actual     - the live value, as text
            Compliant  - whether the two agree
    .EXAMPLE
        PS C:\> $baseline = Get-Content -Path ./repo-baseline.json -Raw | ConvertFrom-Json -AsHashtable
        PS C:\> Test-GHRepoBaseline -Repository 'jjohns-dev/pwsh-module-ci' -Baseline $baseline
        Report every checked setting for one repository.
    .EXAMPLE
        PS C:\> Test-GHRepoBaseline -Repository $repos -Baseline $baseline | Where-Object -Property Compliant -EQ $false
        Show only the drift across a set of repositories.
    .EXAMPLE
        PS C:\> Test-GHRepoBaseline -Repository $repos -Baseline $baseline | Group-Object -Property Repository
        Summarize how many settings were checked per repository.
    .NOTES
        Status: Experimental
        Dependabot alert state comes from the 'vulnerability-alerts' endpoint,
        which answers 204 when enabled and 404 when disabled, so it is probed
        separately rather than read from the repository object.
        Private repositories cannot report secret scanning on a free plan, and
        rulesets on private repositories are paid-gated; expect drift rows there
        that no amount of configuration will clear.
        https://docs.github.com/en/rest/repos/rules
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, HelpMessage = "Repositories in 'owner/name' form")]
        [ValidatePattern('^[^/]+/[^/]+$')]
        [System.String[]] $Repository,

        [Parameter(Mandatory, HelpMessage = 'The baseline definition, as a dictionary')]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Baseline
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)

        if ($Baseline['schema_version'] -ne 1) {
            $message = 'Unsupported baseline schema_version [{0}]; this function understands version 1' -f $Baseline['schema_version']
            Write-Error -Message $message -ErrorAction Stop
        }

        # NORMALIZE ANY VALUE TO TEXT SO MIXED TYPES COMPARE AND DISPLAY CONSISTENTLY
        # MATCH ON IEnumerable, NOT Array >> .Where()/.ForEach() RETURN Collection[PSObject]
        $asText = {
            param([System.Object] $Value)
            if ($null -eq $Value) { return '' }
            if ($Value -is [System.String]) { return $Value }
            if ($Value -is [System.Collections.IEnumerable]) { return ((@($Value) | Sort-Object) -join ', ') }
            return [System.String] $Value
        }
    }
    Process {
        foreach ($repo in $Repository) {
            Write-Verbose -Message ('Checking {0}' -f $repo)
            $info = Invoke-GHApi -Path ('repos/{0}' -f $repo)

            $rows = [System.Collections.Generic.List[System.Object]]::new()
            $addRow = {
                param([System.String] $Category, [System.String] $Setting, [System.Object] $Expected, [System.Object] $Actual)
                $expectedText = & $asText $Expected
                $actualText = & $asText $Actual
                $rows.Add([PSCustomObject] @{
                        Repository = $repo
                        Category   = $Category
                        Setting    = $Setting
                        Expected   = $expectedText
                        Actual     = $actualText
                        Compliant  = ($expectedText -eq $actualText)
                    })
            }

            # REPO SETTINGS >> KEYS MIRROR THE REST FIELD NAMES, SO LOOK THEM UP DIRECTLY
            foreach ($key in @($Baseline['repo_settings'].Keys)) {
                & $addRow 'RepoSettings' $key $Baseline['repo_settings'][$key] $info.$key
            }

            # SECURITY >> DEPENDABOT ALERTS ANSWER 204/404 AND CARRY NO BODY, SO PROBE SEPARATELY
            $security = $Baseline['security']
            if ($null -ne $security) {
                if ($security.Contains('dependabot_alerts')) {
                    $alertsEnabled = $true
                    try { $null = Invoke-GHApi -Path ('repos/{0}/vulnerability-alerts' -f $repo) -ErrorAction Stop }
                    catch {
                        if ($PSItem.Exception.Message -notmatch '404|Not Found') {
                            Write-Error -ErrorRecord $PSItem -ErrorAction Stop
                        }
                        $alertsEnabled = $false
                    }
                    & $addRow 'Security' 'dependabot_alerts' $security['dependabot_alerts'] $alertsEnabled
                }
                foreach ($key in @('dependabot_security_updates', 'secret_scanning', 'secret_scanning_push_protection')) {
                    if (-not $security.Contains($key)) { continue }
                    & $addRow 'Security' $key $security[$key] ($info.security_and_analysis.$key.status -eq 'enabled')
                }
            }

            # RULESET >> AGGREGATE ALL ACTIVE BRANCH RULESETS; GITHUB APPLIES THEM CUMULATIVELY
            $wanted = $Baseline['ruleset']
            if ($null -ne $wanted) {
                $summaries = @(Invoke-GHApi -Path ('repos/{0}/rulesets' -f $repo) -AllowNotFound)
                $active = [System.Collections.Generic.List[System.Object]]::new()
                foreach ($summary in $summaries) {
                    if (-not $summary.id) { continue }
                    $detail = Invoke-GHApi -Path ('repos/{0}/rulesets/{1}' -f $repo, $summary.id) -AllowNotFound
                    if ($detail -and $detail.target -eq 'branch' -and $detail.enforcement -eq 'active') { $active.Add($detail) }
                }
                # List<T> HAS A NATIVE VOID ForEach(Action<T>) THAT SHADOWS THE PWSH INTRINSIC >> USE A LOOP
                $liveRules = [System.Collections.Generic.List[System.Object]]::new()
                foreach ($set in $active) {
                    foreach ($rule in $set.rules) { $liveRules.Add($rule) }
                }

                foreach ($ruleName in @($wanted['rules'].Keys)) {
                    $expected = $wanted['rules'][$ruleName]
                    $match = @($liveRules).Where({ $PSItem.type -eq $ruleName })

                    if ($expected -is [System.Collections.IDictionary]) {
                        # PARAMETERIZED RULE >> COMPARE EACH REQUESTED PARAMETER INDIVIDUALLY
                        foreach ($param in @($expected.Keys)) {
                            $actual = if ($match.Count -gt 0) { $match[0].parameters.$param } else { $null }
                            & $addRow 'Ruleset' ('{0}.{1}' -f $ruleName, $param) $expected[$param] $actual
                        }
                    }
                    else {
                        & $addRow 'Ruleset' ('rule:{0}' -f $ruleName) $expected ($match.Count -gt 0)
                    }
                }

                # BYPASS ACTORS >> COMPARED AS A SORTED SET OF 'type:id:mode' TRIPLES
                if ($wanted.Contains('bypass_actors')) {
                    $expectedActors = @($wanted['bypass_actors']).ForEach({
                            '{0}:{1}:{2}' -f $PSItem['actor_type'], $PSItem['actor_id'], $PSItem['bypass_mode']
                        })
                    $actualActors = [System.Collections.Generic.List[System.String]]::new()
                    foreach ($set in $active) {
                        foreach ($actor in $set.bypass_actors) {
                            $actualActors.Add(('{0}:{1}:{2}' -f $actor.actor_type, $actor.actor_id, $actor.bypass_mode))
                        }
                    }
                    & $addRow 'Ruleset' 'bypass_actors' $expectedActors $actualActors
                }

                # REQUIRED CONTEXTS ARE PER-REPO; AN ABSENT ENTRY MEANS 'NONE EXPECTED'
                $expectedContexts = @()
                if ($null -ne $Baseline['status_checks'] -and $Baseline['status_checks'].Contains($repo)) {
                    $expectedContexts = @($Baseline['status_checks'][$repo])
                }
                $actualContexts = @($liveRules).Where({ $PSItem.type -eq 'required_status_checks' }).ForEach({
                        $PSItem.parameters.required_status_checks.context
                    })
                & $addRow 'Ruleset' 'required_status_checks.contexts' $expectedContexts $actualContexts            }

            Write-Verbose -Message ('{0}: {1} of {2} settings compliant' -f $repo, @($rows).Where({ $PSItem.Compliant }).Count, $rows.Count)
            $rows
        }
    }
}
