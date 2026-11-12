# Contributing Guide

- Minor fixes (typo, doc tweak) can go directly as a pull request.
- Substantive changes should start with a new issue on this repository. See the
  [ADRs](docs/adr/) for architecturally significant decisions that constrain
  what the module does and doesn't do; if a proposed change conflicts with an
  ADR, expect the PR to require a new ADR that supersedes it.
- **Focus each pull request on a single function or a single cross-cutting
  concern.** Big multi-function PRs are hard to review and hard to revert.

## Working conventions

- Branch off `main` using `<issue-number>-<short-slug>` (e.g. `3-add-get-ghlabel`).
- Every commit that traces to an issue includes `(refs #N)` in the subject or
  body. Only the final commit of the last PR under an umbrella issue uses
  `closes #N`.
- Do not commit directly to `main`. All changes land through a PR that passes CI.
- Commit messages follow this shape: `action: scope`, then a blank line, then a
  rationale paragraph (or several) explaining *why*.

## New Function Checklist

- Place the file under `Public/` (exported) or `Private/` (internal only).
- Name the file `Verb-GHNoun.ps1` matching the function name exactly; use the
  `GH` prefix and only [approved verbs](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands).
- Always include comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`,
  `.INPUTS`, `.OUTPUTS`, `.EXAMPLE`, `.NOTES`). The `.NOTES` block must include a
  `Status:` line:

  | Value | Meaning |
  | --- | --- |
  | `Stable` | Production-ready; fully tested and supported |
  | `Beta` | Functional but may have rough edges or limited testing |
  | `Experimental` | Early development; API or behavior may change |
  | `Deprecated` | Still works but will be removed in a future release |

- Route `gh` calls correctly (see [AGENTS.md](AGENTS.md#cross-cutting-rules-every-public-function-honors)):
  **subcommands** through the private `Invoke-GHCli`, **REST** through the
  private `Invoke-GHApi`. No bare `& gh` in `Public/`.
- Do not use `--jq` / `--query` for filter/project; return `[PSCustomObject]`
  and let callers use the pwsh pipeline.
- Org-scanning functions exclude archived repos and forks by default, with
  `-IncludeArchived` / `-IncludeFork` switches.
- Add a Pester test under `Tests/Unit/Verb-GHNoun.tests.ps1`. Mock external side
  effects (`gh`) so tests are hermetic and cross-platform.
- If the function is **exported**, add its name to `FunctionsToExport` in
  [`PS.GHOps.psd1`](PS.GHOps.psd1).
- Run `Analyze` and `Test` locally before opening the PR.

## Function Template

```powershell
function Get-GHNoun {
    <#
    .SYNOPSIS
        One-line summary of what the function does.
    .DESCRIPTION
        Longer description of behavior, side effects, and intended use.
    .PARAMETER Organization
        Description of the parameter.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Get-GHNoun -Organization PS-MCS
        Explanation of what the example does.
    .NOTES
        Status: Experimental
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Organization or user to query')]
        [ValidateNotNullOrEmpty()]
        [System.String] $Organization
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # Subcommands go through Invoke-GHCli (native-preference isolation lives there).
        $repos = Invoke-GHCli -Argument 'repo', 'list', $Organization, '--no-archived', '--source', '--json', 'name' -AsJson
        foreach ($repo in $repos) {
            [PSCustomObject] @{ Repository = $repo.name }
        }
    }
}
```

## Running the build locally

[`Build/build.ps1`](Build/build.ps1) is a shim that runs the shared build harness
from `jjohns-dev/pwsh-module-ci` at the version `ci.yml` pins; see its
[consumer guide](https://github.com/jjohns-dev/pwsh-module-ci/blob/main/docs/consumer-guide.md#running-the-build-locally).
First-time setup installs the build tools:

```powershell
./Build/build.ps1 -ResolveDependency -TaskList Init
```

Then run the same tasks CI runs:

```powershell
./Build/build.ps1 -TaskList CombineFunctionsAndStage
./Build/build.ps1 -TaskList Analyze
./Build/build.ps1 -TaskList Test
```

`Staging/` and `Artifacts/` are gitignored — the harness rebuilds them each run.
