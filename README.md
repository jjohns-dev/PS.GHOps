# PS.GHOps

A PowerShell **operator toolkit for GitHub** — human-facing reporting and
administration helpers over the [`gh`](https://cli.github.com/) CLI.

`PS.GHOps` is the higher layer of a two-module design: the low-level,
determinism-focused [`PS.GitHub`](https://github.com/johnsarie27/PS.GitHub)
module is the substrate; `PS.GHOps` holds the convenience/reporting commands an
operator reaches for from a shell.

## Requirements

- PowerShell 7.4+
- The [`gh` CLI](https://cli.github.com/), authenticated (`gh auth status`).

## Install

`PS.GHOps` is not published to the PowerShell Gallery. Install from a clone:

```powershell
git clone https://github.com/johnsarie27/PS.GHOps.git
Import-Module ./PS.GHOps/PS.GHOps.psd1
```

## Functions

| Function | Summary |
| -------- | ------- |
| `Get-GHActivity` | Your recent issue/PR activity, categorized by lifecycle event (opened/closed/merged). |
| `Get-GHIssue` | Issue report scoped by org, repo-name prefix, or an explicit repo list. |
| `Get-GHOpenBranch` | Non-default branches across an org's active repositories. |
| `Get-GHPullRequest` | Pull requests related to a user (author, reviewer, assignee, etc.) across an org, repo-name prefix, or explicit repo list. |
| `Get-GHRepoFile` | Whether a given file path (e.g. `.github/CODEOWNERS`) exists in each repo of an org. |
| `Get-GHUnpinnedAction` | Workflow `uses:` action references not pinned to a commit SHA, across an org or specific repos. |
| `New-GHIssue` | Create an issue in a repository, with optional body, labels, assignees, and milestone. |
| `New-GHLabel` | Create one or more labels in one or more repositories. |
| `Remove-GHStaleCodeScan` | Removes orphaned code-scanning analyses that block PRs after a scanning workflow is renamed. |

## Examples

```powershell
# Open issues across an org, or just the 'aws' repos
Get-GHIssue -Organization PS-MCS | Format-Table -AutoSize
Get-GHIssue -Organization PS-MCS -Prefix aws

# Which active repos lack a CODEOWNERS file?
Get-GHRepoFile -Organization PS-MCS -Path '.github/CODEOWNERS' -Filter Missing

# Seed the same label across a handful of repos
New-GHLabel -Repository 'PS-MCS/gh-org', 'PS-MCS/vdem' -Name 'security' -Color 'd73a4a' -Description 'Security-related work'

# Open an issue with a body, labels, and an assignee
New-GHIssue -Owner PS-MCS -Repository gh-org -Title 'Rotate the signing key' -Body 'Due this quarter.' -Label 'security' -Assignee octocat

# Actions pinned to a mutable tag/branch instead of a commit SHA
Get-GHUnpinnedAction -Organization PS-MCS -Kind tag

# Non-default branches worth cleaning up
Get-GHOpenBranch -Organization PS-MCS
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the new-function checklist and
[`docs/adr/`](docs/adr/) for the decisions that shape the module. Repo
conventions for agents live in [AGENTS.md](AGENTS.md).
