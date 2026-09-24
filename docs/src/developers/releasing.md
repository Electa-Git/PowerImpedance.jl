# Release and package-registration runbook

This runbook is for maintainers publishing PowerImpedance from the authoritative
KU Leuven GitLab repository to the public GitHub repository and registering the
published version in Julia's General registry.

Follow the steps in order. GitLab is the source repository. GitHub is a public
release mirror. Do not make release commits directly on GitHub.

## Release flow

The complete flow is:

```text
GitLab main
    -> GitLab vX.Y.Z tag
    -> GitLab release pipeline
    -> GitHub main and vX.Y.Z tag
    -> JuliaRegistrator request
    -> General registry pull request
    -> registered Julia package
```

The GitLab pipeline publishes the release commit and tag to GitHub. It does not
register the package with Julia. Registration is a separate action performed on
GitHub after publication succeeds.

## Operator checklist

For an ordinary stable release, the operator must complete these gates:

- [ ] The release merge request updates `Project.toml`, `CHANGELOG.md`, and
  `CITATION.cff` consistently.
- [ ] The release commit is merged into GitLab `main`, and its `main` pipeline
  passes.
- [ ] An annotated `vX.Y.Z` tag is created at that exact `main` commit and
  pushed only to GitLab.
- [ ] The GitLab tag pipeline passes, including GitHub publication and release
  reporting.
- [ ] GitHub `main`, the GitHub tag, and GitHub Release CI identify the same
  commit.
- [ ] `@JuliaRegistrator register` is posted on that GitHub commit.
- [ ] The General registry pull request merges.
- [ ] A clean Julia environment installs and loads the intended version.
- [ ] TagBot publishes the corresponding GitHub Release.

## Invariants

Every release must satisfy all of these conditions:

- The release commit is already on GitLab's default branch, `main`.
- `Project.toml` contains the intended version without a `v` prefix, for
  example `version = "0.3.1"`.
- The Git tag is exactly `v` followed by that version, for example `v0.3.1`.
- The release tag identifies the same commit as GitLab `main` when the release
  is made.
- GitHub `main` is never edited independently. Normal publication only
  fast-forwards it from GitLab.
- A shared release tag is immutable. Never delete it, move it, or reuse its
  version for different source code.

A tag named `0.3.1` is not a release tag for this repository. It must be named
`v0.3.1`. Tags that do not match the release pattern do not start the release
jobs.

## One-time administrator setup

Ordinary release operators should not need to change this configuration. If
publication or registration fails because configuration is absent, ask a GitLab
or GitHub repository administrator to check it.

### GitLab

The GitLab project must have these protected CI/CD variables:

- `GITHUB_DEPLOY_KEY`: a file-type variable containing the private half of a
  GitHub deploy key with write access to `Electa-Git/PowerImpedance.jl`.
- `GITHUB_KNOWN_HOSTS`: a file-type variable containing the trusted
  `github.com` SSH host key.
- `CODECOV_TOKEN`: the token for the public GitHub Codecov project.

The `github-force-reconcile` environment must be protected so that only
authorized maintainers can rewrite GitHub `main` in an exceptional recovery.

### GitHub

The GitHub repository must have:

