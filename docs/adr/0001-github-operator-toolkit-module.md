# ADR 1: A Dedicated Repository for the GitHub Operator Toolkit

## Status

Accepted. Superseded in part by [ADR-0002](0002-self-contained-gh-wrappers.md): the deferred `PS.GitHub` `RequiredModules` dependency is withdrawn in favor of a local `Invoke-GHApi`, so the module depends only on the `gh` CLI. The vendored PSake build is replaced by the shared [pwsh-module-ci harness](https://github.com/jjohns-dev/pwsh-module-ci/blob/main/docs/adr/0006-host-the-build-harness-in-this-repo.md) from `v2`.

## Context

- `johnsarie27/git-ops` accumulated a mix of reusable GitHub functions and one-off scratch scripts under `utils/`, with inconsistent backends (`PowerShellForGitHub` vs raw `gh`).
- `johnsarie27/PS.GitHub` already exists as a curated, deliberately **narrow, agent-facing** module (REST wrapper, signed commits, auth-scope checks), governed by an incident-driven bar and a determinism-vs-knowledge test. It rejects human-facing reporting/wrapper helpers by design.
- The reusable functions extracted from `git-ops` are the opposite shape: human-facing org reports and maintenance actions.
- Reuse is wanted across both agents (`PS.GitHub`) and humans, without diluting `PS.GitHub`'s curated surface.
- The `gh` CLI is an already-required, authenticated prerequisite.

## Decision

- We will host the operator toolkit as its own module and repository, **`PS.GHOps`**, separate from `PS.GitHub` — the higher layer of a two-module design (`PS.GitHub` = determinism substrate; `PS.GHOps` = human-facing reporting/admin).
- We will **mirror `PS.GitHub`'s repository scaffolding** (PSake build, multi-OS CI, release workflow, `.vscode`/analyzer settings, dependabot, ADRs, `Public/`/`Private/` layout, manifest-authoritative exports).
- We will name all exported commands `Verb-GH<Noun>` — the `GH` prefix matching the module name and distinct from `PS.GitHub`'s `Gh` casing.
- `gh` access has two lanes: **subcommands** through a private `Invoke-GHCli` (which isolates `$PSNativeCommandUseErrorActionPreference` and standardizes exit-code handling); **REST** through `PS.GitHub`'s `Invoke-GhApi`.
- We will **defer the `RequiredModules` dependency on `PS.GitHub`.** The initial functions use raw `gh`, so the manifest declares no required modules; the dependency is added when the functions consume `Invoke-GhApi` for REST — at which point `PS.GitHub`'s CI/install distribution must also be solved.

## Consequences

- **Positive** — `PS.GitHub` keeps its narrow, ADR-governed identity; the ops toolkit gets a clean home with a full build/CI/release pipeline from day one.
- **Positive** — declaring no `RequiredModules` yet keeps import and CI green without an as-yet-unpublished `PS.GitHub`, and is accurate for the current raw-`gh` code.
- **Negative** — two lanes for `gh` (subcommand vs REST) is a rule contributors must remember; a bare `& gh` in `Public/` is a review-reject.
- **Negative** — the intended `PS.GitHub` dependency is documented but not yet enforced by the manifest, so the layering is aspirational until the `Invoke-GhApi` wiring lands. Distribution of `PS.GitHub` (not on PSGallery) remains an open question for that step.
- **Neutral** — functions were seeded by copying from `git-ops/utils/functions/`; that copy should be retired from `git-ops` once `PS.GHOps` is the source of truth.
