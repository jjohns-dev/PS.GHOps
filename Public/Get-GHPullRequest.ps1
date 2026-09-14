function Get-GHPullRequest {
    <#
    .SYNOPSIS
        Report pull requests related to a user across a GitHub organization, a
        repo name prefix, or an explicit set of repositories.
    .DESCRIPTION
        Lists pull requests scoped one of three ways:

            -Organization <org>            every repository in the org
            -Organization <org> -Prefix p  org repos whose name starts with 'p'
            -Repository owner/name[, ...]   an explicit set of repositories

        and related to a user by one or more relationships (-Role). The default
        is 'Author' (pull requests the user opened).

        Data comes from 'gh search prs'. Because GitHub search ANDs multiple
        relationship qualifiers in a single query, each selected -Role is run as
        its own search and the result sets are unioned, then deduplicated on
        'owner/repo#number'. The Roles column on each row records which
        relationship(s) matched, so a PR the user both authored and was asked to
        review appears once as 'Author, ReviewRequested' rather than twice.

        The relationships map to 'gh search prs' qualifiers:

            Author          --author           opened by the user
            Assignee        --assignee         assigned to the user
            Mentioned       --mentions         the user is @-mentioned
            Commenter       --commenter        the user commented
            Involves        --involves         author OR assignee OR mentioned
                                               OR commenter (a bundle; does NOT
                                               include review relationships)
            ReviewRequested --review-requested review requested from the user
            ReviewedBy      --reviewed-by      the user submitted a review

        Note that 'Involves' already subsumes Author, Assignee, Mentioned, and
        Commenter, so selecting it alongside those is redundant (the union
        dedupes the overlap). The review relationships (ReviewRequested,
        ReviewedBy) are separate and are NOT part of 'Involves'.

        The prefix form filters the org-wide result set by repository name client
        side, so each role remains a single search.

        Requires the GitHub CLI ('gh') to be installed and authenticated.
    .PARAMETER Organization
        The organization (or user) whose repositories are searched.
    .PARAMETER Prefix
        Restrict the organization scan to repositories whose name begins with
        this string. Only valid with -Organization.
    .PARAMETER Repository
        An explicit list of repositories in 'owner/name' form.
    .PARAMETER User
        GitHub login to report on. Defaults to the authenticated user. For any
        login other than yourself, only pull requests in repositories your token
        can read are visible.
    .PARAMETER Role
        One or more relationships between the user and the pull request. Each is
        run as its own search and the results are unioned and deduplicated.
        Defaults to 'Author'.
    .PARAMETER State
        Pull-request state to include: 'open', 'closed', 'merged', or 'all'.
        Defaults to 'open'. 'merged' maps to gh's --merged filter (only merged
        PRs); 'closed' includes merged PRs, as GitHub treats a merge as a close.
    .PARAMETER Limit
        Maximum number of pull requests to return PER ROLE. Defaults to 200; the
        GitHub search API caps this at 1000.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject, one per pull request, with:
            Repository - 'owner/name'
            Number     - pull-request number
            Title      - pull-request title
            State      - pull-request state
            Draft      - whether the pull request is a draft
            Roles      - comma-separated relationship(s) that matched the user
            Author     - pull-request author login
            Assignees  - comma-separated assignee logins
            Updated    - last-updated timestamp in local time
            Url        - pull-request URL
    .EXAMPLE
        PS C:\> Get-GHPullRequest -Organization PS-MCS | Format-Table -AutoSize
        Open pull requests you authored across all PS-MCS repositories (default -Role Author).
    .EXAMPLE
        PS C:\> Get-GHPullRequest -Organization PS-MCS -User btrampf
        Open pull requests btrampf authored across PS-MCS repos your token can read.
    .EXAMPLE
        PS C:\> Get-GHPullRequest -Organization PS-MCS -Role Involves
        Open PRs where you are the author, an assignee, a commenter, or mentioned
        (everything EXCEPT review requests) across all PS-MCS repositories.
    .EXAMPLE
        PS C:\> Get-GHPullRequest -Organization PS-MCS -Role Involves, ReviewRequested
        The broad "everything touching me" view: the Involves bundle PLUS PRs
        awaiting your review, run as two searches, unioned and deduplicated. The
        Roles column shows which relationship(s) matched each PR.
    .EXAMPLE
        PS C:\> Get-GHPullRequest -Organization PS-MCS -Role ReviewRequested -State open
        Open PRs awaiting your review across all PS-MCS repositories.
    .EXAMPLE
        PS C:\> Get-GHPullRequest -Organization PS-MCS -State merged
        Merged PRs you authored across all PS-MCS repositories.
    .EXAMPLE
        PS C:\> Get-GHPullRequest -Repository 'PS-MCS/gh-org', 'PS-MCS/vdem' -Role Author, ReviewRequested -State all
        Open and closed PRs in the two named repositories that you either authored
        or were asked to review.
    .NOTES
        Status: Experimental
        Uses 'gh search prs', which returns at most 1000 results per role and only
        indexed (searchable) pull requests; for an exhaustive per-repo listing use
        'gh pr list --repo owner/name' instead.
        GitHub search ANDs relationship qualifiers, so combined-relationship views
        require one search per role; there is no single-query OR across roles.
        Searching private repositories requires the 'repo' OAuth scope on the gh
        token; run 'gh auth refresh -h github.com -s repo' if results are missing.
        https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests
    #>
    [CmdletBinding(DefaultParameterSetName = 'Organization')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Organization', HelpMessage = 'Organization or user to search')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Organization,

        [Parameter(ParameterSetName = 'Organization', HelpMessage = 'Restrict to repos whose name starts with this string')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Prefix,

        [Parameter(Mandatory, ParameterSetName = 'Repository', HelpMessage = "Explicit repositories in 'owner/name' form")]
        [ValidatePattern('^[^/]+/[^/]+$')]
        [System.String[]] $Repository,

        [Parameter(HelpMessage = 'GitHub login to report on; defaults to the authenticated user')]
        [ValidateNotNullOrEmpty()]
        [System.String] $User = (Invoke-GHApi -Path 'user').login,

        [Parameter(HelpMessage = 'Relationship(s) between the user and the pull request')]
        [ValidateSet('Author', 'Assignee', 'Mentioned', 'Commenter', 'Involves', 'ReviewRequested', 'ReviewedBy')]
        [System.String[]] $Role = @('Author'),

        [Parameter(HelpMessage = 'Pull-request state to include')]
        [ValidateSet('open', 'closed', 'merged', 'all')]
        [System.String] $State = 'open',

        [Parameter(HelpMessage = 'Maximum number of pull requests to return per role (search caps at 1000)')]
        [ValidateRange(1, 1000)]
        [System.Int32] $Limit = 200
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
        # MAP EACH ROLE TO ITS 'gh search prs' RELATIONSHIP QUALIFIER
        $roleQualifier = @{
            Author          = '--author'
            Assignee        = '--assignee'
            Mentioned       = '--mentions'
            Commenter       = '--commenter'
            Involves        = '--involves'
            ReviewRequested = '--review-requested'
            ReviewedBy      = '--reviewed-by'
        }
    }
    Process {
        $jsonFields = 'number,title,state,isDraft,updatedAt,repository,author,assignees,url'

        # BUILD THE SHARED SEARCH SCOPE >> --owner FOR AN ORG, REPEATED --repo FOR A LIST
        $scopeArgs = [System.Collections.Generic.List[System.String]]::new()
        # 'merged' MAPS TO gh's BOOLEAN --merged FLAG; 'all' OMITS STATE ENTIRELY
        switch ($State) {
            'merged' { $scopeArgs.Add('--merged') }
            'all' { }
            default { $scopeArgs.AddRange([System.String[]] @('--state', $State)) }
        }
        if ($PSCmdlet.ParameterSetName -eq 'Organization') {
            $scopeArgs.AddRange([System.String[]] @('--owner', $Organization))
        }
        else {
            foreach ($repo in $Repository) { $scopeArgs.AddRange([System.String[]] @('--repo', $repo)) }
        }
        $scopeArgs.AddRange([System.String[]] @('--limit', $Limit.ToString(), '--json', $jsonFields))

        # RUN ONE SEARCH PER ROLE AND UNION THE RESULTS, KEYED BY 'owner/repo#number'
        $byItem = [System.Collections.Specialized.OrderedDictionary]::new()
        foreach ($r in $Role) {
            $searchArgs = @('search', 'prs', $roleQualifier[$r], $User) + $scopeArgs
            $prs = @(Invoke-GHCli -Argument $searchArgs -AsJson)

            # FILTER THE ORG RESULT SET BY REPO-NAME PREFIX (SINGLE-SEARCH PREFIX SCOPE)
            if ($Prefix) {
                $prs = $prs.Where({ $PSItem.repository.nameWithOwner.Split('/')[-1].StartsWith($Prefix) })
            }

            foreach ($pr in $prs) {
                $key = '{0}#{1}' -f $pr.repository.nameWithOwner, $pr.number
                if (-not $byItem.Contains($key)) {
                    $byItem[$key] = [PSCustomObject] @{
                        Pr    = $pr
                        Roles = [System.Collections.Generic.List[System.String]]::new()
                    }
                }
                $byItem[$key].Roles.Add($r)
            }
        }

        Write-Verbose -Message ('Returning {0} pull requests' -f $byItem.Count)

        # PROJECT EACH DEDUPED PULL REQUEST INTO A REPORT ROW
        foreach ($entry in $byItem.Values) {
            $pr = $entry.Pr
            [PSCustomObject] @{
                Repository = $pr.repository.nameWithOwner
                Number     = $pr.number
                Title      = $pr.title
                State      = $pr.state
                Draft      = $pr.isDraft
                Roles      = ($entry.Roles -join ', ')
                Author     = $pr.author.login
                Assignees  = ($pr.assignees.login -join ', ')
                Updated    = ([System.DateTimeOffset] $pr.updatedAt).LocalDateTime
                Url        = $pr.url
            }
        }
    }
}