- the public half of the GitLab deploy key, with write access;
- the `DOCUMENTER_KEY` Actions secret used by TagBot;
- GitHub Actions enabled with permission to create releases;
- the
  [JuliaRegistrator GitHub App](https://github.com/JuliaRegistries/Registrator.jl)
  installed for this repository.

The tracked `.github/workflows/TagBot.yml` workflow is necessary, but it does
not install JuliaRegistrator by itself.

## 1. Prepare the release on GitLab

Choose the next version according to the project's semantic-versioning policy.
During the `0.y.z` development series, increment the minor version for a
breaking public API change and describe the break clearly.

Prepare and merge a release merge request that:

1. changes `version` in `Project.toml`;
2. moves the relevant `CHANGELOG.md` entries from `Unreleased` into a dated
   section for the new version;
3. changes `version` and `date-released` in `CITATION.cff`;
4. includes every source, test, documentation, and compatibility change meant
   to be part of the release.

Do not create the release tag from the merge-request branch. Wait until the
release commit has been merged into GitLab `main` and the ordinary `main`
pipeline has passed.

Record the release version and exact GitLab `main` commit before tagging:

```bash
git fetch origin main --tags
release_sha="$(git rev-parse refs/remotes/origin/main)"
release_version="$(
    git show "${release_sha}:Project.toml" |
        sed -n 's/^version *= *"\([^"]*\)".*/\1/p' |
        head -n 1
)"
release_tag="v${release_version}"

printf 'Release commit: %s\n' "$release_sha"
printf 'Release version: %s\n' "$release_version"
printf 'Release tag: %s\n' "$release_tag"
git log -1 --decorate --oneline "$release_sha"
```

Stop if the version is empty, unexpected, or already registered. Inspect the
release metadata directly from that commit:

```bash
git show "${release_sha}:Project.toml" | sed -n '1,5p'
git show "${release_sha}:CITATION.cff" | sed -n '1,12p'
git show "${release_sha}:CHANGELOG.md" | sed -n '1,40p'
```

Check whether the intended tag already exists locally or on GitLab:

```bash
git tag --list "$release_tag"
git ls-remote --tags origin "refs/tags/${release_tag}"
```

Both commands should produce no tag before a new release. If either command
finds the tag, do not overwrite it. Determine whether the version was already
released. If source changes are needed, choose a new version.

## 2. Create the GitLab release tag

Create an annotated tag at the recorded `origin/main` commit:

```bash
git tag -a "$release_tag" "$release_sha" -m "PowerImpedance ${release_tag}"
git show --no-patch --decorate "$release_tag"
```

Confirm that the displayed commit is the recorded release commit. Then push
only that tag to GitLab:

```bash
git push origin "refs/tags/${release_tag}"
```

The same operation can be performed through the GitLab tag interface, provided
the tag name is `vX.Y.Z` and the target is the exact release commit on `main`.

Pushing the tag starts a GitLab tag pipeline. Do not push the tag directly to
GitHub; the pipeline owns GitHub publication.

## 3. Monitor the GitLab release pipeline

Open **GitLab > Build > Pipelines**, select the pipeline whose ref is the new
tag, and wait for it to finish.

The pipeline performs these stages:

1. `test`: core, extension, and plotting tests run for the tagged source;
2. `docs`: documentation is built, with public GitHub links for a stable tag;
3. `release_check`: `github_release_preflight` checks the version, tag, GitLab
   ancestry, GitHub authentication, and fast-forward topology;
4. `deploy`: `github_release_publish` atomically pushes the release commit to
   GitHub `main` and the release tag to GitHub;
5. `release_report`: coverage is uploaded and stable documentation is deployed
   to GitHub Pages.

The publication push is atomic: GitHub should receive both `main` and the tag,
or neither of them.

### Retrying jobs safely

- A transient failure before GitHub publication can be retried if no source or
  release metadata must change.
- If source or release metadata must change, make a new commit, increment the
  version, and create a new release tag. Never move the existing tag.
- If `github_release_publish` succeeded but a later coverage or documentation
  job failed, retry only the failed downstream job. Retrying the successful
  publication job will be refused because the GitHub tag already exists.

## 4. Verify GitHub publication

Do not start Julia registration until all of the following are true:

- GitHub `main` identifies the recorded release commit.
- GitHub contains the `vX.Y.Z` tag at that same commit.
- The GitHub **Release CI** workflow for the tag passed.
- The stable documentation deployment passed for a stable release.

Use the GitHub web interface, or verify the public refs without needing a
configured GitHub remote:

```bash
git ls-remote https://github.com/Electa-Git/PowerImpedance.jl.git \
    refs/heads/main "refs/tags/${release_tag}^{}"
```

Both reported refs must identify `release_sha`. The `^{}` suffix dereferences
an annotated tag to the commit it identifies.

At this point the public source and tag exist, but the package is not
necessarily registered in Julia General yet.

## 5. Request registration in Julia General

Sign in to GitHub using an account that is a collaborator on the repository or
a public member of the owning organization.

Open the release commit on GitHub:

```text
https://github.com/Electa-Git/PowerImpedance.jl/commit/RELEASE_COMMIT_SHA
```

Add this exact comment to the commit:

```text
@JuliaRegistrator register
```

Optional release notes for the GitHub Release may follow in the same comment:

```text
@JuliaRegistrator register

Release notes:

Describe the user-visible changes here.
```

An issue comment in the PowerImpedance GitHub repository can also trigger
Registrator, but a comment on the exact release commit makes the intended source
unambiguous. Do not post the command on a pull request or issue in the General
registry repository.

Registrator checks `Project.toml` and opens a pull request against
[JuliaRegistries/General](https://github.com/JuliaRegistries/General). Follow
the link posted by the bot to that pull request.

## 6. Monitor the General registry pull request

Review every failed registry check. General's AutoMerge verifies registry
metadata and attempts to install and load the package.

At the time of writing, General normally waits:

- three days for a new package;
- approximately 15 minutes for a new version of an already registered package.

The current policy is documented in the
[General registry README](https://github.com/JuliaRegistries/General/blob/master/README.md).

Avoid unnecessary comments on the registry pull request: an ordinary comment
can block AutoMerge. If a purely informational comment is required, follow the
General registry's current instructions for marking it non-blocking.

If a check reveals that the package source or metadata must change:

1. fix the problem on GitLab;
2. increment the package version;
3. publish a new GitLab release tag through this runbook;
4. trigger Registrator on the new GitHub release commit.

Do not move the old tag and do not register different source code under the old
version. Julia registry versions are permanent and must remain reproducible.

The first registered PowerImpedance version does not have to be the earliest
GitHub tag. For example, General may first register `0.3.1` even if the public
repository also contains an unregistered `v0.3.0` tag.

## 7. Verify installation after registry merge

After the General pull request merges, allow time for registry and package
server propagation. Then verify from a temporary Julia environment:

```bash
julia --startup-file=no -e '
    using Pkg
    Pkg.activate(; temp = true)
    Pkg.Registry.update()
    Pkg.add("PowerImpedance")
    using PowerImpedance
    Pkg.status(["PowerImpedance"])
'
```

Confirm that Julia resolves the intended version and loads it without using a
local checkout or an unregistered URL.

## 8. Verify the GitHub Release

After the General registry pull request merges, General notifies JuliaTagBot.
The tracked TagBot workflow should create or backfill the GitHub Release and its
release notes for the tag that the GitLab pipeline already published.

Check **GitHub > Actions > TagBot** and **GitHub > Releases**. If the release is
missing, run the TagBot workflow manually from the GitHub Actions interface and
inspect its log. Do not create or move another tag to solve a missing GitHub
Release: Julia registration and GitHub Releases are separate concepts, and the
correct tag already exists.

## Troubleshooting

### No GitLab release pipeline started

Check the tag spelling. The accepted form is `vX.Y.Z`, optionally followed by a
SemVer prerelease suffix. A tag such as `0.3.1` does not match.

### The tag does not match `Project.toml`

The pipeline requires an exact match. `Project.toml` version `0.3.1` requires
tag `v0.3.1`. Do not repair a shared tag by moving it. Correct the source and
publish a new version when necessary.

### The tagged commit is not on `main`

The release was tagged too early or from the wrong branch. Merge the intended
release into GitLab `main`, increment the version, and create a new tag.

### GitHub `main` has diverged

Normal publication refuses to force-push GitHub. An authorized maintainer must
run the protected `github_force_reconcile` job from the latest GitLab `main`
pipeline. The job archives the former GitHub `main` under an
`archive/github-main-before-reconcile-*` tag before reconciling it. Retry the
release only after reviewing that archive and confirming the reconciliation.

This is exceptional recovery, not a normal release step.

### The GitHub tag already exists

The publication job deliberately refuses to overwrite it. Determine whether a
previous publication already succeeded. If the existing tag points elsewhere,
stop and ask a repository administrator to investigate. Do not force-push or
delete the tag.

### JuliaRegistrator does not respond

Check that:

- the JuliaRegistrator GitHub App is installed for the repository;
- the repository is public;
- the commenter is an eligible collaborator or public organization member;
- the command was posted in the PowerImpedance repository;
- the GitHub commit contains the intended `Project.toml` version.

### General AutoMerge fails to load the package

Open the failing check and reproduce the reported clean-environment failure.
Fix the package on GitLab and publish a new version. Do not add registry-only
workarounds that hide a real load failure.

### TagBot fails or no GitHub Release appears

Registration in General may still be valid. Inspect the TagBot Actions log,
check the `DOCUMENTER_KEY` secret and repository Actions permissions, and
manually dispatch the existing TagBot workflow after correcting configuration.
Do not retrigger Registrator merely to repair a GitHub Release.

## Authoritative configuration

When this runbook and the automation disagree, inspect the current automation
before acting:

- `.gitlab-ci.yml`: tests, preflight, GitHub publication, coverage, and release
  documentation;
- `.gitlab/force_reconcile_github.sh`: exceptional GitHub reconciliation;
- `.github/workflows/release-ci.yml`: verification of the published GitHub tag;
- `.github/workflows/TagBot.yml`: post-registration GitHub Release creation;
- `docs/deploy_github.jl`: stable documentation deployment.

The official external references are the
[Registrator documentation](https://github.com/JuliaRegistries/Registrator.jl),
the [General registry policy](https://github.com/JuliaRegistries/General/blob/master/README.md),
and the [TagBot documentation](https://github.com/JuliaRegistries/TagBot).
