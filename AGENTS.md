# AGENTS.md — repo conventions for `PS.GHOps`

Context for an AI agent (or a human working alongside one) to work productively
in this repo without re-reading every skill file from scratch.

**Read first:** [`docs/adr/`](docs/adr/) — architecturally significant decisions. Start there for "why is it this way?" questions.

## Purpose

`PS.GHOps` is a **human-facing operator toolkit** for GitHub: org-scoped
reporting and administration helpers over the `gh` CLI. It is the higher layer
of a two-module design — the low-level, determinism-focused
[`PS.GitHub`](https://github.com/johnsarie27/PS.GitHub) module is the substrate
(REST wrapper, signed commits, auth-scope checks); `PS.GHOps` holds the
convenience/reporting commands built on top of it.

Where `PS.GitHub` is deliberately narrow and agent-facing, `PS.GHOps` is for a
human running ad-hoc org reports and maintenance from a shell.

## Function inventory

### Public functions (exported via manifest)

| Function | Status | Purpose |
|---|---|---|
| `Get-GHActivity` | Experimental | A user's recent issue/PR activity via `gh search`, categorized by lifecycle event. |
| `Get-GHIssue` | Experimental | Issue report scoped by org, repo-name prefix, or explicit repo list (`gh search issues`). |
| `Get-GHOpenBranch` | Experimental | Non-default branches across an org's active repos (`gh repo list` + branches REST). |
| `Get-GHPullRequest` | Experimental | PRs related to a user by one or more relationships (author/assignee/mentioned/commenter/involves/review-requested/reviewed-by) across an org, prefix, or repo list; one `gh search prs` per role, unioned and deduped (`Roles` column). |
| `Get-GHRepoFile` | Experimental | Presence/absence of a repo-relative file path across an org's repos. |
| `Get-GHUnpinnedAction` | Experimental | Reports workflow `uses:` action refs not pinned to a commit SHA, across an org or explicit repos. |
| `New-GHIssue` | Experimental | Creates an issue in a repository with optional body, labels, assignees, and milestone (issues REST). |
| `New-GHLabel` | Experimental | Creates one or more labels in one or more repositories; skip-or-`-Update` on an existing label. |
| `Remove-GHStaleCodeScan` | Beta | Removes orphaned code-scanning analyses that block PRs after a scanning workflow is renamed. |

### Private helpers (dot-sourced, not exported)

| Helper | Purpose |
|---|---|
| `Invoke-GHCli` | Runs a `gh` **subcommand** with `$PSNativeCommandUseErrorActionPreference` isolation, `$LASTEXITCODE` checking, a consistent terminating error on failure, and optional `-AsJson` parsing. Subcommands only. |
| `Invoke-GHApi` | REST counterpart: runs `gh api <Path>` with the same preference isolation, `-AllowNotFound` (404 → `$null`), `-Paginate` (flattens `--slurp` pages), `-Field` (hashtable request body: strings via `-f key=value`, integers via typed `-F key=value`, arrays via repeated `-f key[]=element`), and JSON parsing. |

`FunctionsToExport` in [PS.GHOps.psd1](PS.GHOps.psd1) is the authoritative export list.

## Cross-cutting rules every public function honors

1. **Two lanes for `gh`.** Subcommands (`gh repo list`, `gh search issues`) go through the private `Invoke-GHCli`; REST calls (`gh api …`) go through the private `Invoke-GHApi`. No bare `& gh` in `Public/`. Both wrappers isolate `$PSNativeCommandUseErrorActionPreference`.
2. **Native-preference isolation.** `Invoke-GHCli` sets `$PSNativeCommandUseErrorActionPreference = $false` so a caller that enabled it cannot turn the `& gh` + `$LASTEXITCODE` pattern into a `NativeCommandExitException`.
3. **No `--jq` / `--query` for filter/project.** Return deserialized objects; callers use the pwsh pipeline (`Where-Object` / `Select-Object` / `Group-Object`).
4. **Active repos by default.** Org-scanning functions exclude archived repos and forks by default (`gh repo list --no-archived --source`) with `-IncludeArchived` / `-IncludeFork` opt-in switches.
5. **`Verb-GH<Noun>` naming.** All exports use the `GH` prefix (matching this module's name); output is a `[PSCustomObject]` stream.

## Layout

```text
PS.GHOps/
  .devcontainer/         devcontainer + Dockerfile (installs gh CLI)
  .github/
    workflows/ci.yml     Pester + PSScriptAnalyzer, matrix on ubuntu + windows + macos
    workflows/release.yml fires on `v*.*.*` tag push; creates a GitHub Release with a .zip artifact
    release.yml          auto-generated-release-notes categorization by PR label
    dependabot.yml
    CODEOWNERS
  .vscode/               editor settings + PSScriptAnalyzer rules
  Build/                 PSake harness (build.ps1 -> build.psake.ps1); module name derived from the .psd1 basename
  Public/                one .ps1 per exported function, Verb-GHNoun.ps1
  Private/               internal helpers, NOT exported
  Tests/                 Pester tests, Tests/Unit/<Function>.tests.ps1
  docs/adr/              architectural decision records
  PS.GHOps.psd1          module manifest (authoritative export list)
  PS.GHOps.psm1          module loader (dot-sources Public/ + Private/)
  README.md              user-facing quickstart + function list
  CONTRIBUTING.md        new-function checklist + template
```

## Working conventions

- Branch off `main` using `<issue-number>-<short-slug>`; no direct commits to `main`.
- One PR per function or per cross-cutting concern.
- Every function ships with comment-based help (`.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.INPUTS`/`.OUTPUTS`/`.EXAMPLE`/`.NOTES`), a `.NOTES Status:` line, an approved verb, and (for exports) an entry in `FunctionsToExport`. A `Tests/Unit/<Verb-Noun>.tests.ps1` is expected for new functions.
- Run the build locally before a PR: `./Build/build.ps1 -ResolveDependency -TaskList Init` then `-TaskList CombineFunctionsAndStage`, `Analyze`, `Test`.

## Relationship to PS.GitHub

`PS.GHOps` is a **standalone** module: it depends only on the `gh` CLI, not on `PS.GitHub`. Both modules share design DNA (the `Invoke-Gh*` wrapper pattern, ADR-driven governance), but `PS.GHOps` owns its own `gh` internals (`Invoke-GHCli` + `Invoke-GHApi`) rather than taking a runtime dependency — which sidesteps `PS.GitHub`'s unresolved gallery/distribution question. See [`docs/adr/0002`](docs/adr/0002-self-contained-gh-wrappers.md) (supersedes the layering half of ADR-0001).
